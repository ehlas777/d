import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/auto_translation_state.dart';

/// Storage service for automatic translation state persistence
/// Handles saving/loading state to survive app restarts
class AutoTranslationStorage {
  static const String _keyPrefix = 'auto_translation_';
  static const String _projectListKey = 'auto_translation_projects';

  /// Save complete state to persistent storage
  Future<void> saveState(AutoTranslationState state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix${state.projectId}';
      final json = jsonEncode(state.toJson());
      
      await prefs.setString(key, json);
      
      // Update project list
      await _addToProjectList(state.projectId);
      
      print('✅ State saved for project: ${state.projectId}');
    } catch (e) {
      print('❌ Failed to save state: $e');
      rethrow;
    }
  }

  /// Load state from persistent storage
  Future<AutoTranslationState?> loadState(String projectId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$projectId';
      final json = prefs.getString(key);
      
      if (json == null) {
        print('ℹ️ No saved state found for project: $projectId');
        return null;
      }
      
      final data = jsonDecode(json) as Map<String, dynamic>;
      final state = AutoTranslationState.fromJson(data);
      
      print('✅ State loaded for project: $projectId');
      return state;
    } catch (e) {
      print('❌ Failed to load state: $e');
      return null;
    }
  }

  /// Clear state for a specific project
  Future<void> clearState(String projectId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$projectId';
      
      await prefs.remove(key);
      await _removeFromProjectList(projectId);
      
      print('✅ State cleared for project: $projectId');
    } catch (e) {
      print('❌ Failed to clear state: $e');
    }
  }

  /// Get list of all saved project IDs
  Future<List<String>> listSavedProjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final projects = prefs.getStringList(_projectListKey) ?? [];
      return projects;
    } catch (e) {
      print('❌ Failed to list projects: $e');
      return [];
    }
  }

  /// Get all saved states
  Future<List<AutoTranslationState>> loadAllStates() async {
    final projectIds = await listSavedProjects();
    final states = <AutoTranslationState>[];
    
    for (final projectId in projectIds) {
      final state = await loadState(projectId);
      if (state != null) {
        states.add(state);
      }
    }
    
    return states;
  }

  /// Check if a project has saved state
  Future<bool> hasState(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_keyPrefix$projectId';
    return prefs.containsKey(key);
  }

  /// Clear all saved states
  Future<void> clearAllStates() async {
    final projectIds = await listSavedProjects();
    
    for (final projectId in projectIds) {
      await clearState(projectId);
    }
    
    print('✅ All states cleared');
  }

  /// Clear old states (older than specified duration)
  Future<void> clearOldStates(Duration maxAge) async {
    final states = await loadAllStates();
    final now = DateTime.now();
    
    for (final state in states) {
      final age = now.difference(state.lastUpdated);
      if (age > maxAge) {
        await clearState(state.projectId);
        print('🗑️ Cleared old state: ${state.projectId} (age: ${age.inDays} days)');
      }
    }
  }

  // Private helper methods

  Future<void> _addToProjectList(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final projects = prefs.getStringList(_projectListKey) ?? [];
    
    if (!projects.contains(projectId)) {
      projects.add(projectId);
      await prefs.setStringList(_projectListKey, projects);
    }
  }

  Future<void> _removeFromProjectList(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final projects = prefs.getStringList(_projectListKey) ?? [];
    
    projects.remove(projectId);
    await prefs.setStringList(_projectListKey, projects);
  }
}
