import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdService {
  static const String _deviceIdKey = 'device_id';
  
  /// Құрылғы ID-ін алу немесе жасау
  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Сақталған ID бар ма екенін тексеру
    String? savedId = prefs.getString(_deviceIdKey);
    if (savedId != null && savedId.isNotEmpty) {
      return savedId;
    }
    
    // Жаңа ID жасау
    String deviceId = await _generateDeviceId();
    await prefs.setString(_deviceIdKey, deviceId);
    return deviceId;
  }
  
  /// Платформаға қарай уникальды ID жасау
  static Future<String> _generateDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        // Android ID немесе serial number қолдану
        return 'android_${androidInfo.id}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        // iOS үшін identifierForVendor қолдану
        return 'ios_${iosInfo.identifierForVendor ?? _generateRandomId()}';
      }
    } catch (e) {
      print('Error generating device ID: $e');
    }
    
    // Fallback: random ID
    return _generateRandomId();
  }
  
  static String _generateRandomId() {
    return 'device_${DateTime.now().millisecondsSinceEpoch}';
  }
}
