import 'dart:convert';
import 'package:http/http.dart' as http;
import 'device_id_service.dart';

class TrialApiService {
  static const String baseUrl = 'https://qaznat.kz'; // Production URL
  
  /// Trial мүмкіндігін тексеру
  static Future<TrialCheckResponse> checkTrial() async {
    try {
      final deviceId = await DeviceIdService.getDeviceId();
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/translation/check-trial'),
        headers: {
          'X-Device-ID': deviceId,
          'Content-Type': 'application/json',
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return TrialCheckResponse.fromJson(data);
      } else {
        throw Exception('Failed to check trial: ${response.statusCode}');
      }
    } catch (e) {
      print('Error checking trial: $e');
      rethrow;
    }
  }
  
  /// Trial-ды аяқталған деп белгілеу
  static Future<TrialCompleteResponse> completeTrial({
    String? videoFileName,
    int? durationSeconds,
  }) async {
    try {
      final deviceId = await DeviceIdService.getDeviceId();
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/translation/complete-trial'),
        headers: {
          'X-Device-ID': deviceId,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          if (videoFileName != null) 'videoFileName': videoFileName,
          if (durationSeconds != null) 'durationSeconds': durationSeconds,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return TrialCompleteResponse.fromJson(data);
      } else {
        throw Exception('Failed to complete trial: ${response.statusCode}');
      }
    } catch (e) {
      print('Error completing trial: $e');
      rethrow;
    }
  }
}

/// Trial status response моделі
class TrialCheckResponse {
  final bool canUseTrial;
  final int attemptsRemaining;
  final int maxVideoDuration;
  final String message;
  
  TrialCheckResponse({
    required this.canUseTrial,
    required this.attemptsRemaining,
    required this.maxVideoDuration,
    required this.message,
  });
  
  factory TrialCheckResponse.fromJson(Map<String, dynamic> json) {
    return TrialCheckResponse(
      canUseTrial: json['canUseTrial'] ?? false,
      attemptsRemaining: json['attemptsRemaining'] ?? 0,
      maxVideoDuration: json['maxVideoDuration'] ?? 60,
      message: json['message'] ?? '',
    );
  }
}

/// Trial completion response моделі
class TrialCompleteResponse {
  final bool success;
  final int attemptsRemaining;
  final String message;
  
  TrialCompleteResponse({
    required this.success,
    required this.attemptsRemaining,
    required this.message,
  });
  
  factory TrialCompleteResponse.fromJson(Map<String, dynamic> json) {
    return TrialCompleteResponse(
      success: json['success'] ?? false,
      attemptsRemaining: json['attemptsRemaining'] ?? 0,
      message: json['message'] ?? '',
    );
  }
}
