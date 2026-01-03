import 'package:flutter/material.dart';
import '../models/payment_models.dart';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';

/// Card widget for displaying a subscription tier with modern design
class SubscriptionCard extends StatelessWidget {
  final SubscriptionPlan plan;
  final bool isCurrentPlan;
  final bool isRecommended;
  final VoidCallback onSubscribe;
  final bool isLoading;

  const SubscriptionCard({
    super.key,
    required this.plan,
    required this.onSubscribe,
    this.isCurrentPlan = false,
    this.isRecommended = false,
    this.isLoading = false,
  });

  Color _getHeaderColor() {
    switch (plan.name.toLowerCase()) {
      case 'standard':
        return const Color(0xFFF5A962); // Orange/Yellow
      case 'pro':
        return AppTheme.primaryBlue; // Blue
      case 'vip':
        return const Color(0xFFE57BA8); // Pink
      default:
        return AppTheme.primaryPurple;
    }
  }

  /// Convert price to USD if it's in KZT
  /// Exchange rate: 1 USD ≈ 450 KZT
  double _getPriceInUSD() {
    if (plan.currency == 'KZT') {
      return plan.price / 450.0;
    }
    return plan.price;
  }

  /// Get localized plan name
  String _getLocalizedPlanName(BuildContext context) {
    final planId = plan.id.toLowerCase();
    final key = 'plan_name_$planId';
    final localized = AppLocalizations.of(context).translate(key);
    // If translation exists and is not the key itself, use it
    if (localized != key) {
      return localized;
    }
    // Otherwise return the original name
    return plan.name;
  }

  /// Get localized plan description  
  String _getLocalizedDescription(BuildContext context) {
    final planId = plan.id.toLowerCase();
    final key = 'plan_desc_$planId';
    final localized = AppLocalizations.of(context).translate(key);
    // If translation exists and is not the key itself, use it
    if (localized != key) {
      return localized;
    }
    // Otherwise return the original description
    return plan.description;
  }

  /// Get localized interval (month/year)
  String _getLocalizedInterval(BuildContext context) {
    final interval = plan.interval.toLowerCase();
    final key = 'interval_$interval';
    final localized = AppLocalizations.of(context).translate(key);
    // If translation exists and is not the key itself, use it
    if (localized != key) {
      return localized;
    }
    // Otherwise return the original interval in uppercase
    return plan.interval.toUpperCase();
  }

  /// Get localized feature text
  String _getLocalizedFeature(BuildContext context, String rawFeature) {
    // Map known backend strings to localization keys
    final Map<String, String> featureMap = {
      '10 минут/күн тегін аудару': 'feature_10min',
      '30 минут/күн тегін аудару': 'feature_30min',
      'Базалық қолдау': 'feature_basic_support',
      'Стандартты сапа': 'feature_standard_quality',
      'Барлық тілдерге қол жетімділік': 'feature_all_languages',
      'Шексіз аударма': 'feature_unlimited',
      'Басымды қолдау': 'feature_priority_support',
      'Басымдықты қолдау': 'feature_priority_support', // Variation
      'Премиум қолдау': 'feature_premium_support',
      'Су таңбасыз': 'feature_no_watermark',
      'Жоғары сапа': 'feature_high_quality',
      'HD сапасы': 'feature_hd_quality',
      'Қосымша мүмкіндіктер': 'feature_extra',
    };

    // Normalize string (trim)
    final normalized = rawFeature.trim();
    
    // Check if we have a mapping
    if (featureMap.containsKey(normalized)) {
       final key = featureMap[normalized]!;
       final localized = AppLocalizations.of(context).translate(key);
       if (localized != key) return localized;
    }
    
    // Fallback: return original if no mapping or translation found
    return rawFeature;
  }

  @override
  Widget build(BuildContext context) {
    final headerColor = _getHeaderColor();
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
        border: isRecommended
            ? Border.all(color: AppTheme.primaryBlue, width: 2)
            : null,
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with gradient
              Container(
                padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      headerColor,
                      headerColor.withOpacity(0.8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Column(
                  children: [
                    // Plan name
                    Text(
                      _getLocalizedPlanName(context).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Price (always display in USD)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '\$',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _getPriceInUSD().toStringAsFixed(0),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 64,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '/ ${_getLocalizedInterval(context)}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Content
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Description
                    Text(
                      _getLocalizedDescription(context),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Features
                    ...plan.features.map((feature) => Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                color: headerColor, // Use dynamic tier color
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _getLocalizedFeature(context, feature),
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )),
                    const SizedBox(height: 24),
                    
                    // Subscribe button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isCurrentPlan || isLoading ? null : onSubscribe,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: headerColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                          disabledBackgroundColor: Colors.grey[300],
                        ),
                        child: isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(
                                isCurrentPlan 
                                  ? AppLocalizations.of(context).translate('current_plan')
                                  : AppLocalizations.of(context).translate('subscribe'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          // Recommended badge
          if (isRecommended)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.star,
                      color: headerColor,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      AppLocalizations.of(context).translate('popular'),
                      style: TextStyle(
                        color: headerColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          // Current plan badge
          if (isCurrentPlan)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.accentCyan,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  AppLocalizations.of(context).translate('active'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
