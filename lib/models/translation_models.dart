class TranslationPricing {
  final double pricePerSecond;
  final String currency;
  final double minimumCharge;

  TranslationPricing({
    required this.pricePerSecond,
    required this.currency,
    required this.minimumCharge,
  });

  factory TranslationPricing.fromJson(Map<String, dynamic> json) {
    return TranslationPricing(
      pricePerSecond: (json['pricePerSecond'] as num).toDouble(),
      currency: json['currency'],
      minimumCharge: (json['minimumCharge'] as num).toDouble(),
    );
  }
}

class TranslationRequest {
  final String text;
  final String targetLanguage;
  final String? sourceLanguage;
  final int durationSeconds;
  final String? videoFileName;

  TranslationRequest({
    required this.text,
    required this.targetLanguage,
    this.sourceLanguage,
    required this.durationSeconds,
    this.videoFileName,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'targetLanguage': targetLanguage,
        if (sourceLanguage != null) 'sourceLanguage': sourceLanguage,
        'durationSeconds': durationSeconds,
        if (videoFileName != null) 'videoFileName': videoFileName,
      };
}

class TranslationJobResult {
  final bool success;
  final String? jobId;
  final String? translatedText;
  final double? price;
  final String? currency;
  final String? message;
  final String? errorMessage;
  final int? inputLineCount;
  final int? outputLineCount;
  final String? sourceLanguage;
  final String? targetLanguage;

  TranslationJobResult({
    required this.success,
    this.jobId,
    this.translatedText,
    this.price,
    this.currency,
    this.message,
    this.errorMessage,
    this.inputLineCount,
    this.outputLineCount,
    this.sourceLanguage,
    this.targetLanguage,
  });

  factory TranslationJobResult.fromJson(Map<String, dynamic> json) {
    return TranslationJobResult(
      success: json['success'] ?? false,
      jobId: json['jobId'],
      translatedText: json['translatedText'],
      price: json['price'] != null ? (json['price'] as num).toDouble() : null,
      currency: json['currency'],
      message: json['message'],
      errorMessage: json['errorMessage'],
      inputLineCount: json['inputLineCount'],
      outputLineCount: json['outputLineCount'],
      sourceLanguage: json['sourceLanguage'],
      targetLanguage: json['targetLanguage'],
    );
  }

  /// Жолдар санының сәйкестігін тексеру
  bool get hasLineCountMismatch {
    if (inputLineCount == null || outputLineCount == null) return false;
    return inputLineCount != outputLineCount;
  }

  /// Validation қате хабарын алу
  String? get validationWarning {
    if (hasLineCountMismatch) {
      return 'Жолдар саны сәйкес емес: күтілген $inputLineCount, алынған $outputLineCount';
    }
    return null;
  }
}

class TranslationJob {
  final String id;
  final String originalText;
  final String translatedText;
  final String sourceLanguage;
  final String targetLanguage;
  final String status;
  final double price;
  final String currency;
  final int durationSeconds;
  final String? videoFileName;
  final DateTime createdAt;
  final DateTime? completedAt;

  TranslationJob({
    required this.id,
    required this.originalText,
    required this.translatedText,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.status,
    required this.price,
    required this.currency,
    required this.durationSeconds,
    this.videoFileName,
    required this.createdAt,
    this.completedAt,
  });

  factory TranslationJob.fromJson(Map<String, dynamic> json) {
    return TranslationJob(
      id: json['id'],
      originalText: json['originalText'],
      translatedText: json['translatedText'],
      sourceLanguage: json['sourceLanguage'],
      targetLanguage: json['targetLanguage'],
      status: json['status'],
      price: (json['price'] as num).toDouble(),
      currency: json['currency'],
      durationSeconds: json['durationSeconds'],
      videoFileName: json['videoFileName'],
      createdAt: DateTime.parse(json['createdAt']),
      completedAt:
          json['completedAt'] != null ? DateTime.parse(json['completedAt']) : null,
    );
  }
}

class TranslationHistory {
  final List<TranslationJob> jobs;
  final int totalCount;
  final int page;
  final int totalPages;

  TranslationHistory({
    required this.jobs,
    required this.totalCount,
    required this.page,
    required this.totalPages,
  });

  factory TranslationHistory.fromJson(Map<String, dynamic> json) {
    return TranslationHistory(
      jobs: (json['jobs'] as List)
          .map((job) => TranslationJob.fromJson(job))
          .toList(),
      totalCount: json['totalCount'],
      page: json['page'],
      totalPages: json['totalPages'],
    );
  }
}

// ============================================================================
// Segments Translation Models
// ============================================================================

/// Аударылатын segment
class TranslationSegment {
  final String id;
  final String text;

  TranslationSegment({
    required this.id,
    required this.text,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
      };
}

/// Segments аударма сұранысы
class TranslateSegmentsRequest {
  final List<TranslationSegment> segments;
  final String targetLanguage;
  final String? sourceLanguage;
  final int durationSeconds;
  final String? videoFileName;

  TranslateSegmentsRequest({
    required this.segments,
    required this.targetLanguage,
    this.sourceLanguage,
    required this.durationSeconds,
    this.videoFileName,
  });

  Map<String, dynamic> toJson() => {
        'segments': segments.map((s) => s.toJson()).toList(),
        'targetLanguage': targetLanguage,
        if (sourceLanguage != null) 'sourceLanguage': sourceLanguage,
        'durationSeconds': durationSeconds,
        if (videoFileName != null) 'videoFileName': videoFileName,
      };
}

/// Аударылған segment
class TranslatedSegment {
  final String id;
  final String originalText;
  final String translatedText;

  TranslatedSegment({
    required this.id,
    required this.originalText,
    required this.translatedText,
  });

  factory TranslatedSegment.fromJson(Map<String, dynamic> json) {
    return TranslatedSegment(
      id: json['id']?.toString() ?? '',
      originalText: json['originalText']?.toString() ?? '',
      translatedText: json['translatedText']?.toString() ?? '',
    );
  }
}

/// Segments аударма нәтижесі
class TranslateSegmentsResult {
  final bool success;
  final String? jobId;
  final List<TranslatedSegment> translatedSegments;
  final List<String>? translatedLines;
  final String? translatedText;
  final String? sourceLanguage;
  final String? targetLanguage;
  final double? price;
  final String? currency;
  final int? inputLineCount;
  final int? outputLineCount;
  final bool? recoveredFromMarkers;
  final bool? partial;
  final List<int>? missingIndexes;
  final List<int>? failedIndexes;
  final int? missingCount;
  final int? expectedSegments;
  final List<String>? rawPartialLines;
  final bool? serverHasLineCountMismatch;
  final String? message;
  final String? errorMessage;

  TranslateSegmentsResult({
    required this.success,
    this.jobId,
    required this.translatedSegments,
    this.translatedLines,
    this.translatedText,
    this.sourceLanguage,
    this.targetLanguage,
    this.price,
    this.currency,
    this.inputLineCount,
    this.outputLineCount,
    this.recoveredFromMarkers,
    this.partial,
    this.missingIndexes,
    this.failedIndexes,
    this.missingCount,
    this.expectedSegments,
    this.rawPartialLines,
    this.serverHasLineCountMismatch,
    this.message,
    this.errorMessage,
  });

  factory TranslateSegmentsResult.fromJson(Map<String, dynamic> json) {
    List<String>? parseStringList(dynamic value) {
      if (value is List) {
        return value.map((e) => e?.toString() ?? '').toList();
      }
      return null;
    }

    List<int>? parseIndexList(dynamic value) {
      if (value is List) {
        return value
            .map((e) => int.tryParse(e.toString()))
            .whereType<int>()
            .toList();
      }
      return null;
    }

    return TranslateSegmentsResult(
      success: json['success'] ?? false,
      jobId: json['jobId'],
      translatedSegments: (json['translatedSegments'] as List?)
              ?.map((s) => TranslatedSegment.fromJson(s))
              .toList() ??
          [],
      translatedLines: parseStringList(json['translatedLines']),
      translatedText: json['translatedText']?.toString(),
      sourceLanguage: json['sourceLanguage'],
      targetLanguage: json['targetLanguage'],
      price: json['price'] != null ? (json['price'] as num).toDouble() : null,
      currency: json['currency'],
      inputLineCount: json['inputLineCount'],
      outputLineCount: json['outputLineCount'],
      recoveredFromMarkers: json['recoveredFromMarkers'],
      partial: json['partial'],
      missingIndexes: parseIndexList(json['missingIndexes']),
      failedIndexes: parseIndexList(json['failedIndexes']),
      missingCount: (json['missingCount'] as num?)?.toInt(),
      expectedSegments: (json['expectedSegments'] as num?)?.toInt(),
      rawPartialLines: parseStringList(json['rawPartialLines']),
      serverHasLineCountMismatch: json['hasLineCountMismatch'],
      message: json['message'],
      errorMessage: json['errorMessage'],
    );
  }

  /// Жолдар санының сәйкестігін тексеру
  bool get hasLineCountMismatch {
    if (inputLineCount == null || outputLineCount == null) {
      return serverHasLineCountMismatch ?? false;
    }
    return inputLineCount != outputLineCount;
  }

  /// Validation қате хабарын алу
  String? get validationWarning {
    if (hasLineCountMismatch) {
      return 'Segments саны сәйкес емес: күтілген $inputLineCount, алынған $outputLineCount';
    }
    return null;
  }
}

// ============================================================================
// Segment Status Tracking (for retry/resume functionality)
// ============================================================================

/// Segment translation status
enum SegmentTranslationStatus {
  pending,     // Not started
  translating, // Currently being translated
  completed,   // Successfully translated
  failed,      // Translation failed
}

/// Tracks the state of an individual segment translation
class SegmentState {
  final int index;
  final String originalText;
  String? translatedText;
  SegmentTranslationStatus status;
  String? errorMessage;
  int retryCount;

  SegmentState({
    required this.index,
    required this.originalText,
    this.translatedText,
    this.status = SegmentTranslationStatus.pending,
    this.errorMessage,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'originalText': originalText,
        'translatedText': translatedText,
        'status': status.name,
        'errorMessage': errorMessage,
        'retryCount': retryCount,
      };

  factory SegmentState.fromJson(Map<String, dynamic> json) {
    return SegmentState(
      index: json['index'],
      originalText: json['originalText'],
      translatedText: json['translatedText'],
      status: SegmentTranslationStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => SegmentTranslationStatus.pending,
      ),
      errorMessage: json['errorMessage'],
      retryCount: json['retryCount'] ?? 0,
    );
  }

  SegmentState copyWith({
    String? translatedText,
    SegmentTranslationStatus? status,
    String? errorMessage,
    int? retryCount,
  }) {
    return SegmentState(
      index: index,
      originalText: originalText,
      translatedText: translatedText ?? this.translatedText,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      retryCount: retryCount ?? this.retryCount,
    );
  }
}
