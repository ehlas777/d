import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/translation_models.dart';

/// Service for persisting translation progress
/// Allows resuming translations after app restart or network interruption
class TranslationProgressStorage {
  static const String _keyPrefix = 'translation_progress_';

  /// Save translation progress for a video file
  Future<void> saveProgress({
    required String videoFileName,
    required List<SegmentState> segmentStates,
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getKey(videoFileName, targetLanguage);

    final data = {
      'videoFileName': videoFileName,
      'targetLanguage': targetLanguage,
      'sourceLanguage': sourceLanguage,
      'segmentStates': segmentStates.map((s) => s.toJson()).toList(),
      'savedAt': DateTime.now().toIso8601String(),
    };

    await prefs.setString(key, jsonEncode(data));
  }

  /// Load translation progress for a video file
  Future<List<SegmentState>?> loadProgress({
    required String videoFileName,
    required String targetLanguage,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getKey(videoFileName, targetLanguage);
    final jsonString = prefs.getString(key);

    if (jsonString == null) return null;

    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      final segmentStatesJson = data['segmentStates'] as List;
      
      return segmentStatesJson
          .map((json) => SegmentState.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // If there's an error parsing, clear the corrupted data
      await clearProgress(videoFileName: videoFileName, targetLanguage: targetLanguage);
      return null;
    }
  }

  /// Check if there's saved progress for a video file
  Future<bool> hasProgress({
    required String videoFileName,
    required String targetLanguage,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getKey(videoFileName, targetLanguage);
    return prefs.containsKey(key);
  }

  /// Clear saved progress for a video file
  Future<void> clearProgress({
    required String videoFileName,
    required String targetLanguage,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getKey(videoFileName, targetLanguage);
    await prefs.remove(key);
  }

  /// Clear all saved progress
  Future<void> clearAllProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    
    for (final key in keys) {
      if (key.startsWith(_keyPrefix)) {
        await prefs.remove(key);
      }
    }
  }

  String _getKey(String videoFileName, String targetLanguage) {
    return '$_keyPrefix${videoFileName}_$targetLanguage';
  }
}
