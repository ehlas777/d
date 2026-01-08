import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:file_picker/file_picker.dart';
import '../l10n/app_localizations.dart';
import '../config/app_theme.dart';

class VideoDropzone extends StatefulWidget {
  final Function(PlatformFile) onFileSelected;
  final VoidCallback? onSessionExpired; // Callback for session expiry

  const VideoDropzone({
    super.key,
    required this.onFileSelected,
    this.onSessionExpired,
  });

  @override
  State<VideoDropzone> createState() => _VideoDropzoneState();
}

class _VideoDropzoneState extends State<VideoDropzone> {
  bool _isHovering = false;

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        widget.onFileSelected(result.files.first);
      }
    } on PlatformException catch (e) {
      // Check for SESSION_NOT_FOUND error
      if (e.code == 'SESSION_NOT_FOUND' || e.message?.contains('Session not found') == true) {
        debugPrint('Session expired: ${e.message}');
        widget.onSessionExpired?.call();
      } else {
        debugPrint('Error picking file: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error selecting file: ${e.message ?? e.code}')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: _pickFile,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          child: DottedBorder(
            color: _isHovering ? AppTheme.accentColor : AppTheme.borderColor,
            strokeWidth: 2,
            borderType: BorderType.RRect,
            radius: const Radius.circular(12),
            dashPattern: const [8, 4],
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Tooltip(
                    message: l10n.addVideo,
                    child: Icon(
                      Icons.cloud_upload_outlined,
                      size: 64,
                      color: _isHovering
                          ? AppTheme.accentColor
                          : AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.dragDropVideo,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: _isHovering
                              ? AppTheme.accentColor
                              : AppTheme.textPrimary,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.orClickToSelect,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.supportedFormats,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.maxFileSize,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
