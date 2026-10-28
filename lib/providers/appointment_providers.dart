import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/appointment.dart';
import '../services/appointment_service.dart';

final appointmentServiceProvider = Provider<AppointmentService>((ref) {
  final service = AppointmentService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Current authenticated Firebase UID (anonymously signed in if guest)
final firebaseUidStreamProvider = StreamProvider<String?>((ref) {
  return FirebaseAuth.instance.authStateChanges().map((u) => u?.uid);
});

/// Live stream of all appointments belonging to current authenticated patient
final patientAppointmentsStreamProvider = StreamProvider<List<Appointment>>((ref) {
  final authUidAsync = ref.watch(firebaseUidStreamProvider);
  final uid = authUidAsync.value;

  if (uid == null || uid.isEmpty) {
    // If auth state is not yet ready or user is anonymous guest without auth change yet,
    // check currentUser directly
    final current = FirebaseAuth.instance.currentUser;
    if (current != null) {
      final service = ref.watch(appointmentServiceProvider);
      return service.streamPatientAppointments(current.uid);
    }
    return Stream.value([]);
  }

  final service = ref.watch(appointmentServiceProvider);
  return service.streamPatientAppointments(uid);
});
