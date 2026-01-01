import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import '../models/transcription_result.dart';

class VideoSplitterService {
  /// FFmpeg жолдары үшін бірлік тырнақшаларға орау (пробел/юникод қауіпсіз)
  String _escapePath(String path) {
    return "'${path.replaceAll("'", "\\'")}'";
  }

  /// Видеоны сегменттерге бөледі және әр сегмент үшін бөлек файл жасайды
  ///
  /// [videoPath] - түпнұсқа видео файлының жолы
  /// [segments] - transcript сегменттері
  /// [onProgress] - прогресс callback функциясы (0.0 - 1.0)
  ///
  /// Қайтарады: бөлінген видео файлдары сақталған каталогтың жолын
  Future<String> splitVideoBySegments({
    required String videoPath,
    required List<TranscriptionSegment> segments,
    required Function(double progress) onProgress,
  }) async {
    // Шығыс каталогын жасау
    final appDir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputDir = Directory('${appDir.path}/split_videos/$timestamp');

    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    // Әр сегмент үшін видео кесу
    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final outputPath = '${outputDir.path}/segment_${i + 1}.mp4';

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

    return outputDir.path;
  }

  /// FFmpeg қолдану арқылы видеоны кесу
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

    args.addAll([
      '-i', escapedInput,
      '-t', duration.toStringAsFixed(3),
      '-c:v', 'libx264',
      '-preset', 'fast',
      '-crf', '23',
      '-c:a', 'aac',
      '-b:a', '128k',
      '-y', // Қайта жазу
      escapedOutput,
    ]);

    final command = args.join(' ');
    final session = await FFmpegKit.execute(command);
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

  /// Видео сегменттерін TTS аудиолармен біріктіру
  ///
  /// [splitVideoDir] - бөлінген видео файлдары бар каталог
  /// [audioDir] - TTS аудио файлдары бар каталог
  /// [segments] - транскрипция сегменттері
  /// [onProgress] - прогресс callback функциясы (0.0 - 1.0)
  ///
  /// Қайтарады: біріктірілген видео файлдары сақталған каталогтың жолын
  Future<String> mergeVideoWithAudio({
    required String splitVideoDir,
    required String audioDir,
    required List<TranscriptionSegment> segments,
    required Function(double progress) onProgress,
  }) async {
    // Шығыс каталогын жасау
    final appDir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputDir = Directory('${appDir.path}/merged_videos/$timestamp');

    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    // Әр сегмент үшін видео мен аудионы біріктіру
    for (int i = 0; i < segments.length; i++) {
      final videoPath = '$splitVideoDir/segment_${i + 1}.mp4';
      final audioPath = '$audioDir/segment_${i + 1}.mp3';
      final outputPath = '${outputDir.path}/merged_${i + 1}.mp4';

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

    return outputDir.path;
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
    // АУДИОНЫ ЖЫЛДАМДЫҒЫ ӨЗГЕРМЕЙДІ!

    final escapedVideo = _escapePath(videoPath);
    final escapedAudio = _escapePath(audioPath);
    final escapedOutput = _escapePath(outputPath);

    final List<String> ffmpegArgs = [
      '-i', escapedVideo,
      '-i', escapedAudio,
    ];

    // Видео жылдамдығын реттеу (setpts = slow motion/fast forward)
    if ((speedRatio - 1.0).abs() > 0.01) {
      // setpts: PTS multiplier < 1.0 = fast forward, > 1.0 = slow motion
      final ptsMultiplier = 1.0 / speedRatio;

      ffmpegArgs.addAll([
        '-filter_complex', '[0:v]setpts=$ptsMultiplier*PTS[v]',
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

    final command = ffmpegArgs.join(' ');
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      final output = await session.getOutput();
      throw Exception('FFmpeg біріктіру қатесі: $output');
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
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.mp4'))
        .cast<File>()
        .toList();

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
      '-f', 'concat',
      '-safe', '0',
      '-i', escapedConcatListPath,
      '-c', 'copy',
      '-y',
      escapedTempMergedPath,
    ];

    final concatCommand = concatArgs.join(' ');
    final concatSession = await FFmpegKit.execute(concatCommand);
    final concatReturnCode = await concatSession.getReturnCode();

    if (!ReturnCode.isSuccess(concatReturnCode)) {
      final output = await concatSession.getOutput();
      throw Exception('Видео біріктіру қатесі: $output');
    }

    onProgress?.call(0.6);

    // Содан кейін жылдамдатып соңғы файлға жазу
    final speedArgs = [
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
    final speedSession = await FFmpegKit.execute(speedCommand);
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
