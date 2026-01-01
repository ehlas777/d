import 'package:shared_preferences/shared_preferences.dart';

/// Қолданушы параметрлерін сақтау және жүктеу сервисі
class SettingsService {
  static const String _speedMultiplierKey = 'speed_multiplier';
  static const double _defaultSpeedMultiplier = 1.0;

  /// Соңғы видео жылдамдығын сақтау
  Future<void> saveSpeedMultiplier(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_speedMultiplierKey, value);
  }

  /// Соңғы видео жылдамдығын жүктеу
  Future<double> loadSpeedMultiplier() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_speedMultiplierKey) ?? _defaultSpeedMultiplier;
  }

  /// Барлық параметрлерді тазалау (қажет болса)
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
