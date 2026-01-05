import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/auto_translation_state.dart';
import '../models/auto_translation_progress.dart';
import '../models/transcription_result.dart';
import '../models/transcription_options.dart';
import '../models/translation_models.dart';
import 'transcription_service.dart';
import 'backend_translation_service.dart';
import 'openai_tts_service.dart';
import 'video_splitter_service.dart';
import 'auto_translation_storage.dart';
import 'throttled_queue.dart';
import 'network_resilience_handler.dart';
import 'storage_manager.dart';

/// Main orchestrator for automatic translation pipeline
/// Coordinates all services and manages the complete workflow
class AutomaticTranslationOrchestrator {
  // Dependencies
  final TranscriptionService transcriptionService;
  final BackendTranslationService translationService;
  final OpenAiTtsService ttsService;
  final VideoSplitterService videoSplitter;
  final AutoTranslationStorage storage;
  final ThrottledQueue apiQueue;
  final NetworkResilienceHandler networkHandler;
  final StorageManager storageManager;

  // State
  AutoTranslationState? _currentState;
  final _progressController = StreamController<AutoTranslationProgress>.broadcast();
  bool _isPaused = false;
  bool _isCancelled = false;
  Timer? _autoSaveTimer;
  Function(AutoTranslationProgress)? _onProgress; // Store current callback

  AutomaticTranslationOrchestrator({
    required this.transcriptionService,
    required this.translationService,
    required this.ttsService,
    required this.videoSplitter,
    required this.storage,
    required this.apiQueue,
    required this.networkHandler,
    required this.storageManager,
  });

  /// Progress stream for UI updates
  Stream<AutoTranslationProgress> get progressStream => _progressController.stream;

  /// Current state
  AutoTranslationState? get currentState => _currentState;

  /// Process video automatically with full pipeline
  Future<AutoTranslationState> processAutomatic({
    required File videoFile,
    required String targetLanguage,
    String? sourceLanguage,
    String? voice,
    TranscriptionResult? existingTranscriptionResult,
    bool resumeFromSaved = false,
    String? projectId,
    Function(AutoTranslationProgress)? onProgress,
  }) async {
    try {
      _isCancelled = false;
      _isPaused = false;
      _onProgress = onProgress; // Store callback for use in _saveState

      // 1. Initialize or resume state
      if (resumeFromSaved && projectId != null) {
        _currentState = await storage.loadState(projectId);
        if (_currentState == null) {
          throw Exception('No saved state found for project: $projectId');
        }
        print('📂 Resumed project: $projectId');
      } else {
        await _initializeNewProject(
          videoFile: videoFile,
          targetLanguage: targetLanguage,
          sourceLanguage: sourceLanguage,
          voice: voice,
          existingTranscriptionResult: existingTranscriptionResult,
        );
      }

      // 2. Pre-flight checks
      await _preflightChecks(videoFile);

      // 3. Start auto-save
      _startAutoSave();

      // 4. Execute pipeline (skip transcription if result already exists)
      await _executePipeline(videoFile, onProgress, skipTranscription: existingTranscriptionResult != null);

      // 5. Finalize
      _currentState = _currentState!.copyWith(
        currentStage: ProcessingStage.completed,
        completedAt: DateTime.now(),
      );
      await _saveState();

      print('✅ Automatic translation completed!');
      return _currentState!;
    } catch (e) {
      print('❌ Automatic translation failed: $e');
      
      if (_currentState != null) {
        _currentState = _currentState!.copyWith(
          currentStage: ProcessingStage.failed,
        );
        await _saveState();
      }
      
      rethrow;
    } finally {
      _stopAutoSave();
    }
  }

  /// Pause processing
  Future<void> pause() async {
    _isPaused = true;
    if (_currentState != null) {
      _currentState = _currentState!.copyWith(
        currentStage: ProcessingStage.paused,
      );
      await _saveState();
    }
    print('⏸️ Processing paused');
  }

  /// Resume processing
  Future<void> resume() async {
    _isPaused = false;
    print('▶️ Processing resumed');
  }

  /// Cancel processing
  Future<void> cancel() async {
    _isCancelled = true;
    print('🛑 Processing cancelled');
  }

  // Private methods

  Future<void> _initializeNewProject({
    required File videoFile,
    required String targetLanguage,
    String? sourceLanguage,
    String? voice,
    TranscriptionResult? existingTranscriptionResult,
  }) async {
    final projectId = const Uuid().v4();
    
    // If transcription exists, create segments from it
    final segments = existingTranscriptionResult != null
        ? existingTranscriptionResult.segments.asMap().entries.map((entry) {
            return SegmentProcessingState(
              index: entry.key,
              originalText: entry.value.text,
              transcriptionComplete: true,
            );
          }).toList()
        : <SegmentProcessingState>[];
    
    _currentState = AutoTranslationState(
      projectId: projectId,
      videoPath: videoFile.path,
      targetLanguage: targetLanguage,
      sourceLanguage: sourceLanguage ?? existingTranscriptionResult?.detectedLanguage,
      voice: voice,
      currentStage: existingTranscriptionResult != null 
          ? ProcessingStage.translating 
          : ProcessingStage.idle,
      segments: segments,
      startedAt: DateTime.now(),
      lastUpdated: DateTime.now(),
    );

    await _saveState();
    print('📝 Created new project: $projectId');
  }

  Future<void> _preflightChecks(File videoFile) async {
    print('🔍 Running pre-flight checks...');

    // 1. Check video file exists
    if (!await videoFile.exists()) {
      throw Exception('Video file not found: ${videoFile.path}');
    }

    // 2. Check network
    if (!await networkHandler.hasNetwork()) {
      throw Exception('No internet connection');
    }

    // 3. Check storage
    final requiredMB = await storageManager.estimateRequiredSpace(
      videoPath: videoFile.path,
      segmentCount: 100, // Estimated max segments
    );
    
    if (!await storageManager.hasEnoughSpace(requiredMB)) {
      throw InsufficientStorageException(requiredMB: requiredMB);
    }

    print('✅ Pre-flight checks passed');
  }

  Future<void> _executePipeline(
    File videoFile,
    Function(AutoTranslationProgress)? onProgress, {
    bool skipTranscription = false,
  }) async {
    // Stage 1: Transcription (skip if already done)
    if (!skipTranscription) {
      await _stageTranscription(videoFile, onProgress);
      _checkPauseOrCancel();
    } else {
      print('⏭️ Skipping transcription - using existing result');
    }

    // Stage 2: Translation (parallel)
    await _stageTranslation(onProgress);
    _checkPauseOrCancel();

    // Stage 3: TTS (parallel)
    await _stageTts(onProgress);
    _checkPauseOrCancel();

    // Stage 4: Video cutting (parallel)
    await _stageVideoCutting(videoFile, onProgress);
    _checkPauseOrCancel();

    // Stage 5: Merging
    await _stageMerging(onProgress);
    _checkPauseOrCancel();

    // Stage 6: Final assembly
    await _stageFinalAssembly(onProgress);
  }

  Future<void> _stageTranscription(
    File videoFile,
    Function(AutoTranslationProgress)? onProgress,
  ) async {
    _currentState = _currentState!.copyWith(
      currentStage: ProcessingStage.transcribing,
    );
    _emitProgress(onProgress, 'Транскрипция бастадық...');

    print('🎤 Stage 1: Transcription');

    final result = await transcriptionService.transcribe(
      videoFile: videoFile,
      options: TranscriptionOptions(
        language: _currentState!.sourceLanguage,
        timestamps: true,
      ),
      onProgress: (progress) {
        _emitProgress(
          onProgress,
          'Транскрипция: ${(progress * 100).toStringAsFixed(0)}%',
        );
      },
    );

    // Create segment states from transcription result
    final segments = result.segments.asMap().entries.map((entry) {
      return SegmentProcessingState(
        index: entry.key,
        originalText: entry.value.text,
        transcriptionComplete: true,
        // Store segment timing for later use
      );
    }).toList();

    _currentState = _currentState!.copyWith(segments: segments);
    await _saveState();

    print('✅ Transcription complete: ${segments.length} segments');
  }

  Future<void> _stageTranslation(
    Function(AutoTranslationProgress)? onProgress,
  ) async {
    _currentState = _currentState!.copyWith(
      currentStage: ProcessingStage.translating,
    );
    _emitProgress(onProgress, 'Аударма бастадық...');

    print('🌐 Stage 2: Translation (parallel)');

    final segments = _currentState!.segments;
    int completed = 0;

    // Process in parallel with throttling
    final futures = segments.map((segment) {
      return apiQueue.add(() async {
        if (segment.translationComplete) {
          return; // Skip already translated
        }

        try {
          final translationSegment = TranslationSegment(
            id: 'segment_${segment.index}',
            text: segment.originalText,
          );

          final result = await networkHandler.retryWithBackoff(
            operation: () => translationService.translateSegments(
              segments: [translationSegment],
              targetLanguage: _currentState!.targetLanguage,
              sourceLanguage: _currentState!.sourceLanguage,
              durationSeconds: 10, // Rough estimate per segment
            ),
          );

          if (result.success && result.translatedSegments.isNotEmpty) {
            final updatedSegment = segment.copyWith(
              translatedText: result.translatedSegments.first.translatedText,
              translationComplete: true,
            );

            // Update state
            _currentState!.segments[segment.index] = updatedSegment;
            completed++;

            _emitProgress(
              onProgress,
              '🌐 Аударма: $completed/${segments.length} (${(completed * 100 / segments.length).toStringAsFixed(0)}%)',
            );
          }
        } catch (e) {
          print('❌ Translation failed for segment ${segment.index}: $e');
          final updatedSegment = segment.copyWith(
            errorMessage: e.toString(),
          );
          _currentState!.segments[segment.index] = updatedSegment;
        }
      });
    }).toList();

    await Future.wait(futures);
    await _saveState();

    print('✅ Translation complete: $completed/${segments.length} segments');
  }

  Future<void> _stageTts(
    Function(AutoTranslationProgress)? onProgress,
  ) async {
    _currentState = _currentState!.copyWith(
      currentStage: ProcessingStage.generatingTts,
    );
    _emitProgress(onProgress, 'Аудио жасалуда...');

    print('🔊 Stage 3: TTS (parallel)');

    final appDir = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${appDir.path}/tts_audio/${_currentState!.projectId}');
    await audioDir.create(recursive: true);
    _currentState = _currentState!.copyWith(audioDir: audioDir.path);

    final segments = _currentState!.segments;
    int completed = 0;

    final futures = segments.map((segment) {
      return apiQueue.add(() async {
        if (segment.ttsComplete || segment.translatedText == null) {
          return;
        }

        try {
          final audioFile = await networkHandler.retryWithBackoff(
            operation: () => ttsService.convert(
              text: segment.translatedText!,
              voice: _currentState!.voice ?? 'alloy',
            ),
          );

          // Move to organized directory
          final targetPath = '${audioDir.path}/segment_${segment.index + 1}.mp3';
          await audioFile.copy(targetPath);
          await audioFile.delete();

          final updatedSegment = segment.copyWith(
            audioPath: targetPath,
            ttsComplete: true,
          );

          _currentState!.segments[segment.index] = updatedSegment;
          completed++;

          // Always report progress to show continuous activity
          _emitProgress(
            onProgress,
            '🔊 Аудио жасау: $completed/${segments.length} (${(completed * 100 / segments.length).toStringAsFixed(0)}%)',
          );
        } catch (e) {
          print('❌ TTS failed for segment ${segment.index}: $e');
          final updatedSegment = segment.copyWith(
            errorMessage: e.toString(),
          );
          _currentState!.segments[segment.index] = updatedSegment;
        }
      });
    }).toList();

    await Future.wait(futures);
    await _saveState();

    print('✅ TTS complete: $completed/${segments.length} segments');
  }

  Future<void> _stageVideoCutting(
    File videoFile,
    Function(AutoTranslationProgress)? onProgress,
  ) async {
    _currentState = _currentState!.copyWith(
      currentStage: ProcessingStage.cuttingVideo,
    );
    _emitProgress(onProgress, 'Видео кесілуде...');

    print('✂️ Stage 4: Video cutting');

    final appDir = await getApplicationDocumentsDirectory();
    final splitDir = Directory('${appDir.path}/split_videos/${_currentState!.projectId}');
    await splitDir.create(recursive: true);

    _currentState = _currentState!.copyWith(splitVideoDir: splitDir.path);

    // Convert segments to transcription segments
    final transcriptionSegments = _currentState!.segments.map((s) {
      return TranscriptionSegment(
        start: s.index * 5.0, // Placeholder timing
        end: (s.index + 1) * 5.0,
        text: s.originalText,
        language: _currentState!.sourceLanguage ?? 'auto',
      );
    }).toList();

    await videoSplitter.splitVideoBySegments(
      videoPath: videoFile.path,
      segments: transcriptionSegments,
      outputDir: splitDir.path,
      onProgress: (progress) {
        _emitProgress(
          onProgress,
          '✂️ Видео кесу: ${(progress * 100).toStringAsFixed(0)}%',
        );
      },
    );

    // Update segment states
    for (var i = 0; i < _currentState!.segments.length; i++) {
      final videoPath = '${splitDir.path}/segment_${i + 1}.mp4';
      _currentState!.segments[i] = _currentState!.segments[i].copyWith(
        videoSegmentPath: videoPath,
        videoCutComplete: true,
      );
    }

    await _saveState();
    print('✅ Video cutting complete');
  }

  Future<void> _stageMerging(
    Function(AutoTranslationProgress)? onProgress,
  ) async {
    _currentState = _currentState!.copyWith(
      currentStage: ProcessingStage.mergingVideo,
    );
    _emitProgress(onProgress, 'Біріктірілуде...');

    print('🔗 Stage 5: Merging video with audio');

    final appDir = await getApplicationDocumentsDirectory();
    final mergedDir = Directory('${appDir.path}/merged_videos/${_currentState!.projectId}');
    await mergedDir.create(recursive: true);

    _currentState = _currentState!.copyWith(mergedVideoDir: mergedDir.path);

    final transcriptionSegments = _currentState!.segments.map((s) {
      return TranscriptionSegment(
        start: s.index * 5.0,
        end: (s.index + 1) * 5.0,
        text: s.originalText,
        language: _currentState!.sourceLanguage ?? 'auto',
      );
    }).toList();

    await videoSplitter.mergeVideoWithAudio(
      splitVideoDir: _currentState!.splitVideoDir!,
      audioDir: _currentState!.audioDir!,
      segments: transcriptionSegments,
      outputDir: mergedDir.path,
      onProgress: (progress) {
        _emitProgress(
          onProgress,
          '🔗 Біріктіру: ${(progress * 100).toStringAsFixed(0)}%',
        );
      },
    );

    for (var i = 0; i < _currentState!.segments.length; i++) {
      final mergedPath = '${mergedDir.path}/merged_${i + 1}.mp4';
      _currentState!.segments[i] = _currentState!.segments[i].copyWith(
        mergedSegmentPath: mergedPath,
        mergeComplete: true,
      );
    }

    await _saveState();
    print('✅ Merging complete');
  }

  Future<void> _stageFinalAssembly(
    Function(AutoTranslationProgress)? onProgress,
  ) async {
    _currentState = _currentState!.copyWith(
      currentStage: ProcessingStage.finalizing,
    );
    _emitProgress(onProgress, 'Аяқталуда...');

    print('🎬 Stage 6: Final assembly');

    final appDir = await getApplicationDocumentsDirectory();
    final finalPath = '${appDir.path}/final_${_currentState!.projectId}.mp4';

    await videoSplitter.concatenateAndSpeedUp(
      mergedVideoDir: _currentState!.mergedVideoDir!,
      outputPath: finalPath,
      speedMultiplier: 1.0,
      onProgress: (progress) {
        _emitProgress(
          onProgress,
          '🎬 Финалдау: ${(progress * 100).toStringAsFixed(0)}%',
        );
      },
    );

    _currentState = _currentState!.copyWith(finalVideoPath: finalPath);
    await _saveState();

    print('✅ Final assembly complete: $finalPath');
  }

  void _checkPauseOrCancel() {
    if (_isCancelled) {
      throw Exception('Processing cancelled by user');
    }
    
    while (_isPaused) {
      // Busy wait - in production, use better synchronization
      Future.delayed(const Duration(milliseconds: 100));
    }
  }

  void _emitProgress(
    Function(AutoTranslationProgress)? onProgress,
    String activity,
  ) {
    if (_currentState == null) return;

    final progress = AutoTranslationProgress.fromState(
      _currentState!,
      currentActivity: activity,
    );

    _progressController.add(progress);
    onProgress?.call(progress);
  }

  Future<void> _saveState() async {
    if (_currentState != null) {
      _currentState = _currentState!.copyWith(
        lastUpdated: DateTime.now(),
      );
      await storage.saveState(_currentState!);
      
      // State save messages removed to reduce monitor noise
      // Progress is shown by stage-specific updates instead
      // _emitProgress(
      //   _onProgress,
      //   '💾 State saved: ${_currentState!.projectId.substring(0, 8)}...',
      // );
    }
  }

  void _startAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _saveState();
    });
  }

  void _stopAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
  }

  /// Dispose resources
  void dispose() {
    _stopAutoSave();
    _progressController.close();
  }
}
