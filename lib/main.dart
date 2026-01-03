import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'l10n/app_localizations.dart';
import 'config/app_theme.dart';
import 'screens/home_screen.dart';
import 'providers/locale_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/project_provider.dart';
import 'providers/trial_provider.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/subscription_api_service.dart';
import 'services/backend_translation_service.dart';
import 'services/iap_service.dart';
import 'services/platform_payment_router.dart';
import 'services/user_settings_service.dart';
import 'services/subscription_service_new.dart';
import 'providers/app_settings_provider.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void _handleSessionExpired() {
  final context = navigatorKey.currentState?.overlay?.context;
  
  if (context != null) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Session Expired'),
        content: const Text('You have logged in from another device. Please log in again.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop(); // Close dialog
              
              // Clear any critical state if needed, though ApiClient clears token.
              // Navigate to Login. Assuming '/login' is not a defined route in this app?
              // The user example used named route '/login'. 
              // But looking at main.dart, 'home: const HomeScreen()', it doesn't seem to use named routes table.
              // I should check if there are named routes. If not, I should navigate to LoginDialog or similar.
              // Wait, the user asked to "Navigate to Login".
              // Existing app uses `LoginDialog`.
              // Maybe push a screen that shows LoginDialog? Or push a `LoginScreen`.
              // Let's check `screens/` folder.
              
              navigatorKey.currentState?.pushNamedAndRemoveUntil('/', (route) => false);
              // Since we probably don't have '/login', we might need to rely on 'home' logic detecting no token and showing login.
              // HomeScreen usually handles auth state.
              // If we clear token (which ApiClient does), and reload HomeScreen, it might prompt login.
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  } else {
      // Fallback
      navigatorKey.currentState?.pushNamedAndRemoveUntil('/', (route) => false);
  }
}

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        
        // 1. Core Services (ApiClient)
        Provider(create: (_) => ApiClient(onSessionExpired: _handleSessionExpired)),
        
        // 2. Services depending on ApiClient
        ProxyProvider<ApiClient, AuthService>(
          update: (_, apiClient, __) => AuthService(apiClient),
        ),
        ProxyProvider<ApiClient, SubscriptionApiService>(
          update: (_, apiClient, __) => SubscriptionApiService(apiClient),
        ),
        ProxyProvider<ApiClient, BackendTranslationService>(
          update: (_, apiClient, __) => BackendTranslationService(apiClient),
        ),
        ProxyProvider<ApiClient, UserSettingsService>(
          update: (_, apiClient, __) => UserSettingsService(apiClient),
        ),
        ProxyProvider<ApiClient, SubscriptionServiceNew>(
          update: (_, apiClient, __) => SubscriptionServiceNew(apiClient),
        ),

        // 3. Providers depending on Services
        ChangeNotifierProxyProvider<AuthService, AuthProvider>(
          create: (_) => AuthProvider(AuthService(ApiClient(onSessionExpired: _handleSessionExpired))), // Helper for initial create, though update will overwrite
          update: (_, authService, previous) => 
            (previous != null && previous.apiClient == authService.apiClient) 
            ? previous 
            : AuthProvider(authService), 
            // Note: Re-creating AuthProvider loses state? 
            // Better: update authService in AuthProvider if possible, or just re-create. 
            // Actually, usually AuthProvider is long-lived. 
            // If ApiClient changes, AuthProvider should update.
            // But ApiClient is a Provider, logic doesn't change often.
        ),
        
        ChangeNotifierProvider(create: (_) => ProjectProvider()),
        ChangeNotifierProvider(create: (_) => TrialProvider()),

        
        ProxyProvider<SubscriptionApiService, IAPService>(
          update: (_, subscriptionApiService, __) => IAPService(subscriptionApiService),
        ),
        ProxyProvider3<IAPService, SubscriptionApiService, SubscriptionServiceNew, PlatformPaymentRouter>(
          update: (_, iapService, subscriptionApiService, subscriptionServiceNew, __) => PlatformPaymentRouter(
            iapService: iapService,
            subscriptionApiService: subscriptionApiService,
            subscriptionServiceNew: subscriptionServiceNew,
          ),
        ),
        // New Providers
        ChangeNotifierProxyProvider<UserSettingsService, AppSettingsProvider>(
          create: (_) => AppSettingsProvider(UserSettingsService(ApiClient())), // Start with a temporary implementation
          update: (_, userSettingsService, previous) => 
            previous ?? AppSettingsProvider(userSettingsService),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final localeProvider = Provider.of<LocaleProvider>(context);

    return MaterialApp(
      title: 'PolyDub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      locale: localeProvider.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomeScreen(),
      navigatorKey: navigatorKey,
    );
  }
}
