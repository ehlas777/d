import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class OpenAiTtsService {
  final String baseUrl;
  final String authToken;
  final http.Client _client;

  OpenAiTtsService({
    required this.baseUrl,
    required this.authToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Map<String, String> get _headers => {
        HttpHeaders.contentTypeHeader: 'application/json',
        HttpHeaders.authorizationHeader: 'Bearer $authToken',
      };

  /// Дыбыстар тізімі
  Future<List<String>> getVoices() async {
    final resp = await _client.get(
      Uri.parse('$baseUrl/api/openaitts/voices'),
      headers: _headers,
    );
    if (resp.statusCode != 200) {
      throw Exception('Voices жүктеу қатесі: ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as List;
    return data.cast<String>();
  }

  /// Модельдер тізімі
  Future<List<String>> getModels() async {
    final resp = await _client.get(
      Uri.parse('$baseUrl/api/openaitts/models'),
      headers: _headers,
    );
    if (resp.statusCode != 200) {
      throw Exception('Модельдер жүктеу қатесі: ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as List;
    return data.cast<String>();
  }

  /// Текстті аудиоға конвертациялау.
  /// Нәтижені локал файлға сақтап, жолын қайтарады.
  Future<File> convert({
    required String text,
    required String voice,
    String model = 'gpt-4o-mini-tts',
    double speed = 1.0,
  }) async {
    final body = jsonEncode({
      'text': text,
      'voice': voice,
      'model': model,
      'speed': speed,
    });

    final resp = await _client.post(
      Uri.parse('$baseUrl/api/openaitts/convert'),
      headers: _headers,
      body: body,
    );

    if (resp.statusCode != 200) {
      // Try to parse error message safely
      try {
        final err = jsonDecode(resp.body);
        throw Exception('TTS қатесі: ${err['errorMessage'] ?? err['error'] ?? resp.statusCode}');
      } catch (e) {
        // If JSON parsing fails, show raw response
        throw Exception('TTS қатесі: HTTP ${resp.statusCode} - ${resp.body.isEmpty ? 'Empty response' : resp.body}');
      }
    }

    // Parse successful response
    try {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final audioUrl = data['audioUrl'] as String?;
      if (audioUrl == null) {
        throw Exception('audioUrl бос қайтты');
      }

      // Аудионы жүктеу
      final download = await _client.get(
        Uri.parse('$baseUrl$audioUrl'),
        headers: {HttpHeaders.authorizationHeader: 'Bearer $authToken'},
      );
      if (download.statusCode != 200) {
        throw Exception('Аудио жүктеу қатесі: ${download.statusCode}');
      }

      final dir = await getApplicationDocumentsDirectory();
      final fileName = data['fileName'] ?? 'tts_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(download.bodyBytes, flush: true);
      return file;
    } on FormatException catch (e) {
      throw Exception('JSON қатесі: ${e.message}. Response: ${resp.body.isEmpty ? 'Empty' : resp.body.substring(0, resp.body.length > 100 ? 100 : resp.body.length)}');
    }
  }

  void dispose() {
    _client.close();
  }
}
