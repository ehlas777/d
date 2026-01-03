import 'dart:io';

/// Configuration for In-App Purchase product IDs (iOS and Android)
class IAPConfig {
  // ========== iOS Product IDs (App Store Connect) ==========
  static const String iosProductIdStandard = 'com.qaznat.polydub.subscription.standard';
  static const String iosProductIdPro = 'com.qaznat.polydub.subscription.pro';

  // ========== Android Product IDs (Google Play Console) ==========
  static const String androidProductIdStandard = 'polydub_standard_monthly';
  static const String androidProductIdPro = 'polydub_pro_monthly';

  // ========== Platform-specific Product IDs ==========
  
  /// Get platform-specific product ID for Standard tier
  static String get productIdStandard => 
      (Platform.isIOS || Platform.isMacOS) ? iosProductIdStandard : androidProductIdStandard;

  /// Get platform-specific product ID for Pro tier
  static String get productIdPro => 
      (Platform.isIOS || Platform.isMacOS) ? iosProductIdPro : androidProductIdPro;

  /// All subscription product IDs for current platform
  static List<String> get allProductIds => (Platform.isIOS || Platform.isMacOS)
      ? [iosProductIdStandard, iosProductIdPro]
      : [androidProductIdStandard, androidProductIdPro];

  // ========== Product ID Mappings ==========
  
  /// Map iOS product IDs to tier names
  static const Map<String, String> iosProductIdToTierName = {
    iosProductIdStandard: 'Standard',
    iosProductIdPro: 'Pro',
  };

  /// Map Android product IDs to tier names
  static const Map<String, String> androidProductIdToTierName = {
    androidProductIdStandard: 'Standard',
    androidProductIdPro: 'Pro',
  };

  /// Get tier name from product ID (platform-agnostic)
  static String? getTierName(String productId) {
    return iosProductIdToTierName[productId] ?? 
           androidProductIdToTierName[productId];
  }

  /// Map tier names to iOS product IDs
  static const Map<String, String> tierNameToIosProductId = {
    'Standard': iosProductIdStandard,
    'Pro': iosProductIdPro,
  };

  /// Map tier names to Android product IDs
  static const Map<String, String> tierNameToAndroidProductId = {
    'Standard': androidProductIdStandard,
    'Pro': androidProductIdPro,
  };

  /// Get product ID from tier name for current platform
  static String? getProductIdForTier(String tierName) {
    return (Platform.isIOS || Platform.isMacOS) 
        ? tierNameToIosProductId[tierName]
        : tierNameToAndroidProductId[tierName];
  }

  // ========== Platform-specific Configuration ==========
  
  /// iOS Subscription group identifier (set in App Store Connect)
  static const String iosSubscriptionGroupId = 'com.qaznat.polydub.subscriptions';

  /// Current platform name (macOS uses iOS StoreKit)
  static String get platformName => Platform.isIOS || Platform.isMacOS ? 'ios' : 
                                     Platform.isAndroid ? 'android' : 'unknown';
}
