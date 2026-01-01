import 'package:flutter/material.dart';
import '../models/translation_project.dart';
import '../services/project_service.dart';

class ProjectProvider extends ChangeNotifier {
  final ProjectService _projectService = ProjectService();

  TranslationProject? _currentProject;
  List<TranslationProject> _recentProjects = [];
  bool _isLoading = false;

  TranslationProject? get currentProject => _currentProject;
  List<TranslationProject> get recentProjects => _recentProjects;
  bool get isLoading => _isLoading;

  /// Initialize and check for incomplete projects
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Load recent incomplete projects
      _recentProjects = await _projectService.getIncompleteProjects();

      // Auto-load the most recent incomplete project
      if (_recentProjects.isNotEmpty) {
        _currentProject = _recentProjects.first;
      }
    } catch (e) {
      debugPrint('Error initializing projects: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create a new project
  Future<TranslationProject> createProject({
    required String videoFileName,
    required String videoPath,
  }) async {
    final project = TranslationProject.create(
      videoFileName: videoFileName,
      videoPath: videoPath,
    );

    await _projectService.saveProject(project);
    _currentProject = project;

    // Reload recent projects
    await _loadRecentProjects();

    notifyListeners();
    return project;
  }

  /// Load a specific project
  Future<void> loadProject(String projectId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final project = await _projectService.getProject(projectId);
      if (project != null) {
        _currentProject = project;
      }
    } catch (e) {
      debugPrint('Error loading project: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Update current project
  Future<void> updateCurrentProject(TranslationProject project) async {
    _currentProject = project;
    await _projectService.saveProject(project);
    await _loadRecentProjects();
    notifyListeners();
  }

  /// Update step progress
  Future<void> updateStepProgress({
    required ProjectStep step,
    required ProjectStatus status,
    double? progress,
    String? errorMessage,
  }) async {
    if (_currentProject == null) return;

    await _projectService.updateStepProgress(
      projectId: _currentProject!.id,
      step: step,
      status: status,
      progress: progress,
      errorMessage: errorMessage,
    );

    // Reload current project
    await loadProject(_currentProject!.id);

    // Force UI update
    notifyListeners();
  }

  /// Clear current project (start fresh)
  void clearCurrentProject() {
    _currentProject = null;
    notifyListeners();
  }

  /// Delete a project
  Future<void> deleteProject(String projectId) async {
    await _projectService.deleteProject(projectId);

    if (_currentProject?.id == projectId) {
      _currentProject = null;
    }

    await _loadRecentProjects();
    notifyListeners();
  }

  /// Load recent incomplete projects
  Future<void> _loadRecentProjects() async {
    _recentProjects = await _projectService.getIncompleteProjects();
  }

  /// Get all incomplete projects (refresh)
  Future<void> refreshRecentProjects() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _loadRecentProjects();
    } catch (e) {
      debugPrint('Error refreshing projects: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Check if there's a project that can be resumed
  bool get hasResumableProject {
    return _currentProject != null && !_currentProject!.isFullyCompleted;
  }

  /// Get the next step name for display
  String? getNextStepName() {
    if (_currentProject == null) return null;

    switch (_currentProject!.currentStep) {
      case ProjectStep.transcription:
        return 'Transcription';
      case ProjectStep.translation:
        return 'Translation';
      case ProjectStep.tts:
        return 'Text-to-Speech';
      case ProjectStep.merge:
        return 'Merge';
      case ProjectStep.completed:
        return 'Completed';
    }
  }
}
