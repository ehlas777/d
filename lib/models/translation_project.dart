import 'transcription_result.dart';

enum ProjectStep {
  transcription, // Step 1: Video to text transcription
  translation,   // Step 2: Text translation and correction
  tts,          // Step 3: Text-to-speech generation
  merge,        // Step 4: Merge audio and video
  completed     // All steps completed
}

enum ProjectStatus {
  notStarted,
  inProgress,
  completed,
  failed
}

class StepProgress {
  final ProjectStep step;
  final ProjectStatus status;
  final double progress; // 0.0 to 1.0
  final String? errorMessage;
  final DateTime? startedAt;
  final DateTime? completedAt;

  StepProgress({
    required this.step,
    required this.status,
    this.progress = 0.0,
    this.errorMessage,
    this.startedAt,
    this.completedAt,
  });

  factory StepProgress.fromJson(Map<String, dynamic> json) {
    return StepProgress(
      step: ProjectStep.values[json['step'] as int],
      status: ProjectStatus.values[json['status'] as int],
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      errorMessage: json['errorMessage'] as String?,
      startedAt: json['startedAt'] != null
          ? DateTime.parse(json['startedAt'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'step': step.index,
      'status': status.index,
      'progress': progress,
      'errorMessage': errorMessage,
      'startedAt': startedAt?.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
    };
  }

  StepProgress copyWith({
    ProjectStep? step,
    ProjectStatus? status,
    double? progress,
    String? errorMessage,
    DateTime? startedAt,
    DateTime? completedAt,
  }) {
    return StepProgress(
      step: step ?? this.step,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

class TranslationProject {
  final String id;
  final String videoFileName;
  final String videoPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ProjectStep currentStep;
  final Map<ProjectStep, StepProgress> steps;

  // Step 1: Transcription results
  final TranscriptionResult? transcriptionResult;

  // Step 2: Translation results
  final String? sourceLanguage;
  final String? targetLanguage;
  final Map<int, String>? translatedSegments; // segment index -> translated text

  // Step 3: TTS results
  final String? audioPath;

  // Step 4: Final merged video output
  final String? finalVideoPath;

  TranslationProject({
    required this.id,
    required this.videoFileName,
    required this.videoPath,
    required this.createdAt,
    required this.updatedAt,
    required this.currentStep,
    required this.steps,
    this.transcriptionResult,
    this.sourceLanguage,
    this.targetLanguage,
    this.translatedSegments,
    this.audioPath,
    this.finalVideoPath,
  });

  factory TranslationProject.create({
    required String videoFileName,
    required String videoPath,
  }) {
    final now = DateTime.now();
    final id = '${now.millisecondsSinceEpoch}_${videoFileName.hashCode}';

    return TranslationProject(
      id: id,
      videoFileName: videoFileName,
      videoPath: videoPath,
      createdAt: now,
      updatedAt: now,
      currentStep: ProjectStep.transcription,
      steps: {
        ProjectStep.transcription: StepProgress(
          step: ProjectStep.transcription,
          status: ProjectStatus.notStarted,
        ),
        ProjectStep.translation: StepProgress(
          step: ProjectStep.translation,
          status: ProjectStatus.notStarted,
        ),
        ProjectStep.tts: StepProgress(
          step: ProjectStep.tts,
          status: ProjectStatus.notStarted,
        ),
        ProjectStep.merge: StepProgress(
          step: ProjectStep.merge,
          status: ProjectStatus.notStarted,
        ),
        ProjectStep.completed: StepProgress(
          step: ProjectStep.completed,
          status: ProjectStatus.notStarted,
        ),
      },
    );
  }

  factory TranslationProject.fromJson(Map<String, dynamic> json) {
    final stepsMap = <ProjectStep, StepProgress>{};
    final stepsJson = json['steps'] as Map<String, dynamic>;

    for (var entry in stepsJson.entries) {
      final step = ProjectStep.values[int.parse(entry.key)];
      stepsMap[step] = StepProgress.fromJson(entry.value as Map<String, dynamic>);
    }

    final translatedSegmentsJson = json['translatedSegments'] as Map<String, dynamic>?;
    final translatedSegments = translatedSegmentsJson?.map(
      (key, value) => MapEntry(int.parse(key), value as String),
    );

    return TranslationProject(
      id: json['id'] as String,
      videoFileName: json['videoFileName'] as String,
      videoPath: json['videoPath'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      currentStep: ProjectStep.values[json['currentStep'] as int],
      steps: stepsMap,
      transcriptionResult: json['transcriptionResult'] != null
          ? TranscriptionResult.fromJson(json['transcriptionResult'] as Map<String, dynamic>)
          : null,
      sourceLanguage: json['sourceLanguage'] as String?,
      targetLanguage: json['targetLanguage'] as String?,
      translatedSegments: translatedSegments,
      audioPath: json['audioPath'] as String?,
      finalVideoPath: json['finalVideoPath'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final stepsJson = <String, dynamic>{};
    steps.forEach((key, value) {
      stepsJson[key.index.toString()] = value.toJson();
    });

    final translatedSegmentsJson = translatedSegments?.map(
      (key, value) => MapEntry(key.toString(), value),
    );

    return {
      'id': id,
      'videoFileName': videoFileName,
      'videoPath': videoPath,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'currentStep': currentStep.index,
      'steps': stepsJson,
      'transcriptionResult': transcriptionResult?.toJson(),
      'sourceLanguage': sourceLanguage,
      'targetLanguage': targetLanguage,
      'translatedSegments': translatedSegmentsJson,
      'audioPath': audioPath,
      'finalVideoPath': finalVideoPath,
    };
  }

  TranslationProject copyWith({
    String? id,
    String? videoFileName,
    String? videoPath,
    DateTime? createdAt,
    DateTime? updatedAt,
    ProjectStep? currentStep,
    Map<ProjectStep, StepProgress>? steps,
    TranscriptionResult? transcriptionResult,
    String? sourceLanguage,
    String? targetLanguage,
    Map<int, String>? translatedSegments,
    String? audioPath,
    String? finalVideoPath,
  }) {
    return TranslationProject(
      id: id ?? this.id,
      videoFileName: videoFileName ?? this.videoFileName,
      videoPath: videoPath ?? this.videoPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      currentStep: currentStep ?? this.currentStep,
      steps: steps ?? this.steps,
      transcriptionResult: transcriptionResult ?? this.transcriptionResult,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      translatedSegments: translatedSegments ?? this.translatedSegments,
      audioPath: audioPath ?? this.audioPath,
      finalVideoPath: finalVideoPath ?? this.finalVideoPath,
    );
  }

  // Helper methods
  bool get isTranscriptionCompleted =>
      steps[ProjectStep.transcription]?.status == ProjectStatus.completed;

  // МАҢЫЗДЫ: Translation қадамы үшін "inProgress" + progress = 1.0 болса, аударма бітті
  bool get isTranslationCompleted {
    final translationStep = steps[ProjectStep.translation];
    if (translationStep == null) return false;

    // Егер status "completed" болса немесе "inProgress" және progress >= 1.0 болса
    if (translationStep.status == ProjectStatus.completed) {
      return true;
    }
    
    if (translationStep.status == ProjectStatus.inProgress) {
      return translationStep.progress >= 1.0;
    }

    return false;
  }

  bool get isTtsCompleted =>
      steps[ProjectStep.tts]?.status == ProjectStatus.completed;

  bool get isFullyCompleted => currentStep == ProjectStep.completed;

  ProjectStep? get nextStep {
    switch (currentStep) {
      case ProjectStep.transcription:
        return isTranscriptionCompleted ? ProjectStep.translation : null;
      case ProjectStep.translation:
        return isTranslationCompleted ? ProjectStep.tts : null;
      case ProjectStep.tts:
        return isTtsCompleted ? ProjectStep.merge : null;
      case ProjectStep.merge:
        return steps[ProjectStep.merge]?.status == ProjectStatus.completed ? ProjectStep.completed : null;
      case ProjectStep.completed:
        return null;
    }
  }

  double get overallProgress {
    final completedSteps = steps.values
        .where((s) => s.status == ProjectStatus.completed)
        .length;
    return completedSteps / steps.length;
  }
}
