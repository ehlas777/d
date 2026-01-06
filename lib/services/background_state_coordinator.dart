import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'background_notification_manager.dart';
import '../models/auto_translation_progress.dart';

/// Coordinates background mode state and resource management
/// Manages wake lock, notifications, and background transitions
class BackgroundStateCoordinator {
  final BackgroundNotificationManager _notificationManager = BackgroundNotificationManager.instance;

  bool _isInBackgroundMode = false;
  bool _wakeLockEnabled = false;
  StreamSubscription<AutoTranslationProgress>? _progressSubscription;

  /// Check if currently in background mode
  bool get isInBackgroundMode => _isInBackgroundMode;

  /// Check if wake lock is enabled
  bool get isWakeLockEnabled => _wakeLockEnabled;

  /// Enable background mode
  Future<void> enableBackgroundMode({
    required Stream<AutoTranslationProgress> progressStream,
  }) async {
    if (_isInBackgroundMode) return;

    print('🌙 Enabling background mode...');

    // Request notification permissions
    final permissionGranted = await _notificationManager.requestPermissions();
    if (!permissionGranted) {
      print('⚠️  Notification permission denied');
    }

    // Initialize notifications
    await _notificationManager.initialize();

    // Listen to progress stream and update notifications
    _progressSubscription = progressStream.listen(
      (progress) {
        _notificationManager.updateFromProgress(progress);
      },
      onError: (error) {
        _notificationManager.showErrorNotification(
          title: 'PolyDub - Қате',
          body: 'Аударма процесінде қате: $error',
        );
      },
    );

    _isInBackgroundMode = true;
    print('✅ Background mode enabled');
  }

  /// Disable background mode
  Future<void> disableBackgroundMode() async {
    if (!_isInBackgroundMode) return;

    print('☀️  Disabling background mode...');

    // Cancel progress subscription
    await _progressSubscription?.cancel();
    _progressSubscription = null;

    // Cancel notifications
    await _notificationManager.cancelProgressNotification();

    // Disable wake lock if enabled
    if (_wakeLockEnabled) {
      await disableWakeLock();
    }

    _isInBackgroundMode = false;
    print('✅ Background mode disabled');
  }

  /// Enable wake lock to prevent device sleep
  Future<void> enableWakeLock() async {
    if (_wakeLockEnabled) return;

    try {
      await WakelockPlus.enable();
      _wakeLockEnabled = true;
      print('🔒 Wake lock enabled');
    } catch (e) {
      print('❌ Failed to enable wake lock: $e');
    }
  }

  /// Disable wake lock
  Future<void> disableWakeLock() async {
    if (!_wakeLockEnabled) return;

    try {
      await WakelockPlus.disable();
      _wakeLockEnabled = false;
      print('🔓 Wake lock disabled');
    } catch (e) {
      print('❌ Failed to disable wake lock: $e');
    }
  }

  /// Handle lifecycle state change
  Future<void> onLifecycleChanged({
    required AppLifecycleState state,
    required Stream<AutoTranslationProgress>? progressStream,
    required bool isProcessing,
  }) async {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // App going to background
        if (isProcessing && progressStream != null) {
          await enableBackgroundMode(progressStream: progressStream);
        }
        break;

      case AppLifecycleState.resumed:
        // App returning to foreground
        await disableBackgroundMode();
        break;

      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // App being terminated or hidden
        break;
    }
  }

  /// Show completion notification
  Future<void> notifyCompletion({required String message}) async {
    await _notificationManager.showCompletionNotification(
      title: 'PolyDub - Дайын',
      body: message,
    );
  }

  /// Show error notification
  Future<void> notifyError({required String error}) async {
    await _notificationManager.showErrorNotification(
      title: 'PolyDub - Қате',
      body: error,
    );
  }

  /// Cleanup resources
  Future<void> dispose() async {
    await disableBackgroundMode();
    await _notificationManager.cancelAll();
  }
}
