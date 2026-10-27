class PatientProfile {
  final String id;
  final String name;
  final String phone;
  final int age;
  final String gender;
  final String bloodGroup;
  final String? photoUrl;
  final double heightCm;
  final double weightKg;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String emergencyContactRelation;
  final List<String> pastDiseases;
  final List<String> allergies;
  final List<String> currentMedications;
  final String currentHealthState;

  const PatientProfile({
    required this.id,
    required this.name,
    required this.phone,
    required this.age,
    required this.gender,
    required this.bloodGroup,
    this.photoUrl,
    required this.heightCm,
    required this.weightKg,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
    required this.emergencyContactRelation,
    required this.pastDiseases,
    required this.allergies,
    required this.currentMedications,
    required this.currentHealthState,
  });

  PatientProfile copyWith({
    String? id,
    String? name,
    String? phone,
    int? age,
    String? gender,
    String? bloodGroup,
    String? photoUrl,
    double? heightCm,
    double? weightKg,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? emergencyContactRelation,
    List<String>? pastDiseases,
    List<String>? allergies,
    List<String>? currentMedications,
    String? currentHealthState,
  }) {
    return PatientProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      bloodGroup: bloodGroup ?? this.bloodGroup,
      photoUrl: photoUrl ?? this.photoUrl,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      emergencyContactName: emergencyContactName ?? this.emergencyContactName,
      emergencyContactPhone:
          emergencyContactPhone ?? this.emergencyContactPhone,
      emergencyContactRelation:
          emergencyContactRelation ?? this.emergencyContactRelation,
      pastDiseases: pastDiseases ?? this.pastDiseases,
      allergies: allergies ?? this.allergies,
      currentMedications: currentMedications ?? this.currentMedications,
      currentHealthState: currentHealthState ?? this.currentHealthState,
    );
  }
}
