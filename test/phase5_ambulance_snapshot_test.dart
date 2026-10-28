import 'package:flutter_test/flutter_test.dart';
import 'package:bedlink/models/emergency_request.dart';

void main() {
  group('Phase 5 - Ambulance Snapshot & Request Model Tests', () {
    test('AmbulanceSnapshot roundtrip serialization', () {
      final snapshot = const AmbulanceSnapshot(
        ambulanceId: 'BL-AMB-998877',
        vehicleNumber: 'MH02CD5678',
        driverName: 'Suresh Patil',
        driverPhone: '+919876543210',
        ambulanceType: 'Advanced Life Support (ALS)',
        ais125Tier: 'Type C',
      );

      final json = snapshot.toJson();
      expect(json['ambulanceId'], 'BL-AMB-998877');
      expect(json['vehicleNumber'], 'MH02CD5678');
      expect(json['driverName'], 'Suresh Patil');
      expect(json['driverPhone'], '+919876543210');
      expect(json['ambulanceType'], 'Advanced Life Support (ALS)');
      expect(json['ais125Tier'], 'Type C');

      final deserialized = AmbulanceSnapshot.fromJson(json);
      expect(deserialized.ambulanceId, snapshot.ambulanceId);
      expect(deserialized.vehicleNumber, snapshot.vehicleNumber);
      expect(deserialized.driverName, snapshot.driverName);
      expect(deserialized.driverPhone, snapshot.driverPhone);
      expect(deserialized.ambulanceType, snapshot.ambulanceType);
      expect(deserialized.ais125Tier, snapshot.ais125Tier);
    });

    test('Old legacy request without ambulance field does not crash fromJson', () {
      final legacyJson = <String, dynamic>{
        'patientLat': 19.0760,
        'patientLng': 72.8777,
        'needs': ['ICU Bed', 'Ventilator'],
        'severity': 'critical',
        'note': 'Severe respiratory distress',
        'status': 'offered',
        'rankedHospitalIds': ['hosp_1', 'hosp_2'],
        'currentIndex': 0,
        'currentHospitalId': 'hosp_1',
        'attempts': [],
      };

      final req = EmergencyRequest.fromJson(legacyJson, 'req_123');
      expect(req.id, 'req_123');
      expect(req.ambulance, isNull);
      expect(req.ambulanceLive, isNull);
      expect(req.crewUid, isNull);
      expect(req.severity, 'critical');
      expect(req.needs, contains('ICU Bed'));
    });

    test('EmergencyRequest with AmbulanceSnapshot serializes and deserializes cleanly', () {
      final req = EmergencyRequest(
        id: 'req_456',
        patientLat: 19.1234,
        patientLng: 72.8567,
        needs: ['Oxygen Bed'],
        severity: 'serious',
        status: 'offered',
        rankedHospitalIds: ['hosp_a'],
        currentIndex: 0,
        currentHospitalId: 'hosp_a',
        attempts: [],
        crewUid: 'crew_uid_001',
        ambulance: const AmbulanceSnapshot(
          ambulanceId: 'BL-AMB-100001',
          vehicleNumber: 'MH01AB1234',
          driverName: 'Vikram Singh',
          driverPhone: '+919123456789',
          ambulanceType: 'Basic Life Support (BLS)',
          ais125Tier: 'Type B',
        ),
        ambulanceLive: null,
      );

      final json = req.toJson();
      expect(json['crewUid'], 'crew_uid_001');
      expect(json['ambulance'], isNotNull);
      final ambMap = json['ambulance'] as Map<String, dynamic>;
      expect(ambMap['ambulanceId'], 'BL-AMB-100001');
      expect(ambMap['vehicleNumber'], 'MH01AB1234');
      expect(ambMap['driverName'], 'Vikram Singh');
      expect(ambMap['driverPhone'], '+919123456789');

      final reconstructed = EmergencyRequest.fromJson(json, 'req_456');
      expect(reconstructed.crewUid, 'crew_uid_001');
      expect(reconstructed.ambulance, isNotNull);
      expect(reconstructed.ambulance!.vehicleNumber, 'MH01AB1234');
      expect(reconstructed.ambulance!.driverName, 'Vikram Singh');
      expect(reconstructed.ambulanceLive, isNull);
    });

    test('AmbulanceLiveLocation placeholder serializes and deserializes without error', () {
      final live = AmbulanceLiveLocation(
        lat: 19.0500,
        lng: 72.8300,
        updatedAt: DateTime(2026, 10, 27, 18, 0),
      );

      final json = live.toJson();
      expect(json['lat'], 19.0500);
      expect(json['lng'], 72.8300);

      final parsed = AmbulanceLiveLocation.fromJson(json);
      expect(parsed.lat, 19.0500);
      expect(parsed.lng, 72.8300);
    });
  });
}
