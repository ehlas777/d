import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../config/app_theme.dart';
import '../models/transcription_result.dart';
import '../services/openai_tts_service.dart';
import '../services/background_audio_service.dart';

class TranscriptionTtsReader extends StatefulWidget {
  final TranscriptionResult result;
  final String baseUrl;
  final String authToken;
  final void Function(String folderPath)? onComplete;
  final void Function()? onAutoMerge; // Trigger automatic merge
  final String? initialAudioPath;
  final String? currentFinalVideoPath;

  const TranscriptionTtsReader({
    super.key,
    required this.result,
    required this.baseUrl,
    required this.authToken,
    this.onComplete,
    this.onAutoMerge,
    this.initialAudioPath,
    this.currentFinalVideoPath,
  });

  @override
  State<TranscriptionTtsReader> createState() => _TranscriptionTtsReaderState();
}

class _TranscriptionTtsReaderState extends State<TranscriptionTtsReader> {
  late OpenAiTtsService _ttsService;
  final BackgroundAudioService _audioService = BackgroundAudioService.instance;
  List<String> _voices = [];
  String? _selectedVoice;
  double _speed = 1.0;
  bool _isLoadingVoices = false;
  bool _isGenerating = false;
  int _currentSegment = 0;
  int _totalSegments = 0;
  List<File> _generatedFiles = [];
  final Map<int, File> _segmentFiles = {};
  final Set<int> _failedSegments = {};
  String? _outputFolder;
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();
    _ttsService = OpenAiTtsService(
      baseUrl: widget.baseUrl,
      authToken: widget.authToken,
    );
    _audioService.initialize();
    _totalSegments = widget.result.segments.length;
    _loadVoices();
    _loadExistingAudio();
  }

  Future<void> _playFile(File file) async {
    if (!file.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Аудио файл табылмады. Қайта оқып көріңіз.'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
      return;
    }
    try {
      await _audioService.stop();
      await _audioService.play(file);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Аудио ойнату қатесі: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _showSegmentEditor(int index) async {
    final segment = widget.result.segments[index];
    final controller = TextEditingController(text: segment.text);

    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Сегмент ${index + 1}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Уақыты: ${segment.start.toStringAsFixed(2)}s - ${segment.end.toStringAsFixed(2)}s',
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Мәтінді түзету',
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: SelectableText(
                    jsonEncode({
                      'start': segment.start,
                      'end': segment.end,
                      'text': segment.text,
                      'language': segment.language,
                    }),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Болдырмау'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final newText = controller.text.trim();
                  if (newText.isEmpty) return;
                  Navigator.of(context).pop();
                  await _regenerateSegment(index, newText);
                },
                child: const Text('Қайта оқыту'),
              ),
            ],
          ),
    );
  }

  Future<void> _regenerateSegment(int index, String text) async {
    if (_selectedVoice == null) return;
    await _ensureOutputFolder();
    if (_outputFolder == null) return;
    if (mounted) {
      setState(() {
        _isGenerating = true;
      });
    }
    try {
      final file = await _ttsService.convert(
        text: text,
        voice: _selectedVoice!,
        speed: _speed,
      );

      final newPath = '$_outputFolder/segment_${index + 1}.mp3';
      final newFile = await file.copy(newPath);
      await file.delete();

      if (mounted) {
        setState(() {
          _segmentFiles[index] = newFile;
          _failedSegments.remove(index);
          if (index < _generatedFiles.length) {
            _generatedFiles[index] = newFile;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Сегментті қайта оқу қатесі: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _regenerateSegmentFromOriginal(int index) async {
    if (_selectedVoice == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Дыбысты таңдаңыз'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
      return;
    }

    final text = widget.result.segments[index].text;
    await _regenerateSegment(index, text);
  }

  Future<List<int>> _findMissingSegments() async {
    if (_outputFolder == null) return List.of(_failedSegments);
    final missing = <int>{..._failedSegments};
    for (var i = 0; i < _totalSegments; i++) {
      final path = '$_outputFolder/segment_${i + 1}.mp3';
      if (!await File(path).exists()) {
        missing.add(i);
      }
    }
    final list = missing.toList()..sort();
    return list;
  }

  String _formatList(List<int> list) {
    if (list.isEmpty) return '';
    final sorted = List<int>.from(list)..sort();
    return sorted.map((e) => '${e + 1}').join(', ');
  }

  @override
  void dispose() {
    _ttsService.dispose();
    _audioService.dispose();
    super.dispose();
  }

  Future<void> _loadVoices() async {
    if (!mounted) return;
    setState(() {
      _isLoadingVoices = true;
    });

    try {
      final voices = await _ttsService.getVoices();
      if (!mounted) return;
      setState(() {
        _voices = voices;
        if (voices.isNotEmpty) {
          _selectedVoice = voices.first;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Дыбыстарды жүктеу қатесі: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingVoices = false;
        });
      }
    }
  }

  Future<void> _loadExistingAudio() async {
    final folder = widget.initialAudioPath;
    if (folder == null) return;
    final dir = Directory(folder);
    if (!await dir.exists()) return;

    final files =
        await dir
            .list()
            .where((e) => e is File && e.path.toLowerCase().endsWith('.mp3'))
            .cast<File>()
            .toList();

    files.sort((a, b) => a.path.compareTo(b.path));

    if (mounted) {
      setState(() {
        _outputFolder = folder;
        _segmentFiles.clear();
        for (var i = 0; i < files.length; i++) {
          _segmentFiles[i] = files[i];
        }
        _generatedFiles = List<File>.from(files);
        _isComplete = files.isNotEmpty;
        _failedSegments.clear();
      });
    }
  }

  Future<void> _startGeneration() async {
    if (_selectedVoice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Дыбысты таңдаңыз'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    // Жаңа TTS басталғанда алдыңғы біріктірілген видеоны өшіру
    if (widget.currentFinalVideoPath != null) {
      try {
        final oldVideo = File(widget.currentFinalVideoPath!);
        if (await oldVideo.exists()) {
          await oldVideo.delete();
          debugPrint('Жаңа TTS үшін алдыңғы біріктірілген видео өшірілді: ${widget.currentFinalVideoPath}');
        }
      } catch (e) {
        debugPrint('Алдыңғы видеоны өшіру қатесі: $e');
      }
    }

    if (mounted) {
      setState(() {
        _isGenerating = true;
        _currentSegment = 0;
        _generatedFiles = [];
        _segmentFiles.clear();
        _failedSegments.clear();
        _isComplete = false;
      });
    }

    try {
      // Папка құру
      await _ensureOutputFolder(forceNew: true);
      if (_outputFolder == null) {
        throw Exception('Аудио папкасын жасау мүмкін болмады');
      }

      // Әр сегментті оқыту
      for (int i = 0; i < widget.result.segments.length; i++) {
        final segment = widget.result.segments[i];

        if (!mounted) return;
        setState(() {
          _currentSegment = i + 1;
        });

        try {
          final file = await _ttsService.convert(
            text: segment.text,
            voice: _selectedVoice!,
            speed: _speed,
          );

          // Файлды папкаға көшіру
          final newPath = '$_outputFolder/segment_${i + 1}.mp3';
          final newFile = await file.copy(newPath);
          await file.delete(); // Уақытша файлды өшіру

          if (!mounted) return;
          setState(() {
            _generatedFiles.add(newFile);
            _segmentFiles[i] = newFile;
            _failedSegments.remove(i);
          });

          // Кішкене кідіріс қою (API rate limit үшін)
          await Future.delayed(const Duration(milliseconds: 300));
        } catch (e) {
          _failedSegments.add(i);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${i + 1}-сөйлем қатесі: $e'),
                backgroundColor: AppTheme.errorColor,
              ),
            );
          }
          // Қатеден кейін жалғастыру
        }
      }

      final missing = await _findMissingSegments();
      final hasErrors = missing.isNotEmpty || _failedSegments.isNotEmpty;

      if (mounted) {
        setState(() {
          _isComplete = !hasErrors;
        });
      }

      if (hasErrors) {
        final missingText = [
          if (missing.isNotEmpty) 'Жоқ: ${_formatList(missing)}',
          if (_failedSegments.isNotEmpty) 'Қате: ${_formatList(_failedSegments.toList())}',
        ].join(' • ');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Аудио толық емес. $missingText'),
              backgroundColor: AppTheme.errorColor,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return; // Тек толық аудио болса ғана merge-ке өтеміз
      }

      // Notify parent about completion with folder path
      if (widget.onComplete != null && _outputFolder != null) {
        widget.onComplete!(_outputFolder!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Барлық файлдар сақталды'),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Қате: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _ensureOutputFolder({bool forceNew = false}) async {
    if (!forceNew && _outputFolder != null) {
      final dir = Directory(_outputFolder!);
      if (await dir.exists()) return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final folderName = 'tts_${widget.result.filename}_$timestamp';
    final folder = Directory('${dir.path}/$folderName');
    await folder.create(recursive: true);

    if (mounted) {
      setState(() {
        _outputFolder = folder.path;
      });
    } else {
      _outputFolder = folder.path;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Тақырып
          Row(
            children: [
              const Icon(
                Icons.record_voice_over,
                color: AppTheme.accentColor,
                size: 24,
              ),
              const SizedBox(width: 12),
              const Text(
                'Транскрипцияны оқыту',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Дыбыс таңдау
          if (_isLoadingVoices)
            const Center(child: CircularProgressIndicator())
          else if (_voices.isEmpty)
            const Text(
              'Дыбыстар жүктелмеді',
              style: TextStyle(color: AppTheme.errorColor),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Дыбысты таңдаңыз:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedVoice,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items:
                        _voices.map((voice) {
                          return DropdownMenuItem(
                            value: voice,
                            child: Text(voice),
                          );
                        }).toList(),
                    onChanged:
                        _isGenerating
                            ? null
                            : (value) {
                              setState(() {
                                _selectedVoice = value;
                              });
                            },
                  ),
                ),
              ],
            ),
          const SizedBox(height: 20),

          // Жылдамдық
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Оқыту жылдамдығы:',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${_speed.toStringAsFixed(1)}x',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.accentColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Slider(
                value: _speed,
                min: 0.5,
                max: 2.0,
                divisions: 15,
                label: '${_speed.toStringAsFixed(1)}x',
                onChanged:
                    _isGenerating
                        ? null
                        : (value) {
                          setState(() {
                            _speed = value;
                          });
                        },
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Ақпарат
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.backgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.borderColor),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 20,
                  color: AppTheme.accentColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Барлығы: $_totalSegments сөйлем',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Прогресс
          if (_isGenerating) ...[
            LinearProgressIndicator(
              value: _currentSegment / _totalSegments,
              backgroundColor: AppTheme.borderColor,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppTheme.accentColor,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                '$_currentSegment-сөйлем оқылуда...',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accentColor,
                ),
              ),
            ),
          ],

          // Нәтижелер тізімі + тыңдау және қайталау
          if (_segmentFiles.isNotEmpty || _isComplete) ...[
            const SizedBox(height: 20),
            const Text(
              'Оқылған сөйлемдер:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: List.generate(_totalSegments, (i) {
                final file = _segmentFiles[i];
                final exists = file != null && file.existsSync();
                final isMissing = !exists || _failedSegments.contains(i);
                final displayIndex = i + 1;

                return Container(
                  width: 140,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isMissing
                        ? Colors.red.withValues(alpha: 0.08)
                        : AppTheme.backgroundColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isMissing ? Colors.red : AppTheme.borderColor,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        backgroundColor: isMissing
                            ? Colors.red.withValues(alpha: 0.2)
                            : AppTheme.accentColor.withValues(alpha: 0.15),
                        child: Text(
                          '$displayIndex',
                          style: TextStyle(
                            color: isMissing ? Colors.red : AppTheme.accentColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                tooltip: isMissing ? 'Файл жоқ' : 'Тыңдау',
                                icon: Icon(
                                  Icons.play_circle_fill,
                                  color: isMissing
                                      ? Colors.grey
                                      : AppTheme.accentColor,
                                ),
                                onPressed:
                                    isMissing ? null : () => _playFile(file!),
                              ),
                              IconButton(
                                tooltip: 'Қайталау / түзету',
                                icon: const Icon(
                                  Icons.repeat,
                                  color: Colors.orange,
                                ),
                                onPressed: () => isMissing
                                    ? _regenerateSegmentFromOriginal(i)
                                    : _showSegmentEditor(i),
                              ),
                            ],
                          ),
                          Text(
                            'Қайталау',
                            style: TextStyle(
                              fontSize: 11,
                              color: isMissing ? Colors.red : Colors.orange,
                              fontWeight: isMissing ? FontWeight.w700 : null,
                            ),
                          ),
                          if (isMissing)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                _failedSegments.contains(i) ? 'Қате/оқылмады' : 'Файл жоқ',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ),
          ],

          const SizedBox(height: 24),

          // Басқару батырмалары
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed:
                      (_isGenerating || _selectedVoice == null)
                          ? null
                          : _startGeneration,
                  icon:
                      _isGenerating
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                          : const Icon(Icons.play_arrow),
                  label: Text(_isGenerating ? 'Оқылуда...' : 'Оқытуды бастау'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              if (_isComplete) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (widget.onAutoMerge != null) {
                        widget.onAutoMerge!();
                      } else if (widget.onComplete != null && _outputFolder != null) {
                        widget.onComplete!(_outputFolder!);
                      }
                    },
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Автоматты Біріктіру'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
