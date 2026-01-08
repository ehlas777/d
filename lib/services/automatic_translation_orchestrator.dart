import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
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
import '../services/background_notification_manager.dart';
import '../exceptions/balance_exceptions.dart';
import '../services/auth_service.dart';

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
  final AuthService authService; // Added dependency

  // State
  AutoTranslationState? _currentState;
  final _progressController = StreamController<AutoTranslationProgress>.broadcast();
  bool _isPaused = false;
  bool _isCancelled = false;
  bool _isDisposed = false; // Dispose safety flag
  Timer? _autoSaveTimer;
  Function(AutoTranslationProgress)? _onProgress; // Store current callback
  bool _isBackgroundMode = false;
  bool _wakeLockEnabled = false;
  final BackgroundNotificationManager _notificationManager = BackgroundNotificationManager.instance;
  
  // Queue references for cleanup on cancel
  ThrottledQueue? _translationQueue;
  ThrottledQueue? _ttsQueue;
  ThrottledQueue? _cuttingQueue;
  ThrottledQueue? _mergingQueue;

  AutomaticTranslationOrchestrator({
    required this.transcriptionService,
    required this.translationService,
    required this.ttsService,
    required this.videoSplitter,
    required this.storage,
    required this.apiQueue,
    required this.networkHandler,
    required this.storageManager,
    required this.authService,
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
    double? videoSpeed, // User's video speed preference
    TranscriptionResult? existingTranscriptionResult,
    bool resumeFromSaved = false,
    String? projectId,
    Function(AutoTranslationProgress)? onProgress,
    String? username, // Added username parameter
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
      } else {
        await _initializeNewProject(
          videoFile: videoFile,
          targetLanguage: targetLanguage,
          sourceLanguage: sourceLanguage,
          voice: voice,
          videoSpeed: videoSpeed,
          existingTranscriptionResult: existingTranscriptionResult,
        );
      }

      // 2. Pre-flight checks
      await _preflightChecks(videoFile, username: username);

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

      print('✅ Аударма аяқталды!');
      return _currentState!;
    } catch (e) {
      print('❌ Қате: $e');

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
  }

  /// Resume processing
  Future<void> resume() async {
    _isPaused = false;
  }

  /// Cancel processing
  Future<void> cancel() async {
    _isCancelled = true;
    
    // Clear all pending tasks from queues
    _translationQueue?.clear();
    _ttsQueue?.clear();
    _cuttingQueue?.clear();
    _mergingQueue?.clear();
    
    print('🛑 Cancellation: Cleared all pending queue tasks');
  }

  // Private methods

  Future<void> _initializeNewProject({
    required File videoFile,
    required String targetLanguage,
    String? sourceLanguage,
    String? voice,
    double? videoSpeed,
    TranscriptionResult? existingTranscriptionResult,
  }) async {
    final projectId = const Uuid().v4();

    // If transcription exists, merge segments first, then create segment states
    final segments = existingTranscriptionResult != null
        ? () {
            // Merge segments based on count using the same rules as transcription stage
            print('📊 Транскрипция: ${existingTranscriptionResult.segments.length} сегмент');
            final mergedSegments = videoSplitter.mergeSegments(existingTranscriptionResult.segments);
            print('📊 Біріктірілді: ${mergedSegments.length} сегмент');

            // Create segment states from merged segments
            return mergedSegments.asMap().entries.map((entry) {
              final segment = entry.value;
              return SegmentProcessingState(
                index: entry.key,
                originalText: segment.text,
                segmentStartTime: segment.start,
                segmentEndTime: segment.end,
                segmentDuration: segment.end - segment.start,
                currentStage: SegmentStage.transcribed,
                transcriptionComplete: true,
              );
            }).toList();
          }()
        : <SegmentProcessingState>[];

    _currentState = AutoTranslationState(
      projectId: projectId,
      videoPath: videoFile.path,
      targetLanguage: targetLanguage,
      sourceLanguage: sourceLanguage ?? existingTranscriptionResult?.detectedLanguage,
      voice: voice,
      videoSpeed: videoSpeed ?? 1.2, // Default to 1.2x if not provided
      currentStage: existingTranscriptionResult != null
          ? ProcessingStage.translating
          : ProcessingStage.idle,
      segments: segments,
      startedAt: DateTime.now(),
      lastUpdated: DateTime.now(),
    );

    await _saveState();
  }

  Future<void> _preflightChecks(File videoFile, {String? username}) async {
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

    // 4. Check Balance & Duration Limits (Two-Bucket System)
    try {
      final durationSeconds = await videoSplitter.getVideoDuration(videoFile.path);
      final durationMinutes = durationSeconds / 60.0;
      
      print('🔍 Pre-flight Balance Check:');
      print('   Video Duration: $durationSeconds sec (${durationMinutes.toStringAsFixed(2)} min)');

      // Fetch fresh user data (authoritative source)
      final user = await authService.getUserMinutesInfo(searchQuery: username);
      
      if (user == null) {
        throw Exception('Failed to retrieve user balance information');
      }
      
      // Check if video is too long (using new field maxVideoDuration)
      if (user.maxVideoDuration != null && durationMinutes > user.maxVideoDuration!) {
        throw VideoTooLongException(
          videoDuration: durationMinutes,
          maxAllowed: user.maxVideoDuration!,
        );
      }

      // Check if user has enough minutes (daily + extra)
      if (!user.hasEnoughMinutes(durationMinutes)) {
         throw InsufficientBalanceException(
           required: durationMinutes,
           available: user.totalAvailable, // Two-bucket total
         );
      }
      
      print('✅ Balance check passed: Available ${user.totalAvailable.toStringAsFixed(2)} min');

    } catch (e) {
      print('❌ Pre-flight check failed: $e');
      rethrow;
    }
  }

  Future<void> _executePipeline(
    File videoFile,
    Function(AutoTranslationProgress)? onProgress, {
    bool skipTranscription = false,
  }) async {
    // Stage 1: Transcription (Global - must be done first)
    if (!skipTranscription) {
      await _stageTranscription(videoFile, onProgress);
      _checkPauseOrCancel();
    }

    // Stage 2: Parallel Pipeline (Translate -> TTS -> Cut -> Merge)
    await _processAllSegmentsParallel(videoFile, onProgress);
    _checkPauseOrCancel();

    // Stage 3: Final Assembly (Global - must wait for all segments)
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

    // Merge segments based on count
    print('📊 Транскрипция: ${result.segments.length} сегмент');
    final mergedSegments = videoSplitter.mergeSegments(result.segments);
    print('📊 Біріктірілді: ${mergedSegments.length} сегмент');

    // Create segment states from merged transcription result
    final segments = mergedSegments.asMap().entries.map((entry) {
      final segment = entry.value;
      return SegmentProcessingState(
        index: entry.key,
        originalText: segment.text,
        segmentStartTime: segment.start,
        segmentEndTime: segment.end,
        segmentDuration: segment.end - segment.start,
        currentStage: SegmentStage.transcribed,
        transcriptionComplete: true,
      );
    }).toList();

    _currentState = _currentState!.copyWith(segments: segments);
    await _saveState();
  }

  /// Runs the full pipeline for all segments in parallel (throttled)
  Future<void> _processAllSegmentsParallel(
    File videoFile,
    Function(AutoTranslationProgress)? onProgress,
  ) async {
    _currentState = _currentState!.copyWith(
      currentStage: ProcessingStage.translating,
    );
    _emitProgress(onProgress, 'Сегменттер өңделуде...');

    await _enableWakeLock();

    // Prepare directories
    final appDir = await getApplicationDocumentsDirectory();
    final projectId = _currentState!.projectId;

    // Directories
    final audioDir = Directory('${appDir.path}/tts_audio/$projectId');
    await audioDir.create(recursive: true);
    _currentState = _currentState!.copyWith(audioDir: audioDir.path);

    final splitDir = Directory('${appDir.path}/split_videos/$projectId');
    await splitDir.create(recursive: true);
    _currentState = _currentState!.copyWith(splitVideoDir: splitDir.path);

    final mergedDir = Directory('${appDir.path}/merged_videos/$projectId');
    await mergedDir.create(recursive: true);
    _currentState = _currentState!.copyWith(mergedVideoDir: mergedDir.path);

    await _saveState();

    // Initialize queues and store references for cleanup
    // MOBILE OPTIMIZATION: FFmpeg operations (cut/merge) use heavy RAM on mobile
    // Translation and TTS are API calls - safe to keep parallel
    final isMobile = Platform.isIOS || Platform.isAndroid;
    
    _translationQueue = ThrottledQueue(maxConcurrent: 5); // API call - safe on mobile
    _ttsQueue = ThrottledQueue(
      maxConcurrent: 1, // Sequential for rate limiting (all platforms)
      delayBetweenRequests: const Duration(seconds: 1),
    );
    _cuttingQueue = ThrottledQueue(maxConcurrent: isMobile ? 1 : 2); // FFmpeg - limit on mobile
    _mergingQueue = ThrottledQueue(maxConcurrent: isMobile ? 1 : 2); // FFmpeg - limit on mobile
    
    if (isMobile) {
      print('📱 Mobile: Sequential FFmpeg operations to reduce RAM usage');
    }

    final segments = _currentState!.segments;
    int completedTasks = 0; // Rough progress tracker
    final totalTasks = segments.length * 4; // 4 steps per segment

    final futures = segments.map((segment) {
      return _processSingleSegmentFlow(
        segmentIndex: segment.index,
        videoFile: videoFile,
        audioDir: audioDir,
        splitDir: splitDir,
        mergedDir: mergedDir,
        translationQueue: _translationQueue!,
        ttsQueue: _ttsQueue!,
        cuttingQueue: _cuttingQueue!,
        mergingQueue: _mergingQueue!,
        onProgress: onProgress,
        onTaskComplete: () {
          completedTasks++;
          // Optional: detailed progress
        },
      );
    }).toList();

    await Future.wait(futures);
    
    await _disableWakeLock();
    await _saveState();
  }

  /// Processes a SINGLE segment through the entire chain:
  /// Translate -> TTS -> Cut -> Merge
  Future<void> _processSingleSegmentFlow({
    required int segmentIndex,
    required File videoFile,
    required Directory audioDir,
    required Directory splitDir,
    required Directory mergedDir,
    required ThrottledQueue translationQueue,
    required ThrottledQueue ttsQueue,
    required ThrottledQueue cuttingQueue,
    required ThrottledQueue mergingQueue,
    required Function(AutoTranslationProgress)? onProgress,
    required Function() onTaskComplete,
  }) async {
    // Helper to get current state safely
    SegmentProcessingState getSegment() => _currentState!.segments[segmentIndex];

    try {
      // Check cancellation at start
      if (_isCancelled) return;

      // -----------------------------------------------------------------
      // STEP 1: TRANSLATION (Reuse user-provided API Queue logic or separate)
      // -----------------------------------------------------------------
      if (!getSegment().translationComplete) {
        await _retrySegmentOperation(
          segmentIndex: segmentIndex,
          operationName: 'Translation',
          operation: () async {
            await translationQueue.add(() async {
              if (_isCancelled || getSegment().translationComplete) return;

              final segment = getSegment();

              final translationSegment = TranslationSegment(
                id: 'segment_${segment.index}',
                text: segment.originalText,
              );

              // GENERATE IDEMPOTENCY KEY (or reuse if retrying same segment op)
              // Ideally store in segment state, but simpler: deterministic seed from project + segment + retry
              // Better: Generate unique key once per segment translation attempt and persist
              final idempotencyKey = const Uuid().v5(Uuid.NAMESPACE_URL, 'project_${_currentState!.projectId}_seg_${segment.index}_trans');
              
              final result = await translationService.translateSegments(
                segments: [translationSegment],
                targetLanguage: _currentState!.targetLanguage,
                sourceLanguage: _currentState!.sourceLanguage,
                durationSeconds: 10,
                idempotencyKey: idempotencyKey, // CRITICAL: Pass key for deduplication
              );

              if (result.success && result.translatedSegments.isNotEmpty) {
                final translatedText = result.translatedSegments.first.translatedText;
                
                await _updateSegmentState(segmentIndex, (s) => s.copyWith(
                  translatedText: translatedText,
                  translationComplete: true,
                  currentStage: SegmentStage.translated,
                ));
                
                onTaskComplete();
                final progressMsg = '✅ 1/4 Translated: Seg ${segmentIndex + 1}';
                print(progressMsg);
                _emitProgress(onProgress, progressMsg);
              } else {
                throw Exception(result.errorMessage ?? 'Translation failed');
              }
            });
          },
        );
      }

      // -----------------------------------------------------------------
      // STEP 2: TTS
      // -----------------------------------------------------------------
      if (getSegment().translationComplete && !getSegment().ttsComplete) {
         if (getSegment().translatedText == null) throw Exception('No translated text');

         await _retrySegmentOperation(
           segmentIndex: segmentIndex,
           operationName: 'TTS',
           operation: () async {
             await ttsQueue.add(() async {
               if (_isCancelled || getSegment().ttsComplete) return;

               final segment = getSegment();

                final audioFile = await ttsService.convert(
                  text: segment.translatedText!,
                  voice: _currentState!.voice ?? 'alloy',
                );

               // Unique naming to avoid collision
               final targetPath = '${audioDir.path}/seg_${segmentIndex}_tts.mp3';
               final targetFile = File(targetPath);
               
               if (await targetFile.exists()) {
                 await targetFile.delete();
               }
               await audioFile.copy(targetPath);
               await audioFile.delete();

               await _updateSegmentState(segmentIndex, (s) => s.copyWith(
                 audioPath: targetPath,
                 ttsComplete: true,
                 currentStage: SegmentStage.ttsReady,
               ));
               
               onTaskComplete();
               final progressMsg = '✅ 2/4 TTS: Seg ${segmentIndex + 1}';
               print(progressMsg);
               _emitProgress(onProgress, progressMsg);
             });
           },
         );
      }

      // -----------------------------------------------------------------
      // STEP 3: CUT VIDEO
      // -----------------------------------------------------------------
      // Note: Cutting depends on original timestamps, strictly speaking it can start 
      // anytime after transcription, but user wants flow: Translate->TTS->Cut->Merge
      // or Translate->TTS->Video(Cut+Stretch).
      // We'll run it after TTS to follow linear logic or keep CPU spikes managed.
      
      if (getSegment().ttsComplete && !getSegment().videoCutComplete) {
         await _retrySegmentOperation(
           segmentIndex: segmentIndex,
           operationName: 'Video Cut',
           operation: () async {
             await cuttingQueue.add(() async {
               if (_isCancelled || getSegment().videoCutComplete) return;

               final segment = getSegment();

               await _updateSegmentState(segmentIndex, (s) => s.copyWith(
                  currentStage: SegmentStage.cuttingVideo,
               ));

               final transcriptionSegment = TranscriptionSegment(
                 start: segment.segmentStartTime!,
                 end: segment.segmentEndTime!,
                 text: segment.originalText,
                 language: _currentState!.sourceLanguage ?? 'auto',
               );

               // Unique temporary directory for this cut operation
               final tempCutDir = Directory('${splitDir.path}/temp_cut_$segmentIndex');
               await tempCutDir.create(recursive: true);

               await videoSplitter.splitVideoBySegments(
                 videoPath: videoFile.path,
                 segments: [transcriptionSegment],
                 outputDir: tempCutDir.path,
                 onProgress: (_) {},
               );

               // Expecting segment_1.mp4 in temp dir
               final tempOutput = '${tempCutDir.path}/segment_1.mp4';
               final finalOutput = '${splitDir.path}/seg_${segmentIndex}_cut.mp4';

               final tempFile = File(tempOutput);
               if (await tempFile.exists()) {
                  if (await File(finalOutput).exists()) {
                    await File(finalOutput).delete();
                  }
                  await tempFile.rename(finalOutput);
               } else {
                  throw Exception('Cut output not found for segment $segmentIndex');
               }
               
               // Cleanup root segment_1.mp4 if it leaked or temp dir
               // `splitVideoBySegments` might write to outputDir/segment_1.mp4
               await tempCutDir.delete(recursive: true);

               await _updateSegmentState(segmentIndex, (s) => s.copyWith(
                   videoSegmentPath: finalOutput,
                   videoCutComplete: true,
                   currentStage: SegmentStage.cutReady,
               ));
               
               onTaskComplete();
               final progressMsg = '✅ 3/4 Cut: Seg ${segmentIndex + 1}';
               print(progressMsg);
               _emitProgress(onProgress, progressMsg);
             });
           },
         );
      }

      // -----------------------------------------------------------------
      // STEP 4: MERGE
      // -----------------------------------------------------------------
      if (getSegment().videoCutComplete && getSegment().ttsComplete && !getSegment().mergeComplete) {
         await _retrySegmentOperation(
           segmentIndex: segmentIndex,
           operationName: 'Merge',
           operation: () async {
             await mergingQueue.add(() async {
               if (_isCancelled || getSegment().mergeComplete) return;
               
               final segment = getSegment();
               
               // STRICT CHECK: Dependencies
               final videoPath = segment.videoSegmentPath;
               final audioPath = segment.audioPath;
               
               if (videoPath == null || !await File(videoPath).exists()) {
                  throw Exception('Missing video cut file for segment $segmentIndex');
               }
               if (audioPath == null || !await File(audioPath).exists()) {
                  throw Exception('Missing audio file for segment $segmentIndex');
               }

               await _updateSegmentState(segmentIndex, (s) => s.copyWith(
                 currentStage: SegmentStage.merging,
              ));
              
              // Prepare isolated environment for merger
              final tempMergeContextDir = Directory('${mergedDir.path}/ctx_$segmentIndex');
              await tempMergeContextDir.create(recursive: true);
              
              final tempSplitDir = Directory('${tempMergeContextDir.path}/split');
              await tempSplitDir.create();
              final tempAudioDir = Directory('${tempMergeContextDir.path}/audio');
              await tempAudioDir.create();
              
              // Copy/Link files to standard names expected by `mergeVideoWithAudio` (segment_1.mp4)
              await File(videoPath).copy('${tempSplitDir.path}/segment_1.mp4');
              await File(audioPath).copy('${tempAudioDir.path}/segment_1.mp3');
              
              final transcriptionSegment = TranscriptionSegment(
                start: segment.segmentStartTime ?? 0.0,
                end: segment.segmentEndTime ?? 0.0,
                text: segment.originalText,
                language: _currentState!.sourceLanguage ?? 'auto',
              );
              
              await videoSplitter.mergeVideoWithAudio(
                splitVideoDir: tempSplitDir.path, // Directory containing segment_1.mp4
                audioDir: tempAudioDir.path,      // Directory containing segment_1.mp3
                segments: [transcriptionSegment], // List of 1 segment
                outputDir: tempMergeContextDir.path,
                onProgress: (_) {},
              );
              
              final tempOutput = '${tempMergeContextDir.path}/merged_1.mp4';
              // CRITICAL: Use merged_N.mp4 naming to match concatenateAndSpeedUp() expectations
              // concatenateAndSpeedUp() searches for pattern: merged_\\d+\\.mp4
              final finalOutput = '${mergedDir.path}/merged_${segmentIndex + 1}.mp4';
              
              if (await File(tempOutput).exists()) {
                 if (await File(finalOutput).exists()) await File(finalOutput).delete();
                 await File(tempOutput).rename(finalOutput);
              } else {
                 throw Exception('Merge output not found for segment $segmentIndex');
              }
              
              await tempMergeContextDir.delete(recursive: true);
              
               await _updateSegmentState(segmentIndex, (s) => s.copyWith(
                  mergedSegmentPath: finalOutput,
                  mergeComplete: true,
                  currentStage: SegmentStage.merged,
              ));
              
              onTaskComplete();
              final progressMsg = '✅ 4/4 Merge: Seg ${segmentIndex + 1}';
              print(progressMsg);
              _emitProgress(onProgress, progressMsg);
             });
           },
         );
      }
      
      // Update general progress indicator
      _emitProgress(onProgress, 'Сегмент ${segmentIndex + 1} дайын...');

    } catch (e) {
       // Determine which stage failed for better diagnostics
       final segment = getSegment();
       final failedStage = !segment.translationComplete 
           ? 'Translation' 
           : !segment.ttsComplete 
               ? 'TTS' 
               : !segment.videoCutComplete 
                   ? 'Video Cut' 
                   : 'Merge';
       
       final errorType = _categorizeError(e.toString());
       final rootCause = _extractRootCause(e.toString(), failedStage);
       
       final errorMsg = '❌ Seg ${segmentIndex + 1} PIPELINE FAILED at $failedStage stage [$errorType: $rootCause]';
       print(errorMsg);
       _emitProgress(onProgress, errorMsg);
       
       await _updateSegmentState(segmentIndex, (s) => s.copyWith(
          errorMessage: '[$failedStage] $errorType: $rootCause',
          currentStage: SegmentStage.failed,
       ));
       // We do NOT rethrow, so other segments can continue.
    }
  }

  /// Retry a segment operation with progressive backoff and detailed error analysis
  /// Provides segment-level retry for transient errors
  Future<void> _retrySegmentOperation({
    required int segmentIndex,
    required String operationName,
    required Future<void> Function() operation,
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 3),
  }) async {
    await networkHandler.retryWithBackoff(
      maxRetries: maxRetries,
      customDelays: [
        const Duration(seconds: 3),
        const Duration(seconds: 8),
        const Duration(seconds: 20),
      ],
      checkNetwork: false, // Already checked or handled by operation
      shouldRetry: (e) {
        // Analyze error type and root cause for logging
        final errorStr = e.toString();
        final errorType = _categorizeError(errorStr);
        final rootCause = _extractRootCause(errorStr, operationName);

        // Concise log for retry
        print('⚠️ Seg ${segmentIndex + 1} $operationName [$errorType] failed ($rootCause). Retrying...');
        return true; 
      },
      operation: () async {
        try {
          await operation();
        } catch (e) {
           // Rethrow so retryHandler catches it
           rethrow;
        }
      },
    ).catchError((e) {
       // Final failure handler after max retries
       // We re-analyze to print the final detailed error message
        final errorStr = e.toString();
        final errorType = _categorizeError(errorStr);
        final rootCause = _extractRootCause(errorStr, operationName);

        print('❌ Seg ${segmentIndex + 1} $operationName FAILED after retries');
        print('   └─ Type: $errorType | Cause: $rootCause');
        
        throw e; // Propagate to _processSingleSegmentFlow catch block
    });
  }
  
  /// Categorize error type for better diagnostics
  String _categorizeError(String error) {
    final errorLower = error.toLowerCase();
    
    // CRITICAL: Check FFmpeg errors FIRST before SESSION
    // FFmpeg errors can contain various patterns
    if (error.contains('FFmpeg') || 
        error.contains('FFmpeg қатесі') ||
        errorLower.contains('codec') ||
        errorLower.contains('conversion failed') ||
        errorLower.contains('error splitting') ||
        errorLower.contains('invalid data') ||
        error.contains('Invalid argument') || 
        error.contains('No such file')) {
      return 'FFMPEG';
    }
    
    // Then check SESSION errors
    if (error.contains('SESSION_NOT_FOUND') || error.contains('401') || error.contains('Unauthorized')) {
      return 'SESSION';
    } else if (error.contains('SocketException') || error.contains('NetworkException') || error.contains('TimeoutException')) {
      return 'NETWORK';
    } else if (error.contains('429') || error.contains('rate limit')) {
      return 'RATE_LIMIT';
    } else if (error.contains('500') || error.contains('502') || error.contains('503')) {
      return 'SERVER';
    }
    return 'API';
  }
  
  /// Extract meaningful root cause from error message
  String _extractRootCause(String error, String operation) {
    // FFmpeg specific extraction
    if (error.contains('FFmpeg қатесі:')) {
      final match = RegExp(r'FFmpeg қатесі: (.+)').firstMatch(error);
      if (match != null) {
        final ffmpegError = match.group(1)?.trim() ?? '';
        if (ffmpegError.isNotEmpty && ffmpegError.length < 100) {
          return ffmpegError;
        }
      }
      return 'FFmpeg operation failed';
    }
    
    // SESSION errors
    if (error.contains('SESSION_NOT_FOUND')) {
      return 'Session expired or invalidated';
    }
    
    // Network errors
    if (error.contains('SocketException')) {
      return 'Network connection failed';
    }
    if (error.contains('TimeoutException')) {
      return 'Request timed out';
    }
    
    // FFmpeg errors
    if (error.contains('No such file')) {
      return 'Input file missing';
    }
    if (error.contains('Invalid argument')) {
      return 'Invalid FFmpeg parameters';
    }
    if (error.toLowerCase().contains('codec')) {
      return 'Codec error or unsupported format';
    }
    
    // API errors
    if (error.contains('429')) {
      return 'API rate limit exceeded';
    }
    if (error.contains('500')) {
      return 'Server internal error';
    }
    
    // Generic extraction - try to get first meaningful line
    final lines = error.split('\n');
    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty && !trimmed.startsWith('at ') && !trimmed.startsWith('#')) {
        if (trimmed.length > 80) {
          return '${trimmed.substring(0, 77)}...';
        }
        return trimmed;
      }
    }
    
    return 'Unknown error';
  }

  /// Thread-safe update of a single segment's state
  /// Uses a strict read-modify-write pattern on the current state list
  Future<void> _updateSegmentState(
    int index,
    SegmentProcessingState Function(SegmentProcessingState) reducer,
  ) async {
    // Dispose safety: Don't update state after disposal
    if (_isDisposed || _currentState == null) return;
    
    // Create shallow copy of list to ensure immutability of previous state
    final segments = List<SegmentProcessingState>.from(_currentState!.segments);
    
    // Check bounds
    if (index >= 0 && index < segments.length) {
      final oldSegment = segments[index];
      final newSegment = reducer(oldSegment);
      segments[index] = newSegment;
      
      _currentState = _currentState!.copyWith(
        segments: segments,
        lastUpdated: DateTime.now(),
      );
      
      // Notify listeners of state change
      _progressController.add(AutoTranslationProgress.fromState(
         _currentState!,
         currentActivity: 'Processing...', // continuous update
      ));
    }
  }

  Future<void> _stageFinalAssembly(
    Function(AutoTranslationProgress)? onProgress,
  ) async {
    _currentState = _currentState!.copyWith(
      currentStage: ProcessingStage.finalizing,
    );
    _emitProgress(onProgress, 'Аяқталуда...');
    
    // STRICT VALIDATION: Check all segments are complete and files exist
    final failedSegments = _currentState!.segments.where((s) {
      if (!s.mergeComplete) return true;
      if (s.mergedSegmentPath == null) return true;
      return !File(s.mergedSegmentPath!).existsSync();
    }).toList();
    
    if (failedSegments.isNotEmpty) {
      // Detailed failure report
      print('');
      print('═══════════════════════════════════════════════════════');
      print('❌ FINAL ASSEMBLY FAILED: ${failedSegments.length}/${_currentState!.segments.length} segments incomplete');
      print('═══════════════════════════════════════════════════════');
      
      for (var seg in failedSegments) {
        final stage = !seg.translationComplete 
            ? 'Translation' 
            : !seg.ttsComplete 
                ? 'TTS' 
                : !seg.videoCutComplete 
                    ? 'Video Cut' 
                    : 'Merge';
        
        final errorInfo = seg.errorMessage ?? 'Stage incomplete';
        print('  Seg ${seg.index + 1}: Failed at $stage - $errorInfo');
      }
      
      print('═══════════════════════════════════════════════════════');
      print('');
      
      final failedIndices = failedSegments.map((s) => s.index + 1).join(', ');
      throw Exception(
        'Cannot assemble: ${failedSegments.length}/${_currentState!.segments.length} segments failed/missing. '
        'Segment indices: $failedIndices'
      );
    }
    
    print('✅ All ${_currentState!.segments.length} segments validated for assembly');

    // Enable wake lock for final assembly
    await _enableWakeLock();

    final appDir = await getApplicationDocumentsDirectory();
    final finalPath = '${appDir.path}/final_${_currentState!.projectId}.mp4';

    // Use user's video speed preference (default to 1.2x if not set)
    final speedMultiplier = _currentState!.videoSpeed ?? 1.2;
    
    await videoSplitter.concatenateAndSpeedUp(
      mergedVideoDir: _currentState!.mergedVideoDir!,
      outputPath: finalPath,
      speedMultiplier: speedMultiplier,
      onProgress: (progress) {
        _emitProgress(
          onProgress,
          '🎬 Финалдау: ${(progress * 100).toStringAsFixed(0)}%',
        );
      },
    );

    _currentState = _currentState!.copyWith(finalVideoPath: finalPath);
    await _saveState();

    // Disable wake lock after final assembly
    await _disableWakeLock();
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
    // Dispose safety: Don't emit progress after disposal
    if (_isDisposed || _currentState == null) return;

    final progress = AutoTranslationProgress.fromState(
      _currentState!,
      currentActivity: activity,
    );

    _progressController.add(progress);
    onProgress?.call(progress);

    // Update notification if in background mode
    if (_isBackgroundMode) {
      _updateNotificationProgress(progress);
    }
  }

  Future<void> _saveState() async {
    // Dispose safety: Don't save state after disposal
    if (_isDisposed || _currentState == null) return;
    
    // Logic moved to periodic timer mostly, but manual calls still ensure checkpoints
    await storage.saveState(_currentState!);
  }

  void _startAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 2), (_) {
       // Save more frequently for granular updates
      _saveState();
    });
  }

  void _stopAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
  }

  /// Enable background mode with wake lock and notifications
  Future<void> enableBackgroundMode() async {
    if (_isBackgroundMode) return;

    // Initialize notification manager
    await _notificationManager.initialize();
    await _notificationManager.requestPermissions();

    _isBackgroundMode = true;
  }

  /// Disable background mode
  Future<void> disableBackgroundMode() async {
    if (!_isBackgroundMode) return;

    // Disable wake lock if enabled
    if (_wakeLockEnabled) {
      await _disableWakeLock();
    }

    _isBackgroundMode = false;
  }

  /// Enable wake lock for CPU-intensive operations
  Future<void> _enableWakeLock() async {
    if (_wakeLockEnabled) return;

    try {
      await WakelockPlus.enable();
      _wakeLockEnabled = true;
    } catch (e) {
      print('❌ Wake lock қатесі: $e');
    }
  }

  /// Disable wake lock
  Future<void> _disableWakeLock() async {
    if (!_wakeLockEnabled) return;

    try {
      await WakelockPlus.disable();
      _wakeLockEnabled = false;
    } catch (e) {
      print('❌ Wake lock өшіру қатесі: $e');
    }
  }

  /// Update notification with current progress (throttled)
  void _updateNotificationProgress(AutoTranslationProgress progress) {
    if (!_isBackgroundMode) return;

    _notificationManager.updateFromProgress(progress);
  }

  /// Dispose resources
  void dispose() {
    // Set flag first to prevent further updates
    _isDisposed = true;
    _isCancelled = true; // Cancel all pending work
    
    // Stop auto-save timer
    _stopAutoSave();
    
    // Clear all queues to prevent pending operations
    _translationQueue?.clear();
    _ttsQueue?.clear();
    _cuttingQueue?.clear();
    _mergingQueue?.clear();
    
    // Disable wake lock safely
    try {
      if (_wakeLockEnabled) {
        WakelockPlus.disable().catchError((e) {
          print('❌ Wake lock cleanup error: $e');
        });
        _wakeLockEnabled = false;
      }
    } catch (e) {
      print('❌ Wake lock cleanup error: $e');
    }
    
    // Cancel notifications
    try {
      _notificationManager.cancelAll();
    } catch (e) {
      print('❌ Notification cleanup error: $e');
    }
    
    // Close stream controller safely
    try {
      if (!_progressController.isClosed) {
        _progressController.close();
      }
    } catch (e) {
      print('❌ Stream controller cleanup error: $e');
    }
    
    print('🧹 Orchestrator disposed successfully');
  }
}
