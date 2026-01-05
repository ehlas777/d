import 'dart:convert';

import 'package:dio/dio.dart';
import '../models/auth_models.dart';
import 'api_client.dart';

class AuthService {
  final ApiClient apiClient;

  AuthService(this.apiClient);

  Future<AuthResponse> login(String username, String password) async {
    try {
      print('=== Login attempt ===');
      print('Username: $username');
      print('API baseUrl: ${apiClient.dio.options.baseUrl}');
      
      final response = await apiClient.post(
        '/api/auth/login',
        data: LoginRequest(username: username, password: password).toJson(),
      );

      print('Login response status: ${response.statusCode}');
      print('Login response data: ${response.data}');

      final authResponse = AuthResponse.fromJson(response.data);

      if (authResponse.success && authResponse.token != null) {
        print('Login successful, saving token');
        await apiClient.saveToken(authResponse.token!);
      } else {
        print('Login failed: ${authResponse.message}');
      }

      return authResponse;
    } on DioException catch (e) {
      print('=== Login DioException ===');
      print('Type: ${e.type}');
      print('Message: ${e.message}');
      print('Response: ${e.response?.data}');
      print('Status code: ${e.response?.statusCode}');
      
      final message = _formatDioError(e, defaultMessage: 'Login failed');
      print('Formatted error: $message');
      
      return AuthResponse(
        success: false,
        message: message,
      );
    } catch (e) {
      print('=== Login unknown error ===');
      print('Error: $e');
      
      return AuthResponse(
        success: false,
        message: 'An error occurred: $e',
      );
    }
  }

  Future<AuthResponse> register(String username, String email, String password) async {
    try {
      final response = await apiClient.post(
        '/api/auth/register',
        data: RegisterRequest(
          username: username,
          password: password,
          email: email,
        ).toJson(),
      );

      final authResponse = AuthResponse.fromJson(response.data);

      if (authResponse.success && authResponse.token != null) {
        await apiClient.saveToken(authResponse.token!);
      }

      return authResponse;
    } on DioException catch (e) {
      final message = _formatDioError(e, defaultMessage: 'Registration failed');
      return AuthResponse(
        success: false,
        message: message,
      );
    } catch (e) {
      return AuthResponse(
        success: false,
        message: 'An error occurred: $e',
      );
    }
  }

  Future<void> logout() async {
    await apiClient.clearToken();
  }

  Future<bool> isAuthenticated() async {
    return await apiClient.isAuthenticated();
  }

  Future<AuthResponse?> getCurrentUser() async {
    try {
      final response = await apiClient.get('/api/user/profile');
      return AuthResponse.fromJson(response.data);
    } catch (e) {
      return null;
    }
  }

  Future<bool> deleteAccount() async {
    try {
      final response = await apiClient.delete('/api/user/profile');
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      print('Error deleting account: $e');
      return false;
    }
  }

  // Пайдаланушы минуттар ақпаратын алу
  Future<User?> getUserMinutesInfo({
    required String searchQuery,
  }) async {
    final normalizedQuery = searchQuery.trim();

    if (normalizedQuery.isEmpty) {
      print('getUserMinutesInfo skipped: empty search query');
      return null;
    }

    if (!await isAuthenticated()) {
      print('getUserMinutesInfo skipped: not authenticated');
      return null;
    }

    try {
      final response = await apiClient.get(
        '/api/TranslationStats/user-balance',
        queryParameters: {'search': normalizedQuery},
      );

      final data = _normalizeResponseData(response.data);
      if (data is Map<String, dynamic>) {
        return User.fromJson(data);
      }

      throw Exception('Unexpected minutes response type: ${data.runtimeType}');
    } on DioException catch (e) {
      final message = _formatDioError(e, defaultMessage: 'Failed to load minutes');
      print('Error getting user minutes info: $message');

      // Try legacy endpoint as a fallback (older backend builds)
      try {
        final legacyResponse = await apiClient.get('/api/user/minutes');
        final legacyData = _normalizeResponseData(legacyResponse.data);
        if (legacyData is Map<String, dynamic>) {
          return User.fromJson(legacyData);
        }
      } catch (_) {
        // Ignore legacy fallback failures
      }

      return null;
    } catch (e) {
      print('Error getting user minutes info: $e');
      return null;
    }
  }

  // Видео аудару алдында минуттар тексеру
  Future<bool> checkMinutesAvailability(double requiredMinutes) async {
    try {
      final response = await apiClient.post(
        '/api/user/check-minutes',
        data: {'requiredMinutes': requiredMinutes},
      );
      return response.data['available'] ?? false;
    } catch (e) {
      print('Error checking minutes availability: $e');
      return false;
    }
  }

  String _formatDioError(
    DioException e, {
    required String defaultMessage,
  }) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Connection timeout. Is the server running?';
    }

    if (e.type == DioExceptionType.connectionError) {
      return 'Cannot connect to server at ${apiClient.dio.options.baseUrl}';
    }

    if (e.response != null) {
      return _extractErrorMessage(
        e.response?.data,
        defaultMessage,
        statusCode: e.response?.statusCode,
      );
    }

    return 'Network error: ${e.message}';
  }

  String _extractErrorMessage(
    dynamic data,
    String fallback, {
    int? statusCode,
  }) {
    if (data == null) {
      return statusCode != null ? '$fallback: $statusCode' : fallback;
    }

    if (data is String) {
      final trimmed = data.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }

    if (data is Map) {
      final keys = ['message', 'Message', 'error', 'Error', 'detail', 'title'];
      for (final key in keys) {
        final value = data[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }

      final errors = data['errors'];
      if (errors is Map) {
        final messages = <String>[];
        errors.forEach((_, value) {
          if (value is List) {
            messages.addAll(value.whereType<String>());
          } else if (value is String) {
            messages.add(value);
          }
        });
        if (messages.isNotEmpty) {
          return messages.join(', ');
        }
      }
    }

    return statusCode != null ? '$fallback: $statusCode' : fallback;
  }

  dynamic _normalizeResponseData(dynamic data) {
    if (data is String) {
      final trimmed = data.trim();
      if (trimmed.isEmpty) return trimmed;
      try {
        return jsonDecode(trimmed);
      } catch (_) {
        return trimmed;
      }
    }
    return data;
  }
}
