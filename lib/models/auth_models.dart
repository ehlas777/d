class LoginRequest {
  final String username;
  final String password;

  LoginRequest({
    required this.username,
    required this.password,
  });

  Map<String, dynamic> toJson() => {
        'Username': username,
        'Password': password,
      };
}

class RegisterRequest {
  final String username;
  final String password;
  final String email;
  final String? profileImageUrl;

  RegisterRequest({
    required this.username,
    required this.password,
    required this.email,
    this.profileImageUrl,
  });

  Map<String, dynamic> toJson() => {
        'Username': username,
        'Password': password,
        'Email': email,
        'ProfileImageUrl': profileImageUrl ?? '',
      };
}

class AuthResponse {
  final bool success;
  final String? token;
  final String? userId;
  final String? username;
  final String? email;
  final List<String>? roles;
  final String? message;

  AuthResponse({
    required this.success,
    this.token,
    this.userId,
    this.username,
    this.email,
    this.roles,
    this.message,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    // Check if it's an error response
    if (json['error'] != null) {
      return AuthResponse(
        success: false,
        message: json['error'],
      );
    }

    // Success response - check for either token (login) or userId (registration)
    final hasToken = json['token'] != null;
    final hasUserId = json['userId'] != null;

    return AuthResponse(
      success: hasToken || hasUserId,
      token: json['token'],
      userId: json['userId'] ?? json['id'],
      username: json['username'] ?? json['userName'],
      email: json['email'],
      roles: json['roles'] != null ? List<String>.from(json['roles']) : null,
      message: json['message'],
    );
  }
}

class User {
  final String id;
  final String email;
  final String name;
  final String? subscriptionStatus;
  final DateTime? subscriptionExpiry;
  final double? freeMinutesLimit;
  final double? remainingFreeMinutes;
  final double? paidMinutesLimit;
  final double? remainingPaidMinutes;
  final bool? hasUnlimitedAccess;
  final double? maxVideoDuration;

  User({
    required this.id,
    required this.email,
    required this.name,
    this.subscriptionStatus,
    this.subscriptionExpiry,
    this.freeMinutesLimit,
    this.remainingFreeMinutes,
    this.paidMinutesLimit,
    this.remainingPaidMinutes,
    this.hasUnlimitedAccess,
    this.maxVideoDuration,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? json['userId'] ?? '').toString();
    final email = (json['email'] ?? '').toString();
    final name = (json['name'] ?? json['userName'] ?? json['username'] ?? email).toString();

    final subscriptionStatus = (json['subscriptionStatus'] ?? json['subscriptionType'])?.toString();
    final subscriptionExpiryRaw = json['subscriptionExpiry'];
    final subscriptionExpiry = subscriptionExpiryRaw != null
        ? DateTime.tryParse(subscriptionExpiryRaw.toString())
        : null;

    // Legacy/paid/free minutes
    double? freeMinutesLimit = _toDouble(json['freeMinutesLimit']);
    double? remainingFreeMinutes = _toDouble(json['remainingFreeMinutes']);
    double? paidMinutesLimit = _toDouble(json['paidMinutesLimit']);
    double? remainingPaidMinutes = _toDouble(json['remainingPaidMinutes']);
    bool? hasUnlimitedAccess = json['hasUnlimitedAccess'] == true;

    // New TranslationStats minutes fields
    final balanceMinutes = _toDouble(json['balanceMinutes']);
    final totalLimit = _toDouble(json['totalLimit']);
    final usedMinutes = _toDouble(json['usedMinutes']);

    // If new fields are present, map them into the legacy structure the UI expects
    if (totalLimit != null || balanceMinutes != null || usedMinutes != null) {
      freeMinutesLimit = totalLimit ?? freeMinutesLimit;
      if (balanceMinutes != null) {
        remainingFreeMinutes = balanceMinutes;
      } else if (totalLimit != null && usedMinutes != null) {
        final remaining = totalLimit - usedMinutes;
        remainingFreeMinutes = remaining < 0 ? 0 : remaining;
      }
      paidMinutesLimit ??= 0;
      remainingPaidMinutes ??= 0;
    }

    final maxVideoDuration = _toDouble(json['maxVideoDuration'] ?? json['max_video_duration']);

    return User(
      id: id,
      email: email,
      name: name,
      subscriptionStatus: subscriptionStatus,
      subscriptionExpiry: subscriptionExpiry,
      freeMinutesLimit: freeMinutesLimit,
      remainingFreeMinutes: remainingFreeMinutes,
      paidMinutesLimit: paidMinutesLimit,
      remainingPaidMinutes: remainingPaidMinutes,
      hasUnlimitedAccess: hasUnlimitedAccess,
      maxVideoDuration: maxVideoDuration,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'subscriptionStatus': subscriptionStatus,
        'subscriptionExpiry': subscriptionExpiry?.toIso8601String(),
        'freeMinutesLimit': freeMinutesLimit,
        'remainingFreeMinutes': remainingFreeMinutes,
        'paidMinutesLimit': paidMinutesLimit,
        'remainingPaidMinutes': remainingPaidMinutes,
        'hasUnlimitedAccess': hasUnlimitedAccess,
        'maxVideoDuration': maxVideoDuration,
      };

  // Жалпы қалған минуттар
  double get totalRemainingMinutes {
    return (remainingFreeMinutes ?? 0) + (remainingPaidMinutes ?? 0);
  }

  // Жалпы лимит
  double get totalMinutesLimit {
    if (hasUnlimitedAccess == true) return double.infinity;
    return (freeMinutesLimit ?? 0) + (paidMinutesLimit ?? 0);
  }

  // Пайыз бойынша қалған минуттар
  double get remainingPercentage {
    if (hasUnlimitedAccess == true) return 100;
    final total = totalMinutesLimit;
    if (total <= 0) return 0;
    return (totalRemainingMinutes / total) * 100;
  }

  // Минуттар жеткілікті ме?
  bool hasEnoughMinutes(double requiredMinutes) {
    if (hasUnlimitedAccess == true) return true;
    return totalRemainingMinutes >= requiredMinutes;
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
