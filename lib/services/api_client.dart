import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'network_resilience_handler.dart';
import 'auth_interceptor.dart';

class ApiClient {
static const String baseUrl = 'http://localhost:5008';
//static const String baseUrl = 'https://qaznat.kz';

  final Dio dio;
  final FlutterSecureStorage storage;
  final NetworkResilienceHandler _networkHandler = NetworkResilienceHandler();
  
  // In-memory token storage (fallback for iOS Keychain issues)
  String? _memoryToken;

  final VoidCallback? onSessionExpired;

  ApiClient({this.onSessionExpired})
    : dio = Dio(
      BaseOptions(
          baseUrl: baseUrl,
          // Removed global timeouts to allow services (like translation) to set their own long timeouts
          // connectTimeout: const Duration(minutes:5),
          // receiveTimeout: const Duration(minutes: 5),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
      ),
      storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(
          encryptedSharedPreferences: true,
          // 允许截屏 - 不设置FLAG_SECURE
        ),
      ) {
    print('ApiClient initialized with baseUrl: $baseUrl');
    _setupInterceptors();
  }

  void _setupInterceptors() {
    // Basic auth token interceptor
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Add token to all requests
          final token = await getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
      ),
    );

    // Session expiry / Auth interceptor
    if (onSessionExpired != null) {
      dio.interceptors.add(
        AuthInterceptor(
          dio: dio,
          onSessionExpired: () async {
            await clearToken();
            onSessionExpired?.call();
          },
        ),
      );
    } else {
        // Fallback if no callback provided (old behavior)
        dio.interceptors.add(
            InterceptorsWrapper(
                onError: (error, handler) async {
                    if (error.response?.statusCode == 401) {
                        await clearToken();
                    }
                    return handler.next(error);
                },
            ),
        );
    }
  }

  // Token management with fallback to memory
  Future<void> saveToken(String token) async {
    _memoryToken = token;
    try {
      await storage.write(key: 'auth_token', value: token);
    } catch (e) {
      // Ignore storage errors, use memory storage as fallback
    }
  }

  Future<String?> getToken() async {
    // Try memory first
    if (_memoryToken != null) {
      return _memoryToken;
    }

    // Try secure storage
    try {
      final token = await storage.read(key: 'auth_token');
      if (token != null) {
        _memoryToken = token;
      }
      return token;
    } catch (e) {
      return _memoryToken;
    }
  }

  Future<void> clearToken() async {
    _memoryToken = null;
    try {
      await storage.delete(key: 'auth_token');
    } catch (e) {
      // Ignore storage errors
    }
  }

  Future<bool> isAuthenticated() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // Remember me functionality
  Future<void> saveCredentials(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_username', username);
    await prefs.setString('saved_password', password);
    await prefs.setBool('remember_me', true);
  }

  Future<Map<String, String>?> getSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool('remember_me') ?? false;

    if (!rememberMe) return null;

    final username = prefs.getString('saved_username');
    final password = prefs.getString('saved_password');

    if (username != null && password != null) {
      return {'username': username, 'password': password};
    }

    return null;
  }

  Future<void> clearSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_username');
    await prefs.remove('saved_password');
    await prefs.setBool('remember_me', false);
  }

  // Generic request methods
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      return await dio.get(path, queryParameters: queryParameters);
    } catch (e) {
      rethrow;
    }
  }

  Future<Response> post(
    String path, {
    dynamic data,
    int maxRetries = 3,
    Options? options,
  }) async {
    return _networkHandler.retryWithBackoff(
      maxRetries: maxRetries,
      initialDelay: const Duration(seconds: 1),
      checkNetwork: false, // ApiClient handles connection errors internally often, or we rely on Handler
      shouldRetry: (e) => _isRetriableError(e),
      operation: () async {
        // DEBUG: Request деректерін log-қа жазу
        print('🌐 API POST Request: $path');
        // (Logging truncated for brevity, but original logic was good)
        
        try {
           final response = await dio.post(path, data: data, options: options);
           return response;
        } catch (e) {
           // Rethrow to let retry handler catch it, but log specific details if needed
           if (e is DioException) {
              print('❌ API Error: ${e.response?.statusCode ?? e.type}');
           }
           rethrow;
        }
      },
    );
  }

  bool _isRetriableError(dynamic error) {
    // Retry on network errors, timeouts, and 5xx server errors
    if (error is DioException) {
      return error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError ||
          (error.response?.statusCode != null &&
              error.response!.statusCode! >= 500);
    }
    return false;
  }

  Future<Response> put(String path, {dynamic data}) async {
    try {
      return await dio.put(path, data: data);
    } catch (e) {
      rethrow;
    }
  }

  Future<Response> delete(String path) async {
    try {
      return await dio.delete(path);
    } catch (e) {
      rethrow;
    }
  }

  // File upload
  Future<Response> uploadFile(
    String path,
    String filePath, {
    Map<String, dynamic>? data,
    ProgressCallback? onProgress,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
        ...?data,
      });

      return await dio.post(path, data: formData, onSendProgress: onProgress);
    } catch (e) {
      rethrow;
    }
  }
}
