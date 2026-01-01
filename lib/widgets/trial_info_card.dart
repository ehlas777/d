import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/trial_provider.dart';
import '../l10n/app_localizations.dart';

class TrialInfoCard extends StatelessWidget {
  const TrialInfoCard({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    
    return Consumer<TrialProvider>(
      builder: (context, trialProvider, child) {
        if (!trialProvider.canUseTrial) {
          return const SizedBox.shrink();
        }
        
        final maxDuration = trialProvider.maxVideoDuration;
        
        return Card(
          color: Colors.orange.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Text(
                      l10n.translate('trial_mode_title'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  context,
                  Icons.numbers,
                  l10n.translate('trial_remaining_attempts'),
                  '${trialProvider.attemptsRemaining} ${l10n.translate('trial_times')}',
                ),
                const SizedBox(height: 8),
                _buildInfoRow(
                  context,
                  Icons.timer,
                  l10n.translate('trial_max_video_duration'),
                  '$maxDuration ${l10n.translate('trial_seconds')}',
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.translate('trial_workflow_note'),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildInfoRow(BuildContext context, IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.orange.shade600),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 14)),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
