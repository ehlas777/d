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
  
  // Legacy fields (kept for backwards compatibility)
  final double? freeMinutesLimit;
  final double? remainingFreeMinutes;
  final double? paidMinutesLimit;
  final double? remainingPaidMinutes;
  
  // Two-Bucket system fields (NEW)
  final double? dailyRemainingMinutes;  // Күнделікті қалған (resets daily UTC 00:00)
  final double? extraMinutes;           // Bonus минуттар (never resets)
  final double? totalLimit;             // Күнделікті лимит
  final double? usedMinutes;            // Бүгін қолданылған
  
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
    this.dailyRemainingMinutes,
    this.extraMinutes,
    this.totalLimit,
    this.usedMinutes,
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

    bool? hasUnlimitedAccess = json['hasUnlimitedAccess'] == true;

    // Two-Bucket system fields (NEW)
    final dailyRemainingMinutes = _toDouble(json['dailyRemainingMinutes']);
    final extraMinutes = _toDouble(json['extraMinutes']);
    final totalLimit = _toDouble(json['totalLimit']);
    final usedMinutes = _toDouble(json['usedMinutes']);
    
    // Legacy balance field  
    final balanceMinutes = _toDouble(json['balanceMinutes']);

    // Map to legacy fields for backwards compatibility
    double? freeMinutesLimit = _toDouble(json['freeMinutesLimit']);
    double? remainingFreeMinutes = _toDouble(json['remainingFreeMinutes']);
    double? paidMinutesLimit = _toDouble(json['paidMinutesLimit']);
    double? remainingPaidMinutes = _toDouble(json['remainingPaidMinutes']);

    // If two-bucket fields present, map to legacy structure for UI compatibility
    if (dailyRemainingMinutes != null || extraMinutes != null || totalLimit != null) {
      freeMinutesLimit = totalLimit ?? freeMinutesLimit;
      // Map dailyRemaining to "free" (UI показывает как основной баланс)
      remainingFreeMinutes = dailyRemainingMinutes ?? remainingFreeMinutes;
      // Map extraMinutes to "paid" (UI показывает как дополнительный баланс)
      paidMinutesLimit = extraMinutes ?? 0.0;
      remainingPaidMinutes = extraMinutes ?? 0.0;
    } else if (balanceMinutes != null || totalLimit != null || usedMinutes != null) {
      // Legacy fallback: old backend response
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
      dailyRemainingMinutes: dailyRemainingMinutes,
      extraMinutes: extraMinutes,
      totalLimit: totalLimit,
      usedMinutes: usedMinutes,
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
        'dailyRemainingMinutes': dailyRemainingMinutes,
        'extraMinutes': extraMinutes,
        'totalLimit': totalLimit,
        'usedMinutes': usedMinutes,
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

  // Two-Bucket: Total available (daily + extra)
  double get totalAvailable {
    if (dailyRemainingMinutes != null || extraMinutes != null) {
      return (dailyRemainingMinutes ?? 0) + (extraMinutes ?? 0);
    }
    // Fallback to legacy
    return totalRemainingMinutes;
  }

  // Минуттар жеткілікті ме? (with maxVideoDuration check)
  bool hasEnoughMinutes(double requiredMinutes) {
    if (hasUnlimitedAccess == true) return true;
    
    // Check max video duration limit
    if (maxVideoDuration != null && requiredMinutes > maxVideoDuration!) {
      return false;
    }
    
    // Check total available balance
    return totalAvailable >= requiredMinutes;
  }

  // Get remaining daily minutes
  double getRemainingDailyMinutes() {
    // Backend returns authoritative remaining minutes in remainingFreeMinutes/remainingPaidMinutes
    // minutesUsedToday is just for display/stats, not for calculation
    return totalRemainingMinutes;
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
