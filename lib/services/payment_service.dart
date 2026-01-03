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
      
      // Check if response is HTML (indicates endpoint doesn't exist)
      if (response.data is String && (response.data as String).contains('<html')) {
        print('Backend subscription endpoint not implemented yet');
        return [];
      }
      
      print('Raw subscription response: ${response.data}');
      
      // Handle different response formats
      final dynamic plansData = response.data is Map ? response.data['plans'] : response.data;
      
      if (plansData == null) {
        print('No plans data found in response');
        return [];
      }
      
      if (plansData is! List) {
        print('Plans data is not a list: $plansData');
        return [];
      }
      
      final List<dynamic> data = plansData as List<dynamic>;
      print('Number of plans: ${data.length}');
      
      return data.map((json) {
        try {
          return SubscriptionPlan.fromJson(json as Map<String, dynamic>);
        } catch (e) {
          print('Error parsing plan: $json');
          print('Parse error: $e');
          rethrow;
        }
      }).toList();
    } catch (e, stackTrace) {
      print('Error in getSubscriptionPlans: $e');
      print('Backend subscription endpoint may not be implemented yet');
      // Return empty list instead of throwing to prevent app crash
      return [];
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
