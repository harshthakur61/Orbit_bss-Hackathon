// Booking configuration constants for clinics and diagnostic labs

class BookingConstants {
  BookingConstants._();

  /// Default booking fee in Indian Rupees for general and specialist clinics
  static const int defaultClinicBookingFeeRupees = 79;

  /// Default booking fee in Indian Rupees for pathology and diagnostic laboratories
  static const int defaultLabBookingFeeRupees = 49;

  /// Default slot duration in minutes
  static const int defaultSlotDurationMinutes = 30;

  /// Temporary reservation hold duration in minutes before payment confirmation
  static const int slotHoldDurationMinutes = 5;

  /// Minimum lead time required in minutes before a slot start time
  static const int minimumLeadMinutes = 30;

  /// Maximum advance booking horizon in days
  static const int maxAdvanceBookingDays = 7;

  /// Canonical time zone for all clinic and lab scheduling calculations
  static const String canonicalTimeZone = 'Asia/Kolkata';

  /// Standard default opening time (24h format HH:mm)
  static const String defaultOpenTime = '08:00';

  /// Standard default closing time (24h format HH:mm)
  static const String defaultCloseTime = '20:00';

  /// Resolves the default booking fee for a clinic type
  static int resolveDefaultFeeRupees(String clinicType) {
    final cleanType = clinicType.toLowerCase().trim();
    if (cleanType == 'pathology_lab' || cleanType == 'diagnostic_center') {
      return defaultLabBookingFeeRupees;
    }
    return defaultClinicBookingFeeRupees;
  }

  /// Mandatory policy notice for appointment booking payments
  static const String nonRefundablePolicyText = 'Booking fee is non-refundable';
}
