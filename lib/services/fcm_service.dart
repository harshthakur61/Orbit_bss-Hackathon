import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/crew_presence_constants.dart';
import '../core/router.dart';
import '../core/theme.dart';
import '../core/utils/alert_sound.dart';
import '../models/relief_offer_data.dart';
import '../providers/relief_providers.dart';
import 'alarm_notification_service.dart';

/// Top-level background message handler for FCM wake-ups.
/// Works when the app is in the background or TERMINATED.
/// Does not depend on Riverpod or UI state.
@pragma('vm:entry-point')
Future<void> bedlinkFcmBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    final data = message.data;
    final type = data['type'];
    final requestId = data['requestId'] as String?;

    if (type == 'incoming_request' && requestId != null) {
      // 1. Delivery ACK: Write alertDeliveredAt on the emergency request doc
      try {
        await FirebaseFirestore.instance
            .collection('requests')
            .doc(requestId)
            .update({
          'alertDeliveredAt': FieldValue.serverTimestamp(),
        });
      } catch (ackErr) {
        debugPrint('[FcmService] ACK write error: $ackErr');
      }

      // 2. Trigger high-importance Android alarm notification with insistent looping siren & fullScreenIntent
      final severity = (data['severity'] as String?) ?? 'serious';
      final needs = (data['needs'] as String?) ?? '';
      DateTime? offerExpiresAt;
      if (data['offerExpiresAt'] != null) {
        offerExpiresAt = DateTime.tryParse(data['offerExpiresAt']);
      }

      await AlarmNotificationService.instance.showEmergencyAlarmNotification(
        requestId: requestId,
        severity: severity,
        needs: needs,
        offerExpiresAt: offerExpiresAt,
      );
    } else if (type == 'cancel_request' && requestId != null) {
      // Cancel system notification and silence siren immediately
      await AlarmNotificationService.instance
          .cancelEmergencyAlarmNotification(requestId);
      await AlertSoundUtil.stopAlert();
    } else if (type == 'relief_request') {
      final reliefRequestId =
          (data['reliefRequestId'] ?? data['requestId']) as String?;
      if (reliefRequestId == null || reliefRequestId.isEmpty) return;

      // Check local crew presence status: Only crews with status AVAILABLE can receive this
      try {
        final prefs = await SharedPreferences.getInstance();
        final crewUid = prefs.getString('bedlink_fcm_target_id');
        final role = prefs.getString('bedlink_fcm_role');
        final status = crewUid != null
            ? prefs.getString('${CrewPresenceConstants.prefsCrewStatusKey}_$crewUid')
            : null;

        if (role == 'crew' && status != CrewPresenceStatus.available.code) {
          debugPrint(
              '[FcmService] Silently ignoring relief request: crew status is $status');
          return;
        }
      } catch (err) {
        debugPrint('[FcmService] Error checking crew status in background: $err');
      }

      final reason = (data['reason'] as String?) ?? 'mechanical_breakdown';
      final severity = (data['severity'] as String?) ?? 'serious';
      final distanceKm = data['distanceKm'] != null
          ? double.tryParse(data['distanceKm'].toString())
          : null;
      final etaMin = data['etaMin'] != null
          ? int.tryParse(data['etaMin'].toString())
          : null;
      final wave = data['wave'] != null
          ? int.tryParse(data['wave'].toString())
          : null;
      final ais125Tier = data['ais125Tier'] as String?;
      DateTime? offerExpiresAt;
      if (data['offerExpiresAt'] != null) {
        offerExpiresAt = DateTime.tryParse(data['offerExpiresAt']);
      }

      await AlarmNotificationService.instance.showReliefAlarmNotification(
        reliefRequestId: reliefRequestId,
        reason: reason,
        severity: severity,
        distanceKm: distanceKm,
        etaMin: etaMin,
        ais125Tier: ais125Tier,
        offerExpiresAt: offerExpiresAt,
        wave: wave,
      );
    } else if (type == 'relief_cancel') {
      final reliefRequestId =
          (data['reliefRequestId'] ?? data['requestId']) as String?;
      if (reliefRequestId != null) {
        await AlarmNotificationService.instance
            .cancelReliefAlarmNotification(reliefRequestId);
        await AlertSoundUtil.stopAlert();
      }
    }
  } catch (e) {
    debugPrint('[FcmService] Background message handler error: $e');
  }
}

class FcmService {
  final FirebaseFirestore? _injectedFirestore;
  final FirebaseMessaging? _injectedMessaging;

  FcmService({
    FirebaseFirestore? firestore,
    FirebaseMessaging? messaging,
  })  : _injectedFirestore = firestore,
        _injectedMessaging = messaging;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;
  FirebaseMessaging get _messaging =>
      _injectedMessaging ?? FirebaseMessaging.instance;

  static const String _prefDeviceIdKey = 'bedlink_device_id';
  static const String _prefRoleKey = 'bedlink_fcm_role';
  static const String _prefTargetIdKey = 'bedlink_fcm_target_id';

  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;
  StreamSubscription<String>? _notificationTappedSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;

  /// Initialize FCM listeners (foreground, background, token refresh, and tap routing)
  Future<void> initialize() async {
    try {
      // Initialize local notification channels
      await AlarmNotificationService.instance.initialize();

      // Register top-level background handler
      FirebaseMessaging.onBackgroundMessage(bedlinkFcmBackgroundHandler);

      // 1. Foreground FCM messages
      await _foregroundSubscription?.cancel();
      _foregroundSubscription =
          FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // 2. Notification opened while backgrounded via FCM system tray
      await _messageOpenedSubscription?.cancel();
      _messageOpenedSubscription =
          FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        final type = message.data['type'];
        if (type == 'relief_request') {
          handleReliefNotificationTap(message.data);
        } else {
          final reqId = message.data['requestId'];
          if (reqId != null) {
            handleNotificationTap(reqId);
          }
        }
      });

      // 3. Notification tapped from local notifications tray
      await _notificationTappedSubscription?.cancel();
      _notificationTappedSubscription = AlarmNotificationService
          .instance.onNotificationTapped
          .listen((payload) {
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map<String, dynamic> &&
              decoded['type'] == 'relief_request') {
            handleReliefNotificationTap(decoded);
          } else {
            final reqId =
                (decoded is Map ? decoded['requestId'] : null) as String?;
            if (reqId != null) {
              handleNotificationTap(reqId);
            } else {
              handleNotificationTap(payload);
            }
          }
        } catch (_) {
          handleNotificationTap(payload);
        }
      });

      // 4. Token refresh listener
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((newToken) {
        _handleTokenRefresh(newToken);
      });

      // 5. Cold start check (tapped from terminated state)
      _checkColdStartNotification();
    } catch (e) {
      debugPrint('[FcmService] FCM initialization notice (mock/offline environment): $e');
    }
  }

  /// Check if the app was launched by tapping an alarm notification from terminated state
  Future<void> _checkColdStartNotification() async {
    try {
      // Check local notifications cold start
      final localLaunchPayload =
          await AlarmNotificationService.instance.getLaunchPayload();
      if (localLaunchPayload != null && localLaunchPayload.isNotEmpty) {
        try {
          final decoded = jsonDecode(localLaunchPayload);
          if (decoded is Map<String, dynamic> &&
              decoded['type'] == 'relief_request') {
            handleReliefNotificationTap(decoded);
            return;
          }
          final reqId =
              (decoded is Map ? decoded['requestId'] : null) as String?;
          if (reqId != null) {
            handleNotificationTap(reqId);
            return;
          }
        } catch (_) {
          handleNotificationTap(localLaunchPayload);
          return;
        }
      }

      // Check FCM getInitialMessage
      final fcmInitialMessage = await _messaging.getInitialMessage();
      if (fcmInitialMessage != null) {
        final type = fcmInitialMessage.data['type'];
        if (type == 'relief_request') {
          handleReliefNotificationTap(fcmInitialMessage.data);
        } else {
          final reqId = fcmInitialMessage.data['requestId'];
          if (reqId != null) {
            handleNotificationTap(reqId);
          }
        }
      }
    } catch (e) {
      debugPrint('[FcmService] Cold start check error: $e');
    }
  }

  /// Handle tapping on an emergency alarm notification across terminated, backgrounded, and foreground states
  Future<void> handleNotificationTap(String requestId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loggedInHospitalId = prefs.getString('bedlink_selected_hospital_id');

      // If nurse is not logged in, route through login then to the request if valid
      if (loggedInHospitalId == null || loggedInHospitalId.isEmpty) {
        appRouter.go('/nurse/login?pendingRequestId=$requestId');
        return;
      }

      // If nurse is logged in, fetch request from Firestore and validate offer
      final doc = await _firestore.collection('requests').doc(requestId).get();
      if (!doc.exists) {
        _handleInvalidOffer(requestId);
        return;
      }

      final data = doc.data()!;
      final status = data['status'] as String?;
      final targetHospitalId = data['currentHospitalId'] as String?;

      DateTime? expiresAt;
      if (data['offerExpiresAt'] != null) {
        final rawExpires = data['offerExpiresAt'];
        if (rawExpires is Timestamp) {
          expiresAt = rawExpires.toDate();
        } else if (rawExpires is String) {
          expiresAt = DateTime.tryParse(rawExpires);
        }
      }

      final isExpired =
          expiresAt != null && DateTime.now().isAfter(expiresAt);

      // Validate still offered to THIS hospital and unexpired
      if (status == 'offered' &&
          targetHospitalId == loggedInHospitalId &&
          !isExpired) {
        // Cancel notification tray item
        await AlarmNotificationService.instance
            .cancelEmergencyAlarmNotification(requestId);

        // Route to nurse home where activeHospitalRequestProvider will display the triage modal
        appRouter.go('/nurse/home');
      } else {
        _handleInvalidOffer(requestId);
      }
    } catch (e) {
      debugPrint('[FcmService] Notification tap routing error: $e');
    }
  }

  void _handleInvalidOffer(String requestId) {
    AlarmNotificationService.instance.cancelEmergencyAlarmNotification(requestId);
    AlertSoundUtil.stopAlert();

    final context = rootNavigatorKey.currentContext;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This request is no longer active'),
          backgroundColor: AppColors.textSecondary,
        ),
      );
    }
    appRouter.go('/nurse/home');
  }

  /// Handle tapping on a relief request alert across terminated, backgrounded, and foreground states
  Future<void> handleReliefNotificationTap(Map<String, dynamic> data) async {
    final reliefRequestId =
        (data['reliefRequestId'] ?? data['requestId']) as String?;
    if (reliefRequestId == null || reliefRequestId.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final crewUid = prefs.getString(_prefTargetIdKey);
      final role = prefs.getString(_prefRoleKey);

      // If crew is not logged in, route through login with pending relief ID
      if (role != 'crew' || crewUid == null || crewUid.isEmpty) {
        appRouter.go('/crew/login?pendingReliefId=$reliefRequestId');
        return;
      }

      // Re-check local crew status: if crew is no longer AVAILABLE, ignore
      final status =
          prefs.getString('${CrewPresenceConstants.prefsCrewStatusKey}_$crewUid');
      if (status != CrewPresenceStatus.available.code) {
        _handleInvalidReliefOffer(
          reliefRequestId,
          message: 'Relief request ignored: your status is currently $status',
        );
        return;
      }

      // Fetch relief request doc from Firestore to validate offer state
      final doc = await _firestore
          .collection('reliefRequests')
          .doc(reliefRequestId)
          .get();

      if (!doc.exists) {
        _handleInvalidReliefOffer(reliefRequestId);
        return;
      }

      final reliefData = doc.data()!;
      final reliefStatus = reliefData['status'] as String?;

      DateTime? expiresAt;
      if (reliefData['offerExpiresAt'] != null) {
        final rawExpires = reliefData['offerExpiresAt'];
        if (rawExpires is Timestamp) {
          expiresAt = rawExpires.toDate();
        } else if (rawExpires is String) {
          expiresAt = DateTime.tryParse(rawExpires);
        }
      }

      final isExpired =
          expiresAt != null && DateTime.now().isAfter(expiresAt);

      if (reliefStatus == 'searching' && !isExpired) {
        // Cancel notification tray item
        await AlarmNotificationService.instance
            .cancelReliefAlarmNotification(reliefRequestId);

        final offerData = ReliefOfferData.fromJson({
          ...data,
          'reliefRequestId': reliefRequestId,
          if (expiresAt != null) 'offerExpiresAt': expiresAt.toIso8601String(),
          if (reliefData['reason'] != null) 'reason': reliefData['reason'],
          if (reliefData['severity'] != null) 'severity': reliefData['severity'],
          if (reliefData['disabledAmbulance'] != null &&
              reliefData['disabledAmbulance'] is Map &&
              reliefData['disabledAmbulance']['ais125Tier'] != null)
            'ais125Tier': reliefData['disabledAmbulance']['ais125Tier'],
          if (reliefData['originalRequestId'] != null)
            'originalRequestId': reliefData['originalRequestId'],
        });

        ReliefService.postReliefOffer(offerData);
        appRouter.go('/crew/home');
      } else {
        _handleInvalidReliefOffer(reliefRequestId);
      }
    } catch (e) {
      debugPrint('[FcmService] Relief notification tap error: $e');
      _handleInvalidReliefOffer(reliefRequestId);
    }
  }

  void _handleInvalidReliefOffer(String reliefRequestId, {String? message}) {
    AlarmNotificationService.instance
        .cancelReliefAlarmNotification(reliefRequestId);
    AlertSoundUtil.stopAlert();
    ReliefService.clearReliefOffer();

    final context = rootNavigatorKey.currentContext;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message ?? 'This request is no longer active'),
          backgroundColor: AppColors.textSecondary,
        ),
      );
    }
    appRouter.go('/crew/home');
  }

  /// Request push notification permissions (Android 13+ POST_NOTIFICATIONS, iOS)
  Future<bool> requestPermissions() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: true,
        badge: true,
        carPlay: false,
        criticalAlert: true,
        provisional: false,
        sound: true,
      );

      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      debugPrint('[FcmService] Permission request failed: $e');
      return false;
    }
  }

  /// Get or create a persistent unique device ID for token document keying
  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var devId = prefs.getString(_prefDeviceIdKey);
    if (devId == null || devId.isEmpty) {
      final randomNum = math.Random().nextInt(999999).toString().padLeft(6, '0');
      devId = 'dev_${DateTime.now().millisecondsSinceEpoch}_$randomNum';
      await prefs.setString(_prefDeviceIdKey, devId);
    }
    return devId;
  }

  /// Save FCM Device Token under hospitals/{hospitalId}/devices/{deviceId}
  Future<void> registerNurseDevice(String hospitalId) async {
    try {
      await requestPermissions();
      final deviceId = await getDeviceId();
      final token = await _messaging.getToken();

      if (token == null) return;

      final deviceDoc = {
        'token': token,
        'platform': defaultTargetPlatform.name,
        'appVersion': '1.0.0',
        'updatedAt': FieldValue.serverTimestamp(),
        'loggedIn': true,
        'deviceId': deviceId,
        'hospitalId': hospitalId,
      };

      await _firestore
          .collection('hospitals')
          .doc(hospitalId)
          .collection('devices')
          .doc(deviceId)
          .set(deviceDoc, SetOptions(merge: true));

      // Flag hospital as having active registered push devices
      await _firestore.collection('hospitals').doc(hospitalId).update({
        'hasActiveDevices': true,
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefRoleKey, 'nurse');
      await prefs.setString(_prefTargetIdKey, hospitalId);
      await prefs.setString('bedlink_selected_hospital_id', hospitalId);
    } catch (e) {
      debugPrint('[FcmService] Failed to register nurse device token: $e');
    }
  }

  /// Remove FCM Device Token on nurse logout
  Future<void> unregisterNurseDevice(String hospitalId) async {
    try {
      final deviceId = await getDeviceId();
      await _firestore
          .collection('hospitals')
          .doc(hospitalId)
          .collection('devices')
          .doc(deviceId)
          .delete();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefRoleKey);
      await prefs.remove(_prefTargetIdKey);
      await prefs.remove('bedlink_selected_hospital_id');
    } catch (e) {
      debugPrint('[FcmService] Failed to unregister nurse device: $e');
    }
  }

  /// Save FCM Device Token under ambulances/{uid}/devices/{deviceId}
  Future<void> registerCrewDevice(String crewUid) async {
    try {
      await requestPermissions();
      final deviceId = await getDeviceId();
      final token = await _messaging.getToken();

      if (token == null) return;

      final deviceDoc = {
        'token': token,
        'platform': defaultTargetPlatform.name,
        'appVersion': '1.0.0',
        'updatedAt': FieldValue.serverTimestamp(),
        'loggedIn': true,
        'deviceId': deviceId,
        'crewUid': crewUid,
      };

      await _firestore
          .collection('ambulances')
          .doc(crewUid)
          .collection('devices')
          .doc(deviceId)
          .set(deviceDoc, SetOptions(merge: true));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefRoleKey, 'crew');
      await prefs.setString(_prefTargetIdKey, crewUid);
    } catch (e) {
      debugPrint('[FcmService] Failed to register crew device token: $e');
    }
  }

  /// Remove FCM Device Token on crew logout
  Future<void> unregisterCrewDevice(String crewUid) async {
    try {
      final deviceId = await getDeviceId();
      await _firestore
          .collection('ambulances')
          .doc(crewUid)
          .collection('devices')
          .doc(deviceId)
          .delete();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefRoleKey);
      await prefs.remove(_prefTargetIdKey);
    } catch (e) {
      debugPrint('[FcmService] Failed to unregister crew device: $e');
    }
  }

  /// Handle incoming foreground FCM messages:
  /// Avoids double notification/siren since the in-app modal already displays and rings
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final data = message.data;
    final type = data['type'];
    final requestId = data['requestId'] as String?;

    if (type == 'incoming_request' && requestId != null) {
      // Write delivery acknowledgment immediately
      try {
        await _firestore.collection('requests').doc(requestId).update({
          'alertDeliveredAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    } else if (type == 'cancel_request' && requestId != null) {
      await AlarmNotificationService.instance
          .cancelEmergencyAlarmNotification(requestId);
      await AlertSoundUtil.stopAlert();
    } else if (type == 'relief_request') {
      final reliefRequestId =
          (data['reliefRequestId'] ?? data['requestId']) as String?;
      if (reliefRequestId == null || reliefRequestId.isEmpty) return;

      // Re-check local availability: if crew is no longer AVAILABLE locally, ignore it silently.
      final prefs = await SharedPreferences.getInstance();
      final crewUid = prefs.getString(_prefTargetIdKey);
      final role = prefs.getString(_prefRoleKey);
      final status = crewUid != null
          ? prefs.getString('${CrewPresenceConstants.prefsCrewStatusKey}_$crewUid')
          : null;

      if (role == 'crew' && status != CrewPresenceStatus.available.code) {
        debugPrint(
            '[FcmService] Foreground relief_request silently ignored: crew status is $status');
        return;
      }

      final offer = ReliefOfferData.fromJson(data);
      if (offer.isExpired) {
        return;
      }

      // Single-source siren: in foreground, the in-app modal triggers siren & ring
      ReliefService.postReliefOffer(offer);
    } else if (type == 'relief_cancel') {
      final reliefRequestId =
          (data['reliefRequestId'] ?? data['requestId']) as String?;
      if (reliefRequestId != null) {
        await AlarmNotificationService.instance
            .cancelReliefAlarmNotification(reliefRequestId);
        await AlertSoundUtil.stopAlert();
        ReliefService.clearReliefOffer();
      }
    }
  }

  /// Handle token rotation
  Future<void> _handleTokenRefresh(String newToken) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString(_prefRoleKey);
      final targetId = prefs.getString(_prefTargetIdKey);
      final deviceId = await getDeviceId();

      if (role == 'nurse' && targetId != null) {
        await _firestore
            .collection('hospitals')
            .doc(targetId)
            .collection('devices')
            .doc(deviceId)
            .set({
          'token': newToken,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else if (role == 'crew' && targetId != null) {
        await _firestore
            .collection('ambulances')
            .doc(targetId)
            .collection('devices')
            .doc(deviceId)
            .set({
          'token': newToken,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('[FcmService] Token refresh error: $e');
    }
  }

  void dispose() {
    _foregroundSubscription?.cancel();
    _messageOpenedSubscription?.cancel();
    _notificationTappedSubscription?.cancel();
    _tokenRefreshSubscription?.cancel();
  }
}
