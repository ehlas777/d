import 'dart:async';
import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

import '../config/iap_config.dart';
import '../models/payment_models.dart';
import 'subscription_api_service.dart';

/// Service for handling In-App Purchase operations (iOS and Android)
class IAPService {
  final InAppPurchase _iap = InAppPurchase.instance;
  final SubscriptionApiService subscriptionApiService;

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  List<ProductDetails> _products = [];
  bool _isAvailable = false;

  IAPService(this.subscriptionApiService);

  Future<bool> initialize() async {
    _isAvailable = await _iap.isAvailable();

    if (!_isAvailable) {
      print('In-App Purchase is not available on this platform');
      return false;
    }

    print('IAP Service initializing for ${IAPConfig.platformName}...');

    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: _onPurchaseDone,
      onError: _onPurchaseError,
    );

    await loadProducts();
    return true;
  }

  /// Load available products from App Store / Play Store
  Future<void> loadProducts() async {
    if (!_isAvailable) return;

    print('═══════════════════════════════════════════════════════');
    print('🔄 LOADING IAP PRODUCTS');
    print('═══════════════════════════════════════════════════════');
    print('Platform: ${IAPConfig.platformName}');
    print('OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    print('Device: ${Platform.isIOS ? "iOS Device" : Platform.isMacOS ? "macOS" : Platform.isAndroid ? "Android" : "Unknown"}');
    print('Product IDs to query: ${IAPConfig.allProductIds}');
    print('═══════════════════════════════════════════════════════');

    final response = await _iap.queryProductDetails(IAPConfig.allProductIds.toSet());

    if (response.error != null) {
      print('❌ ERROR loading products: ${response.error!.message}');
      print('   Error code: ${response.error!.code}');
      print('   Error details: ${response.error!.details}');
      throw Exception('Failed to load products: ${response.error!.message}');
    }

    if (response.notFoundIDs.isNotEmpty) {
      print('⚠️  WARNING: Products NOT FOUND:');
      for (final id in response.notFoundIDs) {
        print('   ❌ $id');
      }
    }

    print('📊 SUMMARY: Requested: ${IAPConfig.allProductIds.length}, Found: ${response.productDetails.length}, Missing: ${response.notFoundIDs.length}');

    _products = response.productDetails;

    if (_products.isEmpty) {
      print('⚠️  WARNING: No products were loaded!');
    } else {
      print('✅ Successfully loaded ${_products.length} products:');
      for (final product in _products) {
        print('   📦 ${product.id}');
        print('      Title: ${product.title}');
        print('      Price: ${product.price}');
        print('      Description: ${product.description}');
        if (Platform.isIOS && product is AppStoreProductDetails) {
          print('      Currency: ${product.skProduct.priceLocale.currencyCode}');
          print('      Subscription Group ID: ${product.skProduct.subscriptionGroupIdentifier ?? "None"}');
        }
      }
    }

    print('═══════════════════════════════════════════════════════');
  }

  /// Get diagnostic information about IAP configuration
  Map<String, dynamic> getConfigurationStatus() {
    return {
      'isAvailable': _isAvailable,
      'productsLoaded': _products.length,
      'expectedProducts': IAPConfig.allProductIds.length,
      'productIds': _products.map((p) => p.id).toList(),
      'missingProducts': IAPConfig.allProductIds
          .where((id) => !_products.any((p) => p.id == id))
          .toList(),
      'platform': IAPConfig.platformName,
      'hasConfigurationIssue': _products.isEmpty && _isAvailable,
    };
  }

  List<ProductDetails> getProducts() => _products;

  SubscriptionPlan productToSubscriptionPlan(ProductDetails product) {
    final tierName = IAPConfig.getTierName(product.id) ?? 'Unknown';

    final price = double.tryParse(
          product.price.replaceAll(RegExp(r'[^\d.]'), ''),
        ) ??
        0.0;

    List<String> features = [];
    switch (tierName) {
      case 'Standard':
        features = [
          '10 minutes/day free translation',
          'Basic support',
          'Standard quality',
          'Access to all languages',
        ];
        break;
      case 'Pro':
        features = [
          '30 minutes/day free translation',
          'Priority support',
          'High quality',
          'Advanced features',
          'No watermark',
        ];
        break;
      case 'VIP':
        features = [
          'Unlimited translation',
          'Premium 24/7 support',
          'Highest quality',
          'All features unlocked',
          'Priority processing',
          'Custom branding options',
        ];
        break;
    }

    String currency = 'USD';
    if (Platform.isIOS && product is AppStoreProductDetails) {
      currency = product.skProduct.priceLocale.currencyCode;
    } else if (Platform.isAndroid && product is GooglePlayProductDetails) {
      // Subscription currency is in subscriptionOfferDetails usually,
      // but we keep fallback to avoid crashes.
      currency = product.productDetails.oneTimePurchaseOfferDetails?.priceCurrencyCode ?? 'USD';
    }

    return SubscriptionPlan(
      id: product.id,
      name: tierName,
      description: product.description,
      price: price,
      currency: currency,
      interval: 'month',
      features: features,
      productId: product.id,
    );
  }

  /// Purchase a subscription (fixes productIndex reload bug)
  Future<bool> purchaseSubscription(String productId) async {
    if (!_isAvailable) {
      throw Exception('In-App Purchase is not available');
    }

    print('═══════════════════════════════════════════════════════');
    print('📱 PURCHASE DEBUG INFO');
    print('═══════════════════════════════════════════════════════');
    print('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    print('Requesting Product ID: $productId');
    print('Loaded Products: ${_products.map((p) => p.id).toList()}');
    print('═══════════════════════════════════════════════════════');

    // Ensure products loaded
    if (_products.isEmpty) {
      await loadProducts();
    }

    // Find product
    var idx = _products.indexWhere((p) => p.id == productId);

    // Reload once if not found
    if (idx == -1) {
      print('🔄 Product not in cache, reloading products...');
      await loadProducts();
      idx = _products.indexWhere((p) => p.id == productId);
    }

    if (idx == -1) {
      final availableIds = _products.map((p) => p.id).join(', ');
      final expectedIds = IAPConfig.allProductIds.join(', ');
      
      print('❌ PRODUCT NOT FOUND: $productId');
      print('   Available products: ${availableIds.isEmpty ? "NONE" : availableIds}');
      print('   Expected products: $expectedIds');
      print('   ');
      print('🔍 TROUBLESHOOTING STEPS:');
      print('   1. Check App Store Connect → Subscriptions');
      print('   2. Verify product status is "Ready to Submit" (not "Developer Action Needed")');
      print('   3. Ensure Product ID matches exactly: $productId');
      print('   4. Verify Agreements, Tax, and Banking are complete');
      print('   5. Test on physical device (not simulator)');
      
      throw Exception(
        'Product not found: $productId\n'
        'Available: ${availableIds.isEmpty ? "NONE" : availableIds}\n'
        'Expected: $expectedIds\n'
        'Please check App Store Connect / Play Console configuration.\n'
        'See debugging guide for detailed steps.',
      );
    }

    final product = _products[idx];
    print('✅ Product found: ${product.title} (${product.id})');
    print('   Price: ${product.price}');

    // Build purchase params
    PurchaseParam purchaseParam;

    if (Platform.isAndroid && product is GooglePlayProductDetails) {
      // For subscriptions GooglePlayPurchaseParam is recommended.
      purchaseParam = GooglePlayPurchaseParam(productDetails: product);
    } else {
      purchaseParam = PurchaseParam(productDetails: product);
    }

    print('🛒 Initiating purchase...');

    // NOTE:
    // in_app_purchase package uses buyNonConsumable for "non-consumable products".
    // Many apps still use it for subscriptions and it triggers the store purchase flow.
    // Once products load correctly, this should open the purchase sheet.
    final result = await _iap.buyNonConsumable(purchaseParam: purchaseParam);

    print('Purchase call result (request sent): $result');
    return result;
  }

  Future<void> restorePurchases() async {
    if (!_isAvailable) {
      throw Exception('In-App Purchase is not available');
    }
    print('Restoring purchases...');
    await _iap.restorePurchases();
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) async {
    for (final purchaseDetails in purchaseDetailsList) {
      print('Purchase update: ${purchaseDetails.productID} - ${purchaseDetails.status}');

      if (purchaseDetails.status == PurchaseStatus.pending) {
        print('Purchase pending: ${purchaseDetails.productID}');
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        print('Purchase error: ${purchaseDetails.error}');
      } else if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {
        final verified = await _verifyPurchase(purchaseDetails);

        if (verified) {
          print('✅ Purchase verified: ${purchaseDetails.productID}');
        } else {
          print('❌ Purchase verification failed: ${purchaseDetails.productID}');
        }
      }

      if (purchaseDetails.pendingCompletePurchase) {
        await _iap.completePurchase(purchaseDetails);
        print('Purchase completed: ${purchaseDetails.productID}');
      }
    }
  }

  Future<bool> _verifyPurchase(PurchaseDetails purchaseDetails) async {
    try {
      if (Platform.isIOS) {
        final iosPurchaseDetails = purchaseDetails as AppStorePurchaseDetails;
        final receiptData = iosPurchaseDetails.verificationData.serverVerificationData;

        print('Verifying Apple receipt...');
        return await subscriptionApiService.verifyAppleReceipt(
          receiptData: receiptData,
          productId: purchaseDetails.productID,
          transactionId: purchaseDetails.purchaseID,
        );
      } else if (Platform.isAndroid) {
        final androidPurchaseDetails = purchaseDetails as GooglePlayPurchaseDetails;
        final purchaseToken = androidPurchaseDetails.verificationData.serverVerificationData;

        print('Verifying Google purchase...');
        return await subscriptionApiService.verifyGooglePurchase(
          purchaseToken: purchaseToken,
          productId: purchaseDetails.productID,
          packageName: 'com.qaznat.polydub',
        );
      }

      return false;
    } catch (e) {
      print('Error verifying purchase: $e');
      return false;
    }
  }

  void _onPurchaseDone() {
    print('Purchase stream done');
  }

  void _onPurchaseError(Object error) {
    print('Purchase stream error: $error');
  }

  Future<bool> hasActiveSubscription() async {
    if (!_isAvailable) return false;

    try {
      final subscription = await subscriptionApiService.getCurrentSubscription();
      return subscription != null && subscription.status == 'active';
    } catch (e) {
      print('Error checking subscription status: $e');
      return false;
    }
  }

  void dispose() {
    _subscription?.cancel();
  }
}