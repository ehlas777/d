import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/auto_translation_progress.dart';
import '../models/auto_translation_state.dart';
import '../l10n/app_localizations.dart';

/// Real-time progress monitor for automatic translation
/// Shows console-style logs of current operations and per-segment status
class AutoTranslationProgressPanel extends StatelessWidget {
  final List<String> logs;
  final bool isActive;
  final List<SegmentProgressInfo>? segmentProgresses;

  const AutoTranslationProgressPanel({
    super.key,
    required this.logs,
    this.isActive = false,
    this.segmentProgresses,
  });

  @override
  Widget build(BuildContext context) {
    if (!isActive || logs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      key: ValueKey('logs_${logs.length}'),
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
                Text(
                  AppLocalizations.of(context).automaticTranslationMonitor,
                  style: const TextStyle(
                    color: Color(0xFF4EC9B0), // Cyan
                    fontFamily: 'Courier',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                Text(
                  '${logs.length} ${AppLocalizations.of(context).opsCount}',
                  style: const TextStyle(
                    color: Color(0xFF858585),
                    fontFamily: 'Courier',
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.visible,
                ),
              ],
            ),
          ),

          // Segment grid (if available)
          if (segmentProgresses != null && segmentProgresses!.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFF3E3E3E), width: 1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context).segmentsStatus,
                    style: const TextStyle(
                      color: Color(0xFF858585),
                      fontFamily: 'Courier',
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildSegmentGrid(),
                ],
              ),
            ),
          ],

          // Logs container
          Container(
            constraints: const BoxConstraints(
              maxHeight: 200, // Reduced height to make room for segment grid
            ),
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: logs.length > 10
                    ? logs.sublist(logs.length - 10).map((log) => _buildLogEntry(log)).toList()
                    : logs.map((log) => _buildLogEntry(log)).toList(),
              ),
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

  Widget _buildSegmentGrid() {
    if (segmentProgresses == null || segmentProgresses!.isEmpty) {
      return const SizedBox.shrink();
    }

    // Calculate grid dimensions
    final segmentCount = segmentProgresses!.length;
    final crossAxisCount = segmentCount > 20 ? 10 : (segmentCount > 10 ? 6 : 5);

    return Container(
      constraints: const BoxConstraints(maxHeight: 120),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 1.0,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: segmentProgresses!.length,
        itemBuilder: (context, index) {
          return _buildSegmentCard(segmentProgresses![index]);
        },
      ),
    );
  }

  Widget _buildSegmentCard(SegmentProgressInfo segment) {
    Color backgroundColor;
    Color textColor;
    IconData icon;

    switch (segment.currentStage) {
      case SegmentStage.completed:
        backgroundColor = const Color(0xFF6A9955); // Green
        textColor = Colors.white;
        icon = Icons.check;
        break;
      case SegmentStage.failed:
        backgroundColor = const Color(0xFFF48771); // Red
        textColor = Colors.white;
        icon = Icons.error;
        break;
      case SegmentStage.translating:
        backgroundColor = const Color(0xFF4EC9B0); // Cyan
        textColor = Colors.white;
        icon = Icons.translate;
        break;
      case SegmentStage.generatingTts:
        backgroundColor = const Color(0xFFDCDCAA); // Yellow
        textColor = const Color(0xFF1E1E1E);
        icon = Icons.volume_up;
        break;
      case SegmentStage.cuttingVideo:
        backgroundColor = const Color(0xFFCE9178); // Orange
        textColor = Colors.white;
        icon = Icons.cut;
        break;
      case SegmentStage.merging:
        backgroundColor = const Color(0xFF9CDCFE); // Light blue
        textColor = const Color(0xFF1E1E1E);
        icon = Icons.merge;
        break;
      case SegmentStage.pending:
        backgroundColor = const Color(0xFF2D2D2D); // Dark gray (pending)
        textColor = const Color(0xFF858585);
        icon = Icons.pending_outlined;
        break;
      case SegmentStage.transcribed:
      case SegmentStage.translated:
      case SegmentStage.ttsReady:
      case SegmentStage.cutReady:
      case SegmentStage.merged:
        backgroundColor = const Color(0xFF3E3E3E); // Gray (ready/waiting)
        textColor = const Color(0xFF858585);
        icon = Icons.pending;
        break;
    }

    return Tooltip(
      message: '#${segment.segmentIndex + 1}: ${segment.currentStage.displayName}',
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: backgroundColor.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 12,
              color: textColor,
            ),
            const SizedBox(height: 2),
            Text(
              '${segment.segmentIndex + 1}',
              style: TextStyle(
                color: textColor,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                fontFamily: 'Courier',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogEntry(String log) {
    // Parse log type and colorize
    Color textColor = const Color(0xFFD4D4D4); // Default white
    IconData? icon;
    Color? iconColor;

    if (log.contains('Translating:') || log.contains('Аударма:')) {
      textColor = const Color(0xFF4EC9B0); // Cyan
      icon = Icons.translate;
      iconColor = const Color(0xFF4EC9B0);
    } else if (log.contains('TTS:') || log.contains('Аудио')) {
      textColor = const Color(0xFFDCDCAA); // Yellow
      icon = Icons.volume_up;
      iconColor = const Color(0xFFDCDCAA);
    } else if (log.contains('Cutting:') || log.contains('Видео кесу')) {
      textColor = const Color(0xFFCE9178); // Orange
      icon = Icons.cut;
      iconColor = const Color(0xFFCE9178);
    } else if (log.contains('Merging:') || log.contains('Біріктіру')) {
      textColor = const Color(0xFF9CDCFE); // Light blue
      icon = Icons.merge;
      iconColor = const Color(0xFF9CDCFE);
    } else if (log.contains('Finalizing:') || log.contains('Финалдау')) {
      textColor = const Color(0xFFC586C0); // Purple
      icon = Icons.movie_creation;
      iconColor = const Color(0xFFC586C0);
    } else if (log.contains('✓') || log.contains('Complete') || log.contains('complete')) {
      textColor = const Color(0xFF6A9955); // Green
      icon = Icons.check_circle;
      iconColor = const Color(0xFF6A9955);
    } else if (log.contains('✗') || log.contains('Error') || log.contains('failed')) {
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
