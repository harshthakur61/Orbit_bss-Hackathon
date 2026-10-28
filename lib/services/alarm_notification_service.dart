import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/utils/alert_sound.dart';

/// Service managing high-importance emergency alarm notifications,
/// full-screen intents, Android 14 permissions, and notification dismissal.
class AlarmNotificationService {
  static final AlarmNotificationService instance =
      AlarmNotificationService._internal();

  AlarmNotificationService._internal();

  factory AlarmNotificationService() => instance;

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String channelId = 'bedlink_emergency_alerts';
  static const String channelName = 'Emergency Requests';
  static const String channelDescription =
      'High-priority incoming emergency triage alerts for hospital nurses';

  // Map of active auto-cancel timers per requestId
  final Map<String, Timer> _autoCancelTimers = {};

  // Broadcast stream for tapped notification payloads
  final StreamController<String> _tapPayloadController =
      StreamController<String>.broadcast();

  Stream<String> get onNotificationTapped => _tapPayloadController.stream;

  bool _initialized = false;

  /// Top-level or background safe initializer
  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      requestCriticalPermission: false,
    );

    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _tapPayloadController.add(payload);
        }
      },
    );

    // Create Android High-Importance Alarm Notification Channel
    final androidImpl = _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidImpl != null) {
      final channel = AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDescription,
        importance: Importance.max,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('siren'),
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
        showBadge: true,
      );

      await androidImpl.createNotificationChannel(channel);
    }

    _initialized = true;
  }

  /// Get the launch payload if the app was launched by tapping a notification from terminated state
  Future<String?> getLaunchPayload() async {
    final launchDetails =
        await _notificationsPlugin.getNotificationAppLaunchDetails();
    if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
      return launchDetails.notificationResponse?.payload;
    }
    return null;
  }

  static const int _kReliefNotifIdOffset = 10000000;

  static int getEmergencyNotifId(String requestId) => requestId.hashCode.abs();
  static int getReliefNotifId(String reliefRequestId) =>
      reliefRequestId.hashCode.abs() + _kReliefNotifIdOffset;

  /// Trigger a full-screen alarm notification with looping siren & insistent sound
  Future<void> showEmergencyAlarmNotification({
    required String requestId,
    required String severity,
    required String needs,
    DateTime? offerExpiresAt,
  }) async {
    await initialize();

    final int notifId = getEmergencyNotifId(requestId);

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      ongoing: true,
      autoCancel: false,
      visibility: NotificationVisibility.public,
      sound: const RawResourceAndroidNotificationSound('siren'),
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
      // FLAG_INSISTENT (4) causes sound/vibration to repeat continuously until cancelled
      additionalFlags: Int32List.fromList([4]),
      styleInformation: BigTextStyleInformation(
        'Inbound ${severity.toUpperCase()} patient requiring ${needs.isEmpty ? "beds" : needs}.\nRespond within 2 min to hold bed.',
        contentTitle: '🚨 EMERGENCY BED HOLD OFFER',
        summaryText: 'Respond within 2 min',
      ),
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
      sound: 'siren.mp3',
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    final payloadMap = {
      'requestId': requestId,
      'type': 'incoming_request',
      'severity': severity,
      'offerExpiresAt': offerExpiresAt?.toIso8601String(),
    };

    await _notificationsPlugin.show(
      notifId,
      '🚨 EMERGENCY BED HOLD OFFER',
      'Inbound ${severity.toUpperCase()} patient • Respond within 2 min',
      notificationDetails,
      payload: jsonEncode(payloadMap),
    );

    // Safety net: Auto-cancel the notification locally when offerExpiresAt is reached
    final timerKey = 'req_$requestId';
    _autoCancelTimers[timerKey]?.cancel();
    _autoCancelTimers[requestId]?.cancel();
    if (offerExpiresAt != null) {
      final remainingMs =
          offerExpiresAt.difference(DateTime.now()).inMilliseconds;
      if (remainingMs > 0) {
        _autoCancelTimers[timerKey] = Timer(
          Duration(milliseconds: remainingMs),
          () {
            cancelEmergencyAlarmNotification(requestId);
          },
        );
      }
    }
  }

  /// Trigger a full-screen alarm notification for relief requests with looping siren & insistent sound
  Future<void> showReliefAlarmNotification({
    required String reliefRequestId,
    required String reason,
    required String severity,
    double? distanceKm,
    int? etaMin,
    String? ais125Tier,
    DateTime? offerExpiresAt,
    int? wave,
  }) async {
    await initialize();

    final int notifId = getReliefNotifId(reliefRequestId);

    final String distanceText = distanceKm != null
        ? '${distanceKm.toStringAsFixed(1)} km'
        : 'Nearby';
    final String etaText = etaMin != null ? ' • $etaMin min ETA' : '';

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      ongoing: true,
      autoCancel: false,
      visibility: NotificationVisibility.public,
      sound: const RawResourceAndroidNotificationSound('siren'),
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
      additionalFlags: Int32List.fromList([4]),
      styleInformation: BigTextStyleInformation(
        'Colleague ambulance needs backup ($reason).\n$distanceText$etaText • Respond within 60s.',
        contentTitle: '🚨 EMERGENCY RELIEF REQUEST',
        summaryText: 'Respond within 60s',
      ),
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
      sound: 'siren.mp3',
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    final payloadMap = <String, dynamic>{
      'reliefRequestId': reliefRequestId,
      'type': 'relief_request',
      'reason': reason,
      'severity': severity,
      'offerExpiresAt': offerExpiresAt?.toIso8601String(),
    };
    if (distanceKm != null) payloadMap['distanceKm'] = distanceKm;
    if (etaMin != null) payloadMap['etaMin'] = etaMin;
    if (ais125Tier != null) payloadMap['ais125Tier'] = ais125Tier;
    if (wave != null) payloadMap['wave'] = wave;

    await _notificationsPlugin.show(
      notifId,
      '🚨 EMERGENCY RELIEF REQUEST',
      'Colleague ambulance needs backup • Respond within 60s',
      notificationDetails,
      payload: jsonEncode(payloadMap),
    );

    // Safety net: Auto-cancel the relief notification locally when offerExpiresAt is reached (60s)
    final timerKey = 'relief_$reliefRequestId';
    _autoCancelTimers[timerKey]?.cancel();
    if (offerExpiresAt != null) {
      final remainingMs =
          offerExpiresAt.difference(DateTime.now()).inMilliseconds;
      if (remainingMs > 0) {
        _autoCancelTimers[timerKey] = Timer(
          Duration(milliseconds: remainingMs),
          () {
            cancelReliefAlarmNotification(reliefRequestId);
          },
        );
      }
    }
  }

  /// Cancels only the system notification tray item (silencing insistent channel sound)
  /// without stopping the in-app siren player.
  Future<void> dismissNotificationTrayItem(String requestId) async {
    final int notifId = getEmergencyNotifId(requestId);
    try {
      await _notificationsPlugin.cancel(notifId);
    } catch (_) {}
  }

  /// Cancel notification and stop any active alarm audio/vibration for hospital requests
  Future<void> cancelEmergencyAlarmNotification(String requestId) async {
    _autoCancelTimers['req_$requestId']?.cancel();
    _autoCancelTimers.remove('req_$requestId');
    _autoCancelTimers[requestId]?.cancel();
    _autoCancelTimers.remove(requestId);

    final int notifId = getEmergencyNotifId(requestId);
    try {
      await _notificationsPlugin.cancel(notifId);
    } catch (_) {}
    await AlertSoundUtil.stopAlert();
  }

  /// Cancel relief notification and stop any active alarm audio/vibration
  Future<void> cancelReliefAlarmNotification(String reliefRequestId) async {
    final timerKey = 'relief_$reliefRequestId';
    _autoCancelTimers[timerKey]?.cancel();
    _autoCancelTimers.remove(timerKey);

    final int notifId = getReliefNotifId(reliefRequestId);
    try {
      await _notificationsPlugin.cancel(notifId);
    } catch (_) {}
    await AlertSoundUtil.stopAlert();
  }

  /// Cancel all active notifications
  Future<void> cancelAllNotifications() async {
    for (final timer in _autoCancelTimers.values) {
      timer.cancel();
    }
    _autoCancelTimers.clear();
    await _notificationsPlugin.cancelAll();
    await AlertSoundUtil.stopAlert();
  }

  /// Request or check Android 14+ full-screen intent permission.
  /// On Android 14+, launches ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT if not granted.
  Future<bool> requestFullScreenIntentPermission() async {
    try {
      final androidImpl = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        final allowed = await androidImpl.requestFullScreenIntentPermission();
        return allowed ?? true;
      }
    } catch (e) {
      debugPrint(
          '[AlarmNotificationService] requestFullScreenIntentPermission error: $e');
    }
    return true;
  }

  /// Open Android 14+ Full Screen Intent permission settings
  Future<void> openFullScreenIntentSettings() async {
    try {
      await requestFullScreenIntentPermission();
    } catch (e) {
      debugPrint('[AlarmNotificationService] Failed to open app settings: $e');
    }
  }

  /// Check if notifications permission is granted
  Future<bool> isNotificationPermissionGranted() async {
    try {
      return await Permission.notification.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Request notification permission
  Future<bool> requestNotificationPermission() async {
    try {
      final status = await Permission.notification.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Check battery optimization exempt status
  Future<bool> isBatteryOptimizationExempt() async {
    try {
      return await Permission.ignoreBatteryOptimizations.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Request battery optimization exemption
  Future<bool> requestBatteryOptimizationExemption() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }
}
