import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/trial_provider.dart';

class TrialBadgeWidget extends StatelessWidget {
  const TrialBadgeWidget({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Consumer<TrialProvider>(
      builder: (context, trialProvider, child) {
        if (!trialProvider.canUseTrial) {
          return const SizedBox.shrink();
        }
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.orange.shade400, Colors.deepOrange.shade600],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.card_giftcard, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(
                'СЫНАУ: ${trialProvider.attemptsRemaining} рет қалды',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
