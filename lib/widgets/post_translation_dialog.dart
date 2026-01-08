import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../config/app_theme.dart';

enum PostTranslationAction {
  continueTranslation,
  clean,
}

class PostTranslationDialog extends StatelessWidget {
  final String targetLanguage;
  final double minutesUsedToday;
  final double minutesRemaining;
  final double totalVideoDuration; // Changed from totalTtsDuration
  final double? dailyLimit; // From backend subscription
  final String? subscriptionType; // Standard, Pro, VIP, etc.
  final bool balanceRefreshFailed; // Track if balance refresh failed

  const PostTranslationDialog({
    super.key,
    required this.targetLanguage,
    required this.minutesUsedToday,
    required this.minutesRemaining,
    required this.totalVideoDuration, // Renamed parameter
    this.dailyLimit,
    this.subscriptionType,
    this.balanceRefreshFailed = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.accentColor.withOpacity(0.1),
                    AppTheme.primaryBlue.withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      color: AppTheme.successColor,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      l10n.translate('post_translation_dialog_title'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Message
                  Text(
                    l10n
                        .translate('post_translation_dialog_message')
                        .replaceAll('{0}', targetLanguage),
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Warning banner if balance refresh failed
                  if (balanceRefreshFailed)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.translate('balance_refresh_failed') ?? 'Balance update failed. Values shown may be outdated.',
                              style: TextStyle(color: Colors.orange.shade900, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Usage Statistics Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.primaryBlue.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        // Subscription Info (if available)
                        if (subscriptionType != null && dailyLimit != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppTheme.accentColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.workspace_premium,
                                  size: 16,
                                  color: AppTheme.accentColor,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$subscriptionType: ${dailyLimit!.toStringAsFixed(0)} min/күн',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.accentColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (subscriptionType != null && dailyLimit != null)
                          const SizedBox(height: 12),
                        
                        // Video Duration (not TTS)
                        _buildStatRow(
                          context,
                          icon: Icons.videocam,
                          label: l10n.translate('total_video_duration') ?? 'Video Duration',
                          value: '${totalVideoDuration.toStringAsFixed(2)} min',
                          color: AppTheme.accentColor,
                        ),
                        const Divider(height: 16),

                        // Minutes Used Today
                        _buildStatRow(
                          context,
                          icon: Icons.timelapse,
                          label: l10n.translate('minutes_used_today'),
                          value: '${minutesUsedToday.toStringAsFixed(2)} min',
                          color: AppTheme.warningColor,
                        ),
                        const Divider(height: 16),

                        // Minutes Remaining
                        _buildStatRow(
                          context,
                          icon: Icons.schedule,
                          label: l10n.translate('minutes_remaining'),
                          value: _formatRemainingMinutes(),
                          color: AppTheme.successColor,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Action Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                children: [
                  // Clean Button
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop(PostTranslationAction.clean);
                      },
                      icon: const Icon(Icons.clear_all),
                      label: Text(l10n.translate('clean')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Continue Button
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context)
                            .pop(PostTranslationAction.continueTranslation);
                      },
                      icon: const Icon(Icons.translate),
                      label: Text(l10n.translate('continue_translation')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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

  /// Format remaining minutes for display
  /// Shows infinity symbol (∞) for VIP/Unlimited users (very large values)
  String _formatRemainingMinutes() {
    // If remaining minutes is very large (>= 999999), it's likely a VIP/Unlimited user
    // Show infinity symbol instead of the number
    if (minutesRemaining >= 999999) {
      return '∞';
    }
    
    return '${minutesRemaining.toStringAsFixed(2)} min';
  }

  Widget _buildStatRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
