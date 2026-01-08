import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:video_player/video_player.dart';

class VideoProcessingResult {
  final String outputPath;
  final bool wasTrimmed;
  final bool watermarkApplied;
  final double originalDuration;
  final double processedDuration;

  const VideoProcessingResult({
    required this.outputPath,
    required this.wasTrimmed,
    required this.watermarkApplied,
    required this.originalDuration,
    required this.processedDuration,
  });
}

/// Video preparation helpers:
/// - Probe duration
/// - Trim to subscription tier limit if exceeded
class VideoProcessingService {
  /// Get video duration using Flutter's native VideoPlayerController (fast)
  /// with fallback to FFprobe (robust)
  Future<double> getVideoDuration(String inputPath) async {
    // 1. Try VideoPlayerController (Fastest)
    try {
      final controller = VideoPlayerController.file(File(inputPath));
      await controller.initialize();
      final duration = controller.value.duration.inMilliseconds / 1000.0;
      await controller.dispose();
      return duration;
    } catch (e) {
      print('VideoPlayerController failed: $e. Falling back to FFprobe...');
    }

    // 2. Fallback to FFprobe (Robust)
    try {
      final session = await FFprobeKit.getMediaInformation(inputPath);
      final info = await session.getMediaInformation();
      final durationStr = info?.getDuration();
      
      if (durationStr != null) {
        return double.parse(durationStr);
      }
    } catch (e) {
      print('FFprobe failed: $e');
    }

    throw Exception('Failed to determine video duration');
  }

  /// Trim video to [maxDurationSeconds] if it exceeds the limit
  /// [knownDuration] - optional duration if already calculated (saves probing)
  Future<VideoProcessingResult> prepareForTranslation({
    required String inputPath,
    double maxDurationSeconds = 60.0,
    String watermarkText = 'PolyDub',
    double? knownDuration,
  }) async {
    final duration = knownDuration ?? await getVideoDuration(inputPath);
    final shouldTrim = duration > maxDurationSeconds + 0.01;
    
    // If video is within limit, return it unchanged
    if (!shouldTrim) {
      return VideoProcessingResult(
        outputPath: inputPath,
        wasTrimmed: false,
        watermarkApplied: false,
        originalDuration: duration,
        processedDuration: duration,
      );
    }

    // Video exceeds limit - trim it
    final appDir = await getApplicationDocumentsDirectory();
    final outputDir = Directory('${appDir.path}/prepared_videos');
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ext = p.extension(inputPath);
    final base = p.basenameWithoutExtension(inputPath);
    final outputPath = '${outputDir.path}/${base}_trimmed_$timestamp$ext';

    // Trim to maxDurationSeconds
    final args = <String>[
      '-i',
      inputPath,
      '-t', maxDurationSeconds.toStringAsFixed(3),
      '-c:v',
      'libx264',
      '-preset',
      'fast',
      '-crf',
      '23',
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      '-movflags',
      '+faststart',
      '-y',
      outputPath,
    ];

    final session = await FFmpegKit.executeWithArguments(args);
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      final output = await session.getOutput();
      throw Exception('Видеоны қысқарту мүмкін болмады: $output');
    }

    return VideoProcessingResult(
      outputPath: outputPath,
      wasTrimmed: true,
      watermarkApplied: false,
      originalDuration: duration,
      processedDuration: maxDurationSeconds,
    );
  }
}
