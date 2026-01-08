import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import '../models/transcription_result.dart';

class VideoSplitterService {
  /// Check if running on mobile platform
  bool get _isMobile => Platform.isIOS || Platform.isAndroid;
  
  /// FFmpeg жолдары үшін бірлік тырнақшаларға орау (пробел/юникод қауіпсіз)
  String _escapePath(String path) {
    return "'${path.replaceAll("'", "\\'")}'";
  }

  /// Extract audio from video file (16kHz mono WAV for Whisper)
  Future<String> extractAudio(File videoFile) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final audioPath = '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.wav';

      // Extract audio as 16kHz mono WAV (required by Whisper)
      print('Extracting audio with FFmpeg...');
      print('Video path: ${videoFile.path}');
      print('Output path: $audioPath');

      // Determine timeout based on platform
      // Mobile devices need more time for processing
      final timeoutDuration = _isMobile 
          ? const Duration(minutes: 30) 
          : const Duration(minutes: 2);

      // Build FFmpeg command
      final arguments = [
        '-i', videoFile.path,
        '-ar', '16000',
        '-ac', '1',
        '-c:a', 'pcm_s16le',
        // Optimizations for mobile/iOS
        if (_isMobile) ...[
          '-max_muxing_queue_size', '1024',
          '-threads', '2', // Limit threads on mobile to prevent OOM
        ],
        '-y',
        audioPath,
      ];
      print('FFmpeg arguments: $arguments');
      
      // Execute with timeout
      final session = await FFmpegKit.executeWithArguments(arguments).timeout(
        timeoutDuration,
        onTimeout: () {
          print('⚠️ FFmpeg audio extraction timed out after ${timeoutDuration.inMinutes} minutes');
          // We can't cancel the static future easily, but we can throw to stop the flow
          throw TimeoutException('FFmpeg audio extraction timed out');
        },
      );

      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        print('Audio extraction successful: $audioPath');
        return audioPath;
      } else {
        final logs = await session.getAllLogsAsString();
        print('FFmpeg failed with logs: $logs');
        // Handle specific FFmpeg errors
        if (logs != null && logs.contains('No such file or directory')) {
          throw Exception('Video file not found: ${videoFile.path}');
        }
        throw Exception('FFmpeg failed with return code $returnCode.\nLogs: $logs');
      }
    } catch (e) {
      print('Audio extraction error: $e');
      rethrow;
    }
  }

  /// Сегменттерді біріктіру: сегмент санына қарай топтау логикасы
  ///
  /// Біріктіру ережелері:
  /// - < 30: біріктірмейміз
  /// - 30-49: 2 сегментті біріктіреміз
  /// - 50-99: 3 сегментті біріктіреміз
  /// - 100-199: 4 сегментті біріктіреміз
  /// - 200-399: 5 сегментті біріктіреміз
  /// - 400-799: 6 сегментті біріктіреміз
  /// - 800-1999: 8 сегментті біріктіреміз
  /// - >= 2000: 10 сегментті біріктіреміз
  List<TranscriptionSegment> mergeSegments(List<TranscriptionSegment> segments) {
    final count = segments.length;

    // 30-дан аз болса біріктірмейміз
    if (count < 30) {
      print('Segment count: $count - No merging needed (< 30)');
      return segments;
    }

    // Біріктіру коэффициентін анықтау
    int mergeCount;
    if (count < 50) {
      mergeCount = 2;
    } else if (count < 100) {
      mergeCount = 3;
    } else if (count < 200) {
      mergeCount = 4;
    } else if (count < 400) {
      mergeCount = 5;
    } else if (count < 800) {
      mergeCount = 6;
    } else if (count < 2000) {
      mergeCount = 8;
    } else {
      mergeCount = 10;
    }

    print('Segment count: $count - Merging every $mergeCount segments');

    final List<TranscriptionSegment> merged = [];

    for (int i = 0; i < segments.length; i += mergeCount) {
      // Біріктірілетін сегменттерді алу
      final end = (i + mergeCount > segments.length) ? segments.length : i + mergeCount;
      final group = segments.sublist(i, end);

      // Бірінші сегменттің start time және соңғы сегменттің end time
      final startTime = group.first.start;
      final endTime = group.last.end;

      // Барлық мәтіндерді біріктіру
      final combinedText = group.map((s) => s.text.trim()).join('\n');

      // Жаңа біріктірілген сегмент жасау
      final mergedSegment = TranscriptionSegment(
        start: startTime,
        end: endTime,
        text: combinedText,
        language: group.first.language,
        confidence: group.map((s) => s.confidence ?? 0.0).reduce((a, b) => a + b) / group.length,
        speaker: group.first.speaker,
      );

      merged.add(mergedSegment);
    }

    print('Merged segments: ${segments.length} → ${merged.length}');
    return merged;
  }

  /// Видеоны сегменттерге бөледі және әр сегмент үшін бөлек файл жасайды
  ///
  /// [videoPath] - түпнұсқа видео файлының жолы
  /// [segments] - transcript сегменттері
  /// [outputDir] - Optional: output directory жолы. Болмаса timestamp қолданылады.
  /// [onProgress] - прогресс callback функциясы (0.0 - 1.0)
  ///
  /// Қайтарады: бөлінген видео файлдары сақталған каталогтың жолын
  Future<String> splitVideoBySegments({
    required String videoPath,
    required List<TranscriptionSegment> segments,
    String? outputDir,
    required Function(double progress) onProgress,
  }) async {
    // Шығыс каталогын жасау
    final Directory outDir;
    if (outputDir != null) {
      outDir = Directory(outputDir);
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      outDir = Directory('${appDir.path}/split_videos/$timestamp');
    }

    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    // Әр сегмент үшін видео кесу
    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final outputPath = '${outDir.path}/segment_${i + 1}.mp4';

      // FFmpeg командасын орындау
      await _splitVideoSegment(
        videoPath: videoPath,
        startTime: segment.start,
        duration: segment.end - segment.start,
        outputPath: outputPath,
      );

      // Прогресті жаңарту
      onProgress((i + 1) / segments.length);
    }

    return outDir.path;
  }

  /// FFmpeg қолдану арқылы видеоны кесу (timeout protection қосылған)
  Future<void> _splitVideoSegment({
    required String videoPath,
    required double startTime,
    required double duration,
    required String outputPath,
  }) async {
    // FFmpeg командасы: видеоны start уақытынан бастап duration ұзақтығында кесу
    // -ss параметрі тек 0-ден үлкен болғанда қосылады

    final args = <String>[];

    // Егер startTime > 0 болса, -ss қосу
    if (startTime > 0.001) {
      args.addAll(['-ss', startTime.toStringAsFixed(3)]);
    }

    final escapedInput = _escapePath(videoPath);
    final escapedOutput = _escapePath(outputPath);

    // Mobile-optimized FFmpeg settings to reduce memory usage
    if (_isMobile) {
      args.addAll([
        '-loglevel', 'error',
        '-i', escapedInput,
        '-t', duration.toStringAsFixed(3),
        '-c:v', 'libx264',
        '-preset', 'ultrafast',  // Less memory, faster
        '-threads', '1',         // Single thread for mobile
        '-crf', '28',            // Lower quality = less memory
        '-c:a', 'aac',
        '-b:a', '96k',           // Lower bitrate
        '-bufsize', '512k',      // Smaller buffer
        '-maxrate', '1500k',     // Rate limit
        '-y',
        escapedOutput,
      ]);
    } else {
      // Desktop: higher quality settings
      args.addAll([
        '-loglevel', 'error',
        '-i', escapedInput,
        '-t', duration.toStringAsFixed(3),
        '-c:v', 'libx264',
        '-preset', 'fast',
        '-crf', '23',
        '-c:a', 'aac',
        '-b:a', '128k',
        '-y',
        escapedOutput,
      ]);
    }

    final command = args.join(' ');
    
    // iOS timeout protection: 60 seconds max per segment cut
    final session = await FFmpegKit.execute(command).timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        throw Exception('FFmpeg timeout: Video cut took longer than 60 seconds');
      },
    );
    
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      final output = await session.getOutput();
      throw Exception('FFmpeg қатесі: $output');
    }
  }

  /// Аудио файлының ұзындығын алу (секундпен)
  Future<double> getAudioDuration(String audioPath) async {
    final command =
        '-v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 ${_escapePath(audioPath)}';
    final session = await FFprobeKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      final output = await session.getOutput();
      throw Exception('FFprobe қатесі: $output');
    }

    final output = await session.getOutput();
    final durationStr = (output ?? '').trim();
    return double.tryParse(durationStr) ?? 0.0;
  }

  /// Видео файлының ұзындығын алу (секундпен)
  Future<double> getVideoDuration(String videoPath) async {
    return getAudioDuration(videoPath); // Reuse same logic as it works for video containers too
  }

  /// Видео файлының видео ағыны бар екенін тексеру
  Future<bool> hasVideoStream(String videoPath) async {
    final command =
        '-v error -select_streams v:0 -count_frames -show_entries stream=codec_type,nb_read_frames -of default=noprint_wrappers=1:nokey=1 ${_escapePath(videoPath)}';
    final session = await FFprobeKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      // Қате болса, видео ағыны жоқ деп санаймыз
      return false;
    }

    final output = await session.getOutput();
    final lines = (output ?? '').trim().split('\n');

    // Екі жол болу керек: codec_type және nb_read_frames
    if (lines.isEmpty) {
      return false;
    }

    // Бірінші жол codec_type болуы керек
    if (lines.first.trim() != 'video') {
      return false;
    }

    // Егер екінші жол болса, фреймдер санын тексеру
    if (lines.length > 1) {
      final frameCount = int.tryParse(lines[1].trim()) ?? 0;
      // Ең азынан 1 фрейм болу керек
      return frameCount > 0;
    }

    // Егер фрейм саны туралы мәлімет жоқ болса, codec_type-қа сеніп қоямыз
    return true;
  }

  /// Видео сегменттерін TTS аудиолармен біріктіру
  ///
  /// [splitVideoDir] - бөлінген видео файлдары бар каталог
  /// [audioDir] - TTS аудио файлдары бар каталог
  /// [segments] - транскрипция сегменттері
  /// [outputDir] - Optional: output directory жолы. Болмаса timestamp қолданылады.
  /// [onProgress] - прогресс callback функциясы (0.0 - 1.0)
  ///
  /// Қайтарады: біріктірілген видео файлдары сақталған каталогтың жолын
  Future<String> mergeVideoWithAudio({
    required String splitVideoDir,
    required String audioDir,
    required List<TranscriptionSegment> segments,
    String? outputDir,
    required Function(double progress) onProgress,
  }) async {
    // Шығыс каталогын жасау
    final Directory outDir;
    if (outputDir != null) {
      outDir = Directory(outputDir);
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      outDir = Directory('${appDir.path}/merged_videos/$timestamp');
    }

    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    // Әр сегмент үшін видео мен аудионы біріктіру
    for (int i = 0; i < segments.length; i++) {
      final videoPath = '$splitVideoDir/segment_${i + 1}.mp4';
      final audioPath = '$audioDir/segment_${i + 1}.mp3';
      final outputPath = '${outDir.path}/merged_${i + 1}.mp4';

      // Файлдардың бар екенін тексеру
      if (!await File(videoPath).exists()) {
        throw Exception('Видео файл табылмады: $videoPath');
      }
      if (!await File(audioPath).exists()) {
        throw Exception('Аудио файл табылмады: $audioPath');
      }

      // Видео мен аудионың ұзындығын алу
      final segment = segments[i];
      final videoDuration = segment.end - segment.start;
      final audioDuration = await getAudioDuration(audioPath);

      // Жылдамдық коэффициентін есептеу
      final speedRatio = videoDuration / audioDuration;

      // Видеоны аудиоға қарап синхрондау
      await _mergeSegmentWithAudio(
        videoPath: videoPath,
        audioPath: audioPath,
        outputPath: outputPath,
        speedRatio: speedRatio,
      );

      // Прогресті жаңарту
      onProgress((i + 1) / segments.length);
    }

    return outDir.path;
  }

  /// Бір сегментті аудиомен біріктіру және синхрондау
  /// МАҢЫЗДЫ: Видеоны slow motion/fast forward арқылы аудио ұзындығына бейімдейміз!
  /// Аудио жылдамдығы өзгермейді, тек видео баяулайды немесе тездейді.
  Future<void> _mergeSegmentWithAudio({
    required String videoPath,
    required String audioPath,
    required String outputPath,
    required double speedRatio,
  }) async {
    // speedRatio = videoDuration / audioDuration
    // speedRatio > 1.0 = видео ұзағырақ, видеоны FAST FORWARD (тездету)
    // speedRatio < 1.0 = видео қысқарақ, видеоны SLOW MOTION (баяулату)
    // speedRatio = 1.0 = синхронды, өзгеріс қажет емес

    // Log parameters for debugging
    print('Merging segment:');
    print('  Video: $videoPath');
    print('  Audio: $audioPath');
    print('  Ratio: $speedRatio');

    if (speedRatio.isInfinite || speedRatio.isNaN || speedRatio <= 0) {
       print('⚠️ Invalid speedRatio: $speedRatio. Defaulting to 1.0');
       // This likely means audioDuration is 0.
       // We should arguably throw or handle gracefully.
       // For now, let's not crash here but FFmpeg might fail if we generate bad filter.
    }

    // Видео ағынының бар-жоғын тексеру
    final hasVideo = await hasVideoStream(videoPath);
    print('  Has video stream: $hasVideo');

    final escapedVideo = _escapePath(videoPath);
    final escapedAudio = _escapePath(audioPath);
    final escapedOutput = _escapePath(outputPath);

    final List<String> ffmpegArgs = [
      '-loglevel', 'error', // Hide verbose progress output
      '-i', escapedVideo,
      '-i', escapedAudio,
    ];

    if (!hasVideo) {
      // Егер видео ағыны жоқ болса, аудиодан қара видео жасаймыз
      print('⚠️ Video has no video stream, creating black video with audio');

      // Аудио файлының ұзындығын алу
      final audioDur = await getAudioDuration(audioPath);

      ffmpegArgs.addAll([
        '-f', 'lavfi',
        '-i', 'color=c=black:s=1280x720:r=25', // Қара экран
        '-t', audioDur.toStringAsFixed(3), // Аудио ұзындығы
        '-map', '2:v:0', // Қара экран видео
        '-map', '1:a:0', // Жаңа аудио
        '-c:v', 'libx264',
        '-preset', 'fast',
        '-crf', '23',
        '-c:a', 'aac',
        '-b:a', '128k',
        '-shortest',
        '-y',
        escapedOutput,
      ]);
    } else {
      // Видео жылдамдығын реттеу (setpts = slow motion/fast forward)
      // Check for valid, finite speedRatio
      if ((speedRatio - 1.0).abs() > 0.01 && speedRatio.isFinite && speedRatio > 0) {
        // setpts: PTS multiplier < 1.0 = fast forward, > 1.0 = slow motion
        final ptsMultiplier = 1.0 / speedRatio;

        // Ensure dot separator for double
        final ptsStr = ptsMultiplier.toStringAsFixed(6);

        ffmpegArgs.addAll([
          '-filter_complex', '[0:v]setpts=$ptsStr*PTS[v]',
          '-map', '[v]',
          '-map', '1:a:0',
        ]);
      } else {
        // Өзгеріс қажет емес
        ffmpegArgs.addAll([
          '-map', '0:v:0',
          '-map', '1:a:0',
        ]);
      }

      ffmpegArgs.addAll([
        '-c:v', 'libx264', // Видео кодек
        '-preset', 'fast', // Жылдам кодтау
        '-crf', '23', // Сапа
        '-c:a', 'aac', // MP3 → AAC (кейбір MP3 форматтары copy режимінде жұмыс істемейді)
        '-b:a', '128k', // Аудио битрейт
        '-shortest', // Қысқа болғанына қарап
        '-y', // Қайта жазу
        escapedOutput,
      ]);
    }

    final command = ffmpegArgs.join(' ');
    print('Running FFmpeg: $command'); // Log the command

    // iOS timeout protection: 90 seconds max per merge operation
    final session = await FFmpegKit.execute(command).timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        throw Exception('FFmpeg timeout: Video merge took longer than 90 seconds');
      },
    );
    
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      final output = await session.getOutput();
      final logs = await session.getLogs();
      final logContent = logs.map((l) => l.getMessage()).join('\n');

      // Get last few lines of log for meaningful error
      final errorSnippet = logContent.length > 500
          ? logContent.substring(logContent.length - 500)
          : logContent;

      print('FFmpeg FAILURE LOG:\n$logContent'); // Print full log to console
      throw Exception('FFmpeg merged failed: $errorSnippet');
    }
  }

  /// Барлық сегменттерді бір видеоға біріктіру және жылдамдату
  ///
  /// [mergedVideoDir] - біріктірілген видео сегменттері бар каталог
  /// [outputPath] - соңғы видеоның шығыс жолы
  /// [speedMultiplier] - жылдамдық коэффициенті (1.2 = 1.2x жылдамырақ)
  /// [onProgress] - прогресс callback функциясы (0.0 - 1.0)
  Future<String> concatenateAndSpeedUp({
    required String mergedVideoDir,
    required String outputPath,
    double speedMultiplier = 1.0,
    Function(double progress)? onProgress,
  }) async {
    // Барлық merged видеоларды тізімге жинау
    final dir = Directory(mergedVideoDir);

    // Каталог бар екенін тексеру
    if (!await dir.exists()) {
      print('❌ Directory does not exist: $mergedVideoDir');
      throw Exception('Біріктіру үшін каталог табылмады: $mergedVideoDir');
    }

    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.mp4'))
        .cast<File>()
        .toList();

    print('📁 Found ${files.length} MP4 files in $mergedVideoDir');
    if (files.isNotEmpty) {
      print('📄 First few files: ${files.take(3).map((f) => p.basename(f.path)).join(', ')}');
    }

    // Сұрыптау - МАҢЫЗДЫ: Файл аттарынан нөмірді алып, сандық мән бойынша сұрыптау керек!
    // merged_1.mp4, merged_2.mp4, ..., merged_10.mp4 деген тәртіп болу үшін
    files.sort((a, b) {
      final nameA = p.basename(a.path);
      final nameB = p.basename(b.path);

      // Regex арқылы нөмірді алу (merged_1.mp4 -> 1)
      final regExp = RegExp(r'merged_(\d+)\.mp4');
      final matchA = regExp.firstMatch(nameA);
      final matchB = regExp.firstMatch(nameB);

      final numberA = matchA != null ? int.parse(matchA.group(1)!) : 0;
      final numberB = matchB != null ? int.parse(matchB.group(1)!) : 0;

      return numberA.compareTo(numberB);
    });

    if (files.isEmpty) {
      // Каталогтағы барлық файлдарды көрсету
      final allFiles = await dir.list().toList();
      print('❌ No MP4 files found. All files in directory:');
      for (final file in allFiles) {
        print('  - ${p.basename(file.path)}');
      }
      throw Exception('Біріктіру үшін видео файлдар табылмады');
    }

    onProgress?.call(0.1);

    // FFmpeg concat үшін файл тізімін жасау
    final appDir = await getApplicationDocumentsDirectory();
    final concatListPath = '${appDir.path}/concat_list.txt';
    final concatFile = File(concatListPath);

    final buffer = StringBuffer();
    for (final file in files) {
      buffer.writeln("file ${_escapePath(file.path)}");
    }
    await concatFile.writeAsString(buffer.toString());

    onProgress?.call(0.2);

    // Алдымен барлық видеоларды біріктіру
    final tempMergedPath = '${appDir.path}/temp_merged.mp4';
    final escapedConcatListPath = _escapePath(concatListPath);
    final escapedTempMergedPath = _escapePath(tempMergedPath);
    final escapedOutputPath = _escapePath(outputPath);

    final concatArgs = [
      '-loglevel', 'error', // Hide verbose progress output
      '-f', 'concat',
      '-safe', '0',
      '-i', escapedConcatListPath,
      '-c', 'copy',
      '-y',
      escapedTempMergedPath,
    ];

    final concatCommand = concatArgs.join(' ');
    
    // iOS timeout protection: Mobile needs more time for concat
    final concatTimeout = _isMobile
        ? const Duration(minutes: 5)  // Mobile: longer timeout
        : const Duration(minutes: 3); // Desktop
    
    final concatSession = await FFmpegKit.execute(concatCommand).timeout(
      concatTimeout,
      onTimeout: () {
        throw Exception('FFmpeg timeout: Video concatenation took longer than ${concatTimeout.inMinutes} min');
      },
    );
    
    final concatReturnCode = await concatSession.getReturnCode();

    if (!ReturnCode.isSuccess(concatReturnCode)) {
      final output = await concatSession.getOutput();
      throw Exception('Видео біріктіру қатесі: $output');
    }

    onProgress?.call(0.6);

    // Содан кейін жылдамдатып соңғы файлға жазу
    final speedArgs = [
      '-loglevel', 'error', // Hide verbose progress output
      '-i', escapedTempMergedPath,
      '-filter_complex', '[0:v]setpts=${1.0 / speedMultiplier}*PTS[v];[0:a]atempo=$speedMultiplier[a]',
      '-map', '[v]',
      '-map', '[a]',
      '-c:v', 'libx264',
      '-preset', 'fast',
      '-crf', '23',
      '-c:a', 'aac',
      '-b:a', '128k',
      '-y',
      escapedOutputPath,
    ];

    final speedCommand = speedArgs.join(' ');
    
    // iOS timeout protection: Mobile needs more time for speed adjustment
    final timeoutDuration = _isMobile 
        ? const Duration(minutes: 5)  // Mobile: longer timeout
        : const Duration(minutes: 3); // Desktop: shorter timeout
    
    final speedSession = await FFmpegKit.execute(speedCommand).timeout(
      timeoutDuration,
      onTimeout: () {
        throw Exception('FFmpeg timeout: Speed adjustment took longer than ${timeoutDuration.inMinutes} min');
      },
    );
    
    final speedReturnCode = await speedSession.getReturnCode();

    if (!ReturnCode.isSuccess(speedReturnCode)) {
      // Уақытша файлды тазалау
      await File(tempMergedPath).delete();
      await concatFile.delete();
      final output = await speedSession.getOutput();
      throw Exception('Жылдамдату қатесі: $output');
    }

    onProgress?.call(0.9);

    // Уақытша файлдарды тазалау
    await File(tempMergedPath).delete();
    await concatFile.delete();

    onProgress?.call(1.0);

    return outputPath;
  }

  /// Бөлінген видео файлдарын тазалау
  Future<void> cleanupSplitVideos(String outputDirPath) async {
    try {
      final dir = Directory(outputDirPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      // Тазалау қатесін елемеу
    }
  }
}
