import 'package:flutter/material.dart';
import '../models/transcription_result.dart';
import 'transcription_editor.dart';

class JsonViewer extends StatefulWidget {
  final TranscriptionResult result;
  final VoidCallback? onDownload;
  final Future<void> Function(String targetLanguage)? onTranslate;

  const JsonViewer({
    super.key,
    required this.result,
    this.onDownload,
    this.onTranslate,
  });

  @override
  State<JsonViewer> createState() => _JsonViewerState();
}

class _JsonViewerState extends State<JsonViewer> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  TranscriptionResult? _translatedResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Editor content
        TranscriptionEditor(
          key: ValueKey(_translatedResult != null ? 'translated' : 'original'),
          result: _translatedResult ?? widget.result,
          onSave: widget.onDownload,
          onTranslate: widget.onTranslate,
        ),
      ],
    );
  }

}
