import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:typed_data';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';

class VideoPreview extends StatefulWidget {
  final String videoPath;

  const VideoPreview({
    super.key,
    required this.videoPath,
  });

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  Uint8List? _thumbnailBytes;
  bool _isLoadingThumbnail = true;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    try {
      // Use native video thumbnail generation (fast, works on Android/iOS/macOS)
      final plugin = FcNativeVideoThumbnail();

      // Create temporary path for thumbnail
      final tempDir = await getTemporaryDirectory();
      final thumbnailPath = '${tempDir.path}/thumbnail_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final success = await plugin.getVideoThumbnail(
        srcFile: widget.videoPath,
        destFile: thumbnailPath,
        width: 300,
        height: 200,
        format: 'jpeg',
        quality: 85,
      );

      if (success) {
        final thumbnailFile = File(thumbnailPath);
        if (await thumbnailFile.exists()) {
          final bytes = await thumbnailFile.readAsBytes();
          if (!mounted) return;
          setState(() {
            _thumbnailBytes = bytes;
            _isLoadingThumbnail = false;
          });
          // Clean up temporary file
          try {
            await thumbnailFile.delete();
          } catch (_) {}
          return;
        }
      }

      // If thumbnail generation fails, show error state
      if (!mounted) return;
      setState(() {
        _isLoadingThumbnail = false;
        _hasError = true;
      });
    } catch (e) {
      debugPrint('Error generating thumbnail: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingThumbnail = false;
        _hasError = true;
      });
    }
  }

  Future<void> _initializeVideo() async {
    if (_controller != null) return;

    try {
      _controller = VideoPlayerController.file(File(widget.videoPath));
      await _controller!.initialize();
      if (!mounted) return;
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      setState(() {
        _hasError = true;
      });
      debugPrint('Error initializing video: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller == null) {
      _initializeVideo().then((_) {
        if (_controller != null && mounted) {
          _controller!.play();
        }
      });
      return;
    }

    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_hasError) {
      return Container(
        height: 300,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: AppTheme.errorColor,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.error,
              style: const TextStyle(color: AppTheme.errorColor),
            ),
          ],
        ),
      );
    }

    // Show loading indicator while generating thumbnail
    if (_isLoadingThumbnail) {
      return Container(
        height: 300,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }

    // Show video player if initialized, otherwise show thumbnail
    if (_isInitialized && _controller != null) {
      return Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 300,
              maxHeight: 200,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_controller!),
                    if (!_controller!.value.isPlaying)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Tooltip(
                          message: l10n.preview,
                          child: IconButton(
                            icon: const Icon(Icons.play_arrow, size: 64),
                            color: Colors.white,
                            onPressed: _togglePlayPause,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Tooltip(
                message: _controller!.value.isPlaying
                    ? l10n.translate('pause')
                    : l10n.translate('play'),
                child: IconButton(
                  icon: Icon(
                    _controller!.value.isPlaying
                        ? Icons.pause
                        : Icons.play_arrow,
                  ),
                  onPressed: _togglePlayPause,
                ),
              ),
              Expanded(
                child: VideoProgressIndicator(
                  _controller!,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: AppTheme.accentColor,
                    bufferedColor: AppTheme.borderColor,
                    backgroundColor: AppTheme.backgroundColor,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '${_formatDuration(_controller!.value.position)} / ${_formatDuration(_controller!.value.duration)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ],
      );
    }

    // Show thumbnail with play button overlay
    return Column(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 300,
            maxHeight: 200,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Thumbnail image
                if (_thumbnailBytes != null)
                  Image.memory(
                    _thumbnailBytes!,
                    fit: BoxFit.cover,
                    width: 300,
                    height: 200,
                  )
                else
                  Container(
                    width: 300,
                    height: 200,
                    color: Colors.grey.shade800,
                    child: const Icon(
                      Icons.videocam,
                      size: 64,
                      color: Colors.grey,
                    ),
                  ),
                // Play button overlay
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Tooltip(
                    message: l10n.translate('play'),
                    child: IconButton(
                      icon: const Icon(Icons.play_arrow, size: 64),
                      color: Colors.white,
                      onPressed: _togglePlayPause,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
