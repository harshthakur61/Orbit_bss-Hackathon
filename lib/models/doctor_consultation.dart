class DoctorConsultation {
  final String id;
  final String name;
  final String qualification;
  final String specialty;
  final int experienceYears;
  final int patientConsultations;
  final double rating;
  final int reviewCount;
  final String hospitalAffiliation;
  final List<String> languages;
  final int pricePerSession;
  final int durationMinutes;
  final bool isOnline;
  final String waitTime;
  final String phone;
  final List<String> focusAreas;
  final String about;

  const DoctorConsultation({
    required this.id,
    required this.name,
    required this.qualification,
    required this.specialty,
    required this.experienceYears,
    required this.patientConsultations,
    required this.rating,
    required this.reviewCount,
    required this.hospitalAffiliation,
    required this.languages,
    required this.pricePerSession,
    this.durationMinutes = 10,
    this.isOnline = true,
    required this.waitTime,
    required this.phone,
    required this.focusAreas,
    required this.about,
  });

  String get priceFormatted => '₹$pricePerSession / $durationMinutes mins';
  String get experienceFormatted => '$experienceYears+ Years Exp';
  String get consultationFormatted => '${_formatNumber(patientConsultations)}+ Consultations';

  static String _formatNumber(int number) {
    if (number >= 1000) {
      final double k = number / 1000.0;
      return '${k.toStringAsFixed(1)}k';
    }
    return number.toString();
  }
}

final List<DoctorConsultation> kSampleDoctors = [
  const DoctorConsultation(
    id: 'doc_1',
    name: 'Dr. Priya Nair',
    qualification: 'MBBS, MD (General Medicine)',
    specialty: 'General Physician & Emergency Triage',
    experienceYears: 12,
    patientConsultations: 4850,
    rating: 4.9,
    reviewCount: 720,
    hospitalAffiliation: 'KEM Hospital & Research Centre, Mumbai',
    languages: ['English', 'Hindi', 'Marathi'],
    pricePerSession: 350,
    durationMinutes: 10,
    isOnline: true,
    waitTime: 'Instant (under 1 min)',
    phone: '+91 22 2410 7000',
    focusAreas: ['Fever & Infection', 'Chest Tightness', 'Hypertension', 'Triage'],
    about:
        'Senior emergency physician specializing in rapid acute symptom assessment, general infection management, and emergency bed referrals.',
  ),
  const DoctorConsultation(
    id: 'doc_2',
    name: 'Dr. Rajesh Kulkarni',
    qualification: 'MBBS, MS, DNB (Cardiology)',
    specialty: 'Senior Cardiologist & Critical Care',
    experienceYears: 16,
    patientConsultations: 6200,
    rating: 4.9,
    reviewCount: 1150,
    hospitalAffiliation: 'Lilavati Hospital & Research Centre, Bandra',
    languages: ['English', 'Hindi', 'Marathi', 'Gujarati'],
    pricePerSession: 450,
    durationMinutes: 10,
    isOnline: true,
    waitTime: '~2 mins wait',
    phone: '+91 22 2675 1000',
    focusAreas: ['Chest Pain', 'Arrhythmia', 'ECG Review', 'Heart Failure'],
    about:
        'Renowned cardiologist with 16+ years in interventional cardiology. Provides immediate cardiac risk evaluation and second opinions on ECG reports.',
  ),
  const DoctorConsultation(
    id: 'doc_3',
    name: 'Dr. Sneha Deshmukh',
    qualification: 'MBBS, MD, DCH (Pediatrics)',
    specialty: 'Consultant Pediatrician & Neonatologist',
    experienceYears: 9,
    patientConsultations: 3900,
    rating: 4.8,
    reviewCount: 580,
    hospitalAffiliation: 'Kokilaben Dhirubhai Ambani Hospital, Andheri',
    languages: ['English', 'Hindi', 'Marathi'],
    pricePerSession: 350,
    durationMinutes: 10,
    isOnline: true,
    waitTime: 'Instant (under 1 min)',
    phone: '+91 22 4269 6969',
    focusAreas: ['Child High Fever', 'Pediatric Asthma', 'Infant Care', 'Allergies'],
    about:
        'Expert in pediatric triage, infant wellness, acute childhood infections, respiratory distress, and round-the-clock urgent child consultations.',
  ),
  const DoctorConsultation(
    id: 'doc_4',
    name: 'Dr. Vikramaditya Rathore',
    qualification: 'MBBS, MD (Dermatology & Venereology)',
    specialty: 'Dermatologist & Skin Allergy Specialist',
    experienceYears: 11,
    patientConsultations: 5120,
    rating: 4.9,
    reviewCount: 890,
    hospitalAffiliation: 'Hinduja Healthcare Surgical, Khar',
    languages: ['English', 'Hindi'],
    pricePerSession: 320,
    durationMinutes: 10,
    isOnline: true,
    waitTime: 'Instant (under 1 min)',
    phone: '+91 22 2445 1515',
    focusAreas: ['Acute Skin Rash', 'Drug Reaction', 'Severe Itch', 'Wound Infection'],
    about:
        'Experienced dermatologist specializing in immediate diagnosis of acute rashes, allergic reactions, burns, bacterial skin infections, and report reviews.',
  ),
  const DoctorConsultation(
    id: 'doc_5',
    name: 'Dr. Ananya Joshi',
    qualification: 'MBBS, MS (Orthopedics), MCh',
    specialty: 'Orthopedic & Joint Trauma Surgeon',
    experienceYears: 14,
    patientConsultations: 4400,
    rating: 4.8,
    reviewCount: 640,
    hospitalAffiliation: 'Nanavati Max Super Speciality Hospital, Vile Parle',
    languages: ['English', 'Hindi', 'Marathi'],
    pricePerSession: 380,
    durationMinutes: 10,
    isOnline: true,
    waitTime: '~2 mins wait',
    phone: '+91 22 2618 2255',
    focusAreas: ['Fractures & Trauma', 'Acute Spine Strain', 'Joint Pain', 'Sports Injury'],
    about:
        'Senior orthopedic trauma specialist providing emergency limb immobilization guidance, pain relief triage, and surgical second opinions.',
  ),
];
