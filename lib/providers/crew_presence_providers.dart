import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/crew_presence_constants.dart';
import '../models/crew_presence.dart';
import '../services/crew_presence_service.dart';
import 'ambulance_auth_provider.dart';

final crewPresenceServiceProvider = Provider<CrewPresenceService>((ref) {
  final service = CrewPresenceService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Current availability status of the active ambulance crew
final currentCrewPresenceStatusProvider = Provider<CrewPresenceStatus>((ref) {
  final service = ref.watch(crewPresenceServiceProvider);
  void listener() => ref.invalidateSelf();
  service.addListener(listener);
  ref.onDispose(() => service.removeListener(listener));
  return service.currentStatus;
});

/// Whether location permission is denied while Available status is chosen
final isCrewLocationDeniedProvider = Provider<bool>((ref) {
  final service = ref.watch(crewPresenceServiceProvider);
  void listener() => ref.invalidateSelf();
  service.addListener(listener);
  ref.onDispose(() => service.removeListener(listener));
  return service.isLocationPermissionDenied;
});

/// Real-time stream of the current crew's presence document
final currentCrewPresenceStreamProvider = StreamProvider<CrewPresence?>((ref) {
  final authStateAsync = ref.watch(ambulanceAuthStateProvider);
  final service = ref.watch(crewPresenceServiceProvider);

  return authStateAsync.when(
    data: (user) {
      final uid = user?.uid;
      if (uid == null || uid.isEmpty) return Stream.value(null);
      return service.streamCrewPresence(uid);
    },
    loading: () => Stream.value(null),
    error: (err, stack) => Stream.value(null),
  );
});
