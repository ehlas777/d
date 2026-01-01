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
import 'services/payment_service.dart';
import 'services/backend_translation_service.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ProjectProvider()),
        ChangeNotifierProvider(create: (_) => TrialProvider()),
        Provider(create: (_) => ApiClient()),
        ProxyProvider<ApiClient, AuthService>(
          update: (_, apiClient, __) => AuthService(apiClient),
        ),
        ProxyProvider<ApiClient, PaymentService>(
          update: (_, apiClient, __) => PaymentService(apiClient),
        ),
        ProxyProvider<ApiClient, BackendTranslationService>(
          update: (_, apiClient, __) => BackendTranslationService(apiClient),
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
      title: 'QazNat VT',
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
    );
  }
}
