import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/crew_presence_constants.dart';
import '../models/ambulance.dart';
import '../models/crew_presence.dart';

/// Service managing real-time ambulance crew availability status,
/// background presence publishing, and relief eligibility.
class CrewPresenceService extends ChangeNotifier {
  final FirebaseFirestore? _injectedFirestore;
  final SharedPreferences? _injectedPrefs;

  CrewPresenceService({
    FirebaseFirestore? firestore,
    SharedPreferences? prefs,
  })  : _injectedFirestore = firestore,
        _injectedPrefs = prefs;

  FirebaseFirestore get _firestore => _injectedFirestore ?? FirebaseFirestore.instance;

  CrewPresenceStatus _currentStatus = CrewPresenceStatus.offline;
  bool _isLocationPermissionDenied = false;
  bool _isPublishing = false;
  Position? _lastPublishedPosition;
  DateTime? _lastPublishedAt;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _heartbeatTimer;

  CrewPresenceStatus get currentStatus => _currentStatus;
  bool get isLocationPermissionDenied => _isLocationPermissionDenied;
  bool get isPublishing => _isPublishing;
  Position? get lastPublishedPosition => _lastPublishedPosition;
  DateTime? get lastPublishedAt => _lastPublishedAt;

  DocumentReference<Map<String, dynamic>> _presenceRef(String uid) =>
      _firestore.collection('crewPresence').doc(uid);

  /// Initializes the crew status from local storage and remote Firestore
  Future<void> initializeStatus(String uid) async {
    try {
      final prefs = _injectedPrefs ?? await SharedPreferences.getInstance();
      final savedCode = prefs.getString('${CrewPresenceConstants.prefsCrewStatusKey}_$uid');
      if (savedCode != null) {
        _currentStatus = CrewPresenceStatus.fromCode(savedCode);
        notifyListeners();
      }

      // Check Firestore doc to ensure synchronization
      final doc = await _presenceRef(uid).get();
      if (doc.exists && doc.data() != null) {
        final remoteStatus = CrewPresenceStatus.fromCode(doc.data()!['status'] as String?);
        if (_currentStatus != remoteStatus) {
          _currentStatus = remoteStatus;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[CrewPresenceService] initializeStatus error: $e');
    }
  }

  /// Sets the crew availability status, persists locally, updates Firestore,
  /// and starts/stops presence publishing.
  Future<void> setCrewStatus(
    String uid,
    CrewPresenceStatus newStatus, {
    required Ambulance? ambulance,
    bool recordPrevious = true,
  }) async {
    final oldStatus = _currentStatus;

    if (recordPrevious && newStatus == CrewPresenceStatus.busy && oldStatus != CrewPresenceStatus.busy) {
      try {
        final prefs = _injectedPrefs ?? await SharedPreferences.getInstance();
        await prefs.setString(
          '${CrewPresenceConstants.prefsPreviousStatusKey}_$uid',
          oldStatus.code,
        );
      } catch (_) {}
    }

    _currentStatus = newStatus;
    notifyListeners();

    try {
      final prefs = _injectedPrefs ?? await SharedPreferences.getInstance();
      await prefs.setString(
        '${CrewPresenceConstants.prefsCrewStatusKey}_$uid',
        newStatus.code,
      );
    } catch (_) {}

    // Update Firestore presence doc
    try {
      final data = <String, dynamic>{
        if (ambulance?.ambulanceId != null) 'ambulanceId': ambulance!.ambulanceId,
        if (ambulance?.ais125Tier != null) 'ais125Tier': ambulance!.ais125Tier,
        'status': newStatus.code,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (newStatus == CrewPresenceStatus.offline) {
        data['lat'] = null;
        data['lng'] = null;
        data['accuracyMeters'] = null;
      }

      await _presenceRef(uid).set(data, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[CrewPresenceService] setCrewStatus Firestore error: $e');
    }

    // Manage presence publisher
    if (newStatus == CrewPresenceStatus.available) {
      await _startPresencePublisher(uid, ambulance);
    } else {
      _stopPresencePublisher();
    }
  }

  /// Restores the status saved prior to a BUSY transition (defaulting to AVAILABLE)
  Future<void> restorePreviousStatus(
    String uid, {
    required Ambulance? ambulance,
  }) async {
    CrewPresenceStatus targetStatus = CrewPresenceStatus.available;
    try {
      final prefs = _injectedPrefs ?? await SharedPreferences.getInstance();
      final prevCode = prefs.getString('${CrewPresenceConstants.prefsPreviousStatusKey}_$uid');
      if (prevCode != null) {
        targetStatus = CrewPresenceStatus.fromCode(prevCode);
      }
    } catch (_) {}

    await setCrewStatus(
      uid,
      targetStatus,
      ambulance: ambulance,
      recordPrevious: false,
    );
  }

  /// Starts throttled background location publishing for relief availability
  Future<void> _startPresencePublisher(String uid, Ambulance? ambulance) async {
    _stopPresencePublisher();

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _isLocationPermissionDenied = true;
        notifyListeners();
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _isLocationPermissionDenied = true;
        notifyListeners();
        return;
      }

      _isLocationPermissionDenied = false;
      _isPublishing = true;
      notifyListeners();

      // Fetch initial position immediately
      try {
        final initialPos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
        await publishPresencePoint(
          uid,
          ambulance: ambulance,
          position: initialPos,
          force: true,
        );
      } catch (e) {
        debugPrint('[CrewPresenceService] initial position fetch error: $e');
      }

      // Stream location with distance filter
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 150, // 150m moved threshold
      );

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (position) async {
          await publishPresencePoint(
            uid,
            ambulance: ambulance,
            position: position,
          );
        },
        onError: (err) {
          debugPrint('[CrewPresenceService] position stream error: $err');
        },
      );

      // Heartbeat timer every 30 seconds
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: CrewPresenceConstants.presencePublishIntervalSeconds),
        (_) async {
          if (_lastPublishedPosition != null) {
            await publishPresencePoint(
              uid,
              ambulance: ambulance,
              position: _lastPublishedPosition!,
              force: true,
            );
          } else {
            try {
              final pos = await Geolocator.getCurrentPosition();
              await publishPresencePoint(
                uid,
                ambulance: ambulance,
                position: pos,
                force: true,
              );
            } catch (_) {}
          }
        },
      );
    } catch (e) {
      debugPrint('[CrewPresenceService] _startPresencePublisher error: $e');
    }
  }

  /// Evaluates whether a new presence point should be committed to Firestore
  Future<void> publishPresencePoint(
    String uid, {
    required Ambulance? ambulance,
    required Position position,
    bool force = false,
  }) async {
    if (_currentStatus != CrewPresenceStatus.available) {
      return;
    }

    if (position.accuracy > CrewPresenceConstants.maxAcceptableAccuracyMeters) {
      debugPrint('[CrewPresenceService] Point dropped: accuracy ${position.accuracy}m > 100m');
      return;
    }

    final now = DateTime.now();

    if (!force && _lastPublishedPosition != null && _lastPublishedAt != null) {
      final elapsedSeconds = now.difference(_lastPublishedAt!).inSeconds;
      final distanceMoved = Geolocator.distanceBetween(
        _lastPublishedPosition!.latitude,
        _lastPublishedPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      if (elapsedSeconds < CrewPresenceConstants.presencePublishIntervalSeconds &&
          distanceMoved < CrewPresenceConstants.presenceMinDistanceMeters) {
        // Throttled: hasn't moved 150m and 30s haven't elapsed
        return;
      }
    }

    _lastPublishedPosition = position;
    _lastPublishedAt = now;

    try {
      await _presenceRef(uid).set({
        if (ambulance?.ambulanceId != null) 'ambulanceId': ambulance!.ambulanceId,
        if (ambulance?.ais125Tier != null) 'ais125Tier': ambulance!.ais125Tier,
        'status': CrewPresenceStatus.available.code,
        'lat': position.latitude,
        'lng': position.longitude,
        'accuracyMeters': position.accuracy,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[CrewPresenceService] publishPresencePoint error: $e');
    }
  }

  /// Stops streaming presence updates
  void _stopPresencePublisher() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _isPublishing = false;
    notifyListeners();
  }

  /// Live Firestore stream of a crew member's presence document
  Stream<CrewPresence?> streamCrewPresence(String uid) {
    if (uid.isEmpty) return Stream.value(null);
    return _presenceRef(uid).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return CrewPresence.fromJson(snap.data()!, snap.id);
    });
  }

  @override
  void dispose() {
    _stopPresencePublisher();
    super.dispose();
  }
}
