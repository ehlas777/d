import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class AuthInterceptor extends Interceptor {
  final Dio dio;
  final VoidCallback onSessionExpired;

  AuthInterceptor({
    required this.dio,
    required this.onSessionExpired,
  });

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      // Check if it's a session conflict (optional, or just logout on any 401)
      final data = err.response?.data;
      if (data is Map && (data['code'] == 'SESSION_CONFLICT' || data['error'] == 'Session expired')) {
        onSessionExpired();
      } else {
        // Handle other 401s (e.g. invalid token) as logout too
        onSessionExpired();
      }
    }
    super.onError(err, handler);
  }
}
