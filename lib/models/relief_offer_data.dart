import 'package:cloud_firestore/cloud_firestore.dart';

/// Data transfer model representing an incoming relief offer alert
/// sent to an eligible candidate ambulance crew.
/// Strictly sanitized of patient clinical notes and hospital destination.
class ReliefOfferData {
  final String reliefRequestId;
  final double distanceKm;
  final int etaMin;
  final String reason;
  final String severity;
  final DateTime offerExpiresAt;
  final int wave;
  final String? ais125Tier;
  final String? disabledAmbulanceId;
  final String? disabledAmbulanceVehicleNumber;
  final String? originalRequestId;

  const ReliefOfferData({
    required this.reliefRequestId,
    required this.distanceKm,
    required this.etaMin,
    required this.reason,
    required this.severity,
    required this.offerExpiresAt,
    this.wave = 1,
    this.ais125Tier,
    this.disabledAmbulanceId,
    this.disabledAmbulanceVehicleNumber,
    this.originalRequestId,
  });

  bool get isExpired => DateTime.now().isAfter(offerExpiresAt);

  int get remainingSeconds {
    final diff = offerExpiresAt.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  String get formattedReason {
    switch (reason.toLowerCase().trim()) {
      case 'mechanical_breakdown':
        return 'Mechanical Breakdown';
      case 'traffic_accident':
        return 'Traffic Accident';
      case 'medical_equipment_failure':
        return 'Medical Equipment Failure';
      case 'fuel_depletion':
        return 'Fuel Depletion';
      case 'crew_incapacitation':
        return 'Crew Incapacitation';
      default:
        return reason
            .split(RegExp(r'[_\s]+'))
            .map((w) => w.isEmpty
                ? ''
                : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
            .join(' ');
    }
  }

  String get formattedDistance => '${distanceKm.toStringAsFixed(1)} km';

  String get formattedEta => '$etaMin min';

  String get formattedTier {
    if (ais125Tier == null || ais125Tier!.isEmpty) return 'AIS-125 Ambulance';
    final upper = ais125Tier!.toUpperCase().replaceAll('_', ' ');
    if (upper.contains('TYPE B')) return 'Type B (Basic Life Support)';
    if (upper.contains('TYPE C')) return 'Type C (Advanced Life Support)';
    if (upper.contains('TYPE D')) return 'Type D (Mobile Intensive Care Unit)';
    if (upper.contains('TYPE A')) return 'Type A (First Responder)';
    return upper;
  }

  factory ReliefOfferData.fromJson(Map<String, dynamic> json) {
    // Parse distanceKm safely from number or string
    double dist = 0.0;
    if (json['distanceKm'] != null) {
      dist = double.tryParse(json['distanceKm'].toString()) ?? 0.0;
    }

    // Parse etaMin safely from number or string
    int eta = 5;
    if (json['etaMin'] != null) {
      eta = int.tryParse(json['etaMin'].toString()) ?? 5;
    }

    // Parse wave safely
    int waveNum = 1;
    if (json['wave'] != null) {
      waveNum = int.tryParse(json['wave'].toString()) ?? 1;
    }

    // Parse offerExpiresAt safely from Timestamp, DateTime, or ISO string
    DateTime expires;
    final rawExpires = json['offerExpiresAt'];
    if (rawExpires is Timestamp) {
      expires = rawExpires.toDate();
    } else if (rawExpires is DateTime) {
      expires = rawExpires;
    } else if (rawExpires is String && rawExpires.isNotEmpty) {
      expires = DateTime.tryParse(rawExpires) ??
          DateTime.now().add(const Duration(seconds: 60));
    } else {
      expires = DateTime.now().add(const Duration(seconds: 60));
    }

    return ReliefOfferData(
      reliefRequestId: (json['reliefRequestId'] as String?) ?? '',
      distanceKm: dist,
      etaMin: eta,
      reason: (json['reason'] as String?) ?? 'mechanical_breakdown',
      severity: (json['severity'] as String?) ?? 'serious',
      offerExpiresAt: expires,
      wave: waveNum,
      ais125Tier: json['ais125Tier'] as String?,
      disabledAmbulanceId: json['disabledAmbulanceId'] as String?,
      disabledAmbulanceVehicleNumber:
          json['disabledAmbulanceVehicleNumber'] as String?,
      originalRequestId: json['originalRequestId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'reliefRequestId': reliefRequestId,
        'distanceKm': distanceKm,
        'etaMin': etaMin,
        'reason': reason,
        'severity': severity,
        'offerExpiresAt': offerExpiresAt.toIso8601String(),
        'wave': wave,
        if (ais125Tier != null) 'ais125Tier': ais125Tier,
        if (disabledAmbulanceId != null)
          'disabledAmbulanceId': disabledAmbulanceId,
        if (disabledAmbulanceVehicleNumber != null)
          'disabledAmbulanceVehicleNumber': disabledAmbulanceVehicleNumber,
        if (originalRequestId != null) 'originalRequestId': originalRequestId,
      };

  ReliefOfferData copyWith({
    String? reliefRequestId,
    double? distanceKm,
    int? etaMin,
    String? reason,
    String? severity,
    DateTime? offerExpiresAt,
    int? wave,
    String? ais125Tier,
    String? disabledAmbulanceId,
    String? disabledAmbulanceVehicleNumber,
    String? originalRequestId,
  }) {
    return ReliefOfferData(
      reliefRequestId: reliefRequestId ?? this.reliefRequestId,
      distanceKm: distanceKm ?? this.distanceKm,
      etaMin: etaMin ?? this.etaMin,
      reason: reason ?? this.reason,
      severity: severity ?? this.severity,
      offerExpiresAt: offerExpiresAt ?? this.offerExpiresAt,
      wave: wave ?? this.wave,
      ais125Tier: ais125Tier ?? this.ais125Tier,
      disabledAmbulanceId: disabledAmbulanceId ?? this.disabledAmbulanceId,
      disabledAmbulanceVehicleNumber:
          disabledAmbulanceVehicleNumber ?? this.disabledAmbulanceVehicleNumber,
      originalRequestId: originalRequestId ?? this.originalRequestId,
    );
  }
}
