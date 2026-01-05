import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../models/transcription_options.dart';
import '../models/transcription_result.dart';
import '../services/transcription_service.dart';
import '../widgets/video_dropzone.dart';
import '../widgets/video_preview.dart';
import '../widgets/transcription_settings_panel.dart';
import '../widgets/json_viewer.dart';
import '../widgets/login_dialog.dart';
import '../widgets/register_dialog.dart';
import '../widgets/profile_dialog.dart';
import '../widgets/project_steps_timeline.dart';
import '../widgets/transcription_tts_reader.dart';
import '../widgets/merge_panel.dart';
import '../widgets/trial_badge_widget.dart';
import '../widgets/trial_info_card.dart';
import '../providers/locale_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/project_provider.dart';
import '../providers/trial_provider.dart';
import '../models/translation_project.dart';
import '../services/api_client.dart';
import '../services/backend_translation_service.dart';
import '../models/translation_models.dart';
import '../services/video_processing_service.dart';
import '../services/openai_tts_service.dart';
import '../services/video_splitter_service.dart';
import '../services/automatic_translation_orchestrator.dart';
import '../services/auto_translation_storage.dart';
import '../services/throttled_queue.dart';
import '../services/network_resilience_handler.dart';
import '../services/storage_manager.dart';
import 'subscription_screen.dart';

enum TranscriptionState {
  idle,
  fileSelected,
  uploading,
  transcribing,
  completed,
  error,
}

enum SecondVideoPromptAction {
  login,
  register,
  skip,
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  TranscriptionState _state = TranscriptionState.idle;
  PlatformFile? _selectedFile;
  TranscriptionOptions _options = const TranscriptionOptions();
  // Hide advanced transcription parameters from end users
  static const bool _showTranscriptionSettings = false;
  TranscriptionResult? _result;
  String? _errorMessage;
  double _progress = 0.0;
  String? _localVideoPath;
  bool _isTranslating = false;
  bool _isSidebarCollapsed = true;
  bool _translationReady = false; // Show "Next step" only after API translation is done


  final _transcriptionService = TranscriptionService();
  final _videoProcessingService = VideoProcessingService();
  final _videoSplitter = VideoSplitterService();
  bool _isInitialized = false;
  
  // Automatic translation
  bool _useAutomaticMode = true; // Default: automatic mode enabled
  final List<String> _automaticLogs = [];
  AutomaticTranslationOrchestrator? _orchestrator;
  String? _finalVideoPath; // Completed video path

  @override
  void initState() {
    super.initState();
    _initializeWhisper();
    _initializeOrchestrator();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForIncompleteProjects();
      _checkTrialStatus();
    });
  }

  Future<void> _checkForIncompleteProjects() async {
    final projectProvider = Provider.of<ProjectProvider>(
      context,
      listen: false,
    );
    await projectProvider.initialize();

    if (projectProvider.hasResumableProject && mounted) {
      _resumeProject(projectProvider.currentProject!);
    }
  }

  Future<void> _resumeProject(TranslationProject project) async {
    final projectProvider = Provider.of<ProjectProvider>(
      context,
      listen: false,
    );
    final resolvedVideoPath = await _resolveProjectVideoPath(project);
    if (resolvedVideoPath != null && resolvedVideoPath != project.videoPath) {
      project = project.copyWith(videoPath: resolvedVideoPath);
      await projectProvider.updateCurrentProject(project);
    }

    // Try to load saved transcription result if it is not in the project
    TranscriptionResult? loadedResult = project.transcriptionResult;
    loadedResult ??= await _loadSavedTranscriptionResult(project.id);

    // МАҢЫЗДЫ: Аударылған мәтінді жүктеу логикасы
    // Аударма бар және progress = 1.0 болса, translated.json жүктеу
    final hasTranslation = project.translatedSegments?.isNotEmpty == true;
    final isTranslationInProgress =
        project.steps[ProjectStep.translation]?.status == ProjectStatus.inProgress;

    bool shouldLoadTranslated = false;
    if (hasTranslation && isTranslationInProgress) {
      final progress = project.steps[ProjectStep.translation]?.progress ?? 0.0;
      if (progress >= 1.0) {
        shouldLoadTranslated = true;
      }
    }

    if (shouldLoadTranslated && loadedResult != null) {
      final translatedResult = await _loadTranslatedResult(project.id);
      if (translatedResult != null) {
        loadedResult = translatedResult;
      }
    }

    // Normalize project state in case translation/TTS was already completed
    project = await _normalizeProjectProgress(project, loadedResult);
    // МАҢЫЗДЫ: Аударылған нәтижені жоғалтпау үшін, тек loadedResult null болса ғана project.transcriptionResult қолдану
    loadedResult ??= project.transcriptionResult;

    if (!mounted) return;

    final effectiveVideoPath = resolvedVideoPath ?? project.videoPath;

    // Load project and continue from current step
    setState(() {
      _selectedFile = PlatformFile(
        name: project.videoFileName,
        size: 0,
        path: effectiveVideoPath,
      );
      _localVideoPath = effectiveVideoPath;

      _result = loadedResult;

      // If transcription was already done (any step beyond transcription), jump straight to completed UI
      if (loadedResult != null ||
          project.currentStep != ProjectStep.transcription) {
        _state = TranscriptionState.completed;
        _progress = 1.0;
      } else if (project.currentStep == ProjectStep.transcription) {
        _state = TranscriptionState.fileSelected;
      } else {
        _state = TranscriptionState.idle;
      }
      _translationReady = _shouldMarkTranslationReady(project);
    });
  }

  Future<String?> _resolveProjectVideoPath(TranslationProject project) async {
    final storedPath = project.videoPath;
    if (await File(storedPath).exists()) {
      return storedPath;
    }

    final appDir = await getApplicationDocumentsDirectory();
    final candidates = <String>[
      p.join(appDir.path, 'videos', project.videoFileName),
      p.join(appDir.path, 'prepared_videos', project.videoFileName),
    ];

    final fallbackName = p.basename(storedPath);
    if (fallbackName.isNotEmpty && fallbackName != project.videoFileName) {
      candidates.addAll([
        p.join(appDir.path, 'videos', fallbackName),
        p.join(appDir.path, 'prepared_videos', fallbackName),
      ]);
    }

    for (final path in candidates) {
      if (await File(path).exists()) {
        return path;
      }
    }

    return null;
  }

  /// Ensure persisted project data reflects the furthest completed step
  /// so reopening the app returns the user to the correct stage (e.g. TTS done).
  Future<TranslationProject> _normalizeProjectProgress(
    TranslationProject project,
    TranscriptionResult? loadedResult,
  ) async {
    final projectProvider = Provider.of<ProjectProvider>(
      context,
      listen: false,
    );

    final updatedSteps = Map<ProjectStep, StepProgress>.from(project.steps);
    var normalizedProject = project;
    var hasChanges = false;

    StepProgress _ensureStep(ProjectStep step) {
      return updatedSteps[step] ??
          StepProgress(step: step, status: ProjectStatus.notStarted);
    }

    void _markCompleted(ProjectStep step) {
      final current = _ensureStep(step);
      if (current.status != ProjectStatus.completed) {
        updatedSteps[step] = current.copyWith(
          status: ProjectStatus.completed,
          progress: 1.0,
          startedAt: current.startedAt ?? DateTime.now(),
          completedAt: current.completedAt ?? DateTime.now(),
        );
        hasChanges = true;
      }
    }

    final hasTranscript = (loadedResult ?? project.transcriptionResult) != null;
    final hasTranslation = project.translatedSegments?.isNotEmpty == true;
    final hasAudio = project.audioPath != null;

    // Debug log
    print('=== _normalizeProjectProgress ===');
    print('hasTranscript: $hasTranscript');
    print('hasTranslation: $hasTranslation');
    print('hasAudio: $hasAudio');
    print('currentStep: ${project.currentStep}');
    print('translatedSegments count: ${project.translatedSegments?.length ?? 0}');
    print('translation status: ${updatedSteps[ProjectStep.translation]?.status}');

    if (hasTranscript) {
      _markCompleted(ProjectStep.transcription);
    }

    // МАҢЫЗДЫ: Translation қадамы ешқашан "completed" болмайды!
    // Translation үшін тек "inProgress" status-ын орнатамыз
    if (hasTranslation) {
      final translationStep = _ensureStep(ProjectStep.translation);
      if (translationStep.status == ProjectStatus.notStarted) {
        updatedSteps[ProjectStep.translation] = translationStep.copyWith(
          status: ProjectStatus.inProgress,
          progress: 1.0,
          startedAt: translationStep.startedAt ?? DateTime.now(),
        );
        hasChanges = true;
      }
    }

    if (hasAudio) {
      _markCompleted(ProjectStep.tts);

      final mergeStep = _ensureStep(ProjectStep.merge);
      if (mergeStep.status == ProjectStatus.notStarted) {
        updatedSteps[ProjectStep.merge] = mergeStep.copyWith(
          status: ProjectStatus.inProgress,
          progress: 0.0,
          startedAt: mergeStep.startedAt ?? DateTime.now(),
        );
        hasChanges = true;
      }
    }

    // Decide the furthest step we should show based on saved artifacts
    // МАҢЫЗДЫ: Translation қадамы үшін currentStep-ті сақтаймыз
    ProjectStep desiredStep = project.currentStep;

    // Қадамдарды артефакттарға қарап анықтау:
    // 1. Аудио файл бар -> TTS аяқталған -> merge қадамында болу керек
    // 2. currentStep = TTS болса -> TTS қадамында қалу
    // 3. currentStep = translation болса -> translation қадамында қалу
    // 4. Транскрипция бар -> translation қадамына өту

    if (hasAudio) {
      // Аудио бар болса, TTS аяқталған, merge қадамына өту
      desiredStep = ProjectStep.merge;
    } else if (project.currentStep == ProjectStep.tts) {
      // TTS қадамында болса, сол қадамда қалу
      desiredStep = ProjectStep.tts;
    } else if (hasTranslation || project.currentStep == ProjectStep.translation) {
      // Аударма бар немесе қазір translation қадамында болса, translation қадамында қалу
      desiredStep = ProjectStep.translation;
    } else if (hasTranscript &&
        updatedSteps[ProjectStep.transcription]?.status == ProjectStatus.completed) {
      // Транскрипция аяқталған болса, translation қадамына өту
      desiredStep = ProjectStep.translation;
    }

    if (desiredStep != project.currentStep) {
      hasChanges = true;
    }

    // Persist normalization so the sidebar timeline and next steps stay consistent
    if (hasChanges ||
        (project.transcriptionResult == null && loadedResult != null)) {
      normalizedProject = project.copyWith(
        currentStep: desiredStep,
        steps: updatedSteps,
        transcriptionResult: project.transcriptionResult ?? loadedResult,
      );

      await projectProvider.updateCurrentProject(normalizedProject);
    }

    return normalizedProject;
  }

  Future<void> _initializeWhisper() async {
    try {
      await _transcriptionService.initialize(modelName: _options.model);
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      setState(() {
        _errorMessage =
            'Failed to initialize Whisper: $e\n'
            'Please download the model file. See WHISPER_LOCAL_SETUP.md';
      });
    }
  }

  void _initializeOrchestrator() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = await authProvider.apiClient.getToken();
    
    _orchestrator = AutomaticTranslationOrchestrator(
      transcriptionService: _transcriptionService,
      translationService: BackendTranslationService(authProvider.apiClient),
      ttsService: OpenAiTtsService(
        baseUrl: ApiClient.baseUrl,
        authToken: token ?? '',
      ),
      videoSplitter: _videoSplitter,
      storage: AutoTranslationStorage(),
      apiQueue: ThrottledQueue(maxConcurrent: 3),
      networkHandler: NetworkResilienceHandler(),
      storageManager: StorageManager(),
    );
  }

  /// Trial статусын тексеру (тек аутентификацияланбаған пайдаланушылар үшін)
  Future<void> _checkTrialStatus() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    // Trial тек аутентификацияланбаған пайдаланушылар үшін
    if (!authProvider.isLoggedIn) {
      final trialProvider = Provider.of<TrialProvider>(context, listen: false);
      await trialProvider.checkTrialStatus();
    }
  }

  /// Trial workflow-ты аяқтау (видео сәтті өңделгеннен кейін)
  Future<void> _completeTrialWorkflow({
    required String videoFileName,
    required int durationSeconds,
  }) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    // Trial тек аутентификацияланбаған пайдаланушылар үшін
    if (!authProvider.isLoggedIn) {
      final trialProvider = Provider.of<TrialProvider>(context, listen: false);
      
      await trialProvider.completeTrial(
        videoFileName: videoFileName,
        durationSeconds: durationSeconds,
      );
      
      // Dialog жасырылды - келесі video select кезінде көрсетіледі
      // Өйткені ағымдағы video сәтті аяқталғанда блок болмауы керек
    }
  }

  /// Trial таусылған кезде көрсетілетін диалог
  void _showTrialExpiredPrompt() {
    final l10n = AppLocalizations.of(context);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('trial_expired_title')),
        content: Text(
          l10n.translate('trial_expired_message'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              showDialog(
                context: context,
                builder: (context) => const RegisterDialog(),
              );
            },
            child: Text(l10n.translate('register')),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _transcriptionService.dispose();
    super.dispose();
  }

  void _onFileSelected(PlatformFile file) async {
    final projectProvider = Provider.of<ProjectProvider>(
      context,
      listen: false,
    );

    // Clean up previous project completely when new video is selected
    final previousProject = projectProvider.currentProject;
    if (previousProject != null) {
      // Delete all artifacts from the previous project
      await _cleanupProjectArtifacts(
        previousProject.id,
        includeTranscription: true,  // Clean everything for new video
        includeTranslation: true,
        includeTts: true,
        includeMerge: true,
      );
      
      // Clear the project from storage
      await projectProvider.deleteProject(previousProject.id);
    }

    // Clean up any previously cached video
    await _deleteLocalVideo();

    setState(() {
      _state = TranscriptionState.uploading;
      _progress = 0.0;
      _errorMessage = null;
      _translationReady = false;
    });

    // Copy selected video into app documents to prevent missing files on resume
    final copied = await _copyVideoToAppStorage(file);
    if (copied == null) {
      setState(() {
        _state = TranscriptionState.error;
        _errorMessage = 'Failed to copy video file. Please try again.';
      });
      return;
    }

    // Check if user is logged in and show guest alert if not
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isLoggedIn) {
      // Trial қолданушылар үшін: attempts қалды ма тексеру
      final trialProvider = Provider.of<TrialProvider>(context, listen: false);
      
      // Егер trial attempts таусылса, блок ету
      if (!trialProvider.canUseTrial) {
        // Clean up
        await _deleteLocalVideo();
        setState(() {
          _state = TranscriptionState.idle;
          _selectedFile = null;
          _localVideoPath = null;
        });
        
        // Trial таусылған диалогын көрсету
        if (mounted) {
          _showTrialExpiredPrompt();
        }
        return;
      }
      
      // Trial қолжетімді болса, guest alert көрсету
      final l10n = AppLocalizations.of(context);
      final shouldProceed = await _showGuestUserAlert(l10n);
      
      // Handle user choice
      if (shouldProceed == false) {
        // User cancelled, clean up and reset
        setState(() {
          _state = TranscriptionState.idle;
          _selectedFile = null;
          _localVideoPath = null;
        });
        return;
      } else if (shouldProceed == null) {
        // User clicked Login button
        // Clean up video first
        await _deleteLocalVideo();
        setState(() {
          _state = TranscriptionState.idle;
          _selectedFile = null;
          _localVideoPath = null;
        });
        
        // Show login dialog
        if (mounted) {
          await showDialog(
            context: context,
            builder: (context) => const LoginDialog(),
          );
        }
        
        // After login dialog closes, user can select video again
        return;
      }
      // If shouldProceed == true, continue with guest upload
    }

    // Determine max video duration based on user subscription tier
    double maxDuration = 60.0; // Default for non-subscribed users

    // VIP немесе абонементі бар пайдаланушылар үшін trim жоқ
    bool skipTrim = false;
    
    if (authProvider.isLoggedIn) {
      // Шексіз қол жетімділік бар ма?
      if (authProvider.userInfo?.hasUnlimitedAccess == true) {
        skipTrim = true;
        print('✅ User has unlimited access - skipping trim');
      }
      // Абонемент бар ма? (VIP, Premium, т.б.)
      else if (authProvider.userInfo?.subscriptionStatus != null &&
          authProvider.userInfo?.subscriptionStatus?.toLowerCase() != 'none' &&
          authProvider.userInfo?.subscriptionStatus?.toLowerCase() != 'free') {
        skipTrim = true;
        print('✅ User has subscription (${authProvider.userInfo?.subscriptionStatus}) - skipping trim');
      }
      // Backend maxVideoDuration қайтарса, оны қолдану
      else if (authProvider.userInfo?.maxVideoDuration != null) {
        maxDuration = authProvider.userInfo!.maxVideoDuration!;
        print('✅ Backend maxVideoDuration: $maxDuration');
      } else {
        print('⚠️ Using default maxDuration: $maxDuration');
        print('   - isLoggedIn: ${authProvider.isLoggedIn}');
        print('   - hasUnlimitedAccess: ${authProvider.userInfo?.hasUnlimitedAccess}');
        print('   - subscriptionStatus: ${authProvider.userInfo?.subscriptionStatus}');
        print('   - maxVideoDuration: ${authProvider.userInfo?.maxVideoDuration}');
      }
    } else {
      // Guest/Trial қолданушылар үшін: TrialProvider-дан maxVideoDuration алу
      final trialProvider = Provider.of<TrialProvider>(context, listen: false);
      maxDuration = trialProvider.maxVideoDuration.toDouble();
      print('🎬 Trial user - maxVideoDuration from backend: $maxDuration seconds');
    }

    // Егер VIP болса, өте үлкен лимит қою (trim болмайды)
    if (skipTrim) {
      maxDuration = double.infinity;
    }

    try {
      // Process video - will trim only if it exceeds maxDuration
      final processingResult = await _videoProcessingService.prepareForTranslation(
        inputPath: copied.path!,
        maxDurationSeconds: maxDuration,
      );


      final processedFile = File(processingResult.outputPath);
      final processedSize = await processedFile.length();
      final preparedFile = PlatformFile(
        name: p.basename(processingResult.outputPath),
        size: processedSize,
        path: processingResult.outputPath,
      );

      // Remove the intermediate copy if we created a new processed file
      if (processingResult.outputPath != copied.path) {
        try {
          final originalCopy = File(copied.path!);
          if (await originalCopy.exists()) {
            await originalCopy.delete();
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _selectedFile = preparedFile;
        _localVideoPath = preparedFile.path;
        _state = TranscriptionState.fileSelected;
        _errorMessage = null;
        _translationReady = false;
      });

      // Create new project when file is selected
      await projectProvider.createProject(
        videoFileName: preparedFile.name,
        videoPath: preparedFile.path!,
      );

      _showVideoPrepMessage(processingResult);
    } catch (e) {
      setState(() {
        _state = TranscriptionState.error;
        _errorMessage = 'Видео дайындау сәтсіз: $e';
      });
    }
  }

  void _onOptionsChanged(TranscriptionOptions options) {
    setState(() {
      _options = options;
    });
  }

  Future<void> _startTranscription() async {
    if (_selectedFile == null || _selectedFile!.path == null) return;

    if (!_isInitialized) {
      setState(() {
        _state = TranscriptionState.error;
        _errorMessage = 'Whisper is not initialized. Please restart the app.';
      });
      return;
    }

    final l10n = AppLocalizations.of(context);
    if (await _shouldPromptForSecondVideo()) {
      final decision = await _showSecondVideoPrompt(l10n);
      await _markSecondVideoPromptShown();

      if (decision == SecondVideoPromptAction.login) {
        await showDialog(
          context: context,
          builder: (context) => const LoginDialog(),
        );
      } else if (decision == SecondVideoPromptAction.register) {
        await showDialog(
          context: context,
          builder: (context) => const RegisterDialog(),
        );
      }
    }

    final projectProvider = Provider.of<ProjectProvider>(
      context,
      listen: false,
    );

    setState(() {
      _state = TranscriptionState.transcribing;
      _progress = 0.0;
      _errorMessage = null;
      _translationReady = false;
    });

    // Update project: start transcription step
    await projectProvider.updateStepProgress(
      step: ProjectStep.transcription,
      status: ProjectStatus.inProgress,
      progress: 0.0,
    );

    // Re-initialize whisper if model has changed
    await _transcriptionService.initialize(modelName: _options.model);

    try {
      final videoFile = File(_selectedFile!.path!);

      // Run local transcription
      final result = await _transcriptionService.transcribe(
        videoFile: videoFile,
        options: _options,
        onProgress: (progress) async {
          setState(() {
            _progress = progress;
          });
          // Update progress in project
          await projectProvider.updateStepProgress(
            step: ProjectStep.transcription,
            status: ProjectStatus.inProgress,
            progress: progress,
          );
        },
      );

      setState(() {
        _result = result;
        _state = TranscriptionState.completed;
        _progress = 1.0;
      });

      // Persist transcription result to disk so it can be restored without re-transcribing
      final currentProjectId = projectProvider.currentProject?.id;
      if (currentProjectId != null) {
        await _saveTranscriptionResult(result, currentProjectId);
      }

      // Save transcription result to project
      if (projectProvider.currentProject != null) {
        final updatedProject = projectProvider.currentProject!.copyWith(
          transcriptionResult: result,
          currentStep: ProjectStep.translation, // Move to translation step
        );
        await projectProvider.updateCurrentProject(updatedProject);

        // Mark transcription step as completed
        await projectProvider.updateStepProgress(
          step: ProjectStep.transcription,
          status: ProjectStatus.completed,
          progress: 1.0,
        );

        // Mark translation step as ready to start
        await projectProvider.updateStepProgress(
          step: ProjectStep.translation,
          status: ProjectStatus.notStarted,
          progress: 0.0,
        );
      }

      await _incrementCompletedTranslations();
    } catch (e) {
      setState(() {
        _state = TranscriptionState.error;
        _errorMessage = e.toString();
      });

      // Mark transcription step as failed
      await projectProvider.updateStepProgress(
        step: ProjectStep.transcription,
        status: ProjectStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _downloadJson() async {
    if (_result == null) return;

    try {
      // Save JSON to file - используем application documents directory
      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          'transcription_${DateTime.now().millisecondsSinceEpoch}.json';
      final savePath = '${directory.path}/$fileName';

      final file = File(savePath);
      const encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(_result!.toJson()));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Saved to: $savePath',
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  void _reset() {
    final projectProvider = Provider.of<ProjectProvider>(
      context,
      listen: false,
    );
    projectProvider.clearCurrentProject();
    _deleteLocalVideo();
    _clearSavedTranscriptionResult();

    setState(() {
      _state = TranscriptionState.idle;
      _selectedFile = null;
      _localVideoPath = null;
      _result = null;
      _errorMessage = null;
      _progress = 0.0;
      _translationReady = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: AppTheme.cardColor,
            elevation: 0,
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryBlue.withOpacity(0.05),
                    AppTheme.primaryPurple.withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border(
                  bottom: BorderSide(
                    color: AppTheme.primaryBlue.withOpacity(0.1),
                    width: 1,
                  ),
                ),
              ),
            ),
            leading: isDesktop
                ? null
                : Builder(
                    builder: (context) => IconButton(
                      icon: Icon(Icons.menu, color: AppTheme.primaryBlue),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
            title: Row(
              children: [
                if (isDesktop) ...[
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.borderColor),
                    ),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 24,
                      height: 24,
                      errorBuilder: (context, error, stack) => const Icon(
                        Icons.play_arrow_rounded,
                        size: 24,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              
              ],
            ),
            actions: [
              Consumer<AuthProvider>(
                builder: (context, authProvider, child) {
                  if (authProvider.isLoggedIn) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Минуттар көрсету (тек desktop-та)
                        if (isDesktop && authProvider.totalRemainingMinutes >= 0) ...[
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: authProvider.remainingPercentage >= 20
                                  ? AppTheme.successColor.withOpacity(0.1)
                                  : AppTheme.errorColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: authProvider.remainingPercentage >= 20
                                    ? AppTheme.successColor
                                    : AppTheme.errorColor,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  authProvider.hasUnlimitedAccess == true
                                      ? Icons.all_inclusive
                                      : Icons.timer,
                                  size: 16,
                                  color: authProvider.remainingPercentage >= 20
                                      ? AppTheme.successColor
                                      : AppTheme.errorColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  authProvider.hasUnlimitedAccess == true
                                      ? '∞'
                                      : '${authProvider.totalRemainingMinutes.toStringAsFixed(0)} мин',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: authProvider.remainingPercentage >= 20
                                        ? AppTheme.successColor
                                        : AppTheme.errorColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        Tooltip(
                          message: l10n.translate('profile'),
                          child: IconButton(
                            icon: const Icon(Icons.account_circle),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => const ProfileDialog(),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  } else {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Trial badge for non-logged-in users
                        // Trial badge жасырылды (қолданушы сұрауы бойынша)
                        // const Padding(
                        //   padding: EdgeInsets.only(right: 12),
                        //   child: TrialBadgeWidget(),
                        // ),
                        Tooltip(
                          message: l10n.translate('login'),
                          child: IconButton(
                            icon: const Icon(Icons.login),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => const LoginDialog(),
                              );
                            },
                          ),
                        ),
                        Tooltip(
                          message: l10n.translate('register'),
                          child: IconButton(
                            icon: const Icon(Icons.person_add),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => const RegisterDialog(),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  }
                },
              ),
              Tooltip(
                message: l10n.chooseLanguage,
                child: PopupMenuButton<Locale>(
                  icon: const Icon(Icons.language),
                  onSelected: (locale) {
                    Provider.of<LocaleProvider>(
                      context,
                      listen: false,
                    ).setLocale(locale);
                  },
                  itemBuilder: (context) => AppLocalizations.allAvailableLocales.map((locale) {
                    // Get language name from locale comment
                    final languageNames = {
                      'kk': 'Қазақша',
                      'tr': 'Türkçe',
                      'uz': 'O\'zbek',
                      'ky': 'Кыргызча',
                      'az': 'Azərbaycan',
                      'en': 'English',
                      'ru': 'Русский',
                      'zh': '中文',
                      'es': 'Español',
                      'fr': 'Français',
                      'de': 'Deutsch',
                      'ja': '日本語',
                      'ar': 'العربية',
                      'pt': 'Português',
                      'hi': 'हिन्दी',
                    };

                    return PopupMenuItem(
                      value: locale,
                      child: Text(languageNames[locale.languageCode] ?? locale.languageCode.toUpperCase()),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          drawer: isDesktop
              ? null
              : Drawer(
                  backgroundColor: AppTheme.cardColor,
                  child: Column(
                    children: [
                      DrawerHeader(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                'assets/images/logo.png',
                                width: 200,
                               // height: 72,
                              ),
                              const SizedBox(height: 4),
                              FutureBuilder<PackageInfo>(
                                future: PackageInfo.fromPlatform(),
                                builder: (context, snapshot) {
                                  if (snapshot.hasData) {
                                    return Text(
                                      'v${snapshot.data!.version}',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: AppTheme.textSecondary,
                                          ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            ],
                          ),
                        ),
                       ),
                       Expanded(
                         child: Consumer<ProjectProvider>(
                           builder: (context, projectProvider, child) {
                             return ProjectStepsTimeline(
                               project: projectProvider.currentProject,
                               onStepTap: (step) {
                                 Navigator.pop(context); // Close drawer
                                 _onStepTap(step, projectProvider);
                               },
                               isCollapsed: false,
                             );
                           },
                         ),
                       ),
                       // Subscription menu item
                       Divider(color: AppTheme.borderColor),
                       ListTile(
                         leading: Icon(
                           Icons.card_membership,
                           color: AppTheme.primaryBlue,
                         ),
                         title: Text(
                           'Subscription',
                           style: TextStyle(color: AppTheme.textPrimary),
                         ),
                         onTap: () {
                           Navigator.pop(context); // Close drawer
                           Navigator.push(
                             context,
                             MaterialPageRoute(
                               builder: (context) => const SubscriptionScreen(),
                             ),
                           );
                         },
                       ),
                     ],
                  ),
                ),
          body: Row(
            children: [
              // Sidebar with timeline (Desktop only)
              if (isDesktop)
                Consumer<ProjectProvider>(
                  builder: (context, projectProvider, child) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: _isSidebarCollapsed ? 76 : 280,
                      decoration: BoxDecoration(
                        color: AppTheme.cardColor,
                        border: Border(
                          right: BorderSide(color: AppTheme.borderColor, width: 1),
                        ),
                      ),
                      child: Column(
                        children: [
                          Align(
                            alignment:
                                _isSidebarCollapsed ? Alignment.center : Alignment.centerRight,
                            child: IconButton(
                              icon: Icon(
                                _isSidebarCollapsed ? Icons.chevron_right : Icons.chevron_left,
                              ),
                              tooltip: _isSidebarCollapsed ? 'Кеңейту' : 'Жинау',
                              onPressed: () {
                                setState(() {
                                  _isSidebarCollapsed = !_isSidebarCollapsed;
                                });
                              },
                            ),
                          ),
                          Expanded(
                            child: ProjectStepsTimeline(
                              project: projectProvider.currentProject,
                              onStepTap: (step) => _onStepTap(step, projectProvider),
                              isCollapsed: _isSidebarCollapsed,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              // Main content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: _buildAnimatedContent(l10n),
                    ),
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) {
              return ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: _buildFloatingActionButton(l10n) ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }

  Widget _buildContent(AppLocalizations l10n) {
    switch (_state) {
      case TranscriptionState.idle:
        return Column(
          children: [
            // Trial info card for non-logged-in users
            Consumer<AuthProvider>(
              builder: (context, authProvider, child) {
                if (!authProvider.isLoggedIn) {
                  return const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: TrialInfoCard(),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            VideoDropzone(onFileSelected: _onFileSelected),
          ],
        );

      case TranscriptionState.fileSelected:
        return Column(
          children: [
            AppTheme.card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _selectedFile!.name,
                          style: Theme.of(context).textTheme.headlineMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Tooltip(
                        message: l10n.translate('remove'),
                        child: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: _reset,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_selectedFile!.path != null)
                    VideoPreview(videoPath: _selectedFile!.path!),
                ],
              ),
            ),
            if (_showTranscriptionSettings) ...[
              const SizedBox(height: 24),
              AppTheme.card(
                child: TranscriptionSettingsPanel(
                  options: _options,
                  onOptionsChanged: _onOptionsChanged,
                ),
              ),
            ],
          ],
        );

      case TranscriptionState.uploading:
      case TranscriptionState.transcribing:
        return _buildProgressView(l10n);

      case TranscriptionState.completed:
        return _buildCompletedView(l10n);

      case TranscriptionState.error:
        return _buildErrorView(l10n);
    }
  }

  Widget _buildAnimatedContent(AppLocalizations l10n) {
    final project = Provider.of<ProjectProvider>(context);
    final contentKey = ValueKey(
      '${_state.name}_${project.currentProject?.currentStep.name ?? 'none'}',
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(0.05, 0),
          end: Offset.zero,
        ).animate(animation);

        return SlideTransition(
          position: offsetAnimation,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: KeyedSubtree(key: contentKey, child: _buildContent(l10n)),
    );
  }

  Widget _buildProgressView(AppLocalizations l10n) {
    final isUploading = _state == TranscriptionState.uploading;
    final statusText =
        isUploading
            ? l10n.translate('uploading')
            : l10n.translate('transcribing');

    return AppTheme.card(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (isUploading)
            const Icon(
              Icons.cloud_upload,
              size: 64,
              color: AppTheme.accentColor,
            )
          else
            const SizedBox(
              width: 60,
              height: 60,
              child: CircularProgressIndicator(),
            ),
          const SizedBox(height: 24),
          Text(statusText, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 24),
          LinearProgressIndicator(value: _progress > 0 ? _progress : null),
          if (_progress > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${(_progress * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorView(AppLocalizations l10n) {
    return AppTheme.card(
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 64, color: AppTheme.errorColor),
          const SizedBox(height: 24),
          Text(
            l10n.error,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(color: AppTheme.errorColor),
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? 'Unknown error',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.translate('try_again')),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedView(AppLocalizations l10n) {
    final projectProvider = Provider.of<ProjectProvider>(
      context,
      listen: true, // МАҢЫЗДЫ: Project өзгергенде UI жаңартылсын
    );
    final project = projectProvider.currentProject;
    final currentStep = project?.currentStep;
    final hasTranscription = _result != null;

    final children = <Widget>[];

    // Transcription result JSON viewer (always show when result exists and not on TTS/completed)
    if (hasTranscription &&
        (currentStep == null ||
            currentStep == ProjectStep.transcription ||
            currentStep == ProjectStep.translation)) {
      children.add(
        AppTheme.card(
          child: JsonViewer(
            result: _result!,
            onDownload: _downloadJson,
            onTranslate: _runInlineTranslation,
            isAutomaticMode: _useAutomaticMode,
            onAutomaticModeChanged: (value) {
              setState(() => _useAutomaticMode = value);
            },
            automaticLogs: _automaticLogs,
          ),
        ),
      );
      children.add(const SizedBox(height: 24));

      // Next-step prompt handled via floating action button; no extra wide button here.
    }

    // Final video download card (show after automatic translation completes)
    if (_finalVideoPath != null && File(_finalVideoPath!).existsSync()) {
      children.add(
        AppTheme.card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.accentColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.video_file,
                        color: AppTheme.accentColor,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Аяқталған Видео',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Автоматты аударма аяқталды',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Play Preview Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _playFinalVideo(_finalVideoPath!),
                    icon: const Icon(Icons.play_circle_outline, size: 28),
                    label: const Text('Видеоны Қарау'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _saveFinalVideo(_finalVideoPath!),
                        icon: const Icon(Icons.download),
                        label: const Text('Видеоны Сақтау'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () => _openVideoInFinder(_finalVideoPath!),
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Finder-де Ашу'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      children.add(const SizedBox(height: 24));
    }

    // Translation UI hidden in this flow (handled inline above the editor)

    // TTS stage (show only on TTS step)
    if (currentStep == ProjectStep.tts && _result != null) {
      children.add(_buildTtsSection(project!, _result!, l10n));
      children.add(const SizedBox(height: 24));
    }

    // Merge stage (show on merge or completed step)
    if ((currentStep == ProjectStep.merge || currentStep == ProjectStep.completed) &&
        _result != null &&
        project != null) {
      // МАҢЫЗДЫ: Біріктіру панелін merge немесе completed қадамында көрсету
      // merge қадамы басылғанда біріктіру панелі ашылады
      if (currentStep == ProjectStep.merge || currentStep == ProjectStep.completed) {
        final videoPath = _localVideoPath ?? project.videoPath;
        final audioPath = project.audioPath;

        children.add(
          AppTheme.card(
            child: MergePanel(
              transcriptionResult: _result!,
              videoPath: videoPath,
              audioPath: audioPath,
              initialFinalVideoPath: project.finalVideoPath,
              onComplete: (String? finalVideoPath) async {
                final projectProvider = Provider.of<ProjectProvider>(
                  context,
                  listen: false,
                );

                // Persist final video path before step changes
                final current = projectProvider.currentProject;
                if (current != null && finalVideoPath != null) {
                  final withFinalPath = current.copyWith(
                    finalVideoPath: finalVideoPath,
                  );
                  await projectProvider.updateCurrentProject(withFinalPath);
                }

                // Update project step to completed when merge is done
                await projectProvider.updateStepProgress(
                  step: ProjectStep.merge,
                  status: ProjectStatus.completed,
                  progress: 1.0,
                );

                final latestProject = projectProvider.currentProject;
                if (latestProject != null) {
                  final updatedProject = latestProject.copyWith(
                    currentStep: ProjectStep.completed,
                  );
                  await projectProvider.updateCurrentProject(updatedProject);
                }

                await projectProvider.updateStepProgress(
                  step: ProjectStep.completed,
                  status: ProjectStatus.completed,
                  progress: 1.0,
                );

                // Complete trial workflow for non-logged-in users
                if (mounted && _selectedFile != null) {
                  final videoFile = File(_selectedFile!.path!);
                  final videoInfo = await videoFile.stat();
                  
                  await _completeTrialWorkflow(
                    videoFileName: _selectedFile!.name,
                    durationSeconds: (videoInfo.size / 1024 / 30).round(), // Approximate duration
                  );
                }

                if (mounted) {
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(l10n.translate('merge_completed')),
                        ],
                      ),
                      backgroundColor: AppTheme.successColor,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              },
            ),
          ),
        );
        children.add(const SizedBox(height: 24));
      }
    }

    // Restart button
    children.add(
      ElevatedButton.icon(
        onPressed: _reset,
        icon: const Icon(Icons.refresh),
        label: Text(l10n.translate('start_over')),
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.grey.shade500,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        ),
      ),
    );

    return Column(children: children);
  }

  Future<void> _prepareForRetranslation(String targetLanguage) async {
    final projectProvider = Provider.of<ProjectProvider>(context, listen: false);
    final project = projectProvider.currentProject;
    if (project == null) return;

    final hasTranslation = project.translatedSegments?.isNotEmpty == true ||
        (_result?.segments.any((s) => s.translatedText != null) ?? false);
    if (!hasTranslation) return;

    final resultHasTranslation =
        _result?.segments.any((s) => s.translatedText != null) ?? false;
    final previousTargetLanguage = resultHasTranslation && _result!.segments.isNotEmpty
        ? (_result!.segments.first.targetLanguage ?? _result!.segments.first.language)
        : (project.targetLanguage?.isNotEmpty == true ? project.targetLanguage : null);

    if (previousTargetLanguage != null && previousTargetLanguage == targetLanguage) {
      return;
    }

    // Use centralized cleanup method (keep transcription, clean language-specific artifacts)
    await _cleanupProjectArtifacts(
      project.id,
      includeTranscription: false,  // Keep transcription when changing language
      includeTranslation: true,     // Delete translation
      includeTts: true,              // Delete TTS audio
      includeMerge: true,            // Delete merged video
    );

    final originalResult =
        await _loadSavedTranscriptionResult(project.id) ?? project.transcriptionResult;
    if (mounted && originalResult != null) {
      setState(() {
        _result = originalResult;
        _translationReady = false;
      });
    }

    final updatedSteps = Map<ProjectStep, StepProgress>.from(project.steps);
    updatedSteps[ProjectStep.translation] = StepProgress(
      step: ProjectStep.translation,
      status: ProjectStatus.inProgress,
      progress: 0.0,
      startedAt: updatedSteps[ProjectStep.translation]?.startedAt ?? DateTime.now(),
    );
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

    final updatedProject = project.copyWith(
      translatedSegments: null,
      targetLanguage: null,
      audioPath: null,
      finalVideoPath: null,  // Clear merged video path
      currentStep: ProjectStep.translation,
      steps: updatedSteps,
    );
    await projectProvider.updateCurrentProject(updatedProject);
  }

  Future<void> _runInlineTranslation(String targetLanguage) async {
    if (_result == null || _isTranslating) return;

    // If automatic mode is enabled, use orchestrator pipeline
    if (_useAutomaticMode && _orchestrator != null && _selectedFile != null) {
      setState(() {
        _isTranslating = true;
        _automaticLogs.clear();
        _automaticLogs.add('[INFO] Automatic mode activated');
      });

      try {
        final videoFile = File(_selectedFile!.path!);
        
        // Get TTS settings from SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final voice = prefs.getString('tts_voice') ?? 'alloy';
        final speed = prefs.getDouble('video_speed') ?? 1.2;
        
        _automaticLogs.add('[INFO] Voice: $voice');
        _automaticLogs.add('[INFO] Video speed: ${speed}x');
        _automaticLogs.add('[INFO] Starting parallel pipeline...');
        
        final result = await _orchestrator!.processAutomatic(
          videoFile: videoFile,
          targetLanguage: targetLanguage,
          voice: voice,
          existingTranscriptionResult: _result, // Pass existing transcription
          onProgress: (progress) {
            if (mounted) {
              setState(() {
                _automaticLogs.add('[${progress.stage.name}] ${progress.currentActivity}');
              });
            }
          },
        );
        
        if (mounted) {
          setState(() {
            _automaticLogs.add('✓ Automatic translation pipeline complete!');
            _automaticLogs.add('Final video: ${result.finalVideoPath ?? "N/A"}');
            _finalVideoPath = result.finalVideoPath;
            _isTranslating = false;
            _useAutomaticMode = false; // Hide monitor after completion
          });

          // Calculate total TTS audio duration for logging
          final authProvider = Provider.of<AuthProvider>(context, listen: false);
          final projectProvider = Provider.of<ProjectProvider>(context, listen: false);
          
          if (authProvider.isLoggedIn) {
            // Calculate total TTS duration from all segments
            double totalTtsDuration = 0.0;
            for (final segment in result.segments) {
              if (segment.audioPath != null) {
                try {
                  final audioFile = File(segment.audioPath!);
                  if (await audioFile.exists()) {
                    // Get audio duration using VideoSplitterService helper
                    final duration = await _videoSplitter.getAudioDuration(segment.audioPath!);
                    totalTtsDuration += duration;
                  }
                } catch (e) {
                  print('Warning: Could not get duration for ${segment.audioPath}: $e');
                }
              }
            }

            final ttsDurationMinutes = totalTtsDuration / 60.0;
            
            if (mounted) {
              setState(() {
                _automaticLogs.add('[INFO] Total TTS duration: ${ttsDurationMinutes.toStringAsFixed(2)} minutes');
              });
            }

            // Update project with completion status
            if (projectProvider.currentProject != null) {
              await projectProvider.updateCurrentProject(
                projectProvider.currentProject!.copyWith(
                  currentStep: ProjectStep.completed,
                ),
              );
            }
            
            await _incrementCompletedTranslations();
          }
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
      return; // Exit early, don't run manual translation
    }

    // Manual translation mode (existing logic)
    final authProvider = Provider.of<AuthProvider>(
      context,
      listen: false,
    );

    // МАҢЫЗДЫ: Trial/guest қолданушылар үшін минуттарды тексермейміз
    // Олар trial attempts қолданады
    if (authProvider.isLoggedIn) {
      // Минуттар тексеру (тек logged in users үшін)
      final videoDurationMinutes = _result!.duration / 60.0;

      // Минуттар ақпаратын жаңарту
      await authProvider.refreshUserMinutes();

      // Жеткілікті минуттар бар ма тексеру
      if (!authProvider.hasEnoughMinutes(videoDurationMinutes)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).translate('insufficient_minutes')),
              backgroundColor: AppTheme.warningColor,
              duration: const Duration(seconds: 3),
            ),
          );

          Navigator.push(
            context,
            MaterialPageRoute(
               builder: (context) => const SubscriptionScreen(),
            ),
          );
        }
        return;
      }
    }
    // Guest users: Жай ғана trial attempts-ты қолданады, минутты тексермейді

    await _prepareForRetranslation(targetLanguage);

    if (!mounted) return;

    setState(() {
      _isTranslating = true;
      _translationReady = false; // Hide next step until API responds
    });

    try {
      // Load original transcription.json to ensure we're translating the original text
      if (!mounted) return;
      final projectProvider = Provider.of<ProjectProvider>(context, listen: false);
      final currentProjectId = projectProvider.currentProject?.id;
      TranscriptionResult? originalResult = _result;

      if (currentProjectId != null) {
        // Try to load original transcription from transcription.json
        final loadedOriginal = await _loadSavedTranscriptionResult(currentProjectId);
        if (loadedOriginal != null) {
          originalResult = loadedOriginal;
        }
      }

      final translationService = BackendTranslationService(authProvider.apiClient);
      final requestSegments = originalResult!.segments.asMap().entries.map((entry) {
        // originalResult now comes from transcription.json, so text is the original
        return TranslationSegment(
          id: 'segment_${entry.key}',
          text: entry.value.text,
        );
      }).toList();

      final duration = _result!.duration.toInt();

      final translationResult = await translationService.translateSegments(
        segments: requestSegments,
        targetLanguage: targetLanguage,
        sourceLanguage: _result!.detectedLanguage,
        durationSeconds: duration,
        videoFileName: _result!.filename,
      );

      final segmentCount = _result!.segments.length;
      final normalized = translationService.normalizeTranslatedSegments(
        result: translationResult,
        expectedCount: segmentCount,
        fallbackOriginalTexts: originalResult.segments.map((s) => s.text).toList(),
      );
      final effectiveSegments = normalized.segments;
      String? validationError;

      if (!translationResult.success) {
        validationError = translationResult.errorMessage ?? translationResult.message ?? 'Translation failed';
      } else if (!normalized.recoveredFromFlattened &&
          (translationResult.hasLineCountMismatch ||
              (translationResult.inputLineCount != null &&
                  translationResult.inputLineCount != segmentCount) ||
              (translationResult.outputLineCount != null &&
                  translationResult.outputLineCount != segmentCount) ||
              effectiveSegments.length != segmentCount)) {
        validationError = translationResult.validationWarning ??
            'Segment count mismatch: expected $segmentCount, got ${translationResult.outputLineCount ?? effectiveSegments.length}';
      } else if (normalized.recoveredFromFlattened && effectiveSegments.length != segmentCount) {
        validationError = 'Segment count mismatch: expected $segmentCount, got ${effectiveSegments.length}';
      }

      if (validationError != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(validationError),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
        return;
      }

      final translatedMap = <int, String>{};
      bool mappingError = false;

      for (var i = 0; i < effectiveSegments.length; i++) {
        final translated = effectiveSegments[i];
        final parsedIndex = _extractSegmentIndex(translated.id) ?? i;

        if (parsedIndex < 0 || parsedIndex >= segmentCount) {
          mappingError = true;
          break;
        }

        final text = translated.translatedText.trim();
        translatedMap[parsedIndex] =
            text.isNotEmpty ? text : _result!.segments[parsedIndex].text;
      }

      if (mappingError || translatedMap.length != segmentCount) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Segment mapping error: expected $segmentCount, got ${translatedMap.length}',
              ),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
        return;
      }

      await _onTranslationComplete(
        translatedMap,
        translationResult.sourceLanguage ?? _result!.detectedLanguage,
        targetLanguage,
        originalResult,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Translation failed: $e'),
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

  Future<void> _onTranslationComplete(
    Map<int, String> translatedSegments,
    String sourceLanguage,
    String targetLanguage,
    TranscriptionResult originalResult,
  ) async {
    final projectProvider = Provider.of<ProjectProvider>(
      context,
      listen: false,
    );

    // Обновляем локальный нәтижені аудармамен
    // Use originalResult segments to preserve the original text
    if (_result != null) {
      final updatedSegments = originalResult.segments.asMap().entries.map((entry) {
        final translated = translatedSegments[entry.key] ?? entry.value.text;
        return entry.value.copyWith(
          text: translated,
          translatedText: entry.value.text,
          // language = аударылған мәтіннің тілі, targetLanguage = таңдалған мақсатты тіл
          language: targetLanguage,
          targetLanguage: targetLanguage,
        );
      }).toList();

      final translatedResult = TranscriptionResult(
        filename: _result!.filename,
        duration: _result!.duration,
        detectedLanguage: _result!.detectedLanguage,
        model: _result!.model,
        createdAt: _result!.createdAt,
        segments: updatedSegments,
      );

      setState(() {
        _result = translatedResult;
        _translationReady = true;
      });

      // Save translated result to translated.json
      final currentProjectId = projectProvider.currentProject?.id;
      if (currentProjectId != null) {
        await _saveTranslatedResult(translatedResult, currentProjectId);
      }
    }

    // Жобаға сақтаймыз
    if (projectProvider.currentProject != null) {
      final project = projectProvider.currentProject!;
      final updatedSteps = Map<ProjectStep, StepProgress>.from(project.steps);

      // Reset TTS/merge so new translation always regenerates audio/video
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
        translatedSegments: translatedSegments,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        audioPath: null,
        finalVideoPath: null,
        currentStep: ProjectStep.translation,
        steps: updatedSteps,
      );

      await projectProvider.updateCurrentProject(updatedProject);

      // МАҢЫЗДЫ: Аударма аяқталды, бірақ "Келесі қадам" батырмасы басылмаған
      // Сондықтан статусты "inProgress" деп белгілейміз, "completed" емес!
      // "Келесі қадам" батырмасы басылғанда ғана "completed" болады
      await projectProvider.updateStepProgress(
        step: ProjectStep.translation,
        status: ProjectStatus.inProgress,
        progress: 1.0,
      );

      if (updatedProject.nextStep != null) {
        await projectProvider.updateStepProgress(
          step: updatedProject.nextStep!,
          status: ProjectStatus.notStarted,
        );
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context).translate('translation_completed'),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  int? _extractSegmentIndex(String id) {
    final match = RegExp('(\\d+)\$').firstMatch(id);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  bool _shouldMarkTranslationReady(TranslationProject? project) {
    if (project == null) return false;

    final translatedMap = project.translatedSegments;
    final expectedCount =
        project.transcriptionResult?.segments.length ?? _result?.segments.length;

    final hasMap = translatedMap != null &&
        translatedMap.isNotEmpty &&
        (expectedCount == null || translatedMap.length == expectedCount);

    final hasTranslatedSegments = (project.transcriptionResult?.segments
                .every((s) => s.translatedText != null) ??
            false) ||
        (_result?.segments.every((s) => s.translatedText != null) ?? false);

    return project.isTranslationCompleted || hasMap || hasTranslatedSegments;
  }

  /// Check if all segments have a translated version even when step status
  /// wasn't explicitly marked (e.g., after restore or manual edits).
  bool _hasCompleteTranslation(TranslationProject? project) {
    final translatedMap = project?.translatedSegments;
    final result = _result;
    final expectedCount =
        result?.segments.length ?? project?.transcriptionResult?.segments.length;

    final hasProjectMap = translatedMap != null &&
        translatedMap.isNotEmpty &&
        (expectedCount == null || translatedMap.length == expectedCount);

    final hasResultTranslation = result != null &&
        result.segments.isNotEmpty &&
        result.segments.every((s) => s.translatedText != null);

    return hasProjectMap || hasResultTranslation;
  }

  Future<void> _onStepTap(ProjectStep step, ProjectProvider projectProvider) async {
    final project = projectProvider.currentProject;
    if (project == null) return;

    // Қазіргі қадаммен бірдей болса, ештеңе істемейміз
    if (project.currentStep == step) return;

    // Қадамды өзгертеміз
    final updatedProject = project.copyWith(currentStep: step);
    await projectProvider.updateCurrentProject(updatedProject);

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _moveToNextStep() async {
    final projectProvider = Provider.of<ProjectProvider>(
      context,
      listen: false,
    );
    var project = projectProvider.currentProject;

    if (project == null) return;

    // If translation is present but the step progress was not persisted,
    // normalize it so the next step becomes available.
    if (project.currentStep == ProjectStep.translation &&
        _hasCompleteTranslation(project) &&
        !project.isTranslationCompleted) {
      await projectProvider.updateStepProgress(
        step: ProjectStep.translation,
        status: ProjectStatus.inProgress,
        progress: 1.0,
      );
      project = projectProvider.currentProject;
    }

    final currentStep = project!.currentStep;
    var nextStep = project.nextStep;

    // Fallback: if translation is ready but nextStep is still null, advance to TTS
    if (nextStep == null &&
        currentStep == ProjectStep.translation &&
        _hasCompleteTranslation(project)) {
      nextStep = ProjectStep.tts;
    }

    if (nextStep != null) {
      // МАҢЫЗДЫ: Translation қадамы үшін status-ты "inProgress" күйінде қалдыру
      // Басқа қадамдар үшін "completed" деп белгілеу
      if (currentStep != ProjectStep.translation) {
        await projectProvider.updateStepProgress(
          step: currentStep,
          status: ProjectStatus.completed,
          progress: 1.0,
        );
      }

      // Update current step to next step
      final updatedProject = project.copyWith(currentStep: nextStep);
      await projectProvider.updateCurrentProject(updatedProject);

      // Update next step status to in progress
      await projectProvider.updateStepProgress(
        step: nextStep,
        status: ProjectStatus.inProgress,
        progress: 0.0,
      );

      setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppLocalizations.of(context).translate('next_step')}: ${_getStepName(nextStep)}',
            ),
          ),
        );
      }
    }
  }

  String _getStepName(ProjectStep step) {
    final l10n = AppLocalizations.of(context);
    switch (step) {
      case ProjectStep.transcription:
        return l10n.translate('step_transcription');
      case ProjectStep.translation:
        return l10n.translate('step_translation');
      case ProjectStep.tts:
        return l10n.translate('step_tts');
      case ProjectStep.merge:
        return l10n.translate('step_merge');
      case ProjectStep.completed:
        return l10n.translate('step_completed');
    }
  }

  String _resultFilePath(String projectId) {
    // Deterministic path for storing the transcription JSON
    return '${_appDocumentsPath ?? ''}/transcription_results/${projectId}_transcription.json';
  }

  String _translatedResultFilePath(String projectId) {
    // Deterministic path for storing the translated JSON
    return '${_appDocumentsPath ?? ''}/transcription_results/${projectId}_translated.json';
  }

  String? _appDocumentsPath;

  Future<void> _ensureAppPath() async {
    if (_appDocumentsPath != null) return;
    final dir = await getApplicationDocumentsDirectory();
    _appDocumentsPath = dir.path;
  }

  Future<void> _saveTranscriptionResult(
    TranscriptionResult result,
    String projectId,
  ) async {
    try {
      await _ensureAppPath();
      final dirPath = '${_appDocumentsPath!}/transcription_results';
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final path = _resultFilePath(projectId);
      final file = File(path);
      const encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(result.toJson()));
    } catch (_) {
      // Best-effort persistence; ignore errors
    }
  }

  Future<void> _saveTranslatedResult(
    TranscriptionResult result,
    String projectId,
  ) async {
    try {
      await _ensureAppPath();
      final dirPath = '${_appDocumentsPath!}/transcription_results';
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final path = _translatedResultFilePath(projectId);
      final file = File(path);
      const encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(result.toJson()));
    } catch (_) {
      // Best-effort persistence; ignore errors
    }
  }

  Future<TranscriptionResult?> _loadSavedTranscriptionResult(
    String projectId,
  ) async {
    try {
      await _ensureAppPath();
      final path = _resultFilePath(projectId);
      final file = File(path);
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final jsonMap = jsonDecode(content) as Map<String, dynamic>;
      return TranscriptionResult.fromJson(jsonMap);
    } catch (_) {
      return null;
    }
  }

  Future<TranscriptionResult?> _loadTranslatedResult(
    String projectId,
  ) async {
    try {
      await _ensureAppPath();
      final path = _translatedResultFilePath(projectId);
      final file = File(path);
      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final jsonMap = jsonDecode(content) as Map<String, dynamic>;
      return TranscriptionResult.fromJson(jsonMap);
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteTranslatedResultFile(String projectId) async {
    try {
      await _ensureAppPath();
      final path = _translatedResultFilePath(projectId);
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cleanup
    }
  }

  Future<void> _deleteTtsFolder(String? folderPath) async {
    if (folderPath == null || folderPath.isEmpty) return;
    try {
      final dir = Directory(folderPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort cleanup
    }
  }

  /// Centralized method to cleanup project artifacts
  /// Used when starting a new video or changing target language
  Future<void> _cleanupProjectArtifacts(
    String projectId, {
    bool includeTranscription = false,
    bool includeTranslation = true,
    bool includeTts = true,
    bool includeMerge = true,
  }) async {
    try {
      // Delete transcription files (original, untranslated)
      if (includeTranscription) {
        await _ensureAppPath();
        final path = _resultFilePath(projectId);
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }

      // Delete translation files (translated result)
      if (includeTranslation) {
        await _deleteTranslatedResultFile(projectId);
      }

      // Delete TTS audio folder
      if (includeTts) {
        final projectProvider = Provider.of<ProjectProvider>(
          context,
          listen: false,
        );
        final project = projectProvider.currentProject;
        if (project?.audioPath != null) {
          await _deleteTtsFolder(project!.audioPath);
        }
      }

      // Delete merged video file
      if (includeMerge) {
        final projectProvider = Provider.of<ProjectProvider>(
          context,
          listen: false,
        );
        final project = projectProvider.currentProject;
        if (project?.finalVideoPath != null && project!.finalVideoPath!.isNotEmpty) {
          try {
            final videoFile = File(project.finalVideoPath!);
            if (await videoFile.exists()) {
              await videoFile.delete();
            }
          } catch (_) {
            // Best-effort cleanup
          }
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up project artifacts: $e');
    }
  }


  Future<PlatformFile?> _copyVideoToAppStorage(PlatformFile file) async {
    try {
      if (file.path == null) return null;

      final appDir = await getApplicationDocumentsDirectory();
      final videosDir = Directory('${appDir.path}/videos');
      if (!await videosDir.exists()) {
        await videosDir.create(recursive: true);
      }

      final safeName = _buildSafeFileName(file.name);
      final targetPath = '${videosDir.path}/$safeName';
      final copiedFile = await File(file.path!).copy(targetPath);

      final copiedSize = await copiedFile.length();
      return PlatformFile(
        name: safeName,
        size: copiedSize,
        path: copiedFile.path,
      );
    } catch (_) {
      return null;
    }
  }

  /// Generate a filesystem-friendly name (keeps extension, strips symbols/Unicode)
  String _buildSafeFileName(String originalName) {
    final ext = p.extension(originalName);
    final base = p.basenameWithoutExtension(originalName);
    final sanitized = base
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceFirst(RegExp(r'^_+'), '')
        .replaceFirst(RegExp(r'_+$'), '');
    final fallback = sanitized.isEmpty ? 'video' : sanitized;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    // Limit length to avoid overly long file names
    final truncated = fallback.length > 80 ? fallback.substring(0, 80) : fallback;
    return '${timestamp}_$truncated$ext';
  }

  void _showVideoPrepMessage(VideoProcessingResult result) {
    if (!mounted) return;

    final l10n = AppLocalizations.of(context);
    final lengthMessage = result.wasTrimmed
        ? l10n.translate('video_too_long')
        : l10n.translate('video_short_enough');

    final watermarkMessage = result.watermarkApplied
        ? l10n.translate('video_watermark_added')
        : l10n.translate('video_watermark_failed');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$lengthMessage $watermarkMessage'),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _deleteLocalVideo() async {
    try {
      if (_localVideoPath == null) return;
      final file = File(_localVideoPath!);
      if (await file.exists()) {
        await file.delete();
      }
      _localVideoPath = null;
    } catch (_) {
      // Best-effort cleanup
    }
  }

  Future<void> _clearSavedTranscriptionResult() async {
    try {
      await _ensureAppPath();
      final dirPath = '${_appDocumentsPath!}/transcription_results';
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // Ignore cleanup errors
    }
  }

  Future<void> _incrementCompletedTranslations() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt('completed_translation_count') ?? 0;
    await prefs.setInt('completed_translation_count', current + 1);
  }

  Future<bool> _shouldPromptForSecondVideo() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getInt('completed_translation_count') ?? 0;
    final promptShown = prefs.getBool('second_video_prompt_shown') ?? false;
    return completed >= 1 && !promptShown;
  }

  Future<void> _markSecondVideoPromptShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('second_video_prompt_shown', true);
  }

  Future<bool?> _showGuestUserAlert(AppLocalizations l10n) async {
    final result = await showDialog<bool?>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.cardColor,
          title: Text(
            l10n.translate('guest_user_alert_title'),
            style: const TextStyle(color: AppTheme.accentColor),
          ),
          content: Text(
            l10n.translate('guest_user_alert_message'),
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                l10n.translate('cancel'),
                style: const TextStyle(color: AppTheme.errorColor),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, null), // null = login
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
              ),
              child: Text(
                l10n.translate('login'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentColor,
              ),
              child: Text(
                l10n.translate('ok'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
    return result;
  }

  Future<SecondVideoPromptAction?> _showSecondVideoPrompt(AppLocalizations l10n) {
    return showDialog<SecondVideoPromptAction>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: null,
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                tooltip: l10n.translate('register'),
                iconSize: 32,
                color: AppTheme.accentColor,
                onPressed: () => Navigator.pop(context, SecondVideoPromptAction.register),
                icon: const Icon(Icons.app_registration),
              ),
              IconButton(
                tooltip: l10n.translate('login'),
                iconSize: 32,
                color: AppTheme.accentColor,
                onPressed: () => Navigator.pop(context, SecondVideoPromptAction.login),
                icon: const Icon(Icons.login),
              ),
              IconButton(
                tooltip: l10n.translate('cancel'),
                iconSize: 32,
                color: AppTheme.errorColor,
                onPressed: () => Navigator.pop(context, SecondVideoPromptAction.skip),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget? _buildFloatingActionButton(AppLocalizations l10n) {
    // Primary action: start transcription when a file is selected
    if (_state == TranscriptionState.fileSelected) {
        return Tooltip(
          message: l10n.sendToTranscribe,
          child: FloatingActionButton.extended(
            key: const ValueKey('fab-transcribe'),
            heroTag: 'fab-transcribe',
            backgroundColor: AppTheme.accentColor,
            foregroundColor: Colors.white,
            onPressed: _startTranscription,
            icon: const Icon(Icons.mic, color: Colors.white),
            label: Text(l10n.sendToTranscribe),
        ),
      );
    }

    // After translation is completed, surface a quick "Next step" action to move to TTS
    if (_state == TranscriptionState.completed) {
      final project =
          Provider.of<ProjectProvider>(context, listen: true).currentProject;

      // МАҢЫЗДЫ: Аударма бітті ме деп тексеру
      final hasTranslationReady =
          _translationReady || _shouldMarkTranslationReady(project);
      final isTranslationDone = project != null &&
          project.currentStep == ProjectStep.translation &&
          hasTranslationReady;

      if (isTranslationDone) {
        return Tooltip(
          message: l10n.translate('next_step'),
          child: FloatingActionButton.extended(
            key: const ValueKey('fab-next-step'),
            heroTag: 'fab-next-step',
            backgroundColor: Colors.green,
            onPressed: _moveToNextStep,
            icon: const Icon(Icons.arrow_forward),
            label: Text(l10n.translate('next_step')),
          ),
        );
      }
    }

    return null;
  }

  Widget _buildTtsSection(
    TranslationProject project,
    TranscriptionResult baseResult,
    AppLocalizations l10n,
  ) {
    final authProvider = Provider.of<AuthProvider>(context);
    final ttsResult = _buildTranslatedResultForTts(project, baseResult);

    return FutureBuilder<String?>(
      future: authProvider.apiClient.getToken(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final token = snapshot.data;
        // Trial/guest users: token жоқ болса, бос token-пен TTS жұмыс істейді
        final effectiveToken = token ?? '';

        return AppTheme.card(
          child: TranscriptionTtsReader(
            result: ttsResult,
            baseUrl: ApiClient.baseUrl,
            authToken: effectiveToken,
            initialAudioPath: project.audioPath,
            currentFinalVideoPath: project.finalVideoPath,
            onComplete: (folderPath) => _onTtsComplete(folderPath),
          ),
        );
      },
    );
  }

  Future<void> _onTtsComplete(String folderPath) async {
    final projectProvider = Provider.of<ProjectProvider>(
      context,
      listen: false,
    );
    final project = projectProvider.currentProject;
    if (project == null) return;

    // Алдыңғы біріктірілген видеоны өшіру
    if (project.finalVideoPath != null) {
      try {
        final oldVideo = File(project.finalVideoPath!);
        if (await oldVideo.exists()) {
          await oldVideo.delete();
          debugPrint('Алдыңғы біріктірілген видео өшірілді: ${project.finalVideoPath}');
        }
      } catch (e) {
        debugPrint('Алдыңғы видеоны өшіру қатесі: $e');
      }
    }

    final updatedProject = project.copyWith(
      audioPath: folderPath,
      currentStep: ProjectStep.merge,
      finalVideoPath: null, // Жаңа TTS үшін finalVideoPath-ты тазалау
    );

    await projectProvider.updateCurrentProject(updatedProject);

    await projectProvider.updateStepProgress(
      step: ProjectStep.tts,
      status: ProjectStatus.completed,
      progress: 1.0,
    );

    // Prepare merge step
    await projectProvider.updateStepProgress(
      step: ProjectStep.merge,
      status: ProjectStatus.inProgress,
      progress: 0.0,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).translate('next_step')),
        ),
      );
      setState(() {});
    }
  }

  TranscriptionResult _buildTranslatedResultForTts(
    TranslationProject project,
    TranscriptionResult fallbackResult,
  ) {
    final sourceResult = project.transcriptionResult ?? fallbackResult;
    final translatedSegments = project.translatedSegments;

    if (translatedSegments == null || translatedSegments.isEmpty) {
      return sourceResult;
    }

    final updatedSegments = <TranscriptionSegment>[];

    for (var i = 0; i < sourceResult.segments.length; i++) {
      final original = sourceResult.segments[i];
      final translatedText = translatedSegments[i];

      updatedSegments.add(
        original.copyWith(
          text: translatedText ?? original.text,
          translatedText: original.text,
          targetLanguage: original.language,
          language: project.targetLanguage ?? original.language,
        ),
      );
    }

    return TranscriptionResult(
      filename: sourceResult.filename,
      duration: sourceResult.duration,
      detectedLanguage: project.targetLanguage ?? sourceResult.detectedLanguage,
      model: sourceResult.model,
      createdAt: sourceResult.createdAt,
      segments: updatedSegments,
    );
  }

  /// Save final video to user-selected location
  Future<void> _saveFinalVideo(String sourcePath) async {
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Видеоны Сақтау',
        fileName: 'translated_video_${DateTime.now().millisecondsSinceEpoch}.mp4',
        type: FileType.video,
      );

      if (result != null) {
        final sourceFile = File(sourcePath);
        await sourceFile.copy(result);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Видео сәтті сақталды!'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Видео сақтау қатесі: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  /// Play/preview final video using system default player
  Future<void> _playFinalVideo(String filePath) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [filePath]);
      } else {
        // For other platforms
        await Process.run('xdg-open', [filePath]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Видео ашу қатесі: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  /// Open video file in Finder (macOS)
  Future<void> _openVideoInFinder(String filePath) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', filePath]);
      } else {
        // For other platforms, just open the containing directory
        final directory = File(filePath).parent.path;
        await Process.run('open', [directory]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Finder ашу қатесі: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }
}
