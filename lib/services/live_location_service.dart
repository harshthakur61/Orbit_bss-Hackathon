import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/emergency_request.dart';

class LiveLocationService extends ChangeNotifier {
  final FirebaseFirestore? _injectedFirestore;

  LiveLocationService({FirebaseFirestore? firestore})
      : _injectedFirestore = firestore;

  FirebaseFirestore get _firestore => _injectedFirestore ?? FirebaseFirestore.instance;

  bool _isPublishing = false;
  bool _isPermissionDenied = false;
  bool _isLocationServiceDisabled = false;
  String? _activeRequestId;
  String? _activeHospitalId;
  String? _activeAmbulanceId;
  String? _activeDocId;
  String? _activeReliefRequestId;
  AmbulanceLiveLocation? _lastPublishedLocation;
  DateTime? _lastWriteTime;
  Position? _lastObservedPosition;
  double _lastGoodHeading = 0.0;

  // Debug Route Simulation State
  bool _isSimulating = false;
  double _simulationSpeedMultiplier = 1.0;
  Timer? _simulationTimer;
  List<LatLng> _simulationRoutePoints = [];
  int _simulationCurrentIndex = 0;

  StreamSubscription<Position>? _positionSubscription;
  Timer? _heartbeatTimer;

  bool get isPublishing => _isPublishing;
  bool get isPermissionDenied => _isPermissionDenied;
  bool get isLocationServiceDisabled => _isLocationServiceDisabled;
  bool get isSimulating => _isSimulating;
  double get simulationSpeedMultiplier => _simulationSpeedMultiplier;
  String? get activeRequestId => _activeRequestId;
  String? get activeHospitalId => _activeHospitalId;
  String? get activeAmbulanceId => _activeAmbulanceId;
  AmbulanceLiveLocation? get lastPublishedLocation => _lastPublishedLocation;
  DateTime? get lastWriteTime => _lastWriteTime;
  double get lastGoodHeading => _lastGoodHeading;

  /// Check permissions and return true if granted
  Future<bool> checkAndRequestPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _isLocationServiceDisabled = true;
        notifyListeners();
        return false;
      }
      _isLocationServiceDisabled = false;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _isPermissionDenied = true;
        notifyListeners();
        return false;
      }

      _isPermissionDenied = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[LiveLocationService] Permission check error: $e');
      return false;
    }
  }

  /// Start streaming position to `liveLocations/{requestId}` (or `customDocId` if specified)
  /// Only call when request is `accepted` or `en_route`.
  Future<void> startPublishing({
    required String requestId,
    required String hospitalId,
    required String ambulanceId,
    String? customDocId,
    String? reliefRequestId,
  }) async {
    final targetDocId = customDocId ?? requestId;

    // If already active on the same request/docId
    if (_isPublishing && _activeRequestId == requestId && _activeDocId == targetDocId) {
      if (_activeHospitalId != hospitalId) {
        await updateHospitalId(hospitalId);
      }
      return;
    }

    // Stop existing session if switching requests
    if (_isPublishing && (_activeRequestId != requestId || _activeDocId != targetDocId)) {
      await stopPublishing(deleteDoc: false);
    }

    _activeRequestId = requestId;
    _activeHospitalId = hospitalId;
    _activeAmbulanceId = ambulanceId;
    _activeDocId = targetDocId;
    _activeReliefRequestId = reliefRequestId;

    final hasPermission = await checkAndRequestPermission();
    if (!hasPermission) {
      debugPrint('[LiveLocationService] Cannot start publishing: Permission denied or service off');
      return;
    }

    _isPublishing = true;
    notifyListeners();

    // Setup platform specific location settings (Foreground service for Android)
    late LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
        intervalDuration: const Duration(seconds: 4),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'BedLink – sharing location with hospital',
          notificationText: 'Ambulance location is updating in real time',
          enableWakeLock: true,
          notificationIcon: AndroidResource(name: 'ic_launcher'),
        ),
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      );
    }

    // Cancel existing stream if any
    await _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) => _handlePositionUpdate(position),
      onError: (err) {
        debugPrint('[LiveLocationService] Position stream error: $err');
      },
    );

    // Initial immediate fetch
    try {
      final initialPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      _handlePositionUpdate(initialPosition, isImmediate: true);
    } catch (_) {}

    // 15-second heartbeat timer: ensures nurse sees live heartbeat even when stopped in traffic
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (!_isPublishing || _isSimulating) {
        if (!_isPublishing) timer.cancel();
        return;
      }
      if (_lastObservedPosition != null) {
        final elapsed = _lastWriteTime == null
            ? const Duration(seconds: 999)
            : DateTime.now().difference(_lastWriteTime!);
        if (elapsed.inSeconds >= 14) {
          _handlePositionUpdate(_lastObservedPosition!, isImmediate: true);
        }
      }
    });
  }

  void _handlePositionUpdate(Position position, {bool isImmediate = false}) {
    if (_isSimulating) return; // Do not override active simulation

    // 1. Skip if accuracy worse than ~100m
    if (position.accuracy > 100.0) {
      return;
    }

    _lastObservedPosition = position;

    // 2. Throttle: minimum interval of ~4s between writes unless immediate first write
    final now = DateTime.now();
    if (!isImmediate && _lastWriteTime != null) {
      final diff = now.difference(_lastWriteTime!);
      if (diff.inSeconds < 4) {
        return;
      }
    }

    final speedKmh = position.speed > 0 ? (position.speed * 3.6) : 0.0;
    double heading = position.heading;

    // GPS jitter at stoplights: ignore heading when speed < ~2 km/h and keep last good heading
    if (speedKmh < 2.0 && _lastGoodHeading > 0) {
      heading = _lastGoodHeading;
    } else if (heading >= 0) {
      _lastGoodHeading = heading;
    }

    _writeRawLocation(
      lat: position.latitude,
      lng: position.longitude,
      heading: heading,
      speedKmh: speedKmh,
      accuracyMeters: position.accuracy,
    );
  }

  /// Unified location publisher: writes telemetry payload to `liveLocations/{requestId}`
  Future<void> _writeRawLocation({
    required double lat,
    required double lng,
    required double heading,
    required double speedKmh,
    required double accuracyMeters,
  }) async {
    final targetDoc = _activeDocId ?? _activeRequestId;
    if (targetDoc == null || (!_isPublishing && !_isSimulating)) return;

    final liveLoc = AmbulanceLiveLocation(
      lat: lat,
      lng: lng,
      heading: heading,
      speedKmh: speedKmh,
      accuracyMeters: accuracyMeters,
      ambulanceId: _activeAmbulanceId,
      hospitalId: _activeHospitalId,
      updatedAt: DateTime.now(),
    );

    final Map<String, dynamic> docData = {
      'lat': lat,
      'lng': lng,
      'heading': heading,
      'speedKmh': speedKmh,
      'accuracyMeters': accuracyMeters,
      'ambulanceId': _activeAmbulanceId,
      'hospitalId': _activeHospitalId,
      'updatedAt': FieldValue.serverTimestamp(),
      if (_activeReliefRequestId != null) 'reliefRequestId': _activeReliefRequestId,
    };

    try {
      await _firestore
          .collection('liveLocations')
          .doc(targetDoc)
          .set(docData, SetOptions(merge: true));

      _lastWriteTime = DateTime.now();
      _lastPublishedLocation = liveLoc;
      notifyListeners();
    } catch (e) {
      debugPrint('[LiveLocationService] Failed to write location: $e');
    }
  }

  // -------------------------------------------------------------
  // DEBUG ROUTE SIMULATOR (Debug/Demo Builds)
  // Replays positions along the OSRM route to the hospital.
  // -------------------------------------------------------------

  /// Start replaying positions along [routePoints] at an adjustable speed.
  Future<void> startSimulation({
    required String requestId,
    required String hospitalId,
    required String ambulanceId,
    required List<LatLng> routePoints,
    double speedMultiplier = 1.0,
  }) async {
    if (routePoints.isEmpty) return;

    // Pause real GPS stream if running
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    _activeRequestId = requestId;
    _activeHospitalId = hospitalId;
    _activeAmbulanceId = ambulanceId;
    _simulationRoutePoints = List.from(routePoints);
    _simulationCurrentIndex = 0;
    _simulationSpeedMultiplier = speedMultiplier.clamp(0.5, 8.0);
    _isSimulating = true;
    _isPublishing = true;
    notifyListeners();

    // Publish initial point immediately
    final firstPoint = _simulationRoutePoints.first;
    double initialHeading = 0.0;
    if (_simulationRoutePoints.length > 1) {
      initialHeading = calculateBearing(
        firstPoint.latitude,
        firstPoint.longitude,
        _simulationRoutePoints[1].latitude,
        _simulationRoutePoints[1].longitude,
      );
    }
    _lastGoodHeading = initialHeading;

    await _writeRawLocation(
      lat: firstPoint.latitude,
      lng: firstPoint.longitude,
      heading: initialHeading,
      speedKmh: 35.0 * _simulationSpeedMultiplier,
      accuracyMeters: 4.0,
    );

    // Tick every 2 seconds
    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _tickSimulation();
    });
  }

  /// Change simulation playback speed (e.g. 1.0x, 2.0x, 4.0x)
  void setSimulationSpeedMultiplier(double mult) {
    _simulationSpeedMultiplier = mult.clamp(0.5, 8.0);
    notifyListeners();
  }

  void _tickSimulation() {
    if (!_isSimulating || _simulationRoutePoints.isEmpty) {
      _simulationTimer?.cancel();
      return;
    }

    // Advance along route geometry based on speed multiplier
    final step = (_simulationSpeedMultiplier).round().clamp(1, 4);
    _simulationCurrentIndex += step;

    if (_simulationCurrentIndex >= _simulationRoutePoints.length - 1) {
      // Reached hospital destination
      final lastPoint = _simulationRoutePoints.last;
      _writeRawLocation(
        lat: lastPoint.latitude,
        lng: lastPoint.longitude,
        heading: _lastGoodHeading,
        speedKmh: 0.0,
        accuracyMeters: 3.0,
      );
      stopSimulation();
      return;
    }

    final curr = _simulationRoutePoints[_simulationCurrentIndex];
    final next = _simulationRoutePoints[
        math.min(_simulationCurrentIndex + 1, _simulationRoutePoints.length - 1)];

    final heading = calculateBearing(
      curr.latitude,
      curr.longitude,
      next.latitude,
      next.longitude,
    );
    _lastGoodHeading = heading;

    _writeRawLocation(
      lat: curr.latitude,
      lng: curr.longitude,
      heading: heading,
      speedKmh: 42.0 * _simulationSpeedMultiplier,
      accuracyMeters: 4.5,
    );
  }

  /// Stop simulation without deleting the doc
  void stopSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _isSimulating = false;
    _simulationRoutePoints = [];
    _simulationCurrentIndex = 0;
    notifyListeners();
  }

  /// Calculates initial bearing in degrees between two GPS points
  static double calculateBearing(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    final phi1 = startLat * (math.pi / 180.0);
    final phi2 = endLat * (math.pi / 180.0);
    final deltaLambda = (endLng - startLng) * (math.pi / 180.0);

    final y = math.sin(deltaLambda) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);
    final theta = math.atan2(y, x);
    return (theta * (180.0 / math.pi) + 360.0) % 360.0;
  }

  /// Update hospitalId when cascading to another hospital
  Future<void> updateHospitalId(String newHospitalId) async {
    _activeHospitalId = newHospitalId;
    final reqId = _activeRequestId;
    if (reqId == null || (!_isPublishing && !_isSimulating)) return;

    try {
      await _firestore.collection('liveLocations').doc(reqId).set({
        'hospitalId': newHospitalId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      notifyListeners();
    } catch (e) {
      debugPrint('[LiveLocationService] Failed to update hospitalId: $e');
    }
  }

  /// Stop publishing. Deletes `liveLocations/{docId}` if [deleteDoc] is true (e.g. on arrival or cancellation).
  Future<void> stopPublishing({bool deleteDoc = false}) async {
    stopSimulation();

    final targetDoc = _activeDocId ?? _activeRequestId;
    _isPublishing = false;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _lastObservedPosition = null;

    if (deleteDoc && targetDoc != null) {
      try {
        await _firestore.collection('liveLocations').doc(targetDoc).delete();
      } catch (e) {
        debugPrint('[LiveLocationService] Failed to delete liveLocation doc: $e');
      }
    }

    _activeRequestId = null;
    _activeHospitalId = null;
    _activeAmbulanceId = null;
    _activeDocId = null;
    _activeReliefRequestId = null;
    _lastPublishedLocation = null;
    _lastWriteTime = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stopPublishing(deleteDoc: false);
    super.dispose();
  }
}
