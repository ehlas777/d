# Flutter Frontend - Көп Қолданбалы Қолданушы Баптаулары

## Шолу

Backend-те іске асырылған көп қолданбалы қолданушы баптаулары жүйесін Flutter frontend-те қолдану нұсқаулығы.

---

## 1. API Client Setup

### Dio Configuration

```dart
import 'package:dio/dio.dart';

class ApiClient {
  final Dio _dio;
  
  ApiClient({required String baseUrl}) : _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));

  // Add auth token interceptor
  void setAuthToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }
}
```

---

## 2. Models

### AppType Enum

```dart
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
```

### UserSettings Model

```dart
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
      userId: json['userId'],
      appType: AppType.fromValue(json['appType']),
      interfaceLanguage: json['interfaceLanguage'],
      settings: json['settings'] as Map<String, dynamic>?,
      updatedAt: DateTime.parse(json['updatedAt']),
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
```

### LocalizedProduct Model

```dart
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
      planId: json['planId'],
      name: json['name'],
      description: json['description'],
      monthlyPrice: (json['monthlyPrice'] as num).toDouble(),
      currency: json['currency'],
      interval: json['interval'],
      features: List<String>.from(json['features']),
      productId: json['productId'],
      dailyFreeMinutes: json['dailyFreeMinutes'],
      pricePerMinute: (json['pricePerMinute'] as num).toDouble(),
    );
  }
}
```

---

## 3. API Service

### UserSettingsService

```dart
import 'package:dio/dio.dart';

class UserSettingsService {
  final ApiClient _apiClient;

  UserSettingsService(this._apiClient);

  /// Қолданушы баптауларын алу
  Future<UserSettings> getUserSettings(AppType appType) async {
    try {
      final response = await _apiClient._dio.get(
        '/api/user/settings',
        queryParameters: {'appType': appType.value},
      );

      return UserSettings.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Қолданушы баптауларын жаңарту
  Future<UserSettings> updateUserSettings({
    required AppType appType,
    String? interfaceLanguage,
    Map<String, dynamic>? settings,
  }) async {
    try {
      final response = await _apiClient._dio.put(
        '/api/user/settings',
        data: {
          'appType': appType.value,
          if (interfaceLanguage != null) 'interfaceLanguage': interfaceLanguage,
          if (settings != null) 'settings': settings,
        },
      );

      return UserSettings.fromJson(response.data['settings']);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  String _handleError(DioException e) {
    if (e.response != null) {
      return e.response?.data['error'] ?? 'Unknown error';
    }
    return e.message ?? 'Network error';
  }
}
```

### SubscriptionService

```dart
class SubscriptionService {
  final ApiClient _apiClient;

  SubscriptionService(this._apiClient);

  /// Локализацияланған жазылым өнімдерін алу
  Future<List<LocalizedProduct>> getLocalizedProducts({
    required String platform, // 'ios', 'android', 'web'
    required String language,  // 'en', 'kk', 'ru', etc.
  }) async {
    try {
      final response = await _apiClient._dio.get(
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
```

---

## 4. State Management (Provider)

### AppSettingsProvider

```dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsProvider extends ChangeNotifier {
  final UserSettingsService _settingsService;
  UserSettings? _currentSettings;
  bool _isLoading = false;

  AppSettingsProvider(this._settingsService);

  UserSettings? get currentSettings => _currentSettings;
  bool get isLoading => _isLoading;

  /// Қолданбаны іске қосқанда баптауларды жүктеу
  Future<void> loadSettings(AppType appType) async {
    _isLoading = true;
    notifyListeners();

    try {
      _currentSettings = await _settingsService.getUserSettings(appType);
      
      // Apply interface language
      if (_currentSettings?.interfaceLanguage != null) {
        await _applyLanguage(_currentSettings!.interfaceLanguage);
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Интерфейс тілін өзгерту
  Future<void> changeLanguage(AppType appType, String languageCode) async {
    try {
      _currentSettings = await _settingsService.updateUserSettings(
        appType: appType,
        interfaceLanguage: languageCode,
      );

      await _applyLanguage(languageCode);
      notifyListeners();
    } catch (e) {
      debugPrint('Error changing language: $e');
      rethrow;
    }
  }

  /// Баптауларды жаңарту
  Future<void> updateSettings(
    AppType appType,
    Map<String, dynamic> settings,
  ) async {
    try {
      _currentSettings = await _settingsService.updateUserSettings(
        appType: appType,
        settings: settings,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating settings: $e');
      rethrow;
    }
  }

  Future<void> _applyLanguage(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', languageCode);
    // Trigger locale change in your app
  }
}
```

---

## 5. UI Implementation

### Settings Screen Example

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatefulWidget {
  final AppType appType;

  const SettingsScreen({Key? key, required this.appType}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Load settings when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppSettingsProvider>().loadSettings(widget.appType);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getAppTitle()),
      ),
      body: Consumer<AppSettingsProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final settings = provider.currentSettings;
          if (settings == null) {
            return const Center(child: Text('No settings found'));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildLanguageSelector(context, provider),
              const SizedBox(height: 16),
              if (widget.appType == AppType.videoTranslation)
                _buildVideoSettings(context, provider),
              if (widget.appType == AppType.bookReading)
                _buildBookSettings(context, provider),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLanguageSelector(
    BuildContext context,
    AppSettingsProvider provider,
  ) {
    final languages = {
      'en': 'English',
      'kk': 'Қазақша',
      'ru': 'Русский',
      'zh': '中文',
      'ar': 'العربية',
      'uz': 'O\'zbekcha',
      'tr': 'Türkçe',
    };

    return Card(
      child: ListTile(
        title: const Text('Interface Language'),
        subtitle: Text(languages[provider.currentSettings?.interfaceLanguage] ?? 'English'),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: () async {
          final selected = await showDialog<String>(
            context: context,
            builder: (context) => SimpleDialog(
              title: const Text('Select Language'),
              children: languages.entries.map((entry) {
                return SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, entry.key),
                  child: Text(entry.value),
                );
              }).toList(),
            ),
          );

          if (selected != null) {
            await provider.changeLanguage(widget.appType, selected);
          }
        },
      ),
    );
  }

  Widget _buildVideoSettings(
    BuildContext context,
    AppSettingsProvider provider,
  ) {
    final settings = provider.currentSettings?.settings ?? {};
    final videoSpeed = settings['videoSpeed'] ?? 1.0;

    return Card(
      child: Column(
        children: [
          ListTile(
            title: const Text('Video Speed'),
            subtitle: Text('${videoSpeed}x'),
          ),
          Slider(
            value: videoSpeed.toDouble(),
            min: 0.5,
            max: 2.0,
            divisions: 6,
            label: '${videoSpeed}x',
            onChanged: (value) async {
              await provider.updateSettings(
                widget.appType,
                {'videoSpeed': value},
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBookSettings(
    BuildContext context,
    AppSettingsProvider provider,
  ) {
    final settings = provider.currentSettings?.settings ?? {};
    final fontSize = settings['fontSize'] ?? 16;

    return Card(
      child: Column(
        children: [
          ListTile(
            title: const Text('Font Size'),
            subtitle: Text('$fontSize'),
          ),
          Slider(
            value: fontSize.toDouble(),
            min: 12,
            max: 24,
            divisions: 12,
            label: '$fontSize',
            onChanged: (value) async {
              await provider.updateSettings(
                widget.appType,
                {'fontSize': value.toInt()},
              );
            },
          ),
        ],
      ),
    );
  }

  String _getAppTitle() {
    switch (widget.appType) {
      case AppType.videoTranslation:
        return 'Video Translation Settings';
      case AppType.bookReading:
        return 'Book Reading Settings';
      case AppType.courseAccess:
        return 'Course Settings';
    }
  }
}
```

### Subscription Products Screen

```dart
class SubscriptionProductsScreen extends StatefulWidget {
  const SubscriptionProductsScreen({Key? key}) : super(key: key);

  @override
  State<SubscriptionProductsScreen> createState() => _SubscriptionProductsScreenState();
}

class _SubscriptionProductsScreenState extends State<SubscriptionProductsScreen> {
  List<LocalizedProduct>? _products;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);

    try {
      final subscriptionService = context.read<SubscriptionService>();
      final locale = Localizations.localeOf(context);
      final platform = Theme.of(context).platform == TargetPlatform.iOS ? 'ios' : 'android';

      final products = await subscriptionService.getLocalizedProducts(
        platform: platform,
        language: locale.languageCode,
      );

      setState(() {
        _products = products;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading products: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription Plans'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _products == null || _products!.isEmpty
              ? const Center(child: Text('No products available'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _products!.length,
                  itemBuilder: (context, index) {
                    final product = _products![index];
                    return _buildProductCard(product);
                  },
                ),
    );
  }

  Widget _buildProductCard(LocalizedProduct product) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              product.name,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              product.description,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            Text(
              '\$${product.monthlyPrice.toStringAsFixed(2)} ${product.currency}/${product.interval}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 16),
            ...product.features.map((feature) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(feature)),
                ],
              ),
            )),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _subscribeToPlan(product),
                child: const Text('Subscribe'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _subscribeToPlan(LocalizedProduct product) async {
    // Implement subscription logic with in_app_purchase package
    print('Subscribe to ${product.planId}');
  }
}
```

---

## 6. Main App Setup

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final apiClient = ApiClient(baseUrl: 'https://qaznat.kz');
    
    return MultiProvider(
      providers: [
        Provider(create: (_) => apiClient),
        Provider(create: (_) => UserSettingsService(apiClient)),
        Provider(create: (_) => SubscriptionService(apiClient)),
        ChangeNotifierProvider(
          create: (context) => AppSettingsProvider(
            context.read<UserSettingsService>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Multi-App Settings Demo',
        home: const HomeScreen(),
      ),
    );
  }
}
```

---

## 7. Қолдану мысалдары

### Тілді өзгерту

```dart
// Қолданушы тілді өзгерткенде
await context.read<AppSettingsProvider>().changeLanguage(
  AppType.videoTranslation,
  'kk', // Kazakh
);
```

### Баптауларды жаңарту

```dart
// Бейне жылдамдығын өзгерту
await context.read<AppSettingsProvider>().updateSettings(
  AppType.videoTranslation,
  {
    'videoSpeed': 1.5,
    'videoQuality': 'high',
  },
);
```

### Жазылым өнімдерін жүктеу

```dart
final products = await subscriptionService.getLocalizedProducts(
  platform: 'ios',
  language: 'kk',
);
```

---

## 8. Маңызды ескертулер

### Синхрондау
- Баптаулар backend-те сақталады
- Барлық құрылғыларда автоматты синхрондалады
- Жаңа құрылғыда кіргенде автоматты жүктеледі

### Қолданба изоляциясы
- Әр қолданба (VideoTranslation, BookReading, CourseAccess) бөлек баптауларға ие
- Бір қолданбаның баптауын өзгерту басқаларына әсер етпейді

### Валюта
- Барлық бағалар USD-да келеді
- Қажет болса frontend-те KZT-ға конвертациялауға болады

### Тілдер
- 7 тілді қолдайды: en, kk, ru, zh, ar, uz, tr
- Қолдамайтын тіл сұралса, автоматты ағылшын тіліне fallback

---

## 9. Dependencies

`pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  dio: ^5.4.0
  provider: ^6.1.1
  shared_preferences: ^2.2.2
  in_app_purchase: ^3.1.13  # For subscription purchases
```

---

## Қорытынды

Бұл құжат Flutter frontend-те көп қолданбалы қолданушы баптаулары жүйесін толық іске асыру үшін барлық қажетті кодты қамтиды.
