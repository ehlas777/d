import 'dart:async';
import 'dart:io';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
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

  /// Initialize IAP connection and set up purchase listener
  Future<bool> initialize() async {
    // Check if IAP is available on this platform
    _isAvailable = await _iap.isAvailable();
    
    if (!_isAvailable) {
      print('In-App Purchase is not available on this platform');
      return false;
    }

    print('IAP Service initializing for ${IAPConfig.platformName}...');

    // Set up purchase update listener
    final Stream<List<PurchaseDetails>> purchaseUpdated = _iap.purchaseStream;
    _subscription = purchaseUpdated.listen(
      _onPurchaseUpdate,
      onDone: _onPurchaseDone,
      onError: _onPurchaseError,
    );

    // Load available products
    await loadProducts();

    return true;
  }

  /// Load available products from App Store / Play Store
  Future<void> loadProducts() async {
    if (!_isAvailable) return;

    print('Loading products for ${IAPConfig.platformName}...');
    print('Product IDs: ${IAPConfig.allProductIds}');

    final ProductDetailsResponse response = await _iap.queryProductDetails(
      IAPConfig.allProductIds.toSet(),
    );

    if (response.error != null) {
      print('Error loading products: ${response.error!.message}');
      throw Exception('Failed to load products: ${response.error!.message}');
    }

    if (response.notFoundIDs.isNotEmpty) {
      print('Products not found: ${response.notFoundIDs}');
    }

    _products = response.productDetails;
    print('Loaded ${_products.length} products');
    for (final product in _products) {
      print('  - ${product.id}: ${product.title} (${product.price})');
    }
  }

  /// Get all available subscription products
  List<ProductDetails> getProducts() {
    return _products;
  }

  /// Convert ProductDetails to SubscriptionPlan model
  SubscriptionPlan productToSubscriptionPlan(ProductDetails product) {
    final tierName = IAPConfig.getTierName(product.id) ?? 'Unknown';
    
    // Parse price from product
    final price = double.tryParse(
      product.price.replaceAll(RegExp(r'[^\d.]'), ''),
    ) ?? 0.0;

    // Get features based on tier
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

    // Extract currency from product if available
    String currency = 'USD';
    if (Platform.isIOS && product is AppStoreProductDetails) {
      currency = product.skProduct.priceLocale.currencyCode;
    } else if (Platform.isAndroid && product is GooglePlayProductDetails) {
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

  /// Purchase a subscription
  Future<bool> purchaseSubscription(String productId) async {
    if (!_isAvailable) {
      throw Exception('In-App Purchase is not available');
    }

    print('Purchasing subscription: $productId');

    final product = _products.firstWhere(
      (p) => p.id == productId,
      orElse: () => throw Exception('Product not found: $productId'),
    );

    final PurchaseParam purchaseParam = PurchaseParam(
      productDetails: product,
    );

    // Use buyNonConsumable for subscriptions (both iOS and Android)
    return await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  /// Restore previous purchases
  Future<void> restorePurchases() async {
    if (!_isAvailable) {
      throw Exception('In-App Purchase is not available');
    }

    print('Restoring purchases...');
    await _iap.restorePurchases();
  }

  /// Handle purchase updates
  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) async {
    for (final purchaseDetails in purchaseDetailsList) {
      print('Purchase update: ${purchaseDetails.productID} - ${purchaseDetails.status}');
      
      if (purchaseDetails.status == PurchaseStatus.pending) {
        // Show pending UI
        print('Purchase pending: ${purchaseDetails.productID}');
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        // Handle error
        print('Purchase error: ${purchaseDetails.error}');
      } else if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {
        // Verify purchase with backend
        final verified = await _verifyPurchase(purchaseDetails);
        
        if (verified) {
          print('✅ Purchase verified: ${purchaseDetails.productID}');
        } else {
          print('❌ Purchase verification failed: ${purchaseDetails.productID}');
        }
      }

      // Complete the purchase
      if (purchaseDetails.pendingCompletePurchase) {
        await _iap.completePurchase(purchaseDetails);
        print('Purchase completed: ${purchaseDetails.productID}');
      }
    }
  }

  /// Verify purchase with backend
  Future<bool> _verifyPurchase(PurchaseDetails purchaseDetails) async {
    try {
      if (Platform.isIOS) {
        // iOS: Verify Apple receipt
        final iosPurchaseDetails = purchaseDetails as AppStorePurchaseDetails;
        final receiptData = iosPurchaseDetails.verificationData.serverVerificationData;

        print('Verifying Apple receipt...');
        return await subscriptionApiService.verifyAppleReceipt(
          receiptData: receiptData,
          productId: purchaseDetails.productID,
          transactionId: purchaseDetails.purchaseID,
        );
      } else if (Platform.isAndroid) {
        // Android: Verify Google purchase token
        final androidPurchaseDetails = purchaseDetails as GooglePlayPurchaseDetails;
        final purchaseToken = androidPurchaseDetails.verificationData.serverVerificationData;
        
        print('Verifying Google purchase...');
        return await subscriptionApiService.verifyGooglePurchase(
          purchaseToken: purchaseToken,
          productId: purchaseDetails.productID,
          packageName: 'com.qaznat.polydub', // Should match your app's package name
        );
      }

      return false;
    } catch (e) {
      print('Error verifying purchase: $e');
      return false;
    }
  }

  /// Handle purchase stream done
  void _onPurchaseDone() {
    print('Purchase stream done');
  }

  /// Handle purchase stream error
  void _onPurchaseError(error) {
    print('Purchase stream error: $error');
  }

  /// Check if user has active subscription
  Future<bool> hasActiveSubscription() async {
    if (!_isAvailable) return false;

    try {
      // Check with backend for active subscription status
      final subscription = await subscriptionApiService.getCurrentSubscription();
      return subscription != null && subscription.status == 'active';
    } catch (e) {
      print('Error checking subscription status: $e');
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    _subscription?.cancel();
  }
}
