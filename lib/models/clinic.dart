import '../core/constants/booking_constants.dart';

class Clinic {
  final String id;
  final String name;
  final String type; // 'clinic' | 'pathology_lab' | 'diagnostic_center'
  final double lat;
  final double lng;
  final String phone;
  final String address;
  final double rating;
  final bool isOpen;
  final String operatingHours;
  final List<String> specialties;
  final List<String> testsAvailable;

  // Phase 11A Scheduling & Booking Fields
  final String openTime; // "HH:mm" 24h format
  final String closeTime; // "HH:mm" 24h format
  final int slotDurationMin; // Default 30 min
  final int bookingFeeRupees; // Default: clinic 79, lab 49
  final List<int> weeklyOffDays; // 1=Mon ... 7=Sun (ISO-8601 standard)

  const Clinic({
    required this.id,
    required this.name,
    required this.type,
    required this.lat,
    required this.lng,
    required this.phone,
    required this.address,
    required this.rating,
    required this.isOpen,
    required this.operatingHours,
    required this.specialties,
    required this.testsAvailable,
    this.openTime = BookingConstants.defaultOpenTime,
    this.closeTime = BookingConstants.defaultCloseTime,
    this.slotDurationMin = BookingConstants.defaultSlotDurationMinutes,
    this.bookingFeeRupees = BookingConstants.defaultClinicBookingFeeRupees,
    this.weeklyOffDays = const [],
  });

  factory Clinic.fromJson(Map<String, dynamic> json, String docId) {
    final typeStr = json['type'] as String? ?? 'clinic';
    final defaultFee = BookingConstants.resolveDefaultFeeRupees(typeStr);

    return Clinic(
      id: docId,
      name: json['name'] as String? ?? 'Clinic & Lab',
      type: typeStr,
      lat: (json['lat'] as num?)?.toDouble() ?? 19.0760,
      lng: (json['lng'] as num?)?.toDouble() ?? 72.8777,
      phone: json['phone'] as String? ?? '+91 22 0000 0000',
      address: json['address'] as String? ?? 'Mumbai',
      rating: (json['rating'] as num?)?.toDouble() ?? 4.5,
      isOpen: json['isOpen'] as bool? ?? true,
      operatingHours: json['operatingHours'] as String? ?? '8:00 AM - 8:00 PM',
      specialties: (json['specialties'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      testsAvailable: (json['testsAvailable'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      openTime: json['openTime'] as String? ?? BookingConstants.defaultOpenTime,
      closeTime: json['closeTime'] as String? ?? BookingConstants.defaultCloseTime,
      slotDurationMin: (json['slotDurationMin'] as num?)?.toInt() ??
          BookingConstants.defaultSlotDurationMinutes,
      bookingFeeRupees:
          (json['bookingFeeRupees'] as num?)?.toInt() ?? defaultFee,
      weeklyOffDays: (json['weeklyOffDays'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type,
      'lat': lat,
      'lng': lng,
      'phone': phone,
      'address': address,
      'rating': rating,
      'isOpen': isOpen,
      'operatingHours': operatingHours,
      'specialties': specialties,
      'testsAvailable': testsAvailable,
      'openTime': openTime,
      'closeTime': closeTime,
      'slotDurationMin': slotDurationMin,
      'bookingFeeRupees': bookingFeeRupees,
      'weeklyOffDays': weeklyOffDays,
    };
  }

  Clinic copyWith({
    String? id,
    String? name,
    String? type,
    double? lat,
    double? lng,
    String? phone,
    String? address,
    double? rating,
    bool? isOpen,
    String? operatingHours,
    List<String>? specialties,
    List<String>? testsAvailable,
    String? openTime,
    String? closeTime,
    int? slotDurationMin,
    int? bookingFeeRupees,
    List<int>? weeklyOffDays,
  }) {
    return Clinic(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      rating: rating ?? this.rating,
      isOpen: isOpen ?? this.isOpen,
      operatingHours: operatingHours ?? this.operatingHours,
      specialties: specialties ?? this.specialties,
      testsAvailable: testsAvailable ?? this.testsAvailable,
      openTime: openTime ?? this.openTime,
      closeTime: closeTime ?? this.closeTime,
      slotDurationMin: slotDurationMin ?? this.slotDurationMin,
      bookingFeeRupees: bookingFeeRupees ?? this.bookingFeeRupees,
      weeklyOffDays: weeklyOffDays ?? this.weeklyOffDays,
    );
  }
}

class ClinicRankResult {
  final Clinic clinic;
  final double distanceKm;
  final int travelMinutes;
  final double totalScore;
  final int matchedSpecialtiesCount;
  final int rank;

  const ClinicRankResult({
    required this.clinic,
    required this.distanceKm,
    required this.travelMinutes,
    required this.totalScore,
    required this.matchedSpecialtiesCount,
    required this.rank,
  });
}
