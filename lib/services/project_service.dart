import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import '../models/translation_project.dart';

class ProjectService {
  static const String _projectsFileName = 'translation_projects.json';
  Future<void> _saveQueue = Future.value();

  /// Get the projects file path
  Future<String> _getProjectsFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/$_projectsFileName';
  }

  /// Load all projects from storage
  Future<List<TranslationProject>> loadProjects() async {
    try {
      final filePath = await _getProjectsFilePath();
      final file = File(filePath);

      if (!await file.exists()) {
        return [];
      }

      final jsonString = await file.readAsString();
      final jsonList = jsonDecode(jsonString) as List;

      return jsonList
          .map((json) => TranslationProject.fromJson(json as Map<String, dynamic>))
          .toList();
    } on FormatException catch (e) {
      // Corrupted file: rename to keep a backup and start fresh
      try {
        final filePath = await _getProjectsFilePath();
        final corruptPath = '$filePath.corrupt_${DateTime.now().millisecondsSinceEpoch}';
        final file = File(filePath);
        if (await file.exists()) {
          await file.rename(corruptPath);
        }
        debugPrint('Corrupted projects file renamed to $corruptPath: $e');
      } catch (renameErr) {
        debugPrint('Error handling corrupted projects file: $renameErr');
      }
      return [];
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == 2) {
        return [];
      }
      debugPrint('Error loading projects: $e');
      return [];
    } catch (e) {
      debugPrint('Error loading projects: $e');
      return [];
    }
  }

  /// Save all projects to storage
  Future<void> saveProjects(List<TranslationProject> projects) async {
    _saveQueue = _saveQueue.then((_) => _saveProjectsInternal(projects));
    await _saveQueue;
  }

  Future<void> _saveProjectsInternal(List<TranslationProject> projects) async {
    try {
      final filePath = await _getProjectsFilePath();
      final file = File(filePath);
      final directory = file.parent;
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final jsonList = projects.map((p) => p.toJson()).toList();
      final jsonString = jsonEncode(jsonList);

      final tempPath = '$filePath.${DateTime.now().microsecondsSinceEpoch}.tmp';
      final tempFile = File(tempPath);

      // Write to a temp file then replace to avoid truncation on partial writes.
      await tempFile.writeAsString(jsonString, flush: true);

      try {
        if (await file.exists()) {
          await file.delete();
        }
      } on FileSystemException catch (e) {
        if (e.osError?.errorCode != 2) {
          rethrow;
        }
      }

      try {
        await tempFile.rename(filePath);
      } on FileSystemException catch (e) {
        if (e.osError?.errorCode == 2) {
          await file.writeAsString(jsonString, flush: true);
          try {
            if (await tempFile.exists()) {
              await tempFile.delete();
            }
          } catch (_) {}
          return;
        }
        rethrow;
      }
    } catch (e) {
      debugPrint('Error saving projects: $e');
    }
  }

  /// Save a single project (updates if exists, adds if new)
  Future<void> saveProject(TranslationProject project) async {
    final projects = await loadProjects();
    final index = projects.indexWhere((p) => p.id == project.id);

    if (index >= 0) {
      projects[index] = project;
    } else {
      projects.add(project);
    }

    await saveProjects(projects);
  }

  /// Get a project by ID
  Future<TranslationProject?> getProject(String id) async {
    final projects = await loadProjects();
    try {
      return projects.firstWhere((p) => p.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Delete a project
  Future<void> deleteProject(String id) async {
    final projects = await loadProjects();
    projects.removeWhere((p) => p.id == id);
    await saveProjects(projects);
  }

  /// Get the most recent incomplete project
  Future<TranslationProject?> getMostRecentIncompleteProject() async {
    final projects = await loadProjects();

    if (projects.isEmpty) return null;

    // Sort by updatedAt descending
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    // Find first incomplete project
    try {
      return projects.firstWhere((p) => !p.isFullyCompleted);
    } catch (e) {
      return null;
    }
  }

  /// Get all incomplete projects
  Future<List<TranslationProject>> getIncompleteProjects() async {
    final projects = await loadProjects();
    final incomplete = projects.where((p) => !p.isFullyCompleted).toList();

    // Sort by updatedAt descending
    incomplete.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return incomplete;
  }

  /// Clear all projects (for testing/debugging)
  Future<void> clearAllProjects() async {
    await saveProjects([]);
  }

  /// Update project step progress
  Future<void> updateStepProgress({
    required String projectId,
    required ProjectStep step,
    required ProjectStatus status,
    double? progress,
    String? errorMessage,
  }) async {
    final project = await getProject(projectId);
    if (project == null) return;

    final stepProgress = project.steps[step];
    if (stepProgress == null) return;

    final updatedStepProgress = stepProgress.copyWith(
      status: status,
      progress: progress,
      errorMessage: errorMessage,
      startedAt: stepProgress.startedAt ?? (status == ProjectStatus.inProgress ? DateTime.now() : null),
      completedAt: status == ProjectStatus.completed ? DateTime.now() : null,
    );

    final updatedSteps = Map<ProjectStep, StepProgress>.from(project.steps);
    updatedSteps[step] = updatedStepProgress;

    final updatedProject = project.copyWith(
      steps: updatedSteps,
      // Don't auto-advance currentStep - let user click "Next Step" button
    );

    await saveProject(updatedProject);
  }
}
