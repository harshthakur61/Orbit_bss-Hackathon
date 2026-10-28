import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ambulance.dart';
import '../core/constants/crew_presence_constants.dart';
import '../services/ambulance_auth_service.dart';
import '../services/fcm_service.dart';
import '../services/crew_presence_service.dart';
import 'crew_presence_providers.dart';
import 'location_providers.dart';

final ambulanceAuthServiceProvider = Provider<AmbulanceAuthService>((ref) {
  return AmbulanceAuthService();
});

/// Stream of raw Firebase Auth User state
final ambulanceAuthStateProvider = StreamProvider<User?>((ref) {
  final service = ref.watch(ambulanceAuthServiceProvider);
  return service.authStateChanges;
});

/// Stream of the current Ambulance Firestore document for the signed-in crew member
final currentAmbulanceProvider = StreamProvider<Ambulance?>((ref) {
  final authUserAsync = ref.watch(ambulanceAuthStateProvider);
  final service = ref.watch(ambulanceAuthServiceProvider);

  return authUserAsync.when(
    data: (user) {
      final uid = user?.uid ?? AmbulanceAuthService.currentSessionUid;
      if (uid == null) return Stream.value(null);
      return service.streamAmbulance(uid);
    },
    loading: () {
      final uid = AmbulanceAuthService.currentSessionUid;
      if (uid != null) return service.streamAmbulance(uid);
      return Stream.value(null);
    },
    error: (err, stack) {
      final uid = AmbulanceAuthService.currentSessionUid;
      if (uid != null) return service.streamAmbulance(uid);
      return Stream.value(null);
    },
  );
});

/// Stream of current Verification Status (PENDING, VERIFIED, REJECTED, NEEDS_REVIEW)
final ambulanceVerificationStatusProvider =
    Provider<AmbulanceVerificationStatus>((ref) {
  final ambulanceAsync = ref.watch(currentAmbulanceProvider);

  return ambulanceAsync.maybeWhen(
    data: (amb) => amb?.verificationStatus ?? AmbulanceVerificationStatus.pending,
    orElse: () => AmbulanceVerificationStatus.pending,
  );
});

/// Helper controller for crew auth actions
class AmbulanceAuthController {
  final AmbulanceAuthService _service;
  final FcmService? _fcmService;
  final CrewPresenceService? _presenceService;

  AmbulanceAuthController(this._service, [this._fcmService, this._presenceService]);

  Future<UserCredential?> signIn({
    required String applicationRef,
    required String password,
  }) async {
    final cred = await _service.signIn(
      applicationRef: applicationRef,
      password: password,
    );
    final uid = AmbulanceAuthService.currentSessionUid;
    if (uid != null && _fcmService != null) {
      await _fcmService.registerCrewDevice(uid);
    }
    return cred;
  }

  Future<RegistrationResult> submitRegistration({
    required String vehicleNumber,
    String? chassisEngineNumber,
    String? rcPhotoStoragePath,
    required String driverLegalName,
    required String dlNumber,
    required String dob,
    required String contactNumber,
    required String password,
    String ais125Tier = 'TYPE_B',
    String ambulanceType = 'PRIVATE',
  }) {
    return _service.submitAmbulanceRegistration(
      vehicleNumber: vehicleNumber,
      chassisEngineNumber: chassisEngineNumber,
      rcPhotoStoragePath: rcPhotoStoragePath,
      driverLegalName: driverLegalName,
      dlNumber: dlNumber,
      dob: dob,
      contactNumber: contactNumber,
      password: password,
      ais125Tier: ais125Tier,
      ambulanceType: ambulanceType,
    );
  }

  Future<ResolvedLogin> resolveCrewLogin(String identifier) {
    return _service.resolveCrewLogin(identifier);
  }

  Future<String?> uploadRcDocument({
    required String tempRef,
    required dynamic fileBytes,
    required String fileName,
  }) {
    return _service.uploadRcDocument(
      tempRef: tempRef,
      fileBytes: fileBytes,
      fileName: fileName,
    );
  }

  Future<void> updateCrewMutableFields({
    required String uid,
    required String ais125Tier,
    required String ambulanceType,
    required String contactNumber,
  }) {
    return _service.updateCrewMutableFields(
      uid: uid,
      ais125Tier: ais125Tier,
      ambulanceType: ambulanceType,
      contactNumber: contactNumber,
    );
  }

  Future<void> signInOrCreateDemoCrew() {
    return _service.signInOrCreateDemoCrew();
  }

  Future<void> signInOrCreateDemoCrewB() {
    return _service.signInOrCreateDemoCrewB();
  }

  Future<void> signOut() async {
    final uid = AmbulanceAuthService.currentSessionUid;
    if (uid != null) {
      if (_presenceService != null) {
        try {
          await _presenceService.setCrewStatus(
            uid,
            CrewPresenceStatus.offline,
            ambulance: null,
            recordPrevious: false,
          );
        } catch (_) {}
      }
      if (_fcmService != null) {
        await _fcmService.unregisterCrewDevice(uid);
      }
    }
    return _service.signOut();
  }
}

final ambulanceAuthControllerProvider = Provider<AmbulanceAuthController>((ref) {
  final service = ref.watch(ambulanceAuthServiceProvider);
  final fcm = ref.watch(fcmServiceProvider);
  final presence = ref.watch(crewPresenceServiceProvider);
  return AmbulanceAuthController(service, fcm, presence);
});
