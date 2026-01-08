import 'package:dio/dio.dart';

class DioErrorFormatter {
  static String format(DioException e, {String? defaultMessage}) {
    // Timeout errors
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Connection timeout. Is the server running?';
    }

    // Connection errors
    if (e.type == DioExceptionType.connectionError) {
      return 'Cannot connect to server. Check your internet connection.';
    }

    // Security errors
    if (e.type == DioExceptionType.badCertificate) {
      return 'Network security error (bad certificate).';
    }

    // Cancellation
    if (e.type == DioExceptionType.cancel) {
      return 'Request cancelled.';
    }

    // Response-based errors
    if (e.response != null) {
      return _extractFromResponse(e.response!.data, defaultMessage, statusCode: e.response?.statusCode);
    }

    // Generic fallback
    return e.message ?? defaultMessage ?? 'Network error';
  }

  static String _extractFromResponse(
    dynamic data,
    String? fallback, {
    int? statusCode,
  }) {
    final effectiveFallback = fallback ?? 'Error';

    if (data == null) {
      return statusCode != null ? '$effectiveFallback: $statusCode' : effectiveFallback;
    }

    if (data is String) {
      final trimmed = data.trim();
      if (trimmed.isNotEmpty) {
        // Clean up excessively long HTML/stacktrace dumps if they occur
        if (trimmed.length > 300) return '${trimmed.substring(0, 300)}...';
        return trimmed;
      }
    }

    if (data is Map) {
      // Try common error keys used in Qaznat backend
      // Based on analysis of AuthService and BackendTranslationService
      final keys = ['message', 'Message', 'error', 'Error', 'detail', 'title', 'errorMessage'];
      for (final key in keys) {
        final value = data[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }

      // Try 'errors' object (ASP.NET Core validation errors often look like this)
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

    return statusCode != null ? '$effectiveFallback: $statusCode' : effectiveFallback;
  }
}
