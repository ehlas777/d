import 'translation_models.dart';

/// Processing stage enum
enum ProcessingStage {
  idle,
  transcribing,
  translating,
  generatingTts,
  cuttingVideo,
  mergingVideo,
  finalizing,
  completed,
  paused,
  failed,
}

/// Extension for user-friendly stage names
extension ProcessingStageExtension on ProcessingStage {
  String get displayName {
    switch (this) {
      case ProcessingStage.idle:
        return 'Дайындалуда';
      case ProcessingStage.transcribing:
        return 'Транскрипция жасалуда';
      case ProcessingStage.translating:
        return 'Аударылуда';
      case ProcessingStage.generatingTts:
        return 'Аудио жасалуда';
      case ProcessingStage.cuttingVideo:
        return 'Видео кесілуде';
      case ProcessingStage.mergingVideo:
        return 'Біріктірілуде';
      case ProcessingStage.finalizing:
        return 'Аяқталуда';
      case ProcessingStage.completed:
        return 'Дайын';
      case ProcessingStage.paused:
        return 'Тоқтатылды';
      case ProcessingStage.failed:
        return 'Қате';
    }
  }
}

/// Individual segment processing state
class SegmentProcessingState {
  final int index;
  final String originalText;
  
  // Processing states
  bool transcriptionComplete;
  bool translationComplete;
  bool ttsComplete;
  bool videoCutComplete;
  bool mergeComplete;
  
  // Results
  String? translatedText;
  String? audioPath;
  String? videoSegmentPath;
  String? mergedSegmentPath;
  
  // Error tracking
  String? errorMessage;
  int retryCount;

  SegmentProcessingState({
    required this.index,
    required this.originalText,
    this.transcriptionComplete = false,
    this.translationComplete = false,
    this.ttsComplete = false,
    this.videoCutComplete = false,
    this.mergeComplete = false,
    this.translatedText,
    this.audioPath,
    this.videoSegmentPath,
    this.mergedSegmentPath,
    this.errorMessage,
    this.retryCount = 0,
  });

  bool get isComplete =>
      transcriptionComplete &&
      translationComplete &&
      ttsComplete &&
      videoCutComplete &&
      mergeComplete;

  bool get hasFailed => errorMessage != null;

  Map<String, dynamic> toJson() => {
        'index': index,
        'originalText': originalText,
        'transcriptionComplete': transcriptionComplete,
        'translationComplete': translationComplete,
        'ttsComplete': ttsComplete,
        'videoCutComplete': videoCutComplete,
        'mergeComplete': mergeComplete,
        'translatedText': translatedText,
        'audioPath': audioPath,
        'videoSegmentPath': videoSegmentPath,
        'mergedSegmentPath': mergedSegmentPath,
        'errorMessage': errorMessage,
        'retryCount': retryCount,
      };

  factory SegmentProcessingState.fromJson(Map<String, dynamic> json) {
    return SegmentProcessingState(
      index: json['index'] as int,
      originalText: json['originalText'] as String,
      transcriptionComplete: json['transcriptionComplete'] as bool? ?? false,
      translationComplete: json['translationComplete'] as bool? ?? false,
      ttsComplete: json['ttsComplete'] as bool? ?? false,
      videoCutComplete: json['videoCutComplete'] as bool? ?? false,
      mergeComplete: json['mergeComplete'] as bool? ?? false,
      translatedText: json['translatedText'] as String?,
      audioPath: json['audioPath'] as String?,
      videoSegmentPath: json['videoSegmentPath'] as String?,
      mergedSegmentPath: json['mergedSegmentPath'] as String?,
      errorMessage: json['errorMessage'] as String?,
      retryCount: json['retryCount'] as int? ?? 0,
    );
  }

  SegmentProcessingState copyWith({
    bool? transcriptionComplete,
    bool? translationComplete,
    bool? ttsComplete,
    bool? videoCutComplete,
    bool? mergeComplete,
    String? translatedText,
    String? audioPath,
    String? videoSegmentPath,
    String? mergedSegmentPath,
    String? errorMessage,
    int? retryCount,
  }) {
    return SegmentProcessingState(
      index: index,
      originalText: originalText,
      transcriptionComplete: transcriptionComplete ?? this.transcriptionComplete,
      translationComplete: translationComplete ?? this.translationComplete,
      ttsComplete: ttsComplete ?? this.ttsComplete,
      videoCutComplete: videoCutComplete ?? this.videoCutComplete,
      mergeComplete: mergeComplete ?? this.mergeComplete,
      translatedText: translatedText ?? this.translatedText,
      audioPath: audioPath ?? this.audioPath,
      videoSegmentPath: videoSegmentPath ?? this.videoSegmentPath,
      mergedSegmentPath: mergedSegmentPath ?? this.mergedSegmentPath,
      errorMessage: errorMessage,
      retryCount: retryCount ?? this.retryCount,
    );
  }
}

/// Complete automatic translation state
class AutoTranslationState {
  final String projectId;
  final String videoPath;
  final String targetLanguage;
  final String? sourceLanguage;
  final String? voice;
  
  ProcessingStage currentStage;
  List<SegmentProcessingState> segments;
  
  // Timestamps
  final DateTime startedAt;
  DateTime lastUpdated;
  DateTime? completedAt;
  
  // Paths
  String? splitVideoDir;
  String? audioDir;
  String? mergedVideoDir;
  String? finalVideoPath;
  
  // Statistics
  double? totalCost;
  String? currency;

  AutoTranslationState({
    required this.projectId,
    required this.videoPath,
    required this.targetLanguage,
    this.sourceLanguage,
    this.voice,
    required this.currentStage,
    required this.segments,
    required this.startedAt,
    required this.lastUpdated,
    this.completedAt,
    this.splitVideoDir,
    this.audioDir,
    this.mergedVideoDir,
    this.finalVideoPath,
    this.totalCost,
    this.currency,
  });

  int get totalSegments => segments.length;
  
  int get completedSegments =>
      segments.where((s) => s.isComplete).length;
  
  int get failedSegments =>
      segments.where((s) => s.hasFailed).length;

  bool get isComplete => currentStage == ProcessingStage.completed;
  
  bool get isPaused => currentStage == ProcessingStage.paused;
  
  bool get hasFailed => currentStage == ProcessingStage.failed;

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'videoPath': videoPath,
        'targetLanguage': targetLanguage,
        'sourceLanguage': sourceLanguage,
        'voice': voice,
        'currentStage': currentStage.name,
        'segments': segments.map((s) => s.toJson()).toList(),
        'startedAt': startedAt.toIso8601String(),
        'lastUpdated': lastUpdated.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'splitVideoDir': splitVideoDir,
        'audioDir': audioDir,
        'mergedVideoDir': mergedVideoDir,
        'finalVideoPath': finalVideoPath,
        'totalCost': totalCost,
        'currency': currency,
      };

  factory AutoTranslationState.fromJson(Map<String, dynamic> json) {
    return AutoTranslationState(
      projectId: json['projectId'] as String,
      videoPath: json['videoPath'] as String,
      targetLanguage: json['targetLanguage'] as String,
      sourceLanguage: json['sourceLanguage'] as String?,
      voice: json['voice'] as String?,
      currentStage: ProcessingStage.values.firstWhere(
        (e) => e.name == json['currentStage'],
        orElse: () => ProcessingStage.idle,
      ),
      segments: (json['segments'] as List)
          .map((s) => SegmentProcessingState.fromJson(s))
          .toList(),
      startedAt: DateTime.parse(json['startedAt'] as String),
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      splitVideoDir: json['splitVideoDir'] as String?,
      audioDir: json['audioDir'] as String?,
      mergedVideoDir: json['mergedVideoDir'] as String?,
      finalVideoPath: json['finalVideoPath'] as String?,
      totalCost: json['totalCost'] as double?,
      currency: json['currency'] as String?,
    );
  }

  AutoTranslationState copyWith({
    ProcessingStage? currentStage,
    List<SegmentProcessingState>? segments,
    DateTime? lastUpdated,
    DateTime? completedAt,
    String? splitVideoDir,
    String? audioDir,
    String? mergedVideoDir,
    String? finalVideoPath,
    double? totalCost,
    String? currency,
  }) {
    return AutoTranslationState(
      projectId: projectId,
      videoPath: videoPath,
      targetLanguage: targetLanguage,
      sourceLanguage: sourceLanguage,
      voice: voice,
      currentStage: currentStage ?? this.currentStage,
      segments: segments ?? this.segments,
      startedAt: startedAt,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      completedAt: completedAt ?? this.completedAt,
      splitVideoDir: splitVideoDir ?? this.splitVideoDir,
      audioDir: audioDir ?? this.audioDir,
      mergedVideoDir: mergedVideoDir ?? this.mergedVideoDir,
      finalVideoPath: finalVideoPath ?? this.finalVideoPath,
      totalCost: totalCost ?? this.totalCost,
      currency: currency ?? this.currency,
    );
  }
}
