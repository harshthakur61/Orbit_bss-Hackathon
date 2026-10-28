/// Configuration constants for Ambulance Crew UI and features.
library;

/// Default tab index for the /crew/home bottom navigation shell.
/// 0 = Profile
/// 1 = New Emergency Dispatch (Default)
const int kCrewDefaultTab = 1;

/// AIS-125 Homologation & Vehicle Tier definition.
class Ais125TierOption {
  final String code;
  final String label;
  final String description;

  const Ais125TierOption({
    required this.code,
    required this.label,
    required this.description,
  });
}

/// Editable list of AIS-125 Ambulance types used across the app.
const List<Ais125TierOption> kAis125Tiers = [
  Ais125TierOption(
    code: 'TYPE_A',
    label: 'Type A: First Responder',
    description: 'First responder & rapid emergency transport',
  ),
  Ais125TierOption(
    code: 'TYPE_B',
    label: 'Type B: Patient Transport (BLS)',
    description: 'Basic Life Support transport with oxygen & monitoring',
  ),
  Ais125TierOption(
    code: 'TYPE_C',
    label: 'Type C: Advanced Life Support (ALS)',
    description: 'ALS equipped with defibrillator, monitor & resuscitation',
  ),
  Ais125TierOption(
    code: 'TYPE_D',
    label: 'Type D: Mobile Intensive Care (MICU)',
    description: 'Full intensive care unit with advanced ventilator & infusion',
  ),
];
