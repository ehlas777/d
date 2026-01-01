class TranscriptionSegment {
  final double start;
  final double end;
  final String text;
  final double? confidence;
  final String language;
  final String? speaker;
  final String? translatedText;
  final String? targetLanguage;

  TranscriptionSegment({
    required this.start,
    required this.end,
    required this.text,
    this.confidence,
    required this.language,
    this.speaker,
    this.translatedText,
    this.targetLanguage,
  });

  factory TranscriptionSegment.fromJson(Map<String, dynamic> json) {
    return TranscriptionSegment(
      start: (json['start'] as num).toDouble(),
      end: (json['end'] as num).toDouble(),
      text: json['text'] as String,
      confidence: json['confidence'] != null
          ? (json['confidence'] as num).toDouble()
          : null,
      language: json['language'] as String,
      speaker: json['speaker'] as String?,
      translatedText: json['translatedText'] as String?,
      targetLanguage: json['targetLanguage'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'start': start,
      'end': end,
      'text': text,
      'confidence': confidence,
      'language': language,
      'speaker': speaker,
      'translatedText': translatedText,
      'targetLanguage': targetLanguage,
    };
  }

  TranscriptionSegment copyWith({
    double? start,
    double? end,
    String? text,
    double? confidence,
    String? language,
    String? speaker,
    String? translatedText,
    String? targetLanguage,
  }) {
    return TranscriptionSegment(
      start: start ?? this.start,
      end: end ?? this.end,
      text: text ?? this.text,
      confidence: confidence ?? this.confidence,
      language: language ?? this.language,
      speaker: speaker ?? this.speaker,
      translatedText: translatedText ?? this.translatedText,
      targetLanguage: targetLanguage ?? this.targetLanguage,
    );
  }
}

class TranscriptionResult {
  final String filename;
  final double duration;
  final String detectedLanguage;
  final String model;
  final String createdAt;
  final List<TranscriptionSegment> segments;

  TranscriptionResult({
    required this.filename,
    required this.duration,
    required this.detectedLanguage,
    required this.model,
    required this.createdAt,
    required this.segments,
  });

  factory TranscriptionResult.fromJson(Map<String, dynamic> json) {
    return TranscriptionResult(
      filename: json['filename'] as String,
      duration: (json['duration'] as num).toDouble(),
      detectedLanguage: json['detected_language'] as String,
      model: json['model'] as String,
      createdAt: json['created_at'] as String,
      segments: (json['segments'] as List)
          .map((s) => TranscriptionSegment.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'filename': filename,
      'duration': duration,
      'detected_language': detectedLanguage,
      'model': model,
      'created_at': createdAt,
      'segments': segments.map((s) => s.toJson()).toList(),
    };
  }

  String get fullText {
    return segments.map((s) => s.text).join(' ');
  }
}
