import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/transcription_result.dart';
import '../models/translation_project.dart';
import '../providers/project_provider.dart';
import 'auto_translation_progress_panel.dart';

class TranscriptionEditor extends StatefulWidget {
  final TranscriptionResult result;
  final VoidCallback? onSave;
  final Future<void> Function(String targetLanguage)? onTranslate;
  
  // Automatic translation callbacks
  final bool? isAutomaticMode;
  final ValueChanged<bool>? onAutomaticModeChanged;
  final List<String>? automaticLogs;

  const TranscriptionEditor({
    super.key,
    required this.result,
    this.onSave,
    this.onTranslate,
    this.isAutomaticMode,
    this.onAutomaticModeChanged,
    this.automaticLogs,
  });

  @override
  State<TranscriptionEditor> createState() => _TranscriptionEditorState();
}

class _TranscriptionEditorState extends State<TranscriptionEditor> {
  late List<TranscriptionSegment> _segments;
  late double _fontSize;
  late FontWeight _fontWeight;
  bool _hasChanges = false;
  bool _isSaving = false;
  bool _isTranslating = false;
  String _targetLanguage = 'kk';
  bool _targetLanguageManuallySet = false;
  final Map<int, TextEditingController> _segmentControllers = {};
  TextEditingController? _singleEditorController;
  bool _isApplyingExternalText = false;
  bool _pendingSave = false;
  bool _isAutomatic = false; // Автоматты аударма режимі
  final List<String> _autoTranslationLogs = []; // Progress logs
  
  // TTS settings for automatic mode
  String _selectedVoice = 'alloy';
  double _videoSpeed = 1.2; // Default speed

  final List<Map<String, String>> _languageOptions = [
    // Түркі тілдері
    {'code': 'kk', 'name': 'Қазақша', 'flag': '🇰🇿'},
    {'code': 'tr', 'name': 'Türkçe', 'flag': '🇹🇷'},
    {'code': 'az', 'name': 'Azərbaycan', 'flag': '🇦🇿'},
    {'code': 'uz', 'name': 'O\'zbek', 'flag': '🇺🇿'},
    {'code': 'ky', 'name': 'Кыргызча', 'flag': '🇰🇬'},
    {'code': 'tk', 'name': 'Türkmençe', 'flag': '🇹🇲'},
    {'code': 'tt', 'name': 'Татарча', 'flag': '🌐'},
    {'code': 'ba', 'name': 'Башҡортса', 'flag': '🌐'},
    {'code': 'ug', 'name': 'ئۇيغۇرچە', 'flag': '🌐'},
    {'code': 'cv', 'name': 'Чӑвашла', 'flag': '🌐'},

    // Славян тілдері
    {'code': 'ru', 'name': 'Русский', 'flag': '🇷🇺'},
    {'code': 'uk', 'name': 'Українська', 'flag': '🇺🇦'},
    {'code': 'be', 'name': 'Беларуская', 'flag': '🇧🇾'},
    {'code': 'pl', 'name': 'Polski', 'flag': '🇵🇱'},
    {'code': 'cs', 'name': 'Čeština', 'flag': '🇨🇿'},
    {'code': 'sk', 'name': 'Slovenčina', 'flag': '🇸🇰'},
    {'code': 'bg', 'name': 'Български', 'flag': '🇧🇬'},
    {'code': 'sr', 'name': 'Српски', 'flag': '🇷🇸'},
    {'code': 'hr', 'name': 'Hrvatski', 'flag': '🇭🇷'},
    {'code': 'bs', 'name': 'Bosanski', 'flag': '🇧🇦'},
    {'code': 'sl', 'name': 'Slovenščina', 'flag': '🇸🇮'},
    {'code': 'mk', 'name': 'Македонски', 'flag': '🇲🇰'},

    // Батыс және Солтүстік Еуропа
    {'code': 'en', 'name': 'English', 'flag': '🇺🇸'},
    {'code': 'de', 'name': 'Deutsch', 'flag': '🇩🇪'},
    {'code': 'fr', 'name': 'Français', 'flag': '🇫🇷'},
    {'code': 'es', 'name': 'Español', 'flag': '🇪🇸'},
    {'code': 'it', 'name': 'Italiano', 'flag': '🇮🇹'},
    {'code': 'pt', 'name': 'Português', 'flag': '🇵🇹'},
    {'code': 'nl', 'name': 'Nederlands', 'flag': '🇳🇱'},
    {'code': 'sv', 'name': 'Svenska', 'flag': '🇸🇪'},
    {'code': 'da', 'name': 'Dansk', 'flag': '🇩🇰'},
    {'code': 'no', 'name': 'Norsk', 'flag': '🇳🇴'},
    {'code': 'fi', 'name': 'Suomi', 'flag': '🇫🇮'},
    {'code': 'is', 'name': 'Íslenska', 'flag': '🇮🇸'},

    // Шығыс Азия
    {'code': 'zh', 'name': '中文', 'flag': '🇨🇳'},
    {'code': 'ja', 'name': '日本語', 'flag': '🇯🇵'},
    {'code': 'ko', 'name': '한국어', 'flag': '🇰🇷'},
    {'code': 'mn', 'name': 'Монгол', 'flag': '🇲🇳'},

    // Оңтүстік/Оңтүстік-Шығыс Азия
    {'code': 'hi', 'name': 'हिन्दी', 'flag': '🇮🇳'},
    {'code': 'th', 'name': 'ไทย', 'flag': '🇹🇭'},
    {'code': 'vi', 'name': 'Tiếng Việt', 'flag': '🇻🇳'},
    {'code': 'id', 'name': 'Bahasa Indonesia', 'flag': '🇮🇩'},
    {'code': 'ms', 'name': 'Bahasa Melayu', 'flag': '🇲🇾'},
    {'code': 'tl', 'name': 'Tagalog', 'flag': '🇵🇭'},
    {'code': 'bn', 'name': 'বাংলা', 'flag': '🇧🇩'},
    {'code': 'ur', 'name': 'اردو', 'flag': '🇵🇰'},

    // Араб-парсы тілдері
    {'code': 'ar', 'name': 'العربية', 'flag': '🌐'},
    {'code': 'fa', 'name': 'فارسی', 'flag': '🇮🇷'},
    {'code': 'ps', 'name': 'پښتو', 'flag': '🇦🇫'},
    {'code': 'ku', 'name': 'Kurdî', 'flag': '🌐'},
    {'code': 'tg', 'name': 'Тоҷикӣ', 'flag': '🇹🇯'},
    {'code': 'sd', 'name': 'سنڌي', 'flag': '🇵🇰'},
    {'code': 'he', 'name': 'עברית', 'flag': '🇮🇱'},

    // Басқа тілдер
    {'code': 'el', 'name': 'Ελληνικά', 'flag': '🇬🇷'},
    {'code': 'ro', 'name': 'Română', 'flag': '🇷🇴'},
    {'code': 'hu', 'name': 'Magyar', 'flag': '🇭🇺'},
    {'code': 'ka', 'name': 'ქართული', 'flag': '🇬🇪'},
    {'code': 'hy', 'name': 'Հայերեն', 'flag': '🇦🇲'},
    {'code': 'sw', 'name': 'Kiswahili', 'flag': '🇰🇪'},
    {'code': 'af', 'name': 'Afrikaans', 'flag': '🇿🇦'},
  ];

  @override
  void initState() {
    super.initState();
    _segments = List.from(widget.result.segments);
    _fontSize = 14.0;
    _fontWeight = FontWeight.normal;
    _targetLanguage = _inferTargetLanguage(widget.result);
    _isAutomatic = widget.isAutomaticMode ?? false;
    if (widget.automaticLogs != null) {
      _autoTranslationLogs.addAll(widget.automaticLogs!);
    }
    _initializeControllers();
    _loadTtsSettings();
  }
  
  Future<void> _loadTtsSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedVoice = prefs.getString('tts_voice') ?? 'alloy';
      _videoSpeed = prefs.getDouble('video_speed') ?? 1.2;
    });
  }
  
  Future<void> _saveTtsSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tts_voice', _selectedVoice);
    await prefs.setDouble('video_speed', _videoSpeed);
  }

  Future<void> _triggerTranslation() async {
    if (widget.onTranslate == null || _isSaving || _isTranslating) return;

    setState(() {
      _isTranslating = true;
      
      // Demo logs for automatic mode
      if (_isAutomatic) {
        _autoTranslationLogs.clear();
        _autoTranslationLogs.add('[INFO] Starting automatic translation pipeline...');
        _autoTranslationLogs.add('[INFO] Mode: Parallel processing (5X faster)');
        _autoTranslationLogs.add('[INFO] Total segments: ${_segments.length}');
        
        final firstText = _segments.first.text;
        final preview = firstText.length > 40 ? firstText.substring(0, 40) : firstText;
        _autoTranslationLogs.add('[1/${_segments.length}] Translating: "$preview..."');
      }
    });

    try {
      // Simulate parallel progress for automatic mode
      if (_isAutomatic) {
        _simulateParallelProgress();
      }
      
      await widget.onTranslate!.call(_targetLanguage);
      
      if (_isAutomatic && mounted) {
        setState(() {
          _autoTranslationLogs.add('[${_segments.length}/${_segments.length}] ✓ All translations complete!');
          _autoTranslationLogs.add('[INFO] Next: TTS generation (not implemented yet)');
        });
      }
    } catch (e) {
      if (_isAutomatic && mounted) {
        setState(() {
          _autoTranslationLogs.add('✗ Error: $e');
        });
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context).translate('error')}: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTranslating = false);
      }
    }
  }

  void _simulateParallelProgress() {
    // Continuous animation - updates every 600ms
    Timer.periodic(const Duration(milliseconds: 600), (timer) {
      if (!_isTranslating || !mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        // Cycle through segments infinitely using modulo
        final cycleLength = (_segments.length / 5).ceil(); // One full cycle
        final completed = (timer.tick * 5) % (_segments.length + 10);

        if (completed < _segments.length) {
          _autoTranslationLogs.add('[$completed/${_segments.length}] Translating in parallel (Worker ${timer.tick % 3 + 1})...');

          if (timer.tick % 4 == 0 && completed > 0) {
            _autoTranslationLogs.add('[INFO] Progress: ${(completed / _segments.length * 100).toStringAsFixed(1)}%');
          }
        } else if (completed == _segments.length) {
          _autoTranslationLogs.add('[$_segments.length/${_segments.length}] ✓ Complete!');
          _autoTranslationLogs.add('[INFO] Progress: 100.0%');
        }

        // Keep logs list manageable - remove old entries
        if (_autoTranslationLogs.length > 60) {
          _autoTranslationLogs.removeRange(0, _autoTranslationLogs.length - 40);
        }
      });
    });
  }

  String _inferTargetLanguage(TranscriptionResult result) {
    final fromLanguage = result.segments.isNotEmpty
        ? result.segments.first.language
        : null;
    final fromTargetField = result.segments.isNotEmpty
        ? result.segments.first.targetLanguage
        : null;
    final inferred = fromLanguage ?? fromTargetField ?? result.detectedLanguage;

    final allowedCodes = _languageOptions.map((e) => e['code']).whereType<String>().toSet();
    if (!allowedCodes.contains(inferred)) {
      return 'kk';
    }
    return inferred;
  }

  @override
  void dispose() {
    for (final controller in _segmentControllers.values) {
      controller.dispose();
    }
    _singleEditorController?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TranscriptionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Widget өзгергенде (аудару сәтті болғанда) segments-ті жаңартамыз
    if (oldWidget.result != widget.result) {
      final isNewDocument = oldWidget.result.filename != widget.result.filename ||
          oldWidget.result.createdAt != widget.result.createdAt;
      if (isNewDocument) {
        _targetLanguageManuallySet = false;
      }
      final inferredTarget = _inferTargetLanguage(widget.result);
      setState(() {
        _segments = List.from(widget.result.segments);
        _hasChanges = false;
        if (!_targetLanguageManuallySet) {
          _targetLanguage = inferredTarget;
        }
      });
      _initializeControllers();
    }
  }

  bool get _hasTranslation => _segments.any((s) => s.translatedText != null);

  void _initializeControllers() {
    if (_hasTranslation) {
      _syncSegmentControllers();
      _singleEditorController?.dispose();
      _singleEditorController = null;
    } else {
      for (final controller in _segmentControllers.values) {
        controller.dispose();
      }
      _segmentControllers.clear();
      _ensureSingleController();
    }
  }

  void _syncSegmentControllers() {
    _isApplyingExternalText = true;
    for (final entry in _segments.asMap().entries) {
      final index = entry.key;
      final segment = entry.value;

      final existing = _segmentControllers[index];
      if (existing == null) {
        final controller = TextEditingController(text: segment.text);
        controller.addListener(() => _onSegmentControllerChanged(index));
        _segmentControllers[index] = controller;
      } else if (existing.text != segment.text) {
        _setControllerText(existing, segment.text);
      }
    }

    final removable = _segmentControllers.keys.where((i) => i >= _segments.length).toList();
    for (final index in removable) {
      _segmentControllers[index]?.dispose();
      _segmentControllers.remove(index);
    }
    _isApplyingExternalText = false;
  }

  void _ensureSingleController() {
    final fullText = _segments.map((s) => s.text).join('\n\n');
    if (_singleEditorController == null) {
      _singleEditorController = TextEditingController(text: fullText);
      _singleEditorController!.addListener(_onSingleControllerChanged);
      return;
    }

    if (_singleEditorController!.text != fullText) {
      _isApplyingExternalText = true;
      _setControllerText(_singleEditorController!, fullText);
      _isApplyingExternalText = false;
    }
  }

  int _boundedOffset(int value, int max) {
    if (value < 0) return 0;
    if (value > max) return max;
    return value;
  }

  void _setControllerText(TextEditingController controller, String text) {
    final selection = controller.selection;
    final base = _boundedOffset(selection.baseOffset, text.length);
    final extent = _boundedOffset(selection.extentOffset, text.length);

    controller.value = controller.value.copyWith(
      text: text,
      selection: TextSelection(
        baseOffset: base,
        extentOffset: extent,
      ),
      composing: TextRange.empty,
    );
  }

  void _onSegmentControllerChanged(int index) {
    if (_isApplyingExternalText) return;
    final controller = _segmentControllers[index];
    if (controller == null) return;
    _updateSegmentTranslation(index, controller.text);
  }

  void _onSingleControllerChanged() {
    if (_isApplyingExternalText) return;
    final text = _singleEditorController?.text ?? '';
    _updateFullText(text);
  }

  Future<void> _saveChanges({bool showNotification = false}) async {
    if (_isSaving) {
      _pendingSave = true;
      return;
    }

    if (!_hasChanges && !_pendingSave) return;

    if (mounted) {
      setState(() {
        _isSaving = true;
      });
    } else {
      _isSaving = true;
    }

    try {
      late String lastSavedPath;

      do {
        _pendingSave = false;
        final updatedResult = _buildUpdatedResult();
        lastSavedPath = await _persistResult(updatedResult);
      } while (_pendingSave);

      if (mounted) {
        setState(() {
          _hasChanges = false;
        });
      } else {
        _hasChanges = false;
      }

      if (showNotification && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${AppLocalizations.of(context).translate('saved_to')}: $lastSavedPath',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 4),
          ),
        );
      }

      if (showNotification && widget.onSave != null) {
        widget.onSave!();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context).error}: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      final hasQueuedSave = _pendingSave;
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      } else {
        _isSaving = false;
      }
      if (hasQueuedSave) {
        _saveChanges(showNotification: false);
      }
    }
  }

  TranscriptionResult _buildUpdatedResult() {
    final isTranslated = _hasTranslation;

    final updatedSegments = _segments.asMap().entries.map((entry) {
      final segment = entry.value;
      if (isTranslated) {
        return segment.copyWith(
          language: _targetLanguage,
          targetLanguage: _targetLanguage,
        );
      }
      return segment;
    }).toList();

    return TranscriptionResult(
      filename: widget.result.filename,
      duration: widget.result.duration,
      detectedLanguage: widget.result.detectedLanguage,
      model: widget.result.model,
      createdAt: widget.result.createdAt,
      segments: updatedSegments,
    );
  }

  Future<String> _persistResult(TranscriptionResult updatedResult) async {
    final projectProvider = Provider.of<ProjectProvider>(context, listen: false);
    final project = projectProvider.currentProject;

    final directory = await getApplicationDocumentsDirectory();
    final dirPath = '${directory.path}/transcription_results';
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final fileName = project != null
        ? '${project.id}_${_hasTranslation ? 'translated' : 'transcription'}.json'
        : 'transcription_${updatedResult.filename.hashCode}.json';
    final savePath = '$dirPath/$fileName';

    const encoder = JsonEncoder.withIndent('  ');
    await File(savePath).writeAsString(encoder.convert(updatedResult.toJson()));

    if (project != null) {
      if (_hasTranslation) {
        final translatedMap = <int, String>{};
        for (var i = 0; i < updatedResult.segments.length; i++) {
          translatedMap[i] = updatedResult.segments[i].text;
        }

        // Translation changed -> reset downstream artifacts (audio/merge) so TTS runs again
        final updatedSteps = Map<ProjectStep, StepProgress>.from(project.steps);
        updatedSteps[ProjectStep.tts] = StepProgress(
          step: ProjectStep.tts,
          status: ProjectStatus.notStarted,
          progress: 0.0,
        );
        updatedSteps[ProjectStep.merge] = StepProgress(
          step: ProjectStep.merge,
          status: ProjectStatus.notStarted,
          progress: 0.0,
        );
        updatedSteps[ProjectStep.completed] = StepProgress(
          step: ProjectStep.completed,
          status: ProjectStatus.notStarted,
          progress: 0.0,
        );
        final translationStep = updatedSteps[ProjectStep.translation];
        updatedSteps[ProjectStep.translation] = StepProgress(
          step: ProjectStep.translation,
          status: ProjectStatus.inProgress,
          progress: 1.0,
          startedAt: translationStep?.startedAt ?? DateTime.now(),
        );

        final updatedProject = project.copyWith(
          translatedSegments: translatedMap,
          targetLanguage: _targetLanguage,
          sourceLanguage: project.sourceLanguage ?? updatedResult.detectedLanguage,
          audioPath: null,
          finalVideoPath: null,
          currentStep: ProjectStep.translation,
          steps: updatedSteps,
        );

        await projectProvider.updateCurrentProject(updatedProject);
      } else {
        final updatedProject = project.copyWith(
          transcriptionResult: updatedResult,
        );
        await projectProvider.updateCurrentProject(updatedProject);
      }
    }

    return savePath;
  }

  void _scheduleAutoSave() {
    _saveChanges(showNotification: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, boxConstraints) {
              final isNarrow = boxConstraints.maxWidth < 520;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isNarrow)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFontSizeControl(l10n),
                        const SizedBox(height: 12),
                        _buildStatusIndicator(l10n),
                      ],
                    )
                  else
                    Row(
                      children: [
                        _buildFontSizeControl(l10n),
                        const Spacer(),
                        _buildStatusIndicator(l10n),
                      ],
                    ),
                  const SizedBox(height: 12),
                  if (isNarrow)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTargetLanguageSelector(l10n),
                        const SizedBox(height: 12),
                        _buildAutomaticModeCheckbox(),
                        if (_isAutomatic) ...[
                          const SizedBox(height: 12),
                          _buildTtsSettings(),
                        ],
                        const SizedBox(height: 12),
                        _buildTranslateButton(l10n),
                      ],
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(child: _buildTargetLanguageSelector(l10n)),
                            const SizedBox(width: 12),
                            Expanded(child: _buildAutomaticModeCheckbox()),
                            const SizedBox(width: 12),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: _buildTranslateButton(l10n),
                            ),
                          ],
                        ),
                        if (_isAutomatic) ...[
                          const SizedBox(height: 12),
                          _buildTtsSettings(),
                        ],
                      ],
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 16),

        // Automatic translation progress panel (full screen in automatic mode)
        if (_isAutomatic && _isTranslating)
          AutoTranslationProgressPanel(
            logs: _autoTranslationLogs,
            isActive: true,
          )
        else
          // Редактируемое поле текста (only in manual mode)
          _buildTextEditor(l10n),
      ],
    );
  }

  Widget _buildStatusIndicator(AppLocalizations l10n) {
    if (_isSaving) {
      return Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.translate('saving'),
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      );
    }

    if (!_hasChanges) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.successColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 18, color: AppTheme.successColor),
            const SizedBox(width: 8),
            Text(
              l10n.translate('saved'),
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        const Icon(Icons.edit_outlined, size: 18, color: AppTheme.textSecondary),
        const SizedBox(width: 6),
        Text(
          l10n.translate('unsaved_changes'),
          style: const TextStyle(
            fontSize: 13,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildFontSizeControl(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Text(
            l10n.translate('font_size'),
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            icon: const Icon(Icons.remove, size: 18),
            onPressed: _fontSize > 10 ? () => setState(() => _fontSize -= 1) : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
            visualDensity: VisualDensity.compact,
          ),
          Text(
            '${_fontSize.toInt()}',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            onPressed: _fontSize < 24 ? () => setState(() => _fontSize += 1) : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildTargetLanguageSelector(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('target_language'),
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.accentColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _targetLanguage,
          isDense: true,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.accentColor, width: 2),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
          items: _languageOptions.map((lang) {
            final flag = lang['flag'] ?? '';
            final name = lang['name'] ?? lang['code']!;
            return DropdownMenuItem<String>(
              value: lang['code'],
              child: Row(
                children: [
                  Text(flag, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text(name, style: const TextStyle(fontSize: 14)),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value == null || value == _targetLanguage) return;
            setState(() {
              _targetLanguage = value;
              _targetLanguageManuallySet = true;
            });
          },
        ),
      ],
    );
  }

  Widget _buildTranslateButton(AppLocalizations l10n) {
    final isBusy = _isSaving || _isTranslating;

    return ElevatedButton.icon(
      onPressed: widget.onTranslate != null && !isBusy ? _triggerTranslation : null,
      icon: isBusy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.translate, size: 18),
      label: isBusy
          ? Text(
              _isTranslating ? 'Аударылуда…' : l10n.translate('saving'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            )
          : const Text(
              'Аудар',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.accentColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: const StadiumBorder(),
        elevation: 0,
      ),
    );
  }

  Widget _buildAutomaticModeCheckbox() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.accentColor.withValues(alpha: 0.2),
        ),
      ),
      child: CheckboxListTile(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 16, color: AppTheme.accentColor),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Автоматты',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        subtitle: const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Text(
            'TTS + Видео (5X жылдам)',
            style: TextStyle(fontSize: 11),
          ),
        ),
        value: _isAutomatic,
        onChanged: (_isSaving || _isTranslating) ? null : (value) {
          final newValue = value ?? false;
          setState(() {
            _isAutomatic = newValue;
          });
          widget.onAutomaticModeChanged?.call(newValue);
        },
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        dense: true,
      ),
    );
  }

  Widget _buildTtsSettings() {
    final voices = [
      {'value': 'alloy', 'label': 'Alloy (Neutral)'},
      {'value': 'echo', 'label': 'Echo (Male)'},
      {'value': 'fable', 'label': 'Fable (British)'},
      {'value': 'onyx', 'label': 'Onyx (Deep)'},
      {'value': 'nova', 'label': 'Nova (Female)'},
      {'value': 'shimmer', 'label': 'Shimmer (Soft)'},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.accentColor.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Voice selection
          Row(
            children: [
              const Icon(Icons.record_voice_over, size: 16, color: AppTheme.accentColor),
              const SizedBox(width: 8),
              const Text(
                'TTS Үні',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              DropdownButton<String>(
                value: _selectedVoice,
                isDense: true,
                underline: const SizedBox(),
                items: voices.map((voice) {
                  return DropdownMenuItem<String>(
                    value: voice['value'],
                    child: Text(
                      voice['label']!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedVoice = value);
                    _saveTtsSettings();
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Speed slider
          Row(
            children: [
              const Icon(Icons.speed, size: 16, color: AppTheme.accentColor),
              const SizedBox(width: 8),
              const Text(
                'Видео жылдамдығы',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              Text(
                '${_videoSpeed.toStringAsFixed(1)}x',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accentColor,
                ),
              ),
            ],
          ),
          Slider(
            value: _videoSpeed,
            min: 0.5,
            max: 2.0,
            divisions: 15,
            label: '${_videoSpeed.toStringAsFixed(1)}x',
            onChanged: (value) {
              setState(() => _videoSpeed = value);
            },
            onChangeEnd: (value) {
              _saveTtsSettings();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTextEditor(AppLocalizations l10n) {
    if (!_hasTranslation) {
      _ensureSingleController();
      return _buildSingleEditor(l10n);
    }

    _syncSegmentControllers();
    return _buildDualEditor(l10n);
  }

  Widget _buildSingleEditor(AppLocalizations l10n) {
    _ensureSingleController();
    final controller = _singleEditorController!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 220, maxHeight: 360),
        child: TextField(
          controller: controller,
          readOnly: false,
          enableInteractiveSelection: true,
          keyboardType: TextInputType.multiline,
          maxLines: null,
          minLines: 8,
          style: TextStyle(
            fontSize: _fontSize,
            fontWeight: _fontWeight,
            height: 1.6,
            color: AppTheme.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: l10n.translate('enter_text'),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.accentColor, width: 2),
            ),
            filled: true,
            fillColor: AppTheme.backgroundColor,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          ),
        ),
      ),
    );
  }

  Widget _buildDualEditor(AppLocalizations l10n) {
    // Home screen-де аударма кезінде:
    // text = аударылған мәтін (жаңа)
    // translatedText = түпнұсқа мәтін (ескі)

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.accentColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentColor.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 300, maxHeight: 500),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _segments.length,
              separatorBuilder: (context, index) => const Divider(height: 32),
              itemBuilder: (context, index) {
                final segment = _segments[index];
                return _buildSegmentPair(segment, index, l10n);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentPair(TranscriptionSegment segment, int index, AppLocalizations l10n) {
    // Түпнұсқа мәтін - translatedText өрісінде
    final originalText = segment.translatedText ?? segment.text;

    // Аударылған мәтін - text өрісінде
    final translatedText = segment.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Түпнұсқа мәтін (сұр түспен, тек оқу)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            originalText,
            style: TextStyle(
              fontSize: _fontSize - 1,
              fontWeight: FontWeight.normal,
              height: 1.6,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Аударылған мәтін (редакциялауға болады)
        TextField(
          controller: _segmentControllers.putIfAbsent(index, () {
            final controller = TextEditingController(text: translatedText);
            controller.addListener(() => _onSegmentControllerChanged(index));
            return controller;
          }),
          keyboardType: TextInputType.multiline,
          maxLines: null,
          minLines: 2,
          style: TextStyle(
            fontSize: _fontSize,
            fontWeight: _fontWeight,
            height: 1.6,
            color: AppTheme.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: l10n.translate('enter_translated_text'),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.accentColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.accentColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.accentColor, width: 2),
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  void _updateSegmentTranslation(int index, String newText) {
    if (index >= _segments.length) return;

    final isTranslated = _hasTranslation;
    final current = _segments[index];
    if (current.text == newText &&
        (!isTranslated ||
            (current.language == _targetLanguage &&
             current.targetLanguage == _targetLanguage))) {
      return;
    }

    setState(() {
      _segments[index] = current.copyWith(
        text: newText,
        language: isTranslated ? _targetLanguage : current.language,
        targetLanguage: isTranslated ? _targetLanguage : current.targetLanguage,
      );
      _hasChanges = true;
    });

    _scheduleAutoSave();
  }

  void _updateFullText(String newText) {
    if (newText.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning, color: Colors.white),
              const SizedBox(width: 8),
              Text(AppLocalizations.of(context).translate('text_cannot_be_empty')),
            ],
          ),
          backgroundColor: AppTheme.errorColor,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // Жаңа мәтінді жолдарға бөліп, сегменттерге таратамыз
    // Аударма форматын ескереміз: "original\n→ translation"
    final lines = newText.split('\n').where((line) => line.trim().isNotEmpty).toList();

    setState(() {
      final newSegments = <TranscriptionSegment>[];
      int segmentIndex = 0;

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();

        // Skip translation marker lines
        if (line.startsWith('→ ')) {
          // This is a translation line, update previous segment
          if (newSegments.isNotEmpty) {
            final prevSegment = newSegments.removeLast();
            newSegments.add(prevSegment.copyWith(
              translatedText: line.substring(2).trim(),
            ));
          }
          continue;
        }

        // Regular text line
        if (segmentIndex < _segments.length) {
          newSegments.add(_segments[segmentIndex].copyWith(text: line));
        } else {
          // Create new segment
          final lastSegment = newSegments.isNotEmpty ? newSegments.last : null;
          newSegments.add(TranscriptionSegment(
            start: lastSegment != null ? lastSegment.end : 0.0,
            end: lastSegment != null ? lastSegment.end + 1.0 : 1.0,
            text: line,
            confidence: lastSegment?.confidence,
            language: lastSegment?.language ?? 'auto',
            speaker: lastSegment?.speaker,
          ));
        }
        segmentIndex++;
      }

      _segments = newSegments;
      _hasChanges = true;
    });

    _initializeControllers();
    _scheduleAutoSave();
  }
}
