import 'dart:io';

/// Configuration for In-App Purchase product IDs (iOS and Android)
class IAPConfig {
  // ========== iOS Product IDs (App Store Connect) ==========
  static const String iosProductIdStandard = 'com.qaznat.polydub.subscription.standard_monthly';
  static const String iosProductIdPro = 'com.qaznat.polydub.subscription.pro_monthly';

  // ========== Android Product IDs (Google Play Console) ==========
  // NOTE: Android-тағы productId-лер Play Console-дағы нақты ID-мен 1:1 сәйкес болуы тиіс.
  // Егер сенде Android-та әлі ескі болса, сол күйі қалдыр:
  static const String androidProductIdStandard = 'polydub_standard_monthly';
  static const String androidProductIdPro = 'polydub_pro_monthly';

  /// Get platform-specific product ID for Standard tier
  static String get productIdStandard =>
      (Platform.isIOS || Platform.isMacOS) ? iosProductIdStandard : androidProductIdStandard;

  /// Get platform-specific product ID for Pro tier
  static String get productIdPro =>
      (Platform.isIOS || Platform.isMacOS) ? iosProductIdPro : androidProductIdPro;

  /// All subscription product IDs for current platform
  static List<String> get allProductIds =>
      (Platform.isIOS || Platform.isMacOS)
          ? [iosProductIdStandard, iosProductIdPro]
          : [androidProductIdStandard, androidProductIdPro];

  // ========== Product ID Mappings ==========
  static const Map<String, String> iosProductIdToTierName = {
    iosProductIdStandard: 'Standard',
    iosProductIdPro: 'Pro',
  };

  static const Map<String, String> androidProductIdToTierName = {
    androidProductIdStandard: 'Standard',
    androidProductIdPro: 'Pro',
  };

  static String? getTierName(String productId) {
    return iosProductIdToTierName[productId] ?? androidProductIdToTierName[productId];
  }

  static const Map<String, String> tierNameToIosProductId = {
    'Standard': iosProductIdStandard,
    'Pro': iosProductIdPro,
  };

  static const Map<String, String> tierNameToAndroidProductId = {
    'Standard': androidProductIdStandard,
    'Pro': androidProductIdPro,
  };

  static String? getProductIdForTier(String tierName) {
    return (Platform.isIOS || Platform.isMacOS)
        ? tierNameToIosProductId[tierName]
        : tierNameToAndroidProductId[tierName];
  }

  /// iOS Subscription group identifier (App Store Connect-тағы group)
  static const String iosSubscriptionGroupId = 'com.qaznat.polydub.subscriptions';

  static String get platformName =>
      (Platform.isIOS || Platform.isMacOS) ? 'ios'
      : Platform.isAndroid ? 'android'
      : 'unknown';
}