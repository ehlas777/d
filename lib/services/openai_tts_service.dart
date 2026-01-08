import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/dio_error_formatter.dart';

class OpenAiTtsService {
  final String baseUrl;
  final String authToken;
  final Dio _dio;

  OpenAiTtsService({
    required this.baseUrl,
    required this.authToken,
    Dio? dio, // For testing injection
  }) : _dio = dio ?? Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
    ),
  );

  /// Дыбыстар тізімі
  Future<List<String>> getVoices() async {
    try {
      final resp = await _dio.get('/api/openaitts/voices');
      final data = resp.data as List;
      return data.cast<String>();
    } on DioException catch (e) {
      throw Exception('Voices жүктеу қатесі: ${DioErrorFormatter.format(e)}');
    }
  }

  /// Модельдер тізімі
  Future<List<String>> getModels() async {
    try {
      final resp = await _dio.get('/api/openaitts/models');
      final data = resp.data as List;
      return data.cast<String>();
    } on DioException catch (e) {
      throw Exception('Модельдер жүктеу қатесі: ${DioErrorFormatter.format(e)}');
    }
  }

  /// Текстті аудиоға конвертациялау.
  /// Нәтижені локал файлға сақтап, жолын қайтарады.
  Future<File> convert({
    required String text,
    required String voice,
    String model = 'gpt-4o-mini-tts',
    double speed = 1.0,
  }) async {
    try {
      final body = {
        'text': text,
        'voice': voice,
        'model': model,
        'speed': speed,
      };

      final resp = await _dio.post(
        '/api/openaitts/convert',
        data: body,
      );

      final data = resp.data as Map<String, dynamic>;
      final audioUrl = data['audioUrl'] as String?;
      if (audioUrl == null) {
        throw Exception('audioUrl бос қайтты');
      }

      // Аудионы жүктеу
      // Relative URL болса base URL қосу
      final downloadUrl = audioUrl.startsWith('http') ? audioUrl : '$baseUrl$audioUrl';
      
      final downloadResp = await _dio.get(
        downloadUrl,
        options: Options(
          responseType: ResponseType.bytes,
        ),
      );

      final dir = await getApplicationDocumentsDirectory();
      final fileName = data['fileName'] ?? 'tts_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(downloadResp.data, flush: true);
      return file;

    } on DioException catch (e) {
      // Extensive logging for debugging
      print('❌ TTS API Error via Dio:');
      print('   HTTP Status: ${e.response?.statusCode}');
      print('   Request ID: ${e.response?.headers.value('x-request-id') ?? 'N/A'}');
      
      final formattedError = DioErrorFormatter.format(e, defaultMessage: 'TTS қатесі');
      throw Exception(formattedError);
    }
  }

  void dispose() {
    _dio.close();
  }
}

