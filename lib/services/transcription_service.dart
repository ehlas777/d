import 'dart:async';
import 'dart:io';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'video_splitter_service.dart';
import '../models/transcription_options.dart';
import '../models/transcription_result.dart';

class TranscriptionService {
  final VideoSplitterService _videoSplitterService;

  TranscriptionService(this._videoSplitterService);

  Whisper? _whisper;
  bool _isInitialized = false;
  WhisperModel _currentModel = WhisperModel.none;
  String? _currentModelDir;

  static const List<String> _modelHostFallbacks = [
    // Default HuggingFace host.
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/main',
    // Mirror host (often more accessible in some regions).
    'https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main',
  ];

  static const Duration _downloadConnectTimeout = Duration(seconds: 40);
  static const Duration _downloadChunkTimeout = Duration(seconds: 80);
  static const Duration _transcribeTimeout = Duration(hours: 2);

  /// Available Whisper models
  static const Map<String, WhisperModel> availableModels = {
    'tiny': WhisperModel.tiny,
    'base': WhisperModel.base,
    'small': WhisperModel.small,
    'medium': WhisperModel.medium,
    'large-v1': WhisperModel.largeV1,
    'large-v2': WhisperModel.largeV2,
    // Backward-compatible alias from earlier UI/options.
    'whisper-1': WhisperModel.base,
  };

  /// Initialize Whisper with a specific model
  /// Model names: 'tiny', 'base', 'small', 'medium'
  Future<void> initialize({String modelName = 'base'}) async {
    final model = availableModels[modelName] ?? WhisperModel.base;
    final modelDir = await _getModelDir();

    if (_isInitialized &&
        _whisper != null &&
        _currentModel == model &&
        _currentModelDir == modelDir) {
      return;
    }

    try {
      _whisper = Whisper(
        model: model,
        modelDir: modelDir,
        downloadHost: _modelHostFallbacks.first,
      );
      _currentModel = model;
      _currentModelDir = modelDir;
      _isInitialized = true;

      print('Whisper initialized with model: $modelName');
    } catch (e) {
      throw Exception('Failed to initialize Whisper: $e');
    }
  }

  Future<String> _getModelDir() async {
    if (_currentModelDir != null) {
      return _currentModelDir!;
    }
    final Directory libraryDirectory =
        Platform.isAndroid ? await getApplicationSupportDirectory() : await getLibraryDirectory();
    _currentModelDir = libraryDirectory.path;
    return _currentModelDir!;
  }

  Future<void> _ensureModelAvailable({
    required WhisperModel model,
    required void Function(double progress) onProgress,
  }) async {
    final modelDir = await _getModelDir();
    final file = File(model.getPath(modelDir));

    if (file.existsSync() && file.lengthSync() > 0) {
      return;
    }

    await Directory(modelDir).create(recursive: true);

    final fileName = 'ggml-${model.modelName}.bin';
    final tempPath = '${file.path}.download';
    final tempFile = File(tempPath);
    if (tempFile.existsSync()) {
      try {
        tempFile.deleteSync();
      } catch (_) {}
    }

    Exception? lastError;
    for (final host in _modelHostFallbacks) {
      final uri = Uri.parse('$host/$fileName');
      try {
        await _downloadFile(
          uri: uri,
          destination: tempFile,
          onProgress: (fraction) {
            // Map download progress into the small range we reserve before transcription.
            onProgress(fraction.clamp(0.0, 1.0));
          },
        );

        // Replace/rename the downloaded file atomically when possible.
        if (file.existsSync()) {
          try {
            file.deleteSync();
          } catch (_) {}
        }
        await tempFile.rename(file.path);

        if (file.lengthSync() <= 0) {
          throw Exception('Downloaded model file is empty');
        }
        return;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        try {
          if (tempFile.existsSync()) {
            tempFile.deleteSync();
          }
        } catch (_) {}
      }
    }

    throw Exception(
      'Whisper model download failed (${model.modelName}).\n'
      '${lastError ?? ''}\n'
      'Please check network access to HuggingFace or use a mirror.',
    );
  }

  Future<void> _downloadFile({
    required Uri uri,
    required File destination,
    required void Function(double fraction) onProgress,
  }) async {
    final client = HttpClient()..connectionTimeout = _downloadConnectTimeout;
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'polydub');
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode} when downloading $uri');
      }

      final totalBytes = response.contentLength;
      final raf = destination.openSync(mode: FileMode.write);
      int receivedBytes = 0;
      DateTime lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

      try {
        await for (final chunk in response.timeout(_downloadChunkTimeout)) {
          raf.writeFromSync(chunk);
          receivedBytes += chunk.length;

          if (totalBytes > 0) {
            final now = DateTime.now();
            if (now.difference(lastEmit).inMilliseconds >= 200) {
              onProgress(receivedBytes / totalBytes);
              lastEmit = now;
            }
          }
        }
      } finally {
        await raf.close();
      }

      if (totalBytes > 0) {
        onProgress(1.0);
        final actualBytes = destination.lengthSync();
        if (actualBytes != totalBytes) {
          throw Exception(
            'Incomplete download: expected $totalBytes bytes, got $actualBytes bytes',
          );
        }
      }
    } finally {
      client.close(force: true);
    }
  }

  /// Extract audio from video file using FFmpeg
  /// Extract audio from video file using FFmpeg


  /// Transcribe video file locally using Whisper
  Future<TranscriptionResult> transcribe({
    required File videoFile,
    required TranscriptionOptions options,
    Function(double)? onProgress,
  }) async {
    if (!_isInitialized || _whisper == null) {
      throw Exception('Whisper not initialized. Call initialize() first.');
    }

    try {
      // Extract audio from video
      onProgress?.call(0.1);
      final audioPath = await _videoSplitterService.extractAudio(videoFile);
      final audioFile = File(audioPath);

      if (!await audioFile.exists()) {
        throw Exception('Audio file not found after extraction');
      }

      onProgress?.call(0.3);

      // Ensure Whisper model is available (download on first run). This is a common
      // reason why Android appears "stuck" at ~40% with no further UI updates.
      await _ensureModelAvailable(
        model: _currentModel == WhisperModel.none ? WhisperModel.base : _currentModel,
        onProgress: (fraction) {
          // Reserve [0.30..0.40] for model download.
          onProgress?.call(0.3 + (0.1 * fraction));
        },
      );

      // Prepare Whisper transcription request
      final request = TranscribeRequest(
        audio: audioPath,
        language: options.language ?? 'auto',
        isTranslate: false,
        threads: 4,
        isVerbose: false,
        isSpecialTokens: false,
        isNoTimestamps: !options.timestamps,
        nProcessors: 1,
        splitOnWord: false,
        noFallback: false,
        diarize: options.speakerDiarization,
        speedUp: false,
      );

      print('Starting Whisper transcription...');
      onProgress?.call(0.4);

      // Whisper doesn't expose granular progress; keep UI alive by gently moving
      // progress towards 0.9 until it finishes.
      double simulatedProgress = 0.4;
      late final Timer progressTimer;
      progressTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) {
        // Exponential approach to 0.89.
        const target = 0.89;
        simulatedProgress = simulatedProgress + (target - simulatedProgress) * 0.08;
        if (simulatedProgress > 0.89) {
          simulatedProgress = 0.89;
        }
        onProgress?.call(simulatedProgress);
        if (simulatedProgress >= 0.889) {
          timer.cancel();
        }
      });

      WhisperTranscribeResponse response;
      try {
        // Run transcription
        response = await _whisper!
            .transcribe(transcribeRequest: request)
            .timeout(_transcribeTimeout);
      } finally {
        progressTimer.cancel();
      }

      onProgress?.call(0.9);

      // Clean up temp audio file
      try {
        await audioFile.delete();
      } catch (e) {
        print('Warning: Could not delete temp audio file: $e');
      }

      onProgress?.call(1.0);

      // Convert to our result format
      return _convertToTranscriptionResult(response, videoPath: videoFile.path);
    } catch (e) {
      throw Exception('Transcription failed: $e');
    }
  }

  /// Convert Whisper response to our TranscriptionResult format
  TranscriptionResult _convertToTranscriptionResult(
    WhisperTranscribeResponse response, {
    required String videoPath,
  }) {
    // Convert Whisper segments to our format
    final segments = <TranscriptionSegment>[];

    if (response.segments != null && response.segments!.isNotEmpty) {
      for (final segment in response.segments!) {
        segments.add(TranscriptionSegment(
          start: segment.fromTs.inMilliseconds / 1000.0,
          end: segment.toTs.inMilliseconds / 1000.0,
          text: segment.text.trim(),
          language: 'auto',
          confidence: 1.0,
          speaker: null,
        ));
      }
    } else {
      // If no segments, create a single segment with full text
      segments.add(TranscriptionSegment(
        start: 0.0,
        end: 0.0,
        text: response.text,
        language: 'auto',
        confidence: 1.0,
        speaker: null,
      ));
    }

    // Calculate total duration from segments
    double duration = 0.0;
    if (segments.isNotEmpty) {
      duration = segments.last.end;
    }

    return TranscriptionResult(
      filename: path.basename(videoPath),
      duration: duration,
      detectedLanguage: 'auto',
      model: 'whisper-local',
      createdAt: DateTime.now().toIso8601String(),
      segments: segments,
    );
  }

  /// Check if model is available (will be downloaded if not)
  Future<bool> isModelAvailable(String modelName) async {
    // whisper_flutter_new automatically downloads models
    return true;
  }

  /// Get model file size info
  static const Map<String, String> modelSizes = {
    'tiny': '~75 MB',
    'base': '~140 MB',
    'small': '~460 MB',
    'medium': '~1.5 GB',
  };

  /// Dispose resources
  void dispose() {
    _whisper = null;
    _isInitialized = false;
  }
}

/*
Usage Example:

final service = TranscriptionService();

// Initialize with a model (do this once at app start or before first use)
await service.initialize(modelName: 'base'); // or 'tiny', 'small', 'medium'

// Transcribe a video
final result = await service.transcribe(
  videoFile: File('/path/to/video.mp4'),
  options: TranscriptionOptions(
    language: 'zh', // or 'en', 'ru', 'kk', null for auto
    timestamps: true,
    speakerDiarization: false,
  ),
  onProgress: (progress) {
    print('Progress: ${(progress * 100).toStringAsFixed(1)}%');
  },
);

print('Transcription: ${result.fullText}');
print('Segments: ${result.segments.length}');

// Clean up when done
service.dispose();

Model Information:
- Models are automatically downloaded on first use
- Downloaded to app's library directory
- No manual download required!

Recommended models:
- tiny: Fastest, lowest quality (~75 MB)
- base: Good balance of speed and quality (~140 MB) ⭐ Recommended
- small: Better quality, slower (~460 MB)
- medium: Best quality, slowest (~1.5 GB)

Supported languages: auto, zh, en, ru, kk, and many more
*/
