import 'package:flutter_test/flutter_test.dart';
import 'package:bedlink/models/emergency_request.dart';

void main() {
  group('Phase 12B - EmergencyRequest Relief Fields & Backward Compatibility', () {
    test('serializes and deserializes reliefState and reliefRequestId correctly', () {
      final req = EmergencyRequest(
        id: 'req_123',
        patientLat: 19.0760,
        patientLng: 72.8777,
        needs: ['ICU', 'Ventilator'],
        severity: 'critical',
        status: 'accepted',
        rankedHospitalIds: ['hosp_1', 'hosp_2'],
        currentIndex: 0,
        currentHospitalId: 'hosp_1',
        attempts: [],
        reliefState: 'searching',
        reliefRequestId: 'relief_xyz_789',
      );

      final json = req.toJson();
      expect(json['reliefState'], 'searching');
      expect(json['reliefRequestId'], 'relief_xyz_789');

      final parsed = EmergencyRequest.fromJson(json, 'req_123');
      expect(parsed.reliefState, 'searching');
      expect(parsed.reliefRequestId, 'relief_xyz_789');
    });

    test('backward compatibility: null-safe when relief fields are absent in legacy requests', () {
      final legacyJson = {
        'patientLat': 19.0760,
        'patientLng': 72.8777,
        'needs': ['ICU'],
        'severity': 'serious',
        'status': 'accepted',
        'rankedHospitalIds': ['hosp_1'],
        'currentIndex': 0,
        'currentHospitalId': 'hosp_1',
        'attempts': [],
      };

      final parsed = EmergencyRequest.fromJson(legacyJson, 'legacy_req');
      expect(parsed.reliefState, isNull);
      expect(parsed.reliefRequestId, isNull);
      expect(parsed.status, 'accepted');
    });

    test('copyWith updates reliefState and reliefRequestId cleanly', () {
      final req = EmergencyRequest(
        id: 'req_123',
        patientLat: 19.0760,
        patientLng: 72.8777,
        needs: ['ICU'],
        severity: 'serious',
        status: 'accepted',
        rankedHospitalIds: ['hosp_1'],
        currentIndex: 0,
        currentHospitalId: 'hosp_1',
        attempts: [],
      );

      final searchingReq = req.copyWith(
        reliefState: 'searching',
        reliefRequestId: 'rel_1',
      );
      expect(searchingReq.reliefState, 'searching');
      expect(searchingReq.reliefRequestId, 'rel_1');

      final acceptedReq = searchingReq.copyWith(
        reliefState: 'accepted',
      );
      expect(acceptedReq.reliefState, 'accepted');
      expect(acceptedReq.reliefRequestId, 'rel_1');

      final completedReq = acceptedReq.copyWith(
        reliefState: 'completed',
      );
      expect(completedReq.reliefState, 'completed');
      expect(completedReq.reliefRequestId, 'rel_1');
    });
  });
}
