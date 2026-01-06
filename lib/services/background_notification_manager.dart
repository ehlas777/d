import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/auto_translation_progress.dart';
import '../models/auto_translation_state.dart';

/// Manages background notifications for translation progress
/// Shows ongoing notifications when app is backgrounded
class BackgroundNotificationManager {
  static BackgroundNotificationManager? _instance;
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  static const int _progressNotificationId = 1000;
  static const String _channelId = 'translation_progress';
  static const String _channelName = 'Translation Progress';

  BackgroundNotificationManager._();

  static BackgroundNotificationManager get instance {
    _instance ??= BackgroundNotificationManager._();
    return _instance!;
  }

  /// Initialize notification system
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Android initialization
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization
    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: false,
    );

    final initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: iosSettings,
    );

    await _notifications.initialize(initializationSettings);

    // Create notification channel for Android
    if (Platform.isAndroid) {
      const androidChannel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Shows automatic translation progress',
        importance: Importance.high,
        playSound: false,
        enableVibration: false,
        showBadge: true,
      );

      await _notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);
    }

    _isInitialized = true;
  }

  /// Request notification permissions
  Future<bool> requestPermissions() async {
    if (!_isInitialized) {
      await initialize();
    }

    if (Platform.isIOS || Platform.isMacOS) {
      final result = await _notifications
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: false,
          );
      return result ?? false;
    } else if (Platform.isAndroid) {
      final result = await _notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      return result ?? false;
    }

    return true;
  }

  /// Show progress notification
  Future<void> showProgressNotification({
    required String title,
    required String body,
    int? progress,
    int? maxProgress,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Shows automatic translation progress',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true, // Cannot be dismissed by user
      autoCancel: false,
      showProgress: progress != null && maxProgress != null,
      maxProgress: maxProgress ?? 100,
      progress: progress ?? 0,
      indeterminate: progress == null, // Show indeterminate if no progress value
      playSound: false,
      enableVibration: false,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: false,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    await _notifications.show(
      _progressNotificationId,
      title,
      body,
      notificationDetails,
    );
  }

  /// Update notification with progress from AutoTranslationProgress
  Future<void> updateFromProgress(AutoTranslationProgress progress) async {
    String title = 'PolyDub - Аударма процесі';
    String body = progress.currentActivity ?? 'Өңделуде...';

    // Calculate overall progress if available
    int? progressValue;
    int? maxProgressValue;

    if (progress.totalSegments > 0) {
      // Use percentage from progress
      progressValue = progress.percentage.toInt();
      maxProgressValue = 100;
    }

    await showProgressNotification(
      title: title,
      body: body,
      progress: progressValue,
      maxProgress: maxProgressValue,
    );
  }

  /// Show completion notification
  Future<void> showCompletionNotification({
    required String title,
    required String body,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.high,
      priority: Priority.high,
      ongoing: false,
      autoCancel: true,
      playSound: true,
      enableVibration: true,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    await _notifications.show(
      _progressNotificationId,
      title,
      body,
      notificationDetails,
    );
  }

  /// Show error notification
  Future<void> showErrorNotification({
    required String title,
    required String body,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.high,
      priority: Priority.high,
      ongoing: false,
      autoCancel: true,
      playSound: true,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(body),
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    await _notifications.show(
      _progressNotificationId + 1, // Different ID for errors
      title,
      body,
      notificationDetails,
    );
  }

  /// Cancel all notifications
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }

  /// Cancel progress notification
  Future<void> cancelProgressNotification() async {
    await _notifications.cancel(_progressNotificationId);
  }
}
