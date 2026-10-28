import 'package:flutter_test/flutter_test.dart';
import 'package:bedlink/core/constants/crew_constants.dart';
import 'package:bedlink/models/ambulance.dart';

void main() {
  group('Ambulance Client Security & Immutability Tests', () {
    test('kCrewDefaultTab is configured to 1 (Dispatch Tab)', () {
      expect(kCrewDefaultTab, 1);
    });

    test('kAis125Tiers has valid standard types', () {
      expect(kAis125Tiers.length, 4);
      final codes = kAis125Tiers.map((t) => t.code).toList();
      expect(codes, containsAll(['TYPE_A', 'TYPE_B', 'TYPE_C', 'TYPE_D']));
    });

    test('toCrewMutableUpdateJson contains ONLY the allowed mutable keys in firestore.rules', () {
      const allowedKeys = {'ais125Tier', 'ambulanceType', 'contactNumber'};

      const ambulance = Ambulance(
        uid: 'test_uid',
        applicationRef: 'APP-123456',
        ambulanceId: 'BL-AMB-100001',
        verificationStatus: AmbulanceVerificationStatus.verified,
        vehicleNumber: 'MH04AB1234',
        driverLegalName: 'Ramesh Kumar',
        ais125Tier: 'TYPE_C',
        ambulanceType: 'GOVERNMENT',
        contactNumber: '+919876543210',
      );

      final updatePayload = ambulance.toCrewMutableUpdateJson();

      // Check all keys in payload are strictly permitted
      expect(updatePayload.keys.toSet().difference(allowedKeys), isEmpty);

      // Verify no immutable field leaked into update payload
      expect(updatePayload.containsKey('ambulanceId'), isFalse);
      expect(updatePayload.containsKey('vehicleNumber'), isFalse);
      expect(updatePayload.containsKey('verificationStatus'), isFalse);
      expect(updatePayload.containsKey('driverLegalName'), isFalse);
      expect(updatePayload.containsKey('dob'), isFalse);
      expect(updatePayload.containsKey('dlNumber'), isFalse);
      expect(updatePayload.containsKey('verifiedAt'), isFalse);
    });

    test('Indian mobile number validation regex matches valid 10-digit formats', () {
      final regex = RegExp(r'^(?:\+91)?[6-9]\d{9}$');

      expect(regex.hasMatch('9876543210'), isTrue);
      expect(regex.hasMatch('+919876543210'), isTrue);
      expect(regex.hasMatch('7012345678'), isTrue);

      // Invalid formats
      expect(regex.hasMatch('1234567890'), isFalse); // Starts with 1
      expect(regex.hasMatch('98765'), isFalse); // Too short
      expect(regex.hasMatch('98765432100'), isFalse); // Too long
    });
  });
}
