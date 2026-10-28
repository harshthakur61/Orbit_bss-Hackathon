/// Configuration constants, status enums, and eligibility thresholds
/// for Ambulance Crew presence and relief candidate matching.
library;

/// Operational availability status of an ambulance crew.
enum CrewPresenceStatus {
  available('AVAILABLE', 'Available', 'Ready to take a relief request.'),
  busy('BUSY', 'Online – Busy', 'Online but on a trip / not available.'),
  offline('OFFLINE', 'Offline', 'Off duty / not taking requests.');

  final String code;
  final String label;
  final String description;

  const CrewPresenceStatus(this.code, this.label, this.description);

  static CrewPresenceStatus fromCode(String? code) {
    switch (code?.toUpperCase()) {
      case 'AVAILABLE':
        return CrewPresenceStatus.available;
      case 'BUSY':
        return CrewPresenceStatus.busy;
      case 'OFFLINE':
      default:
        return CrewPresenceStatus.offline;
    }
  }
}

/// Presence publisher and relief matching thresholds
class CrewPresenceConstants {
  CrewPresenceConstants._();

  /// Maximum age in seconds for a presence update to be considered live for relief dispatch
  static const int maxPresenceAgeSeconds = 120;

  /// Periodic interval in seconds to publish presence while status is AVAILABLE
  static const int presencePublishIntervalSeconds = 30;

  /// Minimum distance in meters moved before publishing a new presence point
  static const double presenceMinDistanceMeters = 150.0;

  /// Accuracy threshold in meters; points with worse accuracy are filtered out
  static const double maxAcceptableAccuracyMeters = 100.0;

  /// SharedPreferences key for persisting crew status
  static const String prefsCrewStatusKey = 'crew_presence_status';

  /// SharedPreferences key for storing the previous status before transition to BUSY
  static const String prefsPreviousStatusKey = 'crew_presence_previous_status';

  /// Android foreground service notification text for Available status
  static const String availableNotificationText = 'BedLink – you are Available';

  /// Warning text when Available status is selected but GPS/location is disabled
  static const String locationOffWarning =
      "Location off – you won't receive relief requests";

  /// Evaluates whether a crew is eligible to receive a relief request
  static bool isCrewEligibleForRelief({
    required CrewPresenceStatus status,
    required DateTime? updatedAt,
    required int activeDeviceTokensCount,
    DateTime? now,
  }) {
    if (status != CrewPresenceStatus.available) {
      return false;
    }

    if (activeDeviceTokensCount <= 0) {
      return false;
    }

    if (updatedAt == null) {
      return false;
    }

    final currentTime = now ?? DateTime.now();
    final difference = currentTime.difference(updatedAt).inSeconds;
    return difference >= 0 && difference <= maxPresenceAgeSeconds;
  }
}
