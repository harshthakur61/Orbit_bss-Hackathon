import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bedlink/models/bed_inventory.dart';
import 'package:bedlink/models/emergency_request.dart';
import 'package:bedlink/models/hospital.dart';

void main() {
  group('Phase 10A - FCM Reachability and Device Token Tests', () {
    Hospital createHospital({
      bool isNurseOnline = true,
      DateTime? lastNurseActive,
      bool hasActiveDevices = false,
      int icuAvailable = 5,
    }) {
      return Hospital(
        id: 'hosp_test_1',
        name: 'Test Memorial Hospital',
        lat: 19.05,
        lng: 72.83,
        phone: '1234567890',
        pin: '1234',
        loadLevel: 'low',
        isNurseOnline: isNurseOnline,
        lastNurseActive: lastNurseActive,
        hasActiveDevices: hasActiveDevices,
        beds: BedInventory(
          icu: BedCount(total: 10, available: icuAvailable),
          ventilator: const BedCount(total: 5, available: 2),
          oxygen: const BedCount(total: 15, available: 8),
          cardiac: const BedCount(total: 8, available: 3),
          burns: const BedCount(total: 4, available: 1),
          general: const BedCount(total: 20, available: 10),
        ),
      );
    }

    test('isReachable is true when nurse is online with fresh heartbeat (<90s)', () {
      final freshHospital = createHospital(
        isNurseOnline: true,
        lastNurseActive: DateTime.now().subtract(const Duration(seconds: 30)),
        hasActiveDevices: false,
      );
      expect(freshHospital.isReachable, isTrue);
    });

    test('isReachable is true when nurse is online with null lastNurseActive (default)', () {
      final defaultHospital = createHospital(
        isNurseOnline: true,
        lastNurseActive: null,
        hasActiveDevices: false,
      );
      expect(defaultHospital.isReachable, isTrue);
    });

    test('isReachable is true when nurse foreground heartbeat is offline/stale but active FCM device exists', () {
      final backgroundedNurseHospital = createHospital(
        isNurseOnline: false,
        lastNurseActive: DateTime.now().subtract(const Duration(minutes: 5)),
        hasActiveDevices: true,
      );
      expect(backgroundedNurseHospital.isReachable, isTrue);
    });

    test('isReachable is false when nurse is offline and no active FCM devices exist', () {
      final unreachableHospital = createHospital(
        isNurseOnline: false,
        lastNurseActive: null,
        hasActiveDevices: false,
      );
      expect(unreachableHospital.isReachable, isFalse);
    });

    test('isReachable is false when nurse heartbeat is stale (>90s) and no active FCM devices exist', () {
      final staleHospital = createHospital(
        isNurseOnline: true,
        lastNurseActive: DateTime.now().subtract(const Duration(seconds: 120)),
        hasActiveDevices: false,
      );
      expect(staleHospital.isReachable, isFalse);
    });

    test('Hospital serialization preserves hasActiveDevices flag', () {
      final hospital = createHospital(hasActiveDevices: true);
      final json = hospital.toJson();
      expect(json['hasActiveDevices'], isTrue);

      final deserialized = Hospital.fromJson(json, 'hosp_test_1');
      expect(deserialized.hasActiveDevices, isTrue);
      expect(deserialized.isReachable, isTrue);
    });

    test('EmergencyRequest.alertDeliveredAt roundtrip serialization', () {
      final deliveredTime = DateTime(2026, 10, 27, 18, 30, 0);
      final req = EmergencyRequest(
        id: 'req_test_ack',
        patientLat: 19.05,
        patientLng: 72.83,
        needs: ['ICU'],
        severity: 'critical',
        status: 'offered',
        rankedHospitalIds: ['hosp_test_1'],
        currentIndex: 0,
        currentHospitalId: 'hosp_test_1',
        attempts: const [],
        alertDeliveredAt: deliveredTime,
      );

      final json = req.toJson();
      expect(json['alertDeliveredAt'], isA<Timestamp>());
      expect((json['alertDeliveredAt'] as Timestamp).toDate(), deliveredTime);

      final restored = EmergencyRequest.fromJson(json, 'req_test_ack');
      expect(restored.alertDeliveredAt, deliveredTime);
    });

    test('EmergencyRequest.fromJson handles ISO string alertDeliveredAt', () {
      final rawMap = {
        'patientLat': 19.05,
        'patientLng': 72.83,
        'needs': ['ICU'],
        'severity': 'critical',
        'status': 'offered',
        'rankedHospitalIds': ['hosp_test_1'],
        'currentIndex': 0,
        'currentHospitalId': 'hosp_test_1',
        'attempts': [],
        'alertDeliveredAt': '2026-10-27T18:45:00.000Z',
      };

      final req = EmergencyRequest.fromJson(rawMap, 'req_str_ack');
      expect(req.alertDeliveredAt, isNotNull);
      expect(req.alertDeliveredAt!.toUtc().hour, 18);
      expect(req.alertDeliveredAt!.toUtc().minute, 45);
    });

    test('Auto-skip check triggers only when hospital is unreachable OR has 0 matching beds', () {
      // Case 1: Reachable via FCM background token with beds -> DO NOT AUTO-SKIP
      final reachableHospitalWithBeds = createHospital(
        isNurseOnline: false,
        hasActiveDevices: true,
        icuAvailable: 2,
      );
      final bool skip1 = !reachableHospitalWithBeds.isReachable ||
          reachableHospitalWithBeds.beds.getForType('ICU').available <= 0;
      expect(skip1, isFalse, reason: 'Must not auto-skip hospital reachable via FCM');

      // Case 2: Unreachable (no online nurse, no active FCM tokens) -> AUTO-SKIP
      final unreachableHospital = createHospital(
        isNurseOnline: false,
        hasActiveDevices: false,
        icuAvailable: 2,
      );
      final bool skip2 = !unreachableHospital.isReachable ||
          unreachableHospital.beds.getForType('ICU').available <= 0;
      expect(skip2, isTrue, reason: 'Must auto-skip unreachable hospital');

      // Case 3: Reachable but 0 matching beds -> AUTO-SKIP
      final reachableNoBeds = createHospital(
        isNurseOnline: true,
        hasActiveDevices: true,
        icuAvailable: 0,
      );
      final bool skip3 = !reachableNoBeds.isReachable ||
          reachableNoBeds.beds.getForType('ICU').available <= 0;
      expect(skip3, isTrue, reason: 'Must auto-skip hospital with 0 matching beds');
    });
  });
}
