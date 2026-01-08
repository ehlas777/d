import 'dart:convert';

import 'package:dio/dio.dart';
import '../utils/dio_error_formatter.dart';
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
      
      final message = DioErrorFormatter.format(e, defaultMessage: 'Login failed');
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
      final message = DioErrorFormatter.format(e, defaultMessage: 'Registration failed');
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
    String? searchQuery,
  }) async {
    if (!await isAuthenticated()) {
      print('getUserMinutesInfo skipped: not authenticated');
      return null;
    }

    String? queryToUse = searchQuery?.trim();

    if (queryToUse == null || queryToUse.isEmpty) {
      // If no query provided, fetch current user profile first
      try {
        final currentUser = await getCurrentUser();
        if (currentUser?.success == true) {
          queryToUse = currentUser?.username ?? currentUser?.email;
        }
      } catch (e) {
        print('Error fetching current user for minutes lookup: $e');
      }
    }

    if (queryToUse == null || queryToUse.isEmpty) {
      print('getUserMinutesInfo skipped: could not determine user to lookup');
      return null;
    }

    try {
      final response = await apiClient.get(
        '/api/TranslationStats/user-balance',
        queryParameters: {'search': queryToUse},
      );

      final data = _normalizeResponseData(response.data);
      
      // DEBUG: Backend response-ін толық көру
      print('🔍 Backend user-balance response:');
      print('   Raw data: $data');
      if (data is Map<String, dynamic>) {
        print('   hasUnlimitedAccess: ${data['hasUnlimitedAccess']}');
        print('   subscriptionStatus: ${data['subscriptionStatus']}');
        print('   balanceMinutes: ${data['balanceMinutes']}');
        print('   usedMinutes: ${data['usedMinutes']}');  // ⚠️ CRITICAL: Check if backend returns this
        print('   totalLimit: ${data['totalLimit']}');
        print('   dailyRemainingMinutes: ${data['dailyRemainingMinutes']}');
        print('   extraMinutes: ${data['extraMinutes']}');
        return User.fromJson(data);
      }

      throw Exception('Unexpected minutes response type: ${data.runtimeType}');
    } on DioException catch (e) {
      final message = DioErrorFormatter.format(e, defaultMessage: 'Failed to load minutes');
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
