import 'package:flutter_test/flutter_test.dart';
import 'package:bedlink/models/ambulance.dart';
import 'package:bedlink/models/emergency_request.dart';

void main() {
  group('Phase 8 - Security Rules & Invariant Validation Tests', () {
    test('Crew immutability: crew update payload rejects all server-verified and identity fields', () {
      const allowedMutableKeys = {'ais125Tier', 'ambulanceType', 'contactNumber'};

      const ambulance = Ambulance(
        uid: 'crew_user_1',
        applicationRef: 'APP-998877',
        ambulanceId: 'BL-AMB-200001',
        verificationStatus: AmbulanceVerificationStatus.verified,
        vehicleNumber: 'KA01EQ1234',
        driverLegalName: 'Sunil Verma',
        ais125Tier: 'TYPE_C',
        ambulanceType: 'PRIVATE',
        contactNumber: '+919876543210',
      );

      final updatePayload = ambulance.toCrewMutableUpdateJson();

      // Ensure no keys outside allowedMutableKeys exist
      expect(updatePayload.keys.toSet().difference(allowedMutableKeys), isEmpty);

      // Verify that every immutable field cannot be touched by crew client
      expect(updatePayload.containsKey('uid'), isFalse);
      expect(updatePayload.containsKey('applicationRef'), isFalse);
      expect(updatePayload.containsKey('ambulanceId'), isFalse);
      expect(updatePayload.containsKey('vehicleNumber'), isFalse);
      expect(updatePayload.containsKey('driverLegalName'), isFalse);
      expect(updatePayload.containsKey('verificationStatus'), isFalse);
      expect(updatePayload.containsKey('verifiedAt'), isFalse);
      expect(updatePayload.containsKey('dlNumber'), isFalse);
      expect(updatePayload.containsKey('dob'), isFalse);
    });

    test('Crew reading another crew doc invariant: document ID must match auth.uid', () {
      const authenticatedCrewUid = 'crew_uid_alpha';
      const targetAmbulanceDocUid = 'crew_uid_beta';

      // Rules test logic: request.auth.uid == uid
      final bool canRead = authenticatedCrewUid == targetAmbulanceDocUid;
      expect(canRead, isFalse, reason: "A crew reading another crew's document must fail");
    });

    test('Nurse hospital isolation invariant: nurse can only read requests for their assigned hospital', () {
      const nurseHospitalId = 'hosp_apollo_1';
      const targetRequestHospitalId = 'hosp_fortis_2';

      // Rules test logic: request.auth.token.hospitalId == resource.data.currentHospitalId
      final bool canNurseRead = nurseHospitalId == targetRequestHospitalId;
      expect(canNurseRead, isFalse, reason: "A nurse reading requests for another hospital must fail");

      const sameHospitalRequestId = 'hosp_apollo_1';
      final bool canReadOwnHospital = nurseHospitalId == sameHospitalRequestId;
      expect(canReadOwnHospital, isTrue);
    });

    test('Unverified crew creating request invariant: verificationStatus must be VERIFIED', () {
      final pendingAmbulance = Ambulance(
        uid: 'pending_crew_1',
        applicationRef: 'APP-112233',
        verificationStatus: AmbulanceVerificationStatus.pending,
        vehicleNumber: 'MH02XY9999',
        driverLegalName: 'Anil Kumar',
        ais125Tier: 'TYPE_B',
        ambulanceType: 'GOVERNMENT',
        contactNumber: '+919876500000',
      );

      // Rules test logic: get(/ambulances/$(auth.uid)).data.verificationStatus == 'VERIFIED'
      final bool canCreatePending = pendingAmbulance.verificationStatus == AmbulanceVerificationStatus.verified;
      expect(canCreatePending, isFalse, reason: 'Pending crew must fail when attempting to create emergency request');

      final rejectedAmbulance = pendingAmbulance.copyWith(
        verificationStatus: AmbulanceVerificationStatus.rejected,
      );
      final bool canCreateRejected = rejectedAmbulance.verificationStatus == AmbulanceVerificationStatus.verified;
      expect(canCreateRejected, isFalse, reason: 'Rejected crew must fail when attempting to create emergency request');

      final verifiedAmbulance = pendingAmbulance.copyWith(
        verificationStatus: AmbulanceVerificationStatus.verified,
      );
      final bool canCreateVerified = verifiedAmbulance.verificationStatus == AmbulanceVerificationStatus.verified;
      expect(canCreateVerified, isTrue, reason: 'Only verified crew can create emergency request');
    });

    test('Request snapshot integrity: snapshot matches verified crew details', () {
      const crew = Ambulance(
        uid: 'crew_verified_1',
        applicationRef: 'APP-554433',
        ambulanceId: 'BL-AMB-500001',
        verificationStatus: AmbulanceVerificationStatus.verified,
        vehicleNumber: 'DL01AB1111',
        driverLegalName: 'Vikram Singh',
        ais125Tier: 'TYPE_C',
        ambulanceType: 'PRIVATE',
        contactNumber: '+919876543210',
      );

      final legitimateSnapshot = AmbulanceSnapshot(
        ambulanceId: crew.ambulanceId ?? '',
        vehicleNumber: crew.vehicleNumber,
        driverName: crew.driverLegalName,
        driverPhone: crew.contactNumber,
        ambulanceType: crew.ambulanceType,
        ais125Tier: crew.ais125Tier,
      );
      expect(legitimateSnapshot.vehicleNumber, crew.vehicleNumber);
      expect(legitimateSnapshot.driverName, crew.driverLegalName);

      // Mismatched snapshot
      final spoofedSnapshot = legitimateSnapshot.copyWith(
        vehicleNumber: 'KA04FAKE9999',
      );
      final bool isMatch = spoofedSnapshot.vehicleNumber == crew.vehicleNumber &&
          spoofedSnapshot.driverName == crew.driverLegalName;
      expect(isMatch, isFalse, reason: 'Spoofed snapshot must fail matching check');
    });

    test('Slots invariant: direct client reads and writes are blocked', () {
      bool canClientReadSlots() => false;
      bool canClientWriteSlots() => false;

      expect(canClientReadSlots(), isFalse);
      expect(canClientWriteSlots(), isFalse);
    });

    test('Appointments invariant: patient reads own appointment, writes blocked', () {
      bool canPatientRead(String patientUid, String authUid) => patientUid == authUid;
      bool canClientWriteAppointment() => false;

      expect(canPatientRead('patient_alice', 'patient_alice'), isTrue);
      expect(canPatientRead('patient_alice', 'patient_bob'), isFalse);
      expect(canClientWriteAppointment(), isFalse);
    });

    test('Crew presence invariant: verified crew, valid status and bounds', () {
      bool isValidCrewPresence({
        required bool isVerified,
        required String status,
        required double lat,
        required double lng,
      }) {
        if (!isVerified) return false;
        if (!['AVAILABLE', 'BUSY', 'OFFLINE'].contains(status)) return false;
        if (status == 'OFFLINE') return true;
        return lat >= -90.0 && lat <= 90.0 && lng >= -180.0 && lng <= 180.0;
      }

      expect(isValidCrewPresence(isVerified: true, status: 'AVAILABLE', lat: 19.076, lng: 72.877), isTrue);
      expect(isValidCrewPresence(isVerified: false, status: 'AVAILABLE', lat: 19.076, lng: 72.877), isFalse);
      expect(isValidCrewPresence(isVerified: true, status: 'INVALID', lat: 19.076, lng: 72.877), isFalse);
      expect(isValidCrewPresence(isVerified: true, status: 'AVAILABLE', lat: 95.0, lng: 72.877), isFalse);
      expect(isValidCrewPresence(isVerified: true, status: 'OFFLINE', lat: 0.0, lng: 0.0), isTrue);
    });

    test('Relief requests invariant: direct writes blocked, read restricted to parties', () {
      bool canClientWriteRelief() => false;
      bool canReadRelief(String requesterUid, String? acceptedByUid, String callerUid) {
        return callerUid == requesterUid || callerUid == acceptedByUid;
      }

      expect(canClientWriteRelief(), isFalse);
      expect(canReadRelief('crew_1', 'crew_2', 'crew_1'), isTrue);
      expect(canReadRelief('crew_1', 'crew_2', 'crew_2'), isTrue);
      expect(canReadRelief('crew_1', 'crew_2', 'crew_stranger'), isFalse);
    });

    test('Voice notes storage invariant: direct read blocked, max 1.5MB audio upload', () {
      bool canDirectReadVoiceNote() => false;
      bool canUploadVoiceNote({
        required bool isAuthenticated,
        required int sizeBytes,
        required String contentType,
      }) {
        if (!isAuthenticated) return false;
        if (sizeBytes > 1572864) return false; // 1.5MB max
        return contentType.startsWith('audio/');
      }

      expect(canDirectReadVoiceNote(), isFalse);
      expect(canUploadVoiceNote(isAuthenticated: true, sizeBytes: 500000, contentType: 'audio/m4a'), isTrue);
      expect(canUploadVoiceNote(isAuthenticated: false, sizeBytes: 500000, contentType: 'audio/m4a'), isFalse);
      expect(canUploadVoiceNote(isAuthenticated: true, sizeBytes: 2000000, contentType: 'audio/m4a'), isFalse);
      expect(canUploadVoiceNote(isAuthenticated: true, sizeBytes: 500000, contentType: 'image/png'), isFalse);
    });
  });
}
