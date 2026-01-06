import 'auto_translation_state.dart';

/// Individual segment progress information
class SegmentProgressInfo {
  final int segmentIndex;
  final SegmentStage currentStage;
  final String? errorMessage;

  SegmentProgressInfo({
    required this.segmentIndex,
    required this.currentStage,
    this.errorMessage,
  });

  factory SegmentProgressInfo.fromSegment(SegmentProcessingState segment) {
    return SegmentProgressInfo(
      segmentIndex: segment.index,
      currentStage: segment.currentStage,
      errorMessage: segment.errorMessage,
    );
  }
}

/// Progress report for automatic translation
class AutoTranslationProgress {
  final ProcessingStage stage;
  final int completedSegments;
  final int totalSegments;
  final int? currentSegmentIndex;
  final double percentage;
  final Duration? estimatedTimeRemaining;
  final String? currentActivity;

  // Per-segment progress tracking
  final List<SegmentProgressInfo> segmentProgresses;

  // Cost tracking
  final double? currentCost;
  final String? currency;

  AutoTranslationProgress({
    required this.stage,
    required this.completedSegments,
    required this.totalSegments,
    this.currentSegmentIndex,
    required this.percentage,
    this.estimatedTimeRemaining,
    this.currentActivity,
    this.segmentProgresses = const [],
    this.currentCost,
    this.currency,
  });

  // Helper getters for stage-based segment counts
  int get segmentsTranslating =>
      segmentProgresses.where((s) => s.currentStage == SegmentStage.translating).length;

  int get segmentsInTts =>
      segmentProgresses.where((s) => s.currentStage == SegmentStage.generatingTts).length;

  int get segmentsCutting =>
      segmentProgresses.where((s) => s.currentStage == SegmentStage.cuttingVideo).length;

  int get segmentsMerging =>
      segmentProgresses.where((s) => s.currentStage == SegmentStage.merging).length;

  factory AutoTranslationProgress.fromState(
    AutoTranslationState state, {
    Duration? estimatedTimeRemaining,
    String? currentActivity,
  }) {
    // Calculate percentage based on stage and segment completion
    double percentage = 0.0;
    
    switch (state.currentStage) {
      case ProcessingStage.idle:
        percentage = 0.0;
        break;
      case ProcessingStage.transcribing:
        percentage = 10.0; // Transcription is 0-20%
        break;
      case ProcessingStage.translating:
        // Translation is 20-50%
        final translationProgress = state.segments.isEmpty
            ? 0.0
            : state.segments.where((s) => s.translationComplete).length /
                state.segments.length;
        percentage = 20.0 + (translationProgress * 30.0);
        break;
      case ProcessingStage.generatingTts:
        // TTS is 50-70%
        final ttsProgress = state.segments.isEmpty
            ? 0.0
            : state.segments.where((s) => s.ttsComplete).length /
                state.segments.length;
        percentage = 50.0 + (ttsProgress * 20.0);
        break;
      case ProcessingStage.cuttingVideo:
        // Video cutting is 70-85%
        final cutProgress = state.segments.isEmpty
            ? 0.0
            : state.segments.where((s) => s.videoCutComplete).length /
                state.segments.length;
        percentage = 70.0 + (cutProgress * 15.0);
        break;
      case ProcessingStage.mergingVideo:
        // Merging is 85-95%
        final mergeProgress = state.segments.isEmpty
            ? 0.0
            : state.segments.where((s) => s.mergeComplete).length /
                state.segments.length;
        percentage = 85.0 + (mergeProgress * 10.0);
        break;
      case ProcessingStage.finalizing:
        percentage = 95.0;
        break;
      case ProcessingStage.completed:
        percentage = 100.0;
        break;
      case ProcessingStage.paused:
      case ProcessingStage.failed:
        // Keep current percentage
        percentage = _calculateCurrentPercentage(state);
        break;
    }

    return AutoTranslationProgress(
      stage: state.currentStage,
      completedSegments: state.completedSegments,
      totalSegments: state.totalSegments,
      percentage: percentage.clamp(0.0, 100.0),
      estimatedTimeRemaining: estimatedTimeRemaining,
      currentActivity: currentActivity ?? state.currentStage.displayName,
      segmentProgresses: state.segments
          .map((s) => SegmentProgressInfo.fromSegment(s))
          .toList(),
      currentCost: state.totalCost,
      currency: state.currency,
    );
  }

  static double _calculateCurrentPercentage(AutoTranslationState state) {
    // Rough estimate based on completed segments
    if (state.segments.isEmpty) return 0.0;
    
    final progress = state.completedSegments / state.totalSegments;
    return progress * 85.0; // Up to merging stage
  }

  /// User-friendly progress message
  String get progressMessage {
    if (totalSegments == 0) {
      return currentActivity ?? stage.displayName;
    }
    
    return '${stage.displayName}: $completedSegments/$totalSegments сегмент';
  }

  /// Detailed status message
  String get detailedStatus {
    final parts = <String>[
      progressMessage,
      '${percentage.toStringAsFixed(1)}% дайын',
    ];
    
    if (estimatedTimeRemaining != null) {
      parts.add('~${_formatDuration(estimatedTimeRemaining!)} қалды');
    }
    
    if (currentCost != null && currency != null) {
      parts.add('Құн: ${currentCost!.toStringAsFixed(2)} $currency');
    }
    
    return parts.join(' • ');
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}с ${duration.inMinutes.remainder(60)}м';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}м ${duration.inSeconds.remainder(60)}с';
    } else {
      return '${duration.inSeconds}с';
    }
  }

  @override
  String toString() => detailedStatus;
}
