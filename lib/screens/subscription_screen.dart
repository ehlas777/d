import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/payment_models.dart';
import '../services/platform_payment_router.dart';
import '../widgets/subscription_card.dart';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';

/// Screen for displaying and managing subscriptions
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  List<SubscriptionPlan> _plans = [];
  Subscription? _currentSubscription;
  bool _isLoading = true;
  String? _error;
  String? _processingPlanId;

  String? _currentLanguageCode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      final newLanguageCode = Localizations.localeOf(context).languageCode;
      if (_currentLanguageCode != newLanguageCode) {
        _currentLanguageCode = newLanguageCode;
        _loadData();
      }
    } catch (e) {
      // Fallback if localizations not ready
      if (_currentLanguageCode == null) {
        _currentLanguageCode = 'en';
        _loadData();
      }
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final router = context.read<PlatformPaymentRouter>();
      
      // Initialize payment services (IAP)
      await router.initialize();
      
      // Load subscription plans with current language
      final allPlans = await router.getSubscriptionPlans(
        languageCode: _currentLanguageCode ?? 'en',
      );
      
      // Filter out VIP subscription (only keep Standard and Pro)
      final plans = allPlans.where((plan) => plan.id != 'vip').toList();
      
      // Load current subscription
      final subscription = await router.getCurrentSubscription();

      setState(() {
        _plans = plans;
        _currentSubscription = subscription;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _subscribe(SubscriptionPlan plan) async {
    setState(() {
      _processingPlanId = plan.id;
    });

    try {
      final router = context.read<PlatformPaymentRouter>();
      final result = await router.subscribe(
        planId: plan.id,
        iapProductId: plan.productId,
      );

      if (result.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${AppLocalizations.of(context).translate('successfully_subscribed')} ${plan.name}!'),
              backgroundColor: AppTheme.accentCyan,
            ),
          );
          // Reload data to refresh subscription status
          await _loadData();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message ?? AppLocalizations.of(context).translate('subscription_failed')),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _processingPlanId = null;
        });
      }
    }
  }

  Future<void> _restorePurchases() async {
    try {
      final router = context.read<PlatformPaymentRouter>();
      await router.restorePurchases();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).translate('purchases_restored')),
            backgroundColor: AppTheme.accentCyan,
          ),
        );
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context).translate('error_restoring_purchases')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).translate('subscription_plans')),
        backgroundColor: AppTheme.cardColor,
        actions: [
          // Show restore button on iOS and Android
          if (Platform.isIOS || Platform.isAndroid)
            TextButton.icon(
              onPressed: _restorePurchases,
              icon: Icon(Icons.restore, color: AppTheme.primaryBlue),
              label: Text(
                AppLocalizations.of(context).translate('restore'),
                style: TextStyle(color: AppTheme.primaryBlue),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: AppTheme.primaryBlue,
              ),
            )
          : _error != null
              ? Center(
                  child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 64,
                              color: Colors.red,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              AppLocalizations.of(context).translate('error_loading_subscriptions'),
                              style: Theme.of(context).textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: _loadData,
                              icon: Icon(Icons.refresh),
                              label: Text(AppLocalizations.of(context).translate('retry')),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryBlue,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Text(
                        AppLocalizations.of(context).translate('choose_your_plan'),
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(context).translate('select_perfect_plan'),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                      ),
                      const SizedBox(height: 32),

                      // Current subscription info
                      if (_currentSubscription != null) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.accentCyan.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.accentCyan,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: AppTheme.accentCyan,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppLocalizations.of(context).translate('active_subscription'),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      '${AppLocalizations.of(context).translate('renews_on')} ${_currentSubscription!.currentPeriodEnd.toString().split(' ')[0]}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Subscription cards
                      if (_plans.isEmpty)
                        Center(
                          child: Text(
                            AppLocalizations.of(context).translate('no_plans_available'),
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                          ),
                        )
                      else
                        LayoutBuilder(
                          builder: (context, constraints) {
                            // Responsive layout
                            final isWide = constraints.maxWidth > 900;
                            
                            if (isWide) {
                              // Desktop: 3 columns
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: _plans.map((plan) {
                                  final isCurrentPlan = _currentSubscription?.planId == plan.id;
                                  final isRecommended = plan.name == 'Pro';
                                  
                                  return Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                      child: SubscriptionCard(
                                        plan: plan,
                                        isCurrentPlan: isCurrentPlan,
                                        isRecommended: isRecommended,
                                        isLoading: _processingPlanId == plan.id,
                                        onSubscribe: () => _subscribe(plan),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              );
                            } else {
                              // Mobile/Tablet: Stacked
                              return Column(
                                children: _plans.map((plan) {
                                  final isCurrentPlan = _currentSubscription?.planId == plan.id;
                                  final isRecommended = plan.name == 'Pro';
                                  
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 16.0),
                                    child: SubscriptionCard(
                                      plan: plan,
                                      isCurrentPlan: isCurrentPlan,
                                      isRecommended: isRecommended,
                                      isLoading: _processingPlanId == plan.id,
                                      onSubscribe: () => _subscribe(plan),
                                    ),
                                  );
                                }).toList(),
                              );
                            }
                          },
                        ),

                      const SizedBox(height: 32),

                      // Footer info
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.cardColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 20,
                                  color: AppTheme.primaryBlue,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  AppLocalizations.of(context).translate('subscription_info'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              AppLocalizations.of(context).translate('subscription_info_text'),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
