import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/translation_models.dart';
import 'api_client.dart';

class BackendTranslationService {
  final ApiClient apiClient;

  BackendTranslationService(this.apiClient);

  static const Duration _defaultTimeout = Duration(minutes: 5);
  static const Duration _mediumTimeout = Duration(minutes: 10);
  static const Duration _longTimeout = Duration(minutes: 15);
  static const Duration _maxTimeout = Duration(minutes: 20);
  static const int _segmentChunkSize = 500;
  static const int _maxCharsPerRequest = 20000;

  Duration _requestTimeout(int itemCount) {
    if (itemCount >= 300) return _maxTimeout;
    if (itemCount >= 150) return _longTimeout;
    if (itemCount >= 80) return _mediumTimeout;
    return _defaultTimeout;
  }

  bool _shouldFallbackSegmentsResult(TranslateSegmentsResult result, int expectedCount) {
    if (_hasCompleteSegments(result, expectedCount)) return false;
    if (!result.success) return true;
    if (result.translatedSegments.isEmpty) return true;
    final hasZeroOutput = result.outputLineCount != null && result.outputLineCount == 0;
    final hasLengthMismatch = result.translatedSegments.length != expectedCount;
    if (hasZeroOutput || result.hasLineCountMismatch || hasLengthMismatch) {
      final recovered = _extractFlattenedTranslations(result, expectedCount);
      if (recovered != null && recovered.length == expectedCount) {
        return false;
      }
    }
    if (hasZeroOutput) return true;
    if (result.hasLineCountMismatch) return true;
    if (hasLengthMismatch) return true;
    return false;
  }

  int _totalTextLength(List<TranslationSegment> segments) {
    var total = 0;
    for (final segment in segments) {
      total += segment.text.length;
    }
    return total;
  }

  bool _hasCompleteSegments(TranslateSegmentsResult result, int expectedCount) {
    return result.translatedSegments.length == expectedCount;
  }

  bool _hasFallbackIndicators(TranslateSegmentsResult result) {
    final missingCount = result.missingCount ?? 0;
    return result.partial == true ||
        missingCount > 0 ||
        (result.missingIndexes?.isNotEmpty ?? false) ||
        (result.failedIndexes?.isNotEmpty ?? false);
  }

  TranslateSegmentsResult _coerceResultIfComplete(
    TranslateSegmentsResult result,
    int expectedCount,
  ) {
    if (!_hasCompleteSegments(result, expectedCount)) return result;

    final effectiveInput = result.inputLineCount ?? expectedCount;
    final hasFallback = _hasFallbackIndicators(result);
    final message = result.message ??
        (hasFallback
            ? 'Translation incomplete; fallback used for missing segments.'
            : 'Translation recovered with complete output.');

    return TranslateSegmentsResult(
      success: true,
      jobId: result.jobId,
      translatedSegments: result.translatedSegments,
      translatedLines: result.translatedLines,
      translatedText: result.translatedText,
      sourceLanguage: result.sourceLanguage,
      targetLanguage: result.targetLanguage,
      price: result.price,
      currency: result.currency,
      inputLineCount: effectiveInput,
      outputLineCount: expectedCount,
      recoveredFromMarkers: result.recoveredFromMarkers,
      partial: result.partial,
      missingIndexes: result.missingIndexes,
      failedIndexes: result.failedIndexes,
      missingCount: result.missingCount,
      expectedSegments: result.expectedSegments ?? expectedCount,
      rawPartialLines: result.rawPartialLines,
      serverHasLineCountMismatch: false,
      message: message,
      errorMessage: null,
    );
  }

  List<String>? _extractTranslatedLinesFromPayload(
    dynamic payload,
    int expectedCount, {
    int depth = 0,
  }) {
    if (payload == null || depth > 6) return null;

    if (payload is Map) {
      final translatedLines = payload['translatedLines'];
      if (translatedLines is List) {
        final lines = _coerceLines(translatedLines);
        if (lines.length == expectedCount) return lines;
      }

      final translatedText = payload['translatedText'];
      if (translatedText is String) {
        final lines = _parseTranslationBlob(translatedText, expectedCount);
        if (lines != null && lines.length == expectedCount) return lines;
      }

      for (final value in payload.values) {
        final lines = _extractTranslatedLinesFromPayload(
          value,
          expectedCount,
          depth: depth + 1,
        );
        if (lines != null && lines.length == expectedCount) return lines;
      }
      return null;
    }

    if (payload is List) {
      for (final value in payload) {
        final lines = _extractTranslatedLinesFromPayload(
          value,
          expectedCount,
          depth: depth + 1,
        );
        if (lines != null && lines.length == expectedCount) return lines;
      }
      return null;
    }

    if (payload is String) {
      final lines = _parseTranslationBlob(payload, expectedCount);
      if (lines != null && lines.length == expectedCount) return lines;
    }

    return null;
  }

  String? _coerceLanguageCode(String? languageCode) {
    final normalized = languageCode?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized.toLowerCase() == 'auto') return null;
    return normalized;
  }

  int _coerceDurationSeconds(int durationSeconds) {
    if (durationSeconds > 0) return durationSeconds;
    // Backend requires durationSeconds > 0; avoid 400 on very short clips.
    return 1;
  }

  String _truncate(String value, {int max = 600}) {
    if (value.length <= max) return value;
    return '${value.substring(0, max)}…';
  }

  String? _extractBackendMessage(dynamic data) {
    if (data == null) return null;

    if (data is String) {
      final trimmed = data.trim();
      return trimmed.isEmpty ? null : _truncate(trimmed);
    }

    if (data is Map) {
      final errorMessage = data['errorMessage'];
      if (errorMessage is String && errorMessage.trim().isNotEmpty) {
        return _truncate(errorMessage.trim());
      }

      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) {
        return _truncate(message.trim());
      }

      final error = data['error'];
      if (error is String && error.trim().isNotEmpty) {
        return _truncate(error.trim());
      }

      final title = data['title'];
      final detail = data['detail'];
      if (title is String && title.trim().isNotEmpty) {
        if (detail is String && detail.trim().isNotEmpty) {
          return _truncate('${title.trim()}: ${detail.trim()}');
        }
        return _truncate(title.trim());
      }

      final errors = data['errors'];
      if (errors is Map) {
        final parts = <String>[];
        for (final entry in errors.entries) {
          final key = entry.key?.toString() ?? 'error';
          final value = entry.value;
          if (value is List && value.isNotEmpty) {
            parts.add('$key: ${value.first}');
          } else if (value != null) {
            parts.add('$key: $value');
          }
        }
        if (parts.isNotEmpty) {
          return _truncate(parts.join(' | '));
        }
      }
    }

    return _truncate(data.toString());
  }

  String _formatDioError(DioException error) {
    final status = error.response?.statusCode;
    final backendMessage = _extractBackendMessage(error.response?.data);
    if (backendMessage != null) {
      return status != null ? '$backendMessage (HTTP $status)' : backendMessage;
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Request timeout. Please try again.';
      case DioExceptionType.connectionError:
        return 'Network error. Check your internet connection.';
      case DioExceptionType.badCertificate:
        return 'Network security error (bad certificate).';
      case DioExceptionType.cancel:
        return 'Request cancelled.';
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        break;
    }

    if (status != null) return 'Request failed (HTTP $status).';
    return 'Request failed. Please try again.';
  }

  // Get pricing information
  Future<TranslationPricing> getPricing() async {
    try {
      final response = await apiClient.get('/api/translation/pricing');
      return TranslationPricing.fromJson(response.data);
    } catch (e) {
      throw Exception('Failed to load pricing: $e');
    }
  }

  // Translate text
  // NOTE: Text is sent as plain string with \n line breaks.
  // Backend handles JSON formatting when calling Gemini API.
  // Response contains pure translated text (JSON parsing done server-side).
  Future<TranslationJobResult> translate({
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
    required int durationSeconds,
    String? videoFileName,
  }) async {
    try {
      final safeSourceLanguage = _coerceLanguageCode(sourceLanguage);
      // Count input lines for validation
      final inputLines = text.split('\n');
      final inputLineCount = inputLines.length;

      debugPrint('=== Translation Request ===');
      debugPrint('Text length: ${text.length} characters');
      debugPrint('Input line count: $inputLineCount');
      final textPreview =
          text.length > 200 ? '${text.substring(0, 200)}...' : text;
      debugPrint('Text preview (first 200 chars): $textPreview');
      debugPrint('Target language: $targetLanguage');
      debugPrint('Source language: ${safeSourceLanguage ?? "auto"}');
      final safeDurationSeconds = _coerceDurationSeconds(durationSeconds);
      if (safeDurationSeconds != durationSeconds) {
        debugPrint('Duration clamped: $durationSeconds -> $safeDurationSeconds seconds');
      }
      debugPrint('Duration: $safeDurationSeconds seconds');

      final request = TranslationRequest(
        text: text,
        targetLanguage: targetLanguage,
        sourceLanguage: safeSourceLanguage,
        durationSeconds: safeDurationSeconds,
        videoFileName: videoFileName,
      );

      final timeout = _requestTimeout(inputLineCount);
      debugPrint('Translation timeout: ${timeout.inMinutes} minutes');

      final response = await apiClient.post(
        '/api/translation/translate',
        data: request.toJson(),
        maxRetries: 1,
        options: Options(receiveTimeout: timeout),
      );

      final result = TranslationJobResult.fromJson(response.data);

      debugPrint('=== Translation Response ===');
      debugPrint('Success: ${result.success}');
      debugPrint(
        'Translated text length: ${result.translatedText?.length ?? 0}',
      );

      // Validate line count
      if (result.translatedText != null) {
        final outputLines = result.translatedText!.split('\n');
        final outputLineCount = outputLines.length;

        debugPrint('Output line count: $outputLineCount');

        if (inputLineCount != outputLineCount) {
          debugPrint('⚠️ WARNING: Line count mismatch!');
          debugPrint('   Expected: $inputLineCount lines');
          debugPrint('   Got: $outputLineCount lines');
          debugPrint('   This may cause subtitle sync issues!');
        } else {
          debugPrint('✅ Line count validation passed: $inputLineCount lines');
        }
      }

      final translatedPreview = result.translatedText?.toString() ?? '';
      final preview =
          translatedPreview.length > 200
              ? '${translatedPreview.substring(0, 200)}...'
              : translatedPreview;
      debugPrint('Translated preview (first 200 chars): $preview');

      // Show validation warning if any
      if (result.validationWarning != null) {
        debugPrint('⚠️ VALIDATION WARNING: ${result.validationWarning}');
      }

      return result;
    } catch (e) {
      debugPrint('=== Translation Error ===');
      debugPrint('Error: $e');
      final friendlyMessage = e is DioException ? _formatDioError(e) : e.toString();
      return TranslationJobResult(
        success: false,
        message: 'Translation failed: $friendlyMessage',
        errorMessage: friendlyMessage,
      );
    }
  }

  /// Жолдар санын сақтап аудару (қосымша validation қабаты)
  Future<TranslationJobResult> translateWithValidation({
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
    required int durationSeconds,
    String? videoFileName,
  }) async {
    // Pre-validation: жолдар санын есептеу
    final inputLines = text.split('\n');
    final inputLineCount = inputLines.length;

    debugPrint('=== Pre-Translation Validation ===');
    debugPrint('Input line count: $inputLineCount');
    debugPrint('Text encoding: UTF-8');
    debugPrint('Newline count: ${'\n'.allMatches(text).length}');

    // Негізгі аударма
    final result = await translate(
      text: text,
      targetLanguage: targetLanguage,
      sourceLanguage: sourceLanguage,
      durationSeconds: durationSeconds,
      videoFileName: videoFileName,
    );

    // Post-validation
    if (result.success && result.translatedText != null) {
      final outputLines = result.translatedText!.split('\n');
      final outputLineCount = outputLines.length;

      if (inputLineCount != outputLineCount) {
        debugPrint('=== Post-Translation Validation FAILED ===');
        debugPrint('Attempting to fix line count mismatch...');

        // TODO: Қажет болса, мұнда автоматты түзету логикасын қосуға болады
        // Мысалы, жолдарды біріктіру немесе ажырату
      } else {
        debugPrint('=== Post-Translation Validation PASSED ===');
      }
    }

    return result;
  }

  /// Segments-терді аудару (batch translation)
  /// JSON segments-терді сақтап, дәл орнына қойып аударады
  Future<TranslateSegmentsResult> translateSegments({
    required List<TranslationSegment> segments,
    required String targetLanguage,
    String? sourceLanguage,
    required int durationSeconds,
    String? videoFileName,
  }) async {
    if (segments.isEmpty) {
      return TranslateSegmentsResult(
        success: false,
        translatedSegments: [],
        errorMessage: 'Segments list is empty',
      );
    }

    final totalChars = _totalTextLength(segments);
    final shouldChunkByCount = segments.length > _segmentChunkSize;
    final shouldChunkBySize =
        totalChars > _maxCharsPerRequest && segments.length > 1;
    if (shouldChunkByCount || shouldChunkBySize) {
      debugPrint(
        'Chunking translation payload (${segments.length} segments, $totalChars chars).',
      );
      return _translateSegmentsInChunks(
        segments: segments,
        targetLanguage: targetLanguage,
        sourceLanguage: sourceLanguage,
        durationSeconds: durationSeconds,
        videoFileName: videoFileName,
        maxCharsPerChunk: shouldChunkBySize ? _maxCharsPerRequest : null,
      );
    }

    final primary = await _translateSegmentsOnce(
      segments: segments,
      targetLanguage: targetLanguage,
      sourceLanguage: sourceLanguage,
      durationSeconds: durationSeconds,
      videoFileName: videoFileName,
    );

    if (!_shouldFallbackSegmentsResult(primary, segments.length)) {
      return primary;
    }

    if (segments.length <= _segmentChunkSize) {
      return primary;
    }

    debugPrint(
      'Batch translation failed, retrying in chunks of $_segmentChunkSize segments.',
    );

    return _translateSegmentsInChunks(
      segments: segments,
      targetLanguage: targetLanguage,
      sourceLanguage: sourceLanguage,
      durationSeconds: durationSeconds,
      videoFileName: videoFileName,
      maxCharsPerChunk: totalChars > _maxCharsPerRequest ? _maxCharsPerRequest : null,
    );
  }

  Future<TranslateSegmentsResult> _translateSegmentsOnce({
    required List<TranslationSegment> segments,
    required String targetLanguage,
    String? sourceLanguage,
    required int durationSeconds,
    String? videoFileName,
  }) async {
    try {
      final safeSourceLanguage = _coerceLanguageCode(sourceLanguage);
      debugPrint('=== Segments Translation Request ===');
      debugPrint('Segment count: ${segments.length}');
      debugPrint('Target language: $targetLanguage');
      debugPrint('Source language: ${safeSourceLanguage ?? "auto"}');
      final safeDurationSeconds = _coerceDurationSeconds(durationSeconds);
      if (safeDurationSeconds != durationSeconds) {
        debugPrint('Duration clamped: $durationSeconds -> $safeDurationSeconds seconds');
      }
      debugPrint('Duration: $safeDurationSeconds seconds');

      if (segments.length > 500) {
        return TranslateSegmentsResult(
          success: false,
          translatedSegments: [],
          errorMessage: 'Maximum 500 segments allowed',
        );
      }

      final request = TranslateSegmentsRequest(
        segments: segments,
        targetLanguage: targetLanguage,
        sourceLanguage: safeSourceLanguage,
        durationSeconds: safeDurationSeconds,
        videoFileName: videoFileName,
      );

      final timeout = _requestTimeout(segments.length);
      debugPrint('Segments translation timeout: ${timeout.inMinutes} minutes');

      final response = await apiClient.post(
        '/api/translation/translate-segments',
        data: request.toJson(),
        maxRetries: 1,
        options: Options(receiveTimeout: timeout),
      );

      final result = TranslateSegmentsResult.fromJson(response.data);
      final shouldAttemptRecovery = !result.success ||
          result.translatedSegments.isEmpty ||
          result.translatedSegments.length != segments.length;
      if (shouldAttemptRecovery) {
        final recoveredLines =
            _extractTranslatedLinesFromPayload(response.data, segments.length);
        if (recoveredLines != null && recoveredLines.length == segments.length) {
          debugPrint('Recovered translated lines from raw response payload.');
          return TranslateSegmentsResult(
            success: true,
            jobId: result.jobId,
            translatedSegments: List.generate(segments.length, (index) {
              return TranslatedSegment(
                id: segments[index].id,
                originalText: segments[index].text,
                translatedText: recoveredLines[index],
              );
            }),
            translatedLines: recoveredLines,
            sourceLanguage: result.sourceLanguage ?? safeSourceLanguage,
            targetLanguage: targetLanguage,
            price: result.price,
            currency: result.currency,
            inputLineCount: segments.length,
            outputLineCount: recoveredLines.length,
            message: result.message ?? 'Recovered from raw response payload',
            errorMessage: null,
          );
        }
      }

      final effectiveResult = _coerceResultIfComplete(result, segments.length);

      debugPrint('=== Segments Translation Response ===');
      debugPrint('Success: ${effectiveResult.success}');
      debugPrint('Translated segments: ${effectiveResult.translatedSegments.length}');
      debugPrint('Input segments: ${effectiveResult.inputLineCount}');
      debugPrint('Output segments: ${effectiveResult.outputLineCount}');
      if (!effectiveResult.success) {
        debugPrint(
          'Segments translation error: ${effectiveResult.errorMessage ?? effectiveResult.message ?? "Unknown error"}',
        );
      }

      if (effectiveResult.hasLineCountMismatch) {
        debugPrint('⚠️ WARNING: ${effectiveResult.validationWarning}');
      } else {
        debugPrint('✅ Segment count validation passed');
      }

      return effectiveResult;
    } catch (e) {
      debugPrint('=== Segments Translation Error ===');
      debugPrint('Error: $e');
      if (e is DioException) {
        debugPrint('HTTP status: ${e.response?.statusCode}');
        debugPrint('Response data: ${_extractBackendMessage(e.response?.data) ?? '(empty)'}');
      }
      final friendlyMessage = e is DioException ? _formatDioError(e) : e.toString();
      return TranslateSegmentsResult(
        success: false,
        translatedSegments: [],
        errorMessage: friendlyMessage,
      );
    }
  }

  Future<TranslateSegmentsResult> _translateSegmentsInChunks({
    required List<TranslationSegment> segments,
    required String targetLanguage,
    String? sourceLanguage,
    required int durationSeconds,
    String? videoFileName,
    int? maxCharsPerChunk,
  }) async {
    final safeSourceLanguage = _coerceLanguageCode(sourceLanguage);
    final aggregated = <TranslatedSegment>[];
    double? totalPrice;
    String? currency;
    String? resolvedSourceLanguage;

    int chunkIndex = 0;
    var start = 0;
    while (start < segments.length) {
      var end = start;
      var charCount = 0;

      while (end < segments.length) {
        final nextLength = segments[end].text.length;
        final wouldExceedChars = maxCharsPerChunk != null &&
            end > start &&
            (charCount + nextLength) > maxCharsPerChunk;
        final wouldExceedSegments = (end - start) >= _segmentChunkSize;

        if (wouldExceedChars || wouldExceedSegments) {
          break;
        }

        charCount += nextLength;
        end += 1;
      }

      if (end == start) {
        end = start + 1;
        charCount = segments[start].text.length;
      }

      final chunk = segments.sublist(start, end);
      start = end;
      chunkIndex += 1;

      debugPrint(
        'Translating chunk $chunkIndex (${chunk.length} segments, $charCount chars)',
      );

      final rawResult = await _translateSegmentsOnce(
        segments: chunk,
        targetLanguage: targetLanguage,
        sourceLanguage: safeSourceLanguage,
        durationSeconds: durationSeconds,
        videoFileName: videoFileName,
      );
      final result = _coerceResultIfComplete(rawResult, chunk.length);

      if (!result.success) {
        final message = result.errorMessage ?? result.message ?? 'Translation failed';
        return TranslateSegmentsResult(
          success: false,
          translatedSegments: [],
          sourceLanguage: resolvedSourceLanguage ?? result.sourceLanguage ?? safeSourceLanguage,
          targetLanguage: targetLanguage,
          errorMessage: 'Chunk $chunkIndex failed: $message',
        );
      }

      final normalized = normalizeTranslatedSegments(
        result: result,
        expectedCount: chunk.length,
        fallbackOriginalTexts: chunk.map((s) => s.text).toList(),
      );
      final effectiveSegments = normalized.segments;

      if (effectiveSegments.length != chunk.length) {
        return TranslateSegmentsResult(
          success: false,
          translatedSegments: [],
          sourceLanguage: resolvedSourceLanguage ?? result.sourceLanguage ?? safeSourceLanguage,
          targetLanguage: targetLanguage,
          errorMessage:
              'Segment count mismatch in chunk $chunkIndex: expected ${chunk.length}, got ${effectiveSegments.length}',
        );
      }

      for (var i = 0; i < chunk.length; i++) {
        aggregated.add(
          TranslatedSegment(
            id: chunk[i].id,
            originalText: chunk[i].text,
            translatedText: effectiveSegments[i].translatedText,
          ),
        );
      }

      if (result.price != null) {
        totalPrice = (totalPrice ?? 0) + result.price!;
      }
      currency ??= result.currency;
      resolvedSourceLanguage ??= result.sourceLanguage;
    }

    return TranslateSegmentsResult(
      success: true,
      translatedSegments: aggregated,
      sourceLanguage: resolvedSourceLanguage ?? safeSourceLanguage,
      targetLanguage: targetLanguage,
      price: totalPrice,
      currency: currency,
      inputLineCount: segments.length,
      outputLineCount: aggregated.length,
      message: 'Segments translated in chunks',
    );
  }

  /// Translate segments sequentially (one by one) with retry support
  /// This allows resuming from failed segments and provides progress updates
  Future<List<SegmentState>> translateSegmentsSequential({
    required List<SegmentState> segmentStates,
    required String targetLanguage,
    String? sourceLanguage,
    required int durationSeconds,
    String? videoFileName,
    Function(int currentIndex, int total, SegmentState state)? onProgress,
  }) async {
    debugPrint('=== Sequential Segments Translation Started ===');
    debugPrint('Total segments: ${segmentStates.length}');
    debugPrint('Target language: $targetLanguage');
    final safeDurationSeconds = _coerceDurationSeconds(durationSeconds);
    final safeSourceLanguage = _coerceLanguageCode(sourceLanguage);
    final requestTimeout = _requestTimeout(1);

    for (var i = 0; i < segmentStates.length; i++) {
      final state = segmentStates[i];

      // Skip already completed segments
      if (state.status == SegmentTranslationStatus.completed) {
        debugPrint('Segment $i already completed, skipping');
        onProgress?.call(i, segmentStates.length, state);
        continue;
      }

      try {
        debugPrint('Translating segment $i: "${state.originalText}"');

        // Update status to translating
        segmentStates[i] = state.copyWith(
          status: SegmentTranslationStatus.translating,
        );
        onProgress?.call(i, segmentStates.length, segmentStates[i]);

        // Translate single segment
        final segment = TranslationSegment(
          id: 'segment_$i',
          text: state.originalText,
        );

        final request = TranslateSegmentsRequest(
          segments: [segment],
          targetLanguage: targetLanguage,
          sourceLanguage: safeSourceLanguage,
          durationSeconds: safeDurationSeconds,
          videoFileName: videoFileName,
        );

        final response = await apiClient.post(
          '/api/translation/translate-segments',
          data: request.toJson(),
          maxRetries: 1,
          options: Options(receiveTimeout: requestTimeout),
        );

        final result = TranslateSegmentsResult.fromJson(response.data);

        if (result.success && result.translatedSegments.isNotEmpty) {
          final translatedText = result.translatedSegments.first.translatedText;

          segmentStates[i] = state.copyWith(
            translatedText: translatedText,
            status: SegmentTranslationStatus.completed,
            errorMessage: null,
          );

          debugPrint('Segment $i completed: "$translatedText"');
        } else {
          throw Exception(result.errorMessage ?? 'Translation failed');
        }
      } catch (e) {
        final friendlyMessage = e is DioException ? _formatDioError(e) : e.toString();
        debugPrint('Segment $i failed: $friendlyMessage');

        segmentStates[i] = state.copyWith(
          status: SegmentTranslationStatus.failed,
          errorMessage: friendlyMessage,
          retryCount: state.retryCount + 1,
        );
      }

      onProgress?.call(i, segmentStates.length, segmentStates[i]);
    }

    debugPrint('=== Sequential Segments Translation Completed ===');
    final completed =
        segmentStates
            .where((s) => s.status == SegmentTranslationStatus.completed)
            .length;
    final failed =
        segmentStates
            .where((s) => s.status == SegmentTranslationStatus.failed)
            .length;
    debugPrint('Completed: $completed, Failed: $failed');

    return segmentStates;
  }

  /// Retry a single failed segment
  Future<SegmentState> retrySingleSegment({
    required SegmentState segmentState,
    required String targetLanguage,
    String? sourceLanguage,
    required int durationSeconds,
    String? videoFileName,
  }) async {
    try {
      debugPrint(
        'Retrying segment ${segmentState.index}: "${segmentState.originalText}"',
      );
      final safeDurationSeconds = _coerceDurationSeconds(durationSeconds);
      final safeSourceLanguage = _coerceLanguageCode(sourceLanguage);
      final requestTimeout = _requestTimeout(1);

      final segment = TranslationSegment(
        id: 'segment_${segmentState.index}',
        text: segmentState.originalText,
      );

      final request = TranslateSegmentsRequest(
        segments: [segment],
        targetLanguage: targetLanguage,
        sourceLanguage: safeSourceLanguage,
        durationSeconds: safeDurationSeconds,
        videoFileName: videoFileName,
      );

      final response = await apiClient.post(
        '/api/translation/translate-segments',
        data: request.toJson(),
        maxRetries: 1,
        options: Options(receiveTimeout: requestTimeout),
      );

      final result = TranslateSegmentsResult.fromJson(response.data);

      if (result.success && result.translatedSegments.isNotEmpty) {
        final translatedText = result.translatedSegments.first.translatedText;

        return segmentState.copyWith(
          translatedText: translatedText,
          status: SegmentTranslationStatus.completed,
          errorMessage: null,
        );
      } else {
        throw Exception(result.errorMessage ?? 'Translation failed');
      }
    } catch (e) {
      final friendlyMessage = e is DioException ? _formatDioError(e) : e.toString();
      debugPrint('Retry failed for segment ${segmentState.index}: $friendlyMessage');

      return segmentState.copyWith(
        status: SegmentTranslationStatus.failed,
        errorMessage: friendlyMessage,
        retryCount: segmentState.retryCount + 1,
      );
    }
  }

  // Get translation history
  Future<TranslationHistory> getHistory({int page = 1, int limit = 20}) async {
    try {
      final response = await apiClient.get(
        '/api/translation/history',
        queryParameters: {'page': page, 'limit': limit},
      );

      return TranslationHistory.fromJson(response.data);
    } catch (e) {
      throw Exception('Failed to load translation history: $e');
    }
  }

  // Get specific translation job details
  Future<TranslationJob?> getJobDetails(String jobId) async {
    try {
      final response = await apiClient.get('/api/translation/$jobId');
      return TranslationJob.fromJson(response.data['job']);
    } catch (e) {
      return null;
    }
  }

  /// Some providers return a single JSON blob like:
  /// { "translatedLines": ["line1", "line2", ...] }
  /// This helper recovers per-segment translations from that shape.
  NormalizedSegmentsResult normalizeTranslatedSegments({
    required TranslateSegmentsResult result,
    required int expectedCount,
    List<String>? fallbackOriginalTexts,
  }) {
    final recoveredLines = _extractFlattenedTranslations(result, expectedCount);
    if (recoveredLines != null && recoveredLines.length == expectedCount) {
      debugPrint('Recovered $expectedCount segments from flattened translation payload');
      final originals = fallbackOriginalTexts ?? const [];
      final normalized = List<TranslatedSegment>.generate(expectedCount, (index) {
        final originalText =
            index < originals.length ? originals[index] : (index < result.translatedSegments.length ? result.translatedSegments[index].originalText : '');
        return TranslatedSegment(
          id: 'segment_$index',
          originalText: originalText,
          translatedText: recoveredLines[index],
        );
      });

      return NormalizedSegmentsResult(
        segments: normalized,
        recoveredFromFlattened: true,
      );
    }

    return NormalizedSegmentsResult(
      segments: result.translatedSegments,
      recoveredFromFlattened: false,
    );
  }

  List<String>? _extractFlattenedTranslations(TranslateSegmentsResult result, int expectedCount) {
    final directLines = result.translatedLines;
    if (directLines != null && directLines.length == expectedCount) {
      return directLines;
    }

    final translatedText = result.translatedText;
    if (translatedText != null) {
      final parsed = _parseTranslationBlob(translatedText, expectedCount);
      if (parsed != null && parsed.length == expectedCount) {
        return parsed;
      }
    }

    for (final segment in result.translatedSegments) {
      final parsed = _parseTranslationBlob(segment.translatedText, expectedCount);
      if (parsed != null && parsed.length == expectedCount) {
        return parsed;
      }
    }
    return null;
  }

  List<String>? _parseTranslationBlob(String raw, int expectedCount) {
    var trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final fencedMatch = RegExp(
      r'```(?:json)?\s*([\s\S]*?)\s*```',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (fencedMatch != null) {
      trimmed = fencedMatch.group(1)?.trim() ?? trimmed;
      if (trimmed.isEmpty) return null;
    }

    // Try strict JSON first
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map && decoded['translatedLines'] is List) {
        final lines = _coerceLines(decoded['translatedLines']);
        if (lines.length == expectedCount) return lines;
      } else if (decoded is List) {
        final lines = _coerceLines(decoded);
        if (lines.length == expectedCount) return lines;
      }
    } catch (_) {
      // Ignore parse errors, try regex fallback below
    }

    // Regex fallback for non-strict JSON blobs
    final match = RegExp(r'"translatedLines"\s*:\s*\[(.*?)\]', dotAll: true).firstMatch(trimmed);
    if (match != null) {
      final inner = match.group(1)!;
      final quoted = RegExp(r'"([^"]*)"').allMatches(inner).map((m) => m.group(1)!.trim()).toList();
      if (quoted.length == expectedCount) return quoted;
    }

    // Last resort: split by newlines if it looks like multiple lines
    final plainLines = trimmed
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim().replaceAll(RegExp(r'^"+|"+$'), ''))
        .where((l) => l.isNotEmpty)
        .toList();
    if (plainLines.length == expectedCount) return plainLines;

    return null;
  }

  List<String> _coerceLines(List<dynamic> raw) {
    return raw.map((e) => e?.toString().trim() ?? '').toList();
  }
}

class NormalizedSegmentsResult {
  final List<TranslatedSegment> segments;
  final bool recoveredFromFlattened;

  NormalizedSegmentsResult({
    required this.segments,
    required this.recoveredFromFlattened,
  });
}
