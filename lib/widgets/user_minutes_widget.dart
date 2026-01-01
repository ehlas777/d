import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../config/app_theme.dart';

/// Пайдаланушының қалған минуттарын көрсететін виджет
class UserMinutesWidget extends StatelessWidget {
  final bool showDetails;

  const UserMinutesWidget({
    Key? key,
    this.showDetails = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        if (!authProvider.isLoggedIn) {
          return const SizedBox.shrink();
        }

        if (authProvider.hasUnlimitedAccess == true) {
          return _buildUnlimitedCard(context);
        }

        return showDetails
            ? _buildDetailedCard(context, authProvider)
            : _buildCompactCard(context, authProvider);
      },
    );
  }

  Widget _buildUnlimitedCard(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              Icons.all_inclusive,
              color: AppTheme.primaryPurple,
              size: 32,
            ),
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
                          color: Colors.grey[600],
                        ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.verified,
              color: AppTheme.accentCyan,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactCard(BuildContext context, AuthProvider authProvider) {
    final percentage = authProvider.remainingPercentage;
    final remaining = authProvider.totalRemainingMinutes;

    Color getColor() {
      if (percentage >= 50) return AppTheme.successColor;
      if (percentage >= 20) return AppTheme.warningColor;
      return AppTheme.errorColor;
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Icon(
              Icons.timer,
              color: getColor(),
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${remaining.toStringAsFixed(1)} мин қалды',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: percentage / 100,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(getColor()),
                      minHeight: 6,
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

  Widget _buildDetailedCard(BuildContext context, AuthProvider authProvider) {
    final freeRemaining = authProvider.remainingFreeMinutes ?? 0;
    final freeLimit = authProvider.freeMinutesLimit ?? 0;
    final paidRemaining = authProvider.remainingPaidMinutes ?? 0;
    final paidLimit = authProvider.paidMinutesLimit ?? 0;
    final totalRemaining = authProvider.totalRemainingMinutes;
    final percentage = authProvider.remainingPercentage;

    Color getColor() {
      if (percentage >= 50) return AppTheme.successColor;
      if (percentage >= 20) return AppTheme.warningColor;
      return AppTheme.errorColor;
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.timer,
                  color: getColor(),
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Қалған минуттар',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${totalRemaining.toStringAsFixed(1)} мин',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: getColor(),
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    context.read<AuthProvider>().refreshUserMinutes();
                  },
                  tooltip: 'Жаңарту',
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: percentage / 100,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(getColor()),
                minHeight: 10,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${percentage.toStringAsFixed(0)}% қалды',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            if (freeLimit > 0 || paidLimit > 0) ...[
              const Divider(height: 24),
              if (freeLimit > 0) ...[
                _buildMinuteRow(
                  context,
                  'Тегін минуттар',
                  freeRemaining,
                  freeLimit,
                  Icons.free_breakfast,
                  Colors.teal,
                ),
                const SizedBox(height: 8),
              ],
              if (paidLimit > 0) ...[
                _buildMinuteRow(
                  context,
                  'Ақылы минуттар',
                  paidRemaining,
                  paidLimit,
                  Icons.paid,
                  Colors.blue,
                ),
              ],
            ],
            if (percentage < 20) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.red[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Минуттар таусылып барады. Абонементті жаңартыңыз.',
                        style: TextStyle(
                          color: Colors.red[700],
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMinuteRow(
    BuildContext context,
    String label,
    double remaining,
    double limit,
    IconData icon,
    Color color,
  ) {
    final percentage = limit > 0 ? (remaining / limit) * 100 : 0;

    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    '${remaining.toStringAsFixed(1)} / ${limit.toStringAsFixed(0)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percentage / 100,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Минуттар жетіспесе ескерту диалогы
class InsufficientMinutesDialog extends StatelessWidget {
  final double required;
  final double available;

  const InsufficientMinutesDialog({
    Key? key,
    required this.required,
    required this.available,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final deficit = required - available;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning, color: Colors.orange),
          const SizedBox(width: 8),
          const Text('Минуттар жеткіліксіз'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Бұл видеоны аудару үшін ${required.toStringAsFixed(1)} минут қажет, бірақ сізде ${available.toStringAsFixed(1)} минут ғана қалды.',
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.info, color: Colors.orange[700], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Тағы ${deficit.toStringAsFixed(1)} минут қажет',
                    style: TextStyle(
                      color: Colors.orange[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Жабу'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            // TODO: Абонемент бетіне өту
          },
          child: const Text('Абонемент алу'),
        ),
      ],
    );
  }

  static Future<void> show(
    BuildContext context, {
    required double required,
    required double available,
  }) {
    return showDialog(
      context: context,
      builder: (context) => InsufficientMinutesDialog(
        required: required,
        available: available,
      ),
    );
  }
}
