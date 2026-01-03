import 'package:dio/dio.dart';
import 'api_client.dart';
import '../models/localized_product.dart';

class SubscriptionServiceNew {
  final ApiClient _apiClient;

  SubscriptionServiceNew(this._apiClient);

  /// Локализацияланған жазылым өнімдерін алу
  Future<List<LocalizedProduct>> getLocalizedProducts({
    required String platform, // 'ios', 'android', 'web'
    required String language,  // 'en', 'kk', 'ru', etc.
  }) async {
    try {
      final response = await _apiClient.get(
        '/api/subscription/products/localized',
        queryParameters: {
          'platform': platform,
          'lang': language,
        },
      );

      final products = response.data['products'] as List;
      return products.map((json) => LocalizedProduct.fromJson(json)).toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  String _handleError(DioException e) {
    if (e.response != null) {
      return e.response?.data['message'] ?? 'Unknown error';
    }
    return e.message ?? 'Network error';
  }
}
