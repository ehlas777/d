import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
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
  /// Get video duration using Flutter's native VideoPlayerController
  /// This is faster than FFprobe and doesn't require spawning external processes
  Future<double> getVideoDuration(String inputPath) async {
    final controller = VideoPlayerController.file(File(inputPath));
    try {
      await controller.initialize();
      final duration = controller.value.duration.inMilliseconds / 1000.0;
      return duration;
    } catch (e) {
      throw Exception('Видео ұзақтығын оқу сәтсіз: $e');
    } finally {
      await controller.dispose();
    }
  }

  /// Trim video to [maxDurationSeconds] if it exceeds the limit
  Future<VideoProcessingResult> prepareForTranslation({
    required String inputPath,
    double maxDurationSeconds = 60.0,
    String watermarkText = 'QazNat VT',
  }) async {
    final duration = await getVideoDuration(inputPath);
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
