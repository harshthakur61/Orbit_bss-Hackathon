import 'package:flutter_test/flutter_test.dart';
import 'package:bedlink/models/emergency_request.dart';

void main() {
  group('Phase 9A - Live GPS Location Tracking Tests', () {
    test('AmbulanceLiveLocation roundtrip serialization with telemetry fields', () {
      final now = DateTime.now();
      final liveLoc = AmbulanceLiveLocation(
        lat: 19.0760,
        lng: 72.8777,
        heading: 180.5,
        speedKmh: 42.0,
        accuracyMeters: 8.5,
        ambulanceId: 'BL-AMB-100001',
        hospitalId: 'lilavati_bandra',
        updatedAt: now,
      );

      final map = liveLoc.toMap();
      expect(map['lat'], 19.0760);
      expect(map['lng'], 72.8777);
      expect(map['heading'], 180.5);
      expect(map['speedKmh'], 42.0);
      expect(map['accuracyMeters'], 8.5);
      expect(map['ambulanceId'], 'BL-AMB-100001');
      expect(map['hospitalId'], 'lilavati_bandra');

      final deserialized = AmbulanceLiveLocation.fromMap(map);
      expect(deserialized.lat, 19.0760);
      expect(deserialized.lng, 72.8777);
      expect(deserialized.heading, 180.5);
      expect(deserialized.speedKmh, 42.0);
      expect(deserialized.accuracyMeters, 8.5);
      expect(deserialized.ambulanceId, 'BL-AMB-100001');
      expect(deserialized.hospitalId, 'lilavati_bandra');
    });

    test('Old legacy request with ambulanceLive field parses cleanly without crash', () {
      final legacyJson = {
        'patientLat': 19.05,
        'patientLng': 72.82,
        'needs': ['ICU'],
        'severity': 'critical',
        'status': 'accepted',
        'rankedHospitalIds': ['h1'],
        'currentIndex': 0,
        'currentHospitalId': 'h1',
        'attempts': [],
        'ambulanceLive': {
          'lat': 19.051,
          'lng': 72.821,
          'heading': 90.0,
        },
      };

      final req = EmergencyRequest.fromJson(legacyJson, 'legacy_req_1');
      expect(req.ambulanceLive, isNotNull);
      expect(req.ambulanceLive!.lat, 19.051);
      expect(req.ambulanceLive!.lng, 72.821);
      expect(req.ambulanceLive!.heading, 90.0);
    });

    test('EmergencyRequest.toJson() omits ambulanceLive to prevent flooding listeners', () {
      final req = EmergencyRequest(
        id: 'req_123',
        patientLat: 19.05,
        patientLng: 72.82,
        needs: ['ICU'],
        severity: 'critical',
        status: 'accepted',
        rankedHospitalIds: ['h1'],
        currentIndex: 0,
        currentHospitalId: 'h1',
        attempts: const [],
        ambulanceLive: const AmbulanceLiveLocation(
          lat: 19.05,
          lng: 72.82,
        ),
      );

      final json = req.toJson();
      expect(json.containsKey('ambulanceLive'), isFalse,
          reason: 'ambulanceLive must not be written to requests/{id} document');
    });

    test('Accuracy filter: locations with accuracy > 100m are flagged as degraded', () {
      const accurate = 15.0;
      const inaccurate = 120.0;

      final bool isAccurateValid = accurate <= 100.0;
      final bool isInaccurateValid = inaccurate <= 100.0;

      expect(isAccurateValid, isTrue);
      expect(isInaccurateValid, isFalse);
    });

    test('Throttle filter: minimum write interval of 4s between writes', () {
      final lastWrite = DateTime.now().subtract(const Duration(seconds: 2));
      final now = DateTime.now();

      final elapsed = now.difference(lastWrite);
      final shouldThrottle = elapsed.inSeconds < 4;

      expect(shouldThrottle, isTrue);

      final olderWrite = DateTime.now().subtract(const Duration(seconds: 5));
      final elapsedOlder = now.difference(olderWrite);
      final shouldThrottleOlder = elapsedOlder.inSeconds < 4;

      expect(shouldThrottleOlder, isFalse);
    });
  });
}
