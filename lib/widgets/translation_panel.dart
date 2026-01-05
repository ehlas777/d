import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/translation_models.dart';
import '../models/transcription_result.dart';
import '../providers/auth_provider.dart';
import '../services/backend_translation_service.dart';
import '../services/translation_progress_storage.dart';

class TranslationPanel extends StatefulWidget {
  final TranscriptionResult transcriptionResult;
  final Function(Map<int, String> translatedSegments, String sourceLanguage, String targetLanguage)? onTranslationComplete;
  final VoidCallback? onNextStep;
  final Map<int, String>? initialTranslatedSegments;
  final String? initialSourceLanguage;
  final String? initialTargetLanguage;

  const TranslationPanel({
    super.key,
    required this.transcriptionResult,
    this.onTranslationComplete,
    this.onNextStep,
    this.initialTranslatedSegments,
    this.initialSourceLanguage,
    this.initialTargetLanguage,
  });

  @override
  State<TranslationPanel> createState() => _TranslationPanelState();
}

class _TranslationPanelState extends State<TranslationPanel> {
  String _sourceLanguage = 'kk'; // Default: Kazakh
  String _targetLanguage = 'zh'; // Default: Chinese
  bool _isTranslating = false;
  String? _errorMessage;
  Map<int, String>? _translatedSegments;
  double? _estimatedCost;
  double _progress = 0.0;
  final Map<int, TextEditingController> _editControllers = {};
  bool _hasUnsavedChanges = false;
  bool _isAutomatic = false; // Автоматты аударма режимі
  
  // Sequential translation with retry support
  List<SegmentState>? _segmentStates;
  final TranslationProgressStorage _progressStorage = TranslationProgressStorage();
  int _currentTranslatingIndex = -1;

  final List<Map<String, String>> _languages = [
    // Түркі тілдері
    {'code': 'kk', 'name': 'Қазақша (Kazakh)'},
    {'code': 'tr', 'name': 'Türkçe (Turkish)'},
    {'code': 'uz', 'name': 'O\'zbek (Uzbek)'},
    {'code': 'ky', 'name': 'Кыргызча (Kyrgyz)'},
    {'code': 'az', 'name': 'Azərbaycan (Azerbaijani)'},
    {'code': 'tt', 'name': 'Татарча (Tatar)'},
    {'code': 'tk', 'name': 'Türkmençe (Turkmen)'},
    {'code': 'ba', 'name': 'Башҡортса (Bashkir)'},
    {'code': 'ug', 'name': 'ئۇيغۇرچە (Uyghur)'},
    {'code': 'cv', 'name': 'Чӑвашла (Chuvash)'},

    // Славян тілдері
    {'code': 'ru', 'name': 'Русский (Russian)'},
    {'code': 'uk', 'name': 'Українська (Ukrainian)'},
    {'code': 'be', 'name': 'Беларуская (Belarusian)'},
    {'code': 'pl', 'name': 'Polski (Polish)'},
    {'code': 'cs', 'name': 'Čeština (Czech)'},
    {'code': 'sk', 'name': 'Slovenčina (Slovak)'},
    {'code': 'bg', 'name': 'Български (Bulgarian)'},
    {'code': 'sr', 'name': 'Српски (Serbian)'},
    {'code': 'hr', 'name': 'Hrvatski (Croatian)'},
    {'code': 'bs', 'name': 'Bosanski (Bosnian)'},
    {'code': 'sl', 'name': 'Slovenščina (Slovenian)'},
    {'code': 'mk', 'name': 'Македонски (Macedonian)'},

    // Батыс Еуропа тілдері
    {'code': 'en', 'name': 'English'},
    {'code': 'de', 'name': 'Deutsch (German)'},
    {'code': 'fr', 'name': 'Français (French)'},
    {'code': 'es', 'name': 'Español (Spanish)'},
    {'code': 'it', 'name': 'Italiano (Italian)'},
    {'code': 'pt', 'name': 'Português (Portuguese)'},
    {'code': 'nl', 'name': 'Nederlands (Dutch)'},

    // Скандинавия тілдері
    {'code': 'sv', 'name': 'Svenska (Swedish)'},
    {'code': 'da', 'name': 'Dansk (Danish)'},
    {'code': 'no', 'name': 'Norsk (Norwegian)'},
    {'code': 'fi', 'name': 'Suomi (Finnish)'},
    {'code': 'is', 'name': 'Íslenska (Icelandic)'},

    // Шығыс Азия тілдері
    {'code': 'zh', 'name': '中文 (Chinese)'},
    {'code': 'ja', 'name': '日本語 (Japanese)'},
    {'code': 'ko', 'name': '한국어 (Korean)'},
    {'code': 'mn', 'name': 'Монгол (Mongolian)'},

    // Оңтүстік/Оңтүстік-Шығыс Азия
    {'code': 'hi', 'name': 'हिन्दी (Hindi)'},
    {'code': 'th', 'name': 'ไทย (Thai)'},
    {'code': 'vi', 'name': 'Tiếng Việt (Vietnamese)'},
    {'code': 'id', 'name': 'Bahasa Indonesia (Indonesian)'},
    {'code': 'ms', 'name': 'Bahasa Melayu (Malay)'},
    {'code': 'tl', 'name': 'Tagalog (Filipino)'},
    {'code': 'bn', 'name': 'বাংলা (Bengali)'},
    {'code': 'ur', 'name': 'اردو (Urdu)'},

    // Араб-парсы және туыс тілдер
    {'code': 'ar', 'name': 'العربية (Arabic)'},
    {'code': 'fa', 'name': 'فارسی (Persian)'},
    {'code': 'he', 'name': 'עברית (Hebrew)'},
    {'code': 'ps', 'name': 'پښتو (Pashto)'},
    {'code': 'ku', 'name': 'Kurdî (Kurdish)'},
    {'code': 'tg', 'name': 'Тоҷикӣ (Tajik)'},
    {'code': 'sd', 'name': 'سنڌي (Sindhi)'},

    // Басқа тілдер
    {'code': 'el', 'name': 'Ελληνικά (Greek)'},
    {'code': 'ro', 'name': 'Română (Romanian)'},
    {'code': 'hu', 'name': 'Magyar (Hungarian)'},
    {'code': 'ka', 'name': 'ქართული (Georgian)'},
    {'code': 'hy', 'name': 'Հայերեն (Armenian)'},
    {'code': 'sw', 'name': 'Kiswahili (Swahili)'},
    {'code': 'af', 'name': 'Afrikaans'},
  ];

  @override
  void dispose() {
    // Dispose all text editing controllers
    for (var controller in _editControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _sourceLanguage =
        widget.initialSourceLanguage ?? widget.transcriptionResult.detectedLanguage;
    _targetLanguage = widget.initialTargetLanguage ?? _targetLanguage;

    _loadSavedTargetLanguage();

    if (widget.initialTranslatedSegments != null &&
        widget.initialTranslatedSegments!.isNotEmpty) {
      _applyExternalTranslation(
        widget.initialTranslatedSegments!,
        widget.initialSourceLanguage,
        widget.initialTargetLanguage,
        shouldSetState: false,
      );
    }
  }

  Future<void> _loadSavedTargetLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('translation_target_language');
    if (saved != null && mounted) {
      setState(() {
        _targetLanguage = saved;
      });
    }
  }

  Future<void> _saveTargetLanguage(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('translation_target_language', value);
  }

  @override
  void didUpdateWidget(covariant TranslationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    final incomingSegments = widget.initialTranslatedSegments;
    // Apply external translation if:
    // 1. We have incoming segments and currently don't have any (_translatedSegments == null)
    // OR
    // 2. The incoming segments are different from what we currently have
    final hasIncomingTranslation = incomingSegments != null &&
        incomingSegments.isNotEmpty &&
        (_translatedSegments == null ||
         oldWidget.initialTranslatedSegments != widget.initialTranslatedSegments);

    if (hasIncomingTranslation) {
      _applyExternalTranslation(
        incomingSegments,
        widget.initialSourceLanguage,
        widget.initialTargetLanguage,
      );
    }
  }

  void _initializeEditControllers(Map<int, String> translatedSegments) {
    // Clear existing controllers
    for (var controller in _editControllers.values) {
      controller.dispose();
    }
    _editControllers.clear();

    // Create new controllers for each segment
    for (var entry in translatedSegments.entries) {
      final controller = TextEditingController(text: entry.value);
      controller.addListener(() {
        // МАҢЫЗДЫ: setState() курсорды жылжытпау үшін жоқ болса ғана шақыру
        if (!_hasUnsavedChanges) {
          setState(() => _hasUnsavedChanges = true);
        }
      });
      _editControllers[entry.key] = controller;
    }
  }

  Future<void> _saveTranslationChanges() async {
    // МАҢЫЗДЫ: _hasUnsavedChanges тексеруін алып тастаймыз!
    // Себебі пайдаланушы өңдеп, басқа жерге басып, қайтадан өңдесе,
    // екінші өңдеу сақталмай қалады
    if (_translatedSegments == null && _editControllers.isEmpty) return;

    // Update translated segments from controllers
    final updatedSegments = <int, String>{};
    for (var entry in _editControllers.entries) {
      final text = entry.value.text;
      // Debug: бос орындарды тексеру
      debugPrint('Saving segment ${entry.key}: length=${text.length}, spaces=${text.split(' ').length - 1}, text="$text"');
      updatedSegments[entry.key] = text;
    }

    setState(() {
      _translatedSegments = updatedSegments;
      _hasUnsavedChanges = false;
    });

    // Notify parent about the changes
    widget.onTranslationComplete?.call(updatedSegments, _sourceLanguage, _targetLanguage);
  }

  /// Start sequential translation with retry support
  Future<void> _startSequentialTranslation() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    setState(() {
      _isTranslating = true;
      _errorMessage = null;
      _progress = 0.0;
      _currentTranslatingIndex = -1;
    });

    try {
      final translationService = BackendTranslationService(authProvider.apiClient);
      final duration = widget.transcriptionResult.duration.toInt();
      final videoFileName = widget.transcriptionResult.filename;

      // Check if we have saved progress
      final savedStates = await _progressStorage.loadProgress(
        videoFileName: videoFileName,
        targetLanguage: _targetLanguage,
      );

      List<SegmentState> segmentStates;
      if (savedStates != null && savedStates.isNotEmpty) {
        debugPrint('Loading saved translation progress: ${savedStates.length} segments');
        segmentStates = savedStates;
      } else {
        // Initialize new segment states
        segmentStates = widget.transcriptionResult.segments.asMap().entries.map((entry) {
          return SegmentState(
            index: entry.key,
            originalText: entry.value.text,
            status: SegmentTranslationStatus.pending,
          );
        }).toList();
      }

      setState(() {
        _segmentStates = segmentStates;
      });

      // Translate segments sequentially
      await translationService.translateSegmentsSequential(
        segmentStates: segmentStates,
        targetLanguage: _targetLanguage,
        sourceLanguage: _sourceLanguage,
        durationSeconds: duration,
        videoFileName: videoFileName,
        onProgress: (currentIndex, total, state) {
          setState(() {
            _currentTranslatingIndex = currentIndex;
            _progress = (currentIndex + 1) / total;
            _segmentStates = segmentStates;
          });

          // Save progress after each segment
          _progressStorage.saveProgress(
            videoFileName: videoFileName,
            segmentStates: segmentStates,
            targetLanguage: _targetLanguage,
            sourceLanguage: _sourceLanguage,
          );
        },
      );

      // Convert to Map<int, String> format for compatibility
      final translatedMap = <int, String>{};
      for (var state in segmentStates) {
        if (state.status == SegmentTranslationStatus.completed && state.translatedText != null) {
          translatedMap[state.index] = state.translatedText!;
        } else {
          translatedMap[state.index] = state.originalText; // Fallback to original
        }
      }

      setState(() {
        _translatedSegments = translatedMap;
        _segmentStates = segmentStates;
        _progress = 1.0;
        _isTranslating = false;
        _currentTranslatingIndex = -1;
        _hasUnsavedChanges = false;
        _initializeEditControllers(translatedMap);
      });

      // Clear progress after successful completion
      final allCompleted = segmentStates.every((s) => s.status == SegmentTranslationStatus.completed);
      if (allCompleted) {
        await _progressStorage.clearProgress(
          videoFileName: videoFileName,
          targetLanguage: _targetLanguage,
        );
      }

      // Notify parent
      widget.onTranslationComplete?.call(translatedMap, _sourceLanguage, _targetLanguage);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isTranslating = false;
        _currentTranslatingIndex = -1;
      });
    }
  }

  /// Retry a single failed segment
  Future<void> _retrySegment(int index) async {
    if (_segmentStates == null || index >= _segmentStates!.length) return;

    final state = _segmentStates![index];
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    setState(() {
      _segmentStates![index] = state.copyWith(
        status: SegmentTranslationStatus.translating,
      );
    });

    try {
      final translationService = BackendTranslationService(authProvider.apiClient);
      final duration = widget.transcriptionResult.duration.toInt();
      final videoFileName = widget.transcriptionResult.filename;

      final updatedState = await translationService.retrySingleSegment(
        segmentState: state,
        targetLanguage: _targetLanguage,
        sourceLanguage: _sourceLanguage,
        durationSeconds: duration,
        videoFileName: videoFileName,
      );

      setState(() {
        _segmentStates![index] = updatedState;
        
        // Update translated segments map
        if (updatedState.status == SegmentTranslationStatus.completed && 
            updatedState.translatedText != null) {
          _translatedSegments?[index] = updatedState.translatedText!;
          _editControllers[index]?.text = updatedState.translatedText!;
        }
      });

      // Save progress
      await _progressStorage.saveProgress(
        videoFileName: videoFileName,
        segmentStates: _segmentStates!,
        targetLanguage: _targetLanguage,
        sourceLanguage: _sourceLanguage,
      );

      // Notify parent about the changes
      if (_translatedSegments != null) {
        widget.onTranslationComplete?.call(_translatedSegments!, _sourceLanguage, _targetLanguage);
      }
    } catch (e) {
      setState(() {
        _segmentStates![index] = state.copyWith(
          status: SegmentTranslationStatus.failed,
          errorMessage: e.toString(),
          retryCount: state.retryCount + 1,
        );
      });
    }
  }



  Future<void> _startTranslation() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    setState(() {
      _isTranslating = true;
      _errorMessage = null;
      _progress = 0.0;
    });

    try {
      // Use the AuthProvider's ApiClient so the auth token is attached
      final translationService = BackendTranslationService(authProvider.apiClient);
      debugPrint(
        'Translation API request: source=$_sourceLanguage -> target=$_targetLanguage',
      );

      // Build TranslationSegment list (1:1 with original segments)
      final requestSegments = widget.transcriptionResult.segments.asMap().entries.map((entry) {
        return TranslationSegment(
          id: 'segment_${entry.key}',
          text: entry.value.text,
        );
      }).toList();

      // Calculate duration
      final duration = widget.transcriptionResult.duration.toInt();

      setState(() => _progress = 0.3);

      // Call segment translation API
      final result = await translationService.translateSegments(
        segments: requestSegments,
        targetLanguage: _targetLanguage,
        sourceLanguage: _sourceLanguage,
        durationSeconds: duration,
        videoFileName: widget.transcriptionResult.filename,
      );

      setState(() => _progress = 0.9);

      final segmentCount = widget.transcriptionResult.segments.length;
      final normalized = translationService.normalizeTranslatedSegments(
        result: result,
        expectedCount: segmentCount,
        fallbackOriginalTexts: widget.transcriptionResult.segments.map((s) => s.text).toList(),
      );
      final effectiveSegments = normalized.segments;

      String? validationError;
      if (!result.success) {
        validationError = result.errorMessage ?? 'Аударма сәтсіз аяқталды';
      } else if (!normalized.recoveredFromFlattened &&
          (result.hasLineCountMismatch ||
              (result.inputLineCount != null && result.inputLineCount != segmentCount) ||
              (result.outputLineCount != null && result.outputLineCount != segmentCount) ||
              effectiveSegments.length != segmentCount)) {
        validationError = result.validationWarning ??
            'Segment count mismatch: күтілген $segmentCount, алынған ${result.outputLineCount ?? effectiveSegments.length}';
      } else if (normalized.recoveredFromFlattened && effectiveSegments.length != segmentCount) {
        validationError =
            'Segment count mismatch: күтілген $segmentCount, алынған ${effectiveSegments.length}';
      }

      if (validationError != null) {
        setState(() {
          _errorMessage = validationError;
          _isTranslating = false;
          _progress = 0.0;
        });
        return;
      }

      // Build translated map using returned IDs
      final translatedMap = <int, String>{};
      bool mappingError = false;

      for (var i = 0; i < effectiveSegments.length; i++) {
        final translated = effectiveSegments[i];
        final parsedIndex = _extractSegmentIndex(translated.id) ?? i;

        if (parsedIndex < 0 || parsedIndex >= segmentCount) {
          mappingError = true;
          break;
        }

        final text = translated.translatedText;
        // Debug: бос орындарды тексеру
        debugPrint('Segment $parsedIndex: length=${text.length}, spaces=${text.split(' ').length - 1}');
        translatedMap[parsedIndex] =
            text.trim().isNotEmpty ? text : widget.transcriptionResult.segments[parsedIndex].text;
      }

      if (mappingError || translatedMap.length != segmentCount) {
        setState(() {
          _errorMessage =
              'Segment mapping error: күтілген $segmentCount сегмент, алынған ${translatedMap.length}';
          _isTranslating = false;
          _progress = 0.0;
        });
        return;
      }

      // Reinsert in index order to keep UI/controller alignment deterministic
      final orderedMap = <int, String>{};
      for (var i = 0; i < segmentCount; i++) {
        orderedMap[i] = translatedMap[i]!;
      }

      setState(() {
        _translatedSegments = orderedMap;
        _estimatedCost = result.price;
        _progress = 1.0;
        _isTranslating = false;
        _hasUnsavedChanges = false;
        _initializeEditControllers(orderedMap);
      });

      // Notify parent after state update
      final callback = widget.onTranslationComplete;
      if (callback != null) {
        // Try to await if it's a Future, otherwise just call it
        final callbackResult = callback(translatedMap, _sourceLanguage, _targetLanguage);
        if (callbackResult is Future) {
          await callbackResult;
        } else {
          // Give parent time to update its state if callback is synchronous
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isTranslating = false;
      });
    }
  }

  void _applyExternalTranslation(
    Map<int, String> translatedSegments,
    String? sourceLanguage,
    String? targetLanguage, {
    bool shouldSetState = true,
  }) {
    // Ensure incoming translation aligns with original segment count
    final expectedCount = widget.transcriptionResult.segments.length;
    if (translatedSegments.length != expectedCount) {
      if (shouldSetState) {
        setState(() {
          _errorMessage =
              'Segment count mismatch: күтілген $expectedCount, алынған ${translatedSegments.length}';
          _isTranslating = false;
        });
      } else {
        _errorMessage =
            'Segment count mismatch: күтілген $expectedCount, алынған ${translatedSegments.length}';
        _isTranslating = false;
      }
      return;
    }

    void apply() {
      final orderedMap = <int, String>{};
      for (var i = 0; i < expectedCount; i++) {
        orderedMap[i] =
            translatedSegments[i] ?? widget.transcriptionResult.segments[i].text;
      }
      _translatedSegments = orderedMap;
      _sourceLanguage = sourceLanguage ?? _sourceLanguage;
      _targetLanguage = targetLanguage ?? _targetLanguage;
      _progress = 1.0;
      _isTranslating = false;
      _hasUnsavedChanges = false;
      _initializeEditControllers(_translatedSegments!);
    }

    if (shouldSetState) {
      setState(apply);
    } else {
      apply();
    }
  }

  int? _extractSegmentIndex(String id) {
    final match = RegExp('(\\d+)\$').firstMatch(id);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_translatedSegments != null) {
      return _buildTranslationResult(l10n);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('step_translation'),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),

        // Target language (only) - компактная версия
        _buildLanguageDropdown(
          label: l10n.translate('target_language'),
          value: _targetLanguage,
          onChanged: (value) {
            if (value != null) {
              setState(() => _targetLanguage = value);
              _saveTargetLanguage(value);
            }
          },
        ),
        const SizedBox(height: 12),

        // Автоматты режим checkbox
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppTheme.accentColor.withValues(alpha: 0.2),
            ),
          ),
          child: CheckboxListTile(
            title: Row(
              children: [
                const Icon(Icons.auto_awesome, size: 18, color: AppTheme.accentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Автоматты режим',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Аударма + TTS + Видео өңдеу (5X жылдамырақ)',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            value: _isAutomatic,
            onChanged: _isTranslating ? null : (value) {
              setState(() {
                _isAutomatic = value ?? false;
              });
            },
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            dense: true,
          ),
        ),

        // Info box - компактная версия
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.accentColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: AppTheme.accentColor, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Сегменттер: ${widget.transcriptionResult.segments.length} • '
                  'Ұзақтығы: ${widget.transcriptionResult.duration.toInt()} сек',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Error message
        if (_errorMessage != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppTheme.errorColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.errorColor),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: AppTheme.errorColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage ??
                        'Аударма сәтсіз аяқталды. Кіру керек немесе қайталап көріңіз.',
                    style: const TextStyle(color: AppTheme.errorColor),
                  ),
                ),
              ],
            ),
          ),

        // Progress indicator - компактная версия
        if (_isTranslating) ...[
          LinearProgressIndicator(
            value: _progress > 0 ? _progress : null,
            backgroundColor: Colors.grey.withValues(alpha: 0.2),
            color: AppTheme.accentColor,
          ),
          const SizedBox(height: 4),
          Text(
            '${(_progress * 100).toInt()}% - ${l10n.translate('translating')}...',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
        ],

        // Buttons row - компактная версия
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isTranslating ? null : _startSequentialTranslation,
                icon: _isTranslating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.translate, size: 16),
                label: Text(_translatedSegments != null
                    ? 'Қайта аудару'
                    : l10n.translate('start_translation')),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: AppTheme.accentColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppTheme.accentColor.withValues(alpha: 0.5),
                  disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTranslationResult(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, color: AppTheme.successColor, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.translate('translation_completed'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppTheme.successColor,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Target language selector and JSON button on top - компактная версия
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildLanguageDropdown(
                label: l10n.translate('target_language'),
                value: _targetLanguage,
                onChanged: (value) async {
                  if (value != null && value != _targetLanguage) {
                    // Алдымен тілді өзгертеміз, бірақ _translatedSegments-ті қалдырамыз
                    final newLanguage = value;
                    setState(() {
                      _targetLanguage = newLanguage;
                      // _translatedSegments = null; // ОСЫНЫ АЛЫП ТАСТАДЫҚ
                      _editControllers.clear();
                      _hasUnsavedChanges = false;
                      _estimatedCost = null;
                      _errorMessage = null;
                      _isTranslating = true; // Аударма процесін бастаймыз
                    });
                    _saveTargetLanguage(newLanguage);

                    // Содан кейін жаңа тілде аударма жасаймыз
                    await _startTranslation();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _isTranslating ? null : () async {
                setState(() {
                  _translatedSegments = null;
                  _editControllers.clear();
                  _hasUnsavedChanges = false;
                  _estimatedCost = null;
                  _errorMessage = null;
                });
                await _startTranslation();
              },
              icon: _isTranslating
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.refresh, size: 14),
              label: const Text('Қайта', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                disabledBackgroundColor: AppTheme.accentColor.withValues(alpha: 0.5),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _showJsonViewer,
              icon: const Icon(Icons.code, size: 14),
              label: const Text('JSON', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Cost information - компактная версия
        if (_estimatedCost != null)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.successColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.payment, color: AppTheme.successColor, size: 16),
                const SizedBox(width: 6),
                Text(
                  '${l10n.translate('estimated_cost')}: ¥$_estimatedCost',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.successColor,
                        fontWeight: FontWeight.w500,
                        fontSize: 11,
                      ),
                ),
              ],
            ),
          ),
        if (_estimatedCost != null) const SizedBox(height: 12),

        // Translated segments preview - компактная версия
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.translate('translation_result'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            if (_hasUnsavedChanges)
              Text(
                l10n.translate('unsaved_changes'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.warningColor,
                      fontStyle: FontStyle.italic,
                    ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 150),
          decoration: BoxDecoration(
            color: AppTheme.cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: _translatedSegments!.length,
            separatorBuilder: (context, index) => const Divider(height: 8),
            itemBuilder: (context, index) {
              final originalSegment = widget.transcriptionResult.segments[index];
              final controller = _editControllers[index];
              final segmentState = _segmentStates != null && index < _segmentStates!.length
                  ? _segmentStates![index]
                  : null;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      // Status indicator
                      if (segmentState != null) ...[
                        if (segmentState.status == SegmentTranslationStatus.completed)
                          const Icon(Icons.check_circle, color: AppTheme.successColor, size: 14),
                        if (segmentState.status == SegmentTranslationStatus.failed)
                          const Icon(Icons.error, color: AppTheme.errorColor, size: 14),
                        if (segmentState.status == SegmentTranslationStatus.translating)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          originalSegment.text,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey,
                                fontSize: 11,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Retry button for failed segments
                      if (segmentState?.status == SegmentTranslationStatus.failed)
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 14),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _retrySegment(index),
                          tooltip: 'Қайталау',
                        ),
                    ],
                  ),
                  // Show error message for failed segments
                  if (segmentState?.status == SegmentTranslationStatus.failed &&
                      segmentState?.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 2),
                      child: Text(
                        'Қате: ${segmentState!.errorMessage}',
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 9,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: controller,
                    maxLines: null,
                    minLines: 1,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableInteractiveSelection: true,
                    enableIMEPersonalizedLearning: false,
                    style: Theme.of(context).textTheme.bodySmall,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      isDense: true,
                      hintText: '在此输入翻译 / Аударманы осында енгізіңіз',
                      hintStyle: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),

      ],
    );
  }

  Widget _buildLanguageDropdown({
    required String label,
    required String value,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          items: _languages.map((lang) {
            return DropdownMenuItem<String>(
              value: lang['code'],
              child: Text(lang['name']!),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }


  void _showJsonViewer() {
    // Create a TranscriptionResult with translated segments
    final translatedResult = TranscriptionResult(
      filename: widget.transcriptionResult.filename,
      duration: widget.transcriptionResult.duration,
      detectedLanguage: _targetLanguage,
      model: widget.transcriptionResult.model,
      createdAt: widget.transcriptionResult.createdAt,
      segments: widget.transcriptionResult.segments.asMap().entries.map((entry) {
        final index = entry.key;
        final originalSegment = entry.value;
        final translatedText = _editControllers[index]?.text ?? _translatedSegments![index] ?? '';

        return TranscriptionSegment(
          start: originalSegment.start,
          end: originalSegment.end,
          text: translatedText,
          confidence: originalSegment.confidence,
          language: _targetLanguage,
          speaker: originalSegment.speaker,
          translatedText: originalSegment.text,
          targetLanguage: _targetLanguage,
        );
      }).toList(),
    );

    // Convert to formatted JSON
    final jsonEncoder = const JsonEncoder.withIndent('  ');
    final jsonString = jsonEncoder.convert(translatedResult.toJson());

    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'JSON көрінісі',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: 'Көшіру',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: jsonString));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('JSON көшірілді'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      jsonString,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
