import 'dart:io';
import '../config/iap_config.dart';
import '../models/payment_models.dart';
import 'iap_service.dart';
import 'subscription_api_service.dart';
import 'subscription_service_new.dart';

/// Platform-aware payment routing service
/// Routes to IAP on iOS/Android, backend service for web/desktop
class PlatformPaymentRouter {
  final IAPService? iapService;
  final SubscriptionApiService subscriptionApiService;
  final SubscriptionServiceNew? subscriptionServiceNew; // Added

  PlatformPaymentRouter({
    this.iapService,
    required this.subscriptionApiService,
    this.subscriptionServiceNew, // Added
  });

  /// Check if current platform should use IAP (iOS, macOS, or Android)
  bool get shouldUseIAP => Platform.isIOS || Platform.isAndroid || Platform.isMacOS;

  /// Get platform name for logging
  String get platformName => IAPConfig.platformName;

  /// Initialize payment services
  Future<void> initialize() async {
    print('Initializing payment services for $platformName...');
    
    if (shouldUseIAP && iapService != null) {
      final success = await iapService!.initialize();
      if (success) {
        print('IAP service initialized successfully');
      } else {
        print('IAP service initialization failed');
      }
    } else {
      print('Using web payment service (no IAP)');
    }
  }

  /// Get available subscription plans
  /// Priority: Backend API (Localized) → IAP Store (fallback)
  Future<List<SubscriptionPlan>> getSubscriptionPlans({String languageCode = 'en'}) async {
    try {
      print('Fetching subscription plans from backend (localized)...');
      
      List<SubscriptionPlan> backendPlans = [];

      // Try using new localized service first
      if (subscriptionServiceNew != null) {
        try {
          final platform = Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'web');
          final localizedProducts = await subscriptionServiceNew!.getLocalizedProducts(
            platform: platform,
            language: languageCode,
          );
          
          backendPlans = localizedProducts.map((p) => SubscriptionPlan(
            id: p.planId,
            name: p.name,
            description: p.description,
            price: p.monthlyPrice,
            currency: p.currency,
            interval: p.interval,
            features: p.features,
            productId: p.productId,
          )).toList();
        } catch (e) {
          print('Error fetching localized plans: $e');
        }
      }

      // Fallback to old service if no plans found
      if (backendPlans.isEmpty) {
         try {
           final oldPlans = await subscriptionApiService.getProducts(languageCode: languageCode);
           backendPlans = oldPlans;
         } catch(e) {
           print('Error fetching old plans: $e');
         }
      }
      
      if (backendPlans.isNotEmpty) {
        print('Loaded ${backendPlans.length} plans from backend');
        
        if (shouldUseIAP && iapService != null) {
          // Ensure IAP products are loaded for purchase capability
          if (iapService!.getProducts().isEmpty) {
            print('Preloading IAP products...');
            iapService!.loadProducts().catchError((e) {
              print('Error loading IAP products: $e');
            });
          }
          
          // Map backend plans to include correct IAP Product IDs
          return backendPlans.map((plan) {
            // Use productId from backend if available, otherwise map from name
            String? productId = plan.productId;
            
            if (productId == null || productId.isEmpty) {
              productId = IAPConfig.getProductIdForTier(plan.name);
            }

            return SubscriptionPlan(
              id: plan.id,
              name: plan.name,
              description: plan.description,
              price: plan.price,
              currency: plan.currency,
              interval: plan.interval,
              features: List<String>.from(plan.features),
              productId: productId,
            );
          }).toList();
        }
        
        return backendPlans;
      }
      
      // 2. Fallback to IAP products if backend returns empty
      if (shouldUseIAP && iapService != null) {
        print('Backend returned empty, using IAP products as fallback');
        final products = iapService!.getProducts();
        if (products.isNotEmpty) {
          return products.map((p) => iapService!.productToSubscriptionPlan(p)).toList();
        }
      }
      
      print('No subscription plans available');
      return [];
    } catch (e) {
      print('Error fetching plans from backend: $e');
      
      // Fallback to IAP products if backend fails
      if (shouldUseIAP && iapService != null) {
        final products = iapService!.getProducts();
        if (products.isNotEmpty) {
          print('Using IAP products as fallback (${products.length} products)');
          return products.map((p) => iapService!.productToSubscriptionPlan(p)).toList();
        }
      }
      
      return [];
    }
  }

  /// Subscribe to a plan
  Future<PaymentResult> subscribe({
    required String planId,
    String? iapProductId,
    String? paymentMethodId,
  }) async {
    print('Subscribing to plan: $planId (platform: $platformName)');
    
    if (shouldUseIAP) {
      if (iapService != null) {
        // Use IAP for iOS/Android
        try {
          // Use the IAP product ID if provided, otherwise use planId
          final productId = iapProductId ?? planId;
          print('Initiating IAP purchase for product: $productId');
          
          final success = await iapService!.purchaseSubscription(productId);
          return PaymentResult(
            success: success,
            message: success 
                ? 'Subscription purchase initiated. Please complete the purchase.'
                : 'Failed to initiate subscription purchase',
          );
        } catch (e) {
          print('IAP purchase error: $e');
          
          // Provide more helpful error message for product not found
          String userMessage = 'Purchase error: $e';
          if (e.toString().contains('Product not found')) {
            userMessage = 'Unable to load subscription products.\n\n'
                'This usually means:\n'
                '• Products need to be configured in App Store Connect\n'
                '• Agreements and banking info must be completed\n\n'
                'Please contact support if this issue persists.';
          }
          
          return PaymentResult(
            success: false,
            message: userMessage,
          );
        }
      } else {
        return PaymentResult(
          success: false,
          message: 'In-App Purchase service not initialized',
        );
      }
    } else {
      // For web/desktop without IAP, we cannot offer subscriptions currently
      // to remain compliant with App Store guidelines if this code is shared.
      // If this is a purely web build, different logic applies, but for
      // the shared codebase delivered to App Store, we must be strict.
      
      return PaymentResult(
        success: false,
        message: 'Subscriptions are currently only available on mobile devices.',
      );
    }
  }

  /// Get current active subscription
  Future<Subscription?> getCurrentSubscription() async {
    try {
      return await subscriptionApiService.getCurrentSubscription();
    } catch (e) {
      print('Error getting current subscription: $e');
      return null;
    }
  }

  /// Check if user has active subscription
  Future<bool> hasActiveSubscription() async {
    if (shouldUseIAP && iapService != null) {
      return await iapService!.hasActiveSubscription();
    } else {
      final subscription = await getCurrentSubscription();
      return subscription != null && subscription.status == 'active';
    }
  }

  /// Cancel subscription
  Future<bool> cancelSubscription() async {
    if (shouldUseIAP) {
      // On iOS/Android, users must cancel through store settings
      // We mark it for cancellation in backend
      print('Note: On $platformName, cancel subscription in store settings');
      return await subscriptionApiService.cancelSubscription();
    } else {
      return await subscriptionApiService.cancelSubscription();
    }
  }

  /// Restore purchases (iOS/Android only)
  Future<void> restorePurchases() async {
    if (shouldUseIAP && iapService != null) {
      print('Restoring purchases for $platformName...');
      await iapService!.restorePurchases();
    } else {
      print('Restore purchases is only available on supported platforms');
    }
  }

  /// Dispose resources
  void dispose() {
    iapService?.dispose();
  }
}
