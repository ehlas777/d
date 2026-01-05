import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../screens/subscription_screen.dart';

class ProfileDialog extends StatelessWidget {
  const ProfileDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final maxHeight = MediaQuery.of(context).size.height * 0.8;

    return Dialog(
      backgroundColor: AppTheme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 400,
          maxHeight: maxHeight,
        ),
        padding: const EdgeInsets.all(32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.account_circle,
                    color: AppTheme.accentColor,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l10n.translate('profile'),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Center(
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: AppTheme.accentColor.withValues(alpha: 0.2),
                  child: Text(
                    authProvider.username?.substring(0, 1).toUpperCase() ?? '?',
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.accentColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  authProvider.username ?? '',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              const SizedBox(height: 16),
              if ((authProvider.email?.isNotEmpty ?? false) ||
                  (authProvider.userId?.isNotEmpty ?? false))
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (authProvider.email != null && authProvider.email!.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.email, size: 18, color: AppTheme.accentColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                authProvider.email!,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                      ],
                      if (authProvider.userId != null && authProvider.userId!.isNotEmpty)
                        Row(
                          children: [
                            const Icon(Icons.badge, size: 18, color: AppTheme.accentColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'ID: ${authProvider.userId}',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              tooltip: 'ID көшіру',
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: authProvider.userId!),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('ID көшірілді')),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              // Минуттар ақпараты
              if (authProvider.hasUnlimitedAccess == true)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryPurple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primaryPurple),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.all_inclusive, color: AppTheme.primaryPurple, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Шектеусіз қол жеткізу',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Премиум абонемент',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.verified, color: AppTheme.accentCyan, size: 24),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: authProvider.remainingPercentage >= 20
                        ? AppTheme.successColor.withValues(alpha: 0.1)
                        : AppTheme.warningColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: authProvider.remainingPercentage >= 20
                          ? AppTheme.successColor
                          : AppTheme.warningColor,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.timer,
                            color: authProvider.remainingPercentage >= 20
                                ? AppTheme.successColor
                                : AppTheme.warningColor,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Қалған минуттар',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 20),
                            onPressed: () {
                              authProvider.refreshUserMinutes();
                            },
                            tooltip: 'Жаңарту',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${authProvider.totalRemainingMinutes.toStringAsFixed(1)} мин',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: authProvider.remainingPercentage >= 20
                                  ? AppTheme.successColor
                                  : AppTheme.warningColor,
                            ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: authProvider.remainingPercentage / 100,
                          backgroundColor: AppTheme.borderColor,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            authProvider.remainingPercentage >= 20
                                ? AppTheme.successColor
                                : AppTheme.warningColor,
                          ),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${authProvider.remainingPercentage.toStringAsFixed(0)}% қалды',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                      if (authProvider.freeMinutesLimit != null &&
                          authProvider.freeMinutesLimit! > 0) ...[
                        const SizedBox(height: 12),
                        const Divider(),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.free_breakfast, size: 16, color: Colors.teal),
                                const SizedBox(width: 4),
                                const Text('Тегін:', style: TextStyle(fontSize: 12)),
                              ],
                            ),
                            Text(
                              '${authProvider.remainingFreeMinutes?.toStringAsFixed(1)} / ${authProvider.freeMinutesLimit?.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (authProvider.paidMinutesLimit != null &&
                          authProvider.paidMinutesLimit! > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.paid, size: 16, color: Colors.blue),
                                const SizedBox(width: 4),
                                const Text('Ақылы:', style: TextStyle(fontSize: 12)),
                              ],
                            ),
                            Text(
                              '${authProvider.remainingPaidMinutes?.toStringAsFixed(1)} / ${authProvider.paidMinutesLimit?.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                   Navigator.of(context).pop(); 
                   Navigator.push(
                     context,
                     MaterialPageRoute(
                       builder: (context) => const SubscriptionScreen(),
                     ),
                   );
                },
                icon: const Icon(Icons.star),
                label: Text(l10n.translate('get_subscription')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  authProvider.logout();
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n.translate('logout_successful')),
                      backgroundColor: AppTheme.successColor,
                    ),
                  );
                },
                icon: const Icon(Icons.logout),
                label: Text(l10n.translate('logout')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.errorColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(l10n.deleteAccountConfirmationTitle),
                      content: Text(l10n.deleteAccountConfirmationMessage),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text(l10n.cancel),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.errorColor,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(l10n.delete),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true && context.mounted) {
                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(context);
                    
                    try {
                      // Show loading indicator
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => const Center(
                          child: CircularProgressIndicator(),
                        ),
                      );

                      final success = await authProvider.deleteAccount();
                      
                      if (context.mounted) {
                        Navigator.of(context).pop(); // Close loading dialog
                        
                        if (success) {
                          navigator.pop(); // Close profile dialog
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text(l10n.deleteAccountSuccess),
                              backgroundColor: AppTheme.successColor,
                            ),
                          );
                        } else {
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text(l10n.deleteAccountError),
                              backgroundColor: AppTheme.errorColor,
                            ),
                          );
                        }
                      }
                    } catch (e) {
                      if (context.mounted) {
                        Navigator.of(context).pop(); // Close loading dialog
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text(l10n.deleteAccountError),
                            backgroundColor: AppTheme.errorColor,
                          ),
                        );
                      }
                    }
                  }
                },
                icon: const Icon(Icons.delete_forever, size: 20),
                label: Text(l10n.deleteAccount),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.errorColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
