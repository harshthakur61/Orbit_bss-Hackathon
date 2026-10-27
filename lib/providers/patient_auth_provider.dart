import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/patient_profile.dart';

class PatientAuthState {
  final bool isAuthenticated;
  final PatientProfile profile;

  const PatientAuthState({
    required this.isAuthenticated,
    required this.profile,
  });

  PatientAuthState copyWith({
    bool? isAuthenticated,
    PatientProfile? profile,
  }) {
    return PatientAuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      profile: profile ?? this.profile,
    );
  }
}

class PatientAuthNotifier extends Notifier<PatientAuthState> {
  @override
  PatientAuthState build() {
    return const PatientAuthState(
      isAuthenticated: false,
      profile: PatientProfile(
        id: 'PAT-88204',
        name: 'Rahul Sharma',
        phone: '+91 98765 43210',
        age: 32,
        gender: 'Male',
        bloodGroup: 'O+',
        heightCm: 175,
        weightKg: 72,
        emergencyContactName: 'Priya Sharma',
        emergencyContactPhone: '+91 98123 45678',
        emergencyContactRelation: 'Spouse',
        pastDiseases: [
          'Mild Asthma (Diagnosed 2021)',
          'Primary Hypertension (Controlled)',
        ],
        allergies: [
          'Penicillin Antibiotics',
          'Environmental Dust & Pollen',
        ],
        currentMedications: [
          'Amlodipine 5mg (Daily Morning)',
          'Salbutamol Inhaler (As needed)',
        ],
        currentHealthState: 'Stable & Healthy',
      ),
    );
  }

  void login(String phone, String password) {
    final updatedPhone = phone.trim().isEmpty ? state.profile.phone : phone.trim();
    state = state.copyWith(
      isAuthenticated: true,
      profile: state.profile.copyWith(phone: updatedPhone),
    );
  }

  void logout() {
    state = state.copyWith(isAuthenticated: false);
  }

  void updateProfile(PatientProfile newProfile) {
    state = state.copyWith(
      isAuthenticated: true,
      profile: newProfile,
    );
  }
}

final patientAuthProvider =
    NotifierProvider<PatientAuthNotifier, PatientAuthState>(
        PatientAuthNotifier.new);
