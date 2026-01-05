  Future<void> _runAutomaticTranslation(String targetLanguage) async {
    if (_result == null || _isTranslating || _orchestrator == null || _selectedFile == null) return;

    setState(() {
      _isTranslating = true;
      _automaticLogs.clear();
      _automaticLogs.add('[INFO] Automatic mode activated');
    });

    try {
      final videoFile = File(_selectedFile!.path!);
      
      // Get TTS settings from TranscriptionEditor (already saved in SharedPreferences)
      final prefs = await SharedPreferences.getInstance();
      final voice = prefs.getString('tts_voice') ?? 'alloy';
      final speed = prefs.getDouble('video_speed') ?? 1.2;
      
      _automaticLogs.add('[INFO] Voice: $voice, Speed: ${speed}x');
      
      final result = await _orchestrator!.processAutomatic(
        videoFile: videoFile,
        targetLanguage: targetLanguage,
        voice: voice,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _automaticLogs.add('[${progress.currentStage.name}] ${progress.currentActivity}');
            });
          }
        },
      );
      
      if (mounted) {
        setState(() {
          _automaticLogs.add('✓ Automatic translation pipeline complete!');
          _automaticLogs.add('Final video: ${result.finalVideoPath ?? "N/A"}');
          _isTranslating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _automaticLogs.add('✗ Error: $e');
          _isTranslating = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Automatic translation failed: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }
