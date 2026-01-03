import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/user_settings_service.dart';
import '../models/user_settings.dart';

class AppSettingsProvider extends ChangeNotifier {
  final UserSettingsService _settingsService;
  UserSettings? _currentSettings;
  bool _isLoading = false;

  AppSettingsProvider(this._settingsService);

  UserSettings? get currentSettings => _currentSettings;
  bool get isLoading => _isLoading;

  /// Қолданбаны іске қосқанда баптауларды жүктеу
  Future<void> loadSettings(AppType appType) async {
    _isLoading = true;
    notifyListeners();

    try {
      _currentSettings = await _settingsService.getUserSettings(appType);
      
      // Apply interface language if needed
      if (_currentSettings?.interfaceLanguage != null) {
        await _saveLanguageToPrefs(_currentSettings!.interfaceLanguage);
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Интерфейс тілін өзгерту
  Future<void> changeLanguage(AppType appType, String languageCode) async {
    try {
      // Optimistic update locally
      // (This assumes your app listens to SharedPreferences or has another LocaleProvider)
      await _saveLanguageToPrefs(languageCode);

      _currentSettings = await _settingsService.updateUserSettings(
        appType: appType,
        interfaceLanguage: languageCode,
      );
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error changing language: $e');
      rethrow;
    }
  }

  /// Баптауларды жаңарту
  Future<void> updateSettings(
    AppType appType,
    Map<String, dynamic> settings,
  ) async {
    try {
      _currentSettings = await _settingsService.updateUserSettings(
        appType: appType,
        settings: settings,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating settings: $e');
      rethrow;
    }
  }

  Future<void> _saveLanguageToPrefs(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', languageCode);
  }
}
