import 'package:flutter/material.dart';
import '../config/app_theme.dart';

/// Real-time progress monitor for automatic translation
/// Shows console-style logs of current operations
class AutoTranslationProgressPanel extends StatelessWidget {
  final List<String> logs;
  final bool isActive;

  const AutoTranslationProgressPanel({
    super.key,
    required this.logs,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!isActive || logs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E), // VS Code dark theme
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.accentColor.withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentColor.withValues(alpha: 0.1),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                // Blinking indicator
                _buildBlinkingDot(),
                const SizedBox(width: 8),
                const Text(
                  'AUTOMATIC TRANSLATION MONITOR',
                  style: TextStyle(
                    color: Color(0xFF4EC9B0), // Cyan
                    fontFamily: 'Courier',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                Text(
                  '${logs.length} operations',
                  style: const TextStyle(
                    color: Color(0xFF858585),
                    fontFamily: 'Courier',
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          // Logs container
          Container(
            constraints: const BoxConstraints(
              maxHeight: 400, // Larger for automatic mode
            ),
            child: ListView.builder(
              shrinkWrap: true,
              reverse: true, // Latest at bottom
              padding: const EdgeInsets.all(12),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final reversedIndex = logs.length - 1 - index;
                return _buildLogEntry(logs[reversedIndex]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlinkingDot() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: const Color(0xFF4EC9B0),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4EC9B0).withValues(alpha: 0.5),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        );
      },
      onEnd: () {
        // Restart animation (handled by framework on rebuild)
      },
    );
  }

  Widget _buildLogEntry(String log) {
    // Parse log type and colorize
    Color textColor = const Color(0xFFD4D4D4); // Default white
    IconData? icon;
    Color? iconColor;

    if (log.contains('Translating:')) {
      textColor = const Color(0xFF4EC9B0); // Cyan
      icon = Icons.translate;
      iconColor = const Color(0xFF4EC9B0);
    } else if (log.contains('TTS:')) {
      textColor = const Color(0xFFDCDCAA); // Yellow
      icon = Icons.volume_up;
      iconColor = const Color(0xFFDCDCAA);
    } else if (log.contains('Cutting:')) {
      textColor = const Color(0xFFCE9178); // Orange
      icon = Icons.cut;
      iconColor = const Color(0xFFCE9178);
    } else if (log.contains('Merging:')) {
      textColor = const Color(0xFF9CDCFE); // Light blue
      icon = Icons.merge;
      iconColor = const Color(0xFF9CDCFE);
    } else if (log.contains('✓') || log.contains('Complete')) {
      textColor = const Color(0xFF6A9955); // Green
      icon = Icons.check_circle;
      iconColor = const Color(0xFF6A9955);
    } else if (log.contains('✗') || log.contains('Error')) {
      textColor = const Color(0xFFF48771); // Red
      icon = Icons.error;
      iconColor = const Color(0xFFF48771);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              log,
              style: TextStyle(
                color: textColor,
                fontFamily: 'Courier',
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
