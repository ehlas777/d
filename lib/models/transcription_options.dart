class TranscriptionOptions {
  final String? language; // null = auto-detect, or 'kk', 'ru', 'en', 'zh'
  final bool timestamps;
  final bool speakerDiarization;
  final bool profanityFilter;
  final bool punctuation;
  final String outputFormat; // 'json', 'srt', 'vtt'
  final String model; // 'whisper-1', 'large-v2', etc.

  const TranscriptionOptions({
    this.language,
    this.timestamps = true,
    this.speakerDiarization = false,
    this.profanityFilter = false,
    this.punctuation = true,
    this.outputFormat = 'json',
    this.model = 'whisper-1',
  });

  Map<String, dynamic> toJson() {
    return {
      'language': language ?? 'auto',
      'timestamps': timestamps,
      'speaker_diarization': speakerDiarization,
      'profanity_filter': profanityFilter,
      'punctuation': punctuation,
      'output_format': outputFormat,
      'model': model,
    };
  }

  TranscriptionOptions copyWith({
    String? language,
    bool? timestamps,
    bool? speakerDiarization,
    bool? profanityFilter,
    bool? punctuation,
    String? outputFormat,
    String? model,
  }) {
    return TranscriptionOptions(
      language: language ?? this.language,
      timestamps: timestamps ?? this.timestamps,
      speakerDiarization: speakerDiarization ?? this.speakerDiarization,
      profanityFilter: profanityFilter ?? this.profanityFilter,
      punctuation: punctuation ?? this.punctuation,
      outputFormat: outputFormat ?? this.outputFormat,
      model: model ?? this.model,
    );
  }
}
