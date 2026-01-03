enum AppType {
  videoTranslation(0),
  bookReading(1),
  courseAccess(2);

  final int value;
  const AppType(this.value);

  static AppType fromValue(int value) {
    return AppType.values.firstWhere((e) => e.value == value);
  }
}

class UserSettings {
  final String userId;
  final AppType appType;
  final String interfaceLanguage;
  final Map<String, dynamic>? settings;
  final DateTime updatedAt;

  UserSettings({
    required this.userId,
    required this.appType,
    required this.interfaceLanguage,
    this.settings,
    required this.updatedAt,
  });

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    return UserSettings(
      userId: json['userId'] ?? '',
      appType: AppType.fromValue(json['appType'] ?? 0),
      interfaceLanguage: json['interfaceLanguage'] ?? 'en',
      settings: json['settings'] as Map<String, dynamic>?,
      updatedAt: json['updatedAt'] != null 
          ? DateTime.parse(json['updatedAt']) 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'appType': appType.value,
      'interfaceLanguage': interfaceLanguage,
      'settings': settings,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
