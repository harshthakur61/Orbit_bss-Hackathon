import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/emergency_request.dart';
import 'hospital_providers.dart';

final requestsStreamProvider = StreamProvider<List<EmergencyRequest>>((ref) {
  final firestoreService = ref.watch(firestoreServiceProvider);
  return firestoreService.streamRequests();
});

class SelectedRequestIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final selectedRequestIdProvider =
    NotifierProvider<SelectedRequestIdNotifier, String?>(
        SelectedRequestIdNotifier.new);

final currentRequestProvider = StreamProvider<EmergencyRequest?>((ref) {
  final requestId = ref.watch(selectedRequestIdProvider);
  if (requestId == null || requestId.isEmpty) {
    return Stream.value(null);
  }
  final firestoreService = ref.watch(firestoreServiceProvider);
  return firestoreService.streamRequest(requestId);
});

final activeHospitalRequestProvider = StreamProvider.family<EmergencyRequest?, String>((ref, hospitalId) {
  final firestoreService = ref.watch(firestoreServiceProvider);
  return firestoreService.streamActiveRequestForHospital(hospitalId);
});

final acceptedHospitalRequestsProvider =
    StreamProvider.family<List<EmergencyRequest>, String>((ref, hospitalId) {
  final firestoreService = ref.watch(firestoreServiceProvider);
  return firestoreService.streamAcceptedRequestsForHospital(hospitalId);
});

final liveLocationStreamProvider =
    StreamProvider.family.autoDispose<AmbulanceLiveLocation?, String>(
        (ref, requestId) {
  final firestoreService = ref.watch(firestoreServiceProvider);
  return firestoreService.streamLiveLocation(requestId);
});

class IsPatientModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setPatientMode(bool isPatient) => state = isPatient;
}

final isPatientModeProvider =
    NotifierProvider<IsPatientModeNotifier, bool>(IsPatientModeNotifier.new);

