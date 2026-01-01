import '../models/payment_models.dart';
import 'api_client.dart';

class PaymentService {
  final ApiClient apiClient;

  PaymentService(this.apiClient);

  // Payment Methods
  Future<List<PaymentMethod>> getPaymentMethods() async {
    try {
      final response = await apiClient.get('/api/payment/methods');
      final List<dynamic> data = response.data['paymentMethods'];
      return data.map((json) => PaymentMethod.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to load payment methods: $e');
    }
  }

  Future<PaymentResult> addPaymentMethod(String paymentMethodId) async {
    try {
      final response = await apiClient.post(
        '/api/payment/methods',
        data: {'paymentMethodId': paymentMethodId},
      );
      return PaymentResult.fromJson(response.data);
    } catch (e) {
      return PaymentResult(
        success: false,
        message: 'Failed to add payment method: $e',
      );
    }
  }

  Future<bool> deletePaymentMethod(String paymentMethodId) async {
    try {
      await apiClient.delete('/api/payment/methods/$paymentMethodId');
      return true;
    } catch (e) {
      return false;
    }
  }

  // Subscription Plans
  Future<List<SubscriptionPlan>> getSubscriptionPlans() async {
    try {
      final response = await apiClient.get('/api/payment/subscription/plans');
      final List<dynamic> data = response.data['plans'];
      return data.map((json) => SubscriptionPlan.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to load subscription plans: $e');
    }
  }

  // Subscribe
  Future<PaymentResult> subscribe({
    required String planId,
    String? paymentMethodId,
  }) async {
    try {
      final response = await apiClient.post(
        '/api/payment/subscription/subscribe',
        data: {
          'planId': planId,
          if (paymentMethodId != null) 'paymentMethodId': paymentMethodId,
        },
      );
      return PaymentResult.fromJson(response.data);
    } catch (e) {
      return PaymentResult(
        success: false,
        message: 'Failed to subscribe: $e',
      );
    }
  }

  // Current Subscription
  Future<Subscription?> getCurrentSubscription() async {
    try {
      final response = await apiClient.get('/api/payment/subscription/current');
      if (response.data['subscription'] != null) {
        return Subscription.fromJson(response.data['subscription']);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Cancel Subscription
  Future<bool> cancelSubscription() async {
    try {
      final response = await apiClient.post('/api/payment/subscription/cancel');
      return response.data['success'] ?? false;
    } catch (e) {
      return false;
    }
  }

  // Book Purchase
  Future<PaymentResult> purchaseBook({
    required String bookId,
    String? paymentMethodId,
  }) async {
    try {
      final response = await apiClient.post(
        '/api/payment/books/purchase',
        data: {
          'bookId': bookId,
          if (paymentMethodId != null) 'paymentMethodId': paymentMethodId,
        },
      );
      return PaymentResult.fromJson(response.data);
    } catch (e) {
      return PaymentResult(
        success: false,
        message: 'Failed to purchase book: $e',
      );
    }
  }

  // Transaction History
  Future<List<Transaction>> getTransactions({int page = 1, int limit = 20}) async {
    try {
      final response = await apiClient.get(
        '/api/payment/transactions',
        queryParameters: {'page': page, 'limit': limit},
      );
      final List<dynamic> data = response.data['transactions'];
      return data.map((json) => Transaction.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Failed to load transactions: $e');
    }
  }
}
