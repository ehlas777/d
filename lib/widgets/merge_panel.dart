import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:video_player/video_player.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'dart:io';
import 'dart:typed_data';
import '../config/app_theme.dart';
import '../models/transcription_result.dart';
import '../services/video_splitter_service.dart';
import '../services/settings_service.dart';
import 'video_preview.dart';

class MergePanel extends StatefulWidget {
  final TranscriptionResult transcriptionResult;
  final String videoPath;
  final String? audioPath;
  final String? initialFinalVideoPath;
  final ValueChanged<String?>? onComplete;

  const MergePanel({
    super.key,
    required this.transcriptionResult,
    required this.videoPath,
    this.audioPath,
    this.initialFinalVideoPath,
    this.onComplete,
  });

  @override
  State<MergePanel> createState() => _MergePanelState();
}

class _MergePanelState extends State<MergePanel> {
  bool _isSplitting = false;
  bool _isMerging = false;
  bool _isConcatenating = false;
  double _progress = 0.0;
  String? _errorMessage;
  String? _splitVideoDirectory;
  String? _mergedVideoDirectory;
  String? _finalVideoPath;
  Uint8List? _thumbnailBytes;
  double _speedMultiplier = 1.0;
  final VideoSplitterService _splitterService = VideoSplitterService();
  final SettingsService _settingsService = SettingsService();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    if (widget.initialFinalVideoPath != null) {
      _prepareFinalVideo(widget.initialFinalVideoPath!);
    }
  }

  /// Сақталған параметрлерді жүктеу
  Future<void> _loadSettings() async {
    final savedSpeed = await _settingsService.loadSpeedMultiplier();
    setState(() {
      _speedMultiplier = savedSpeed;
    });
  }

  /// Жылдамдықты сақтау
  Future<void> _saveSpeedMultiplier(double value) async {
    await _settingsService.saveSpeedMultiplier(value);
    setState(() {
      _speedMultiplier = value;
    });
  }

  void _showNotSupportedMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).translate('action_not_supported')),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Photos қолданбасына видео сақтау
  Future<void> _saveToPhotos(String videoPath) async {
    try {
      if (Platform.isIOS || Platform.isAndroid) {
        bool success = false;
        try {
          await Gal.putVideo(videoPath);
          success = true;
        } catch (e) {
          success = false;
        }
        if (!mounted) return;
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context).translate('video_saved_to_photos')),
                ],
              ),
              backgroundColor: AppTheme.successColor,
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(child: Text(AppLocalizations.of(context).translate('video_not_saved_to_photos'))),
                ],
              ),
              backgroundColor: AppTheme.errorColor,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else if (Platform.isMacOS) {
        // Photos іске қосылып тұрғанына көз жеткізу
        await Process.run('open', ['-a', 'Photos']);

        final escapedPath = videoPath.replaceAll('"', '\\"');
        final script = '''
tell application "Photos"
  activate
  import POSIX file "$escapedPath"
end tell
''';

        final result = await Process.run('osascript', ['-e', script]);

        if (mounted) {
          if (result.exitCode == 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(AppLocalizations.of(context).translate('video_added_to_photos')),
                  ],
                ),
                backgroundColor: AppTheme.successColor,
                duration: const Duration(seconds: 3),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${AppLocalizations.of(context).translate('video_save_error')}: ${result.stderr}')),
                  ],
                ),
                backgroundColor: AppTheme.errorColor,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } else if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        final picturesDir =
            userProfile != null ? Directory('$userProfile\\Pictures') : null;
        final targetDir =
            picturesDir != null && picturesDir.existsSync()
                ? picturesDir
                : await getApplicationDocumentsDirectory();

        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }

        final fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
        final destination =
            '${targetDir.path}${Platform.pathSeparator}$fileName';
        await File(videoPath).copy(destination);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context).translate('video_saved_to_photos')),
                ],
              ),
              backgroundColor: AppTheme.successColor,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        _showNotSupportedMessage();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('${AppLocalizations.of(context).translate('video_save_error')}: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Downloads қалтасына видео көшіру (macOS, Windows және Android үшін)
  Future<void> _saveToDownloads(String videoPath) async {
    try {
      Directory? downloadsDir;
      String? destination;

      if (Platform.isAndroid) {
        // Android үшін gal пайдаланамыз
        // Бұл галереяға автоматты түрде сақтайды
        bool success = false;
        try {
          await Gal.putVideo(videoPath);
          success = true;
        } catch (e) {
          success = false;
        }

        if (!mounted) return;

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(child: Text(AppLocalizations.of(context).translate('video_saved_to_downloads'))),
                ],
              ),
              backgroundColor: AppTheme.successColor,
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          throw Exception('Видео сақтау сәтсіз аяқталды');
        }
        return;
      } else if (Platform.isMacOS || Platform.isWindows) {
        // Try to use getDownloadsDirectory for proper sandbox support
        try {
          downloadsDir = await getDownloadsDirectory();
        } catch (_) {
          // Fallback to manual path resolution
          if (Platform.isMacOS) {
            final home = Platform.environment['HOME'];
            if (home != null) {
              downloadsDir = Directory('$home/Downloads');
            }
          } else if (Platform.isWindows) {
            final userProfile = Platform.environment['USERPROFILE'];
            if (userProfile != null) {
              downloadsDir = Directory('$userProfile\\Downloads');
            }
          }
        }
      } else {
        _showNotSupportedMessage();
        return;
      }

      if (downloadsDir == null) {
        throw Exception('Downloads қалтасын анықтау мүмкін болмады');
      }

      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      final fileName =
          'translated_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      destination = '${downloadsDir.path}${Platform.pathSeparator}$fileName';

      await File(videoPath).copy(destination);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(AppLocalizations.of(context).translate('video_saved_to_downloads'))),
            ],
          ),
          backgroundColor: AppTheme.successColor,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: AppLocalizations.of(context).translate('open'),
            textColor: Colors.white,
            onPressed: () => _openInFolder(destination!),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('${AppLocalizations.of(context).translate('video_save_error')}: $e')),
              ],
            ),
            backgroundColor: AppTheme.errorColor,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Файлды қалтада ашу
  Future<void> _openInFolder(String filePath) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', filePath]);
      } else if (Platform.isWindows) {
        await Process.run('explorer.exe', ['/select,', filePath]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context).translate('error')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _prepareFinalVideo(String originalPath) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final finalDir = Directory('${appDir.path}/final_videos');
      if (!await finalDir.exists()) {
        await finalDir.create(recursive: true);
      }

      final fileName = originalPath.split(Platform.pathSeparator).last;
      String targetPath = '${finalDir.path}/$fileName';

      if (originalPath != targetPath) {
        var counterPath = targetPath;
        while (await File(counterPath).exists()) {
          counterPath =
              '${finalDir.path}/${DateTime.now().millisecondsSinceEpoch}_$fileName';
        }
        targetPath = counterPath;
        await File(originalPath).copy(targetPath);
      }

      if (mounted) {
        setState(() {
          _finalVideoPath = targetPath;
        });
      } else {
        _finalVideoPath = targetPath;
      }

      await _generateThumbnail(targetPath);
    } catch (_) {
      if (mounted) {
        setState(() {
          _finalVideoPath = originalPath;
        });
      } else {
        _finalVideoPath = originalPath;
      }
    }
  }

  Future<void> _generateThumbnail(String videoPath) async {
    try {
      // Use native video thumbnail generation (fast, works on Android/iOS/macOS)
      final plugin = FcNativeVideoThumbnail();

      // Create temporary path for thumbnail
      final tempDir = await getTemporaryDirectory();
      final thumbnailPath =
          '${tempDir.path}/merge_thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final success = await plugin.getVideoThumbnail(
        srcFile: videoPath,
        destFile: thumbnailPath,
        width: 640,
        height: 360,
        format: 'jpeg',
        quality: 85,
      );

      if (success) {
        final thumbnailFile = File(thumbnailPath);
        if (await thumbnailFile.exists()) {
          final bytes = await thumbnailFile.readAsBytes();
          if (mounted) {
            setState(() {
              _thumbnailBytes = bytes;
            });
          }
          // Clean up temporary file
          try {
            await thumbnailFile.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Error generating thumbnail: $e');
    }
  }

  Future<void> _openVideoPreview(String videoPath) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    VideoPreview(videoPath: videoPath),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _startSplitting() async {
    final videoFile = File(widget.videoPath);
    if (!await videoFile.exists()) {
      setState(() {
        _errorMessage =
            'Бейне файл табылмады. Бейненi қайта таңдаңыз немесе жобаны қайта бастаңыз.';
      });
      return;
    }

    setState(() {
      _isSplitting = true;
      _progress = 0.0;
      _errorMessage = null;
      _splitVideoDirectory = null;
      _mergedVideoDirectory = null;
      _finalVideoPath = null;
      _thumbnailBytes = null;
    });

    try {
      final outputDir = await _splitterService.splitVideoBySegments(
        videoPath: widget.videoPath,
        segments: widget.transcriptionResult.segments,
        onProgress: (progress) {
          setState(() {
            _progress = progress;
          });
        },
      );

      setState(() {
        _splitVideoDirectory = outputDir;
        _progress = 1.0;
        _isSplitting = false;
      });

      // Егер аудио жолы бар болса, автоматты түрде біріктіруді бастау
      if (widget.audioPath != null) {
        await _startMerging();
      } else {
        widget.onComplete?.call(null);
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isSplitting = false;
      });
    }
  }

  Future<void> _startMerging() async {
    if (_splitVideoDirectory == null || widget.audioPath == null) {
      setState(() {
        _errorMessage = 'Видео немесе аудио файлдар табылмады';
      });
      return;
    }

    // Алдымен аудио папкасын тексереміз: қай сегмент жетіспейді?
    final missingSegments = await _findMissingAudioSegments(
      widget.audioPath!,
      widget.transcriptionResult.segments.length,
    );
    if (missingSegments.isNotEmpty) {
      final formatted = missingSegments.length > 10
          ? '${missingSegments.take(10).join(', ')} ... (барлығы ${missingSegments.length})'
          : missingSegments.join(', ');
      setState(() {
        _errorMessage =
            'Аудио файлдар табылмады: сегменттер $formatted. TTS панелінде осы сегменттерді қайта оқытып, Merge-ті қайта бастаңыз.';
      });
      return;
    }

    setState(() {
      _isMerging = true;
      _progress = 0.0;
      _errorMessage = null;
    });

    try {
      final mergedDir = await _splitterService.mergeVideoWithAudio(
        splitVideoDir: _splitVideoDirectory!,
        audioDir: widget.audioPath!,
        segments: widget.transcriptionResult.segments,
        onProgress: (progress) {
          setState(() {
            _progress = progress;
          });
        },
      );

      setState(() {
        _mergedVideoDirectory = mergedDir;
        _progress = 1.0;
        _isMerging = false;
      });

      // Аудио біріктіру аяқталғаннан кейін соңғы видеоны біріктіру
      await _concatenateFinalVideo();
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isMerging = false;
      });
    }
  }

  /// Merge алдында аудио файлдардың толықтығын тексеру
  Future<List<int>> _findMissingAudioSegments(String audioDir, int segmentCount) async {
    final missing = <int>[];
    for (var i = 0; i < segmentCount; i++) {
      final path = '$audioDir/segment_${i + 1}.mp3';
      if (!await File(path).exists()) {
        missing.add(i + 1);
      }
    }
    return missing;
  }

  Future<void> _concatenateFinalVideo() async {
    if (_mergedVideoDirectory == null) {
      setState(() {
        _errorMessage = 'Біріктірілген видео файлдар табылмады';
      });
      return;
    }

    setState(() {
      _isConcatenating = true;
      _progress = 0.0;
      _errorMessage = null;
    });

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${appDir.path}/final_videos/final_$timestamp.mp4';

      // Каталогты жасау
      final outputDir = Directory('${appDir.path}/final_videos');
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      final finalPath = await _splitterService.concatenateAndSpeedUp(
        mergedVideoDir: _mergedVideoDirectory!,
        outputPath: outputPath,
        speedMultiplier: _speedMultiplier,
        onProgress: (progress) {
          setState(() {
            _progress = progress;
          });
        },
      );

      await _prepareFinalVideo(finalPath);

      setState(() {
        _progress = 1.0;
        _isConcatenating = false;
      });

      widget.onComplete?.call(_finalVideoPath ?? finalPath);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isConcatenating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('step_merge'),
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        // Жылдамдық реттегіші
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.translate('final_video_speed'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${_speedMultiplier.toStringAsFixed(1)}x',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accentColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('0.5x', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: _speedMultiplier,
                      min: 0.5,
                      max: 2.0,
                      divisions: 30,
                      activeColor: AppTheme.accentColor,
                      inactiveColor: AppTheme.borderColor,
                      onChanged:
                          (_isSplitting || _isMerging || _isConcatenating)
                              ? null
                              : (value) {
                                _saveSpeedMultiplier(value);
                              },
                    ),
                  ),
                  const Text('2.0x', style: TextStyle(fontSize: 12)),
                ],
              ),

            ],
          ),
        ),
        const SizedBox(height: 24),

        // Батырмалар панелі (тек финалдық видео дайын болғанда)
        if (_finalVideoPath != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.video_library,
                      color: AppTheme.primaryBlue,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.translate('video_actions'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_finalVideoPath != null) ...[
                  GestureDetector(
                    onTap: () => _openVideoPreview(_finalVideoPath!),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            height: 180,
                            width: double.infinity,
                            child:
                                _thumbnailBytes != null
                                    ? Image.memory(
                                      _thumbnailBytes!,
                                      fit: BoxFit.cover,
                                    )
                                    : _VideoThumbnail(path: _finalVideoPath!),
                          ),
                          Container(
                            height: 180,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  AppTheme.textPrimary.withValues(alpha: 0.0),
                                  AppTheme.textPrimary.withValues(alpha: 0.3),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_circle_fill,
                              size: 56,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed:
                            _finalVideoPath != null
                                ? () async {
                                  await _saveToPhotos(_finalVideoPath!);
                                }
                                : null,
                        icon: const Icon(Icons.photo_library, size: 20),
                        label: Text(l10n.translate('save_to_photos')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          disabledBackgroundColor: Colors.grey.shade300,
                        ),
                      ),
                    ),
                    if (Platform.isMacOS ||
                        Platform.isWindows ||
                        Platform.isAndroid) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed:
                              _finalVideoPath != null
                                  ? () async {
                                    await _saveToDownloads(_finalVideoPath!);
                                  }
                                  : null,
                          icon: const Icon(Icons.download, size: 20),
                          label: Text(l10n.translate('download')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.successColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            disabledBackgroundColor: Colors.grey.shade300,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),

        // Қате хабарламасы
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
                    _errorMessage!,
                    style: const TextStyle(color: AppTheme.errorColor),
                  ),
                ),
              ],
            ),
          ),

        // Прогресс индикатор
        if (_isSplitting || _isMerging || _isConcatenating) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: Colors.grey.withValues(alpha: 0.2),
                  color: AppTheme.accentColor,
                ),
                const SizedBox(height: 12),
                Text(
                  '${(_progress * 100).toInt()}% - ${l10n.translate('processing')}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Түймелер
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed:
                    (_isSplitting || _isMerging) ? null : _startSplitting,
                icon: const Icon(Icons.content_cut),
                label: Text(l10n.translate('step_merge')),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: AppTheme.accentColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _VideoThumbnail extends StatefulWidget {
  final String path;

  const _VideoThumbnail({required this.path});

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  @override
  void didUpdateWidget(covariant _VideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _controller.dispose();
      _initialized = false;
      _hasError = false;
      _initController();
    }
  }

  Future<void> _initController() async {
    final path = widget.path;
    _controller = VideoPlayerController.file(File(path));
    try {
      await _controller.initialize();
      if (mounted && path == widget.path) {
        setState(() {
          _initialized = true;
        });
      }
    } catch (_) {
      if (mounted && path == widget.path) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _buildPlaceholder(icon: Icons.error_outline, color: Colors.red);
    }
    if (!_initialized) {
      return _buildPlaceholder(icon: Icons.movie, color: Colors.grey);
    }

    return AspectRatio(
      aspectRatio: _controller.value.aspectRatio,
      child: VideoPlayer(_controller),
    );
  }

  Widget _buildPlaceholder({required IconData icon, required Color color}) {
    return Container(
      color: Colors.black12,
      alignment: Alignment.center,
      child: Icon(icon, size: 48, color: color),
    );
  }
}
