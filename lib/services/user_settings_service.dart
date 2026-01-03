import 'package:dio/dio.dart';
import 'api_client.dart';
import '../models/user_settings.dart';

class UserSettingsService {
  final ApiClient _apiClient;

  UserSettingsService(this._apiClient);

  /// Қолданушы баптауларын алу
  Future<UserSettings> getUserSettings(AppType appType) async {
    try {
      final response = await _apiClient.get(
        '/api/user/settings',
        queryParameters: {'appType': appType.value},
      );

      return UserSettings.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Қолданушы баптауларын жаңарту
  Future<UserSettings> updateUserSettings({
    required AppType appType,
    String? interfaceLanguage,
    Map<String, dynamic>? settings,
  }) async {
    try {
      final response = await _apiClient.put(
        '/api/user/settings',
        data: {
          'appType': appType.value,
          if (interfaceLanguage != null) 'interfaceLanguage': interfaceLanguage,
          if (settings != null) 'settings': settings,
        },
      );

      return UserSettings.fromJson(response.data['settings']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  String _handleError(DioException e) {
    if (e.response != null) {
      return e.response?.data['error'] ?? 'Unknown error';
    }
    return e.message ?? 'Network error';
  }
}
