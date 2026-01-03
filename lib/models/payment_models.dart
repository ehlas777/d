class PaymentMethod {
  final String id;
  final String type;
  final String brand;
  final String last4;
  final int expMonth;
  final int expYear;
  final bool isDefault;

  PaymentMethod({
    required this.id,
    required this.type,
    required this.brand,
    required this.last4,
    required this.expMonth,
    required this.expYear,
    required this.isDefault,
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['id'],
      type: json['type'],
      brand: json['brand'],
      last4: json['last4'],
      expMonth: json['expMonth'],
      expYear: json['expYear'],
      isDefault: json['isDefault'] ?? false,
    );
  }
}

class SubscriptionPlan {
  final String id;
  final String name;
  final String description;
  final double price;
  final String currency;
  final String interval;
  final List<String> features;
  final String? productId; // IAP product ID for iOS

  SubscriptionPlan({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.currency,
    required this.interval,
    required this.features,
    this.productId,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: json['id'] ?? (json['tierName'] as String?)?.toLowerCase() ?? 'unknown',
      name: json['name'] ?? json['tierName'] ?? 'Unknown Plan',
      description: json['description'] ?? '',
      price: (json['price'] ?? json['monthlyPrice'] ?? 0.0).toDouble(),
      currency: json['currency'] ?? 'USD',
      interval: json['interval'] ?? 'month',
      features: List<String>.from(json['features'] ?? []),
      productId: json['productId'],
    );
  }
}

class Subscription {
  final String id;
  final String planId;
  final String status;
  final DateTime currentPeriodStart;
  final DateTime currentPeriodEnd;
  final bool cancelAtPeriodEnd;
  final SubscriptionPlan? plan;
  final String? platform; // 'ios', 'android', 'web', etc.

  Subscription({
    required this.id,
    required this.planId,
    required this.status,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    required this.cancelAtPeriodEnd,
    this.plan,
    this.platform,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) {
    return Subscription(
      id: json['id'],
      planId: json['planId'],
      status: json['status'],
      currentPeriodStart: DateTime.parse(json['currentPeriodStart']),
      currentPeriodEnd: DateTime.parse(json['currentPeriodEnd']),
      cancelAtPeriodEnd: json['cancelAtPeriodEnd'] ?? false,
      plan: json['plan'] != null ? SubscriptionPlan.fromJson(json['plan']) : null,
      platform: json['platform'],
    );
  }
}

class PaymentResult {
  final bool success;
  final String? message;
  final String? subscriptionId;
  final String? transactionId;
  final String? receiptData; // IAP receipt data

  PaymentResult({
    required this.success,
    this.message,
    this.subscriptionId,
    this.transactionId,
    this.receiptData,
  });

  factory PaymentResult.fromJson(Map<String, dynamic> json) {
    return PaymentResult(
      success: json['success'] ?? false,
      message: json['message'],
      subscriptionId: json['subscriptionId'],
      transactionId: json['transactionId'],
      receiptData: json['receiptData'],
    );
  }
}

class Transaction {
  final String id;
  final double amount;
  final String currency;
  final String status;
  final String description;
  final DateTime createdAt;

  Transaction({
    required this.id,
    required this.amount,
    required this.currency,
    required this.status,
    required this.description,
    required this.createdAt,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'],
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'],
      status: json['status'],
      description: json['description'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}
