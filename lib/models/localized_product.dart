class LocalizedProduct {
  final String planId;
  final String name;
  final String description;
  final double monthlyPrice;
  final String currency;
  final String interval;
  final List<String> features;
  final String? productId;
  final int dailyFreeMinutes;
  final double pricePerMinute;

  LocalizedProduct({
    required this.planId,
    required this.name,
    required this.description,
    required this.monthlyPrice,
    required this.currency,
    required this.interval,
    required this.features,
    this.productId,
    required this.dailyFreeMinutes,
    required this.pricePerMinute,
  });

  factory LocalizedProduct.fromJson(Map<String, dynamic> json) {
    return LocalizedProduct(
      planId: json['planId'] ?? 'unknown',
      name: json['name'] ?? 'Unknown Plan',
      description: json['description'] ?? '',
      monthlyPrice: (json['monthlyPrice'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] ?? 'USD',
      interval: json['interval'] ?? 'month',
      features: List<String>.from(json['features'] ?? []),
      productId: json['productId'],
      dailyFreeMinutes: json['dailyFreeMinutes'] ?? 0,
      pricePerMinute: (json['pricePerMinute'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
