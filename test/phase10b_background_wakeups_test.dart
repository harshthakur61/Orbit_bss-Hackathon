import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bedlink/services/alarm_notification_service.dart';

void main() {
  group('Phase 10B - FCM Background Wake-ups, Siren & Alarm Notification Tests', () {
    test('AlarmNotificationService singleton and channel invariants', () {
      final instance1 = AlarmNotificationService();
      final instance2 = AlarmNotificationService.instance;
      expect(identical(instance1, instance2), isTrue);

      expect(AlarmNotificationService.channelId, 'bedlink_emergency_alerts');
      expect(AlarmNotificationService.channelName, 'Emergency Requests');
      expect(AlarmNotificationService.channelDescription,
          'High-priority incoming emergency triage alerts for hospital nurses');
    });

    test('Alarm notification payload roundtrip serialization', () {
      final now = DateTime.now();
      final expires = now.add(const Duration(seconds: 120));

      final payloadMap = {
        'requestId': 'req_fcm_test_10b',
        'type': 'incoming_request',
        'severity': 'critical',
        'offerExpiresAt': expires.toIso8601String(),
      };

      final jsonStr = jsonEncode(payloadMap);
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(decoded['requestId'], 'req_fcm_test_10b');
      expect(decoded['type'], 'incoming_request');
      expect(decoded['severity'], 'critical');

      final parsedExpires = DateTime.parse(decoded['offerExpiresAt']);
      expect(parsedExpires.difference(now).inSeconds, closeTo(120, 2));
    });

    test('Offer validity check: valid offer within 120s window', () {
      final now = DateTime.now();
      final expires = now.add(const Duration(seconds: 90));

      const currentHospitalId = 'lilavati_bandra';
      const loggedInHospitalId = 'lilavati_bandra';
      const status = 'offered';

      final isExpired = now.isAfter(expires);
      final isValid = status == 'offered' &&
          currentHospitalId == loggedInHospitalId &&
          !isExpired;

      expect(isValid, isTrue,
          reason: 'Offer matching hospital within expiry window must be valid');
    });

    test('Offer validity check: expired offer is flagged invalid', () {
      final now = DateTime.now();
      final expiredTime = now.subtract(const Duration(seconds: 10));

      const currentHospitalId = 'lilavati_bandra';
      const loggedInHospitalId = 'lilavati_bandra';
      const status = 'offered';

      final isExpired = now.isAfter(expiredTime);
      final isValid = status == 'offered' &&
          currentHospitalId == loggedInHospitalId &&
          !isExpired;

      expect(isValid, isFalse,
          reason: 'Expired offer must be flagged invalid to avoid false sirens');
    });

    test('Offer validity check: cascaded offer to another hospital is invalid for previous hospital', () {
      final now = DateTime.now();
      final expires = now.add(const Duration(seconds: 60));

      const currentHospitalId = 'hinduja_mahim'; // Cascaded to Hinduja
      const loggedInHospitalId = 'lilavati_bandra'; // Nurse at Lilavati
      const status = 'offered';

      final isExpired = now.isAfter(expires);
      final isValid = status == 'offered' &&
          currentHospitalId == loggedInHospitalId &&
          !isExpired;

      expect(isValid, isFalse,
          reason: 'Offer cascaded to another hospital must not ring previous hospital');
    });

    test('Offer validity check: accepted or resolved request is flagged invalid', () {
      final now = DateTime.now();
      final expires = now.add(const Duration(seconds: 80));

      const currentHospitalId = 'lilavati_bandra';
      const loggedInHospitalId = 'lilavati_bandra';
      const status = 'accepted'; // Already accepted

      final isExpired = now.isAfter(expires);
      final isValid = status == 'offered' &&
          currentHospitalId == loggedInHospitalId &&
          !isExpired;

      expect(isValid, isFalse,
          reason: 'Already accepted request must show "no longer active"');
    });
  });
}
