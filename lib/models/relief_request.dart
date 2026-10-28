import 'package:cloud_firestore/cloud_firestore.dart';
import 'emergency_request.dart';

/// Full representation of a relief request document in `reliefRequests/{id}`.
class ReliefRequest {
  final String id;
  final String originalRequestId;
  final String requesterUid;
  final AmbulanceSnapshot requesterAmbulance;
  final String reason;
  final String status; // 'searching' | 'accepted' | 'cancelled' | 'no_ambulance' | 'completed'
  final int wave;
  final int radiusKm;
  final DateTime offerExpiresAt;
  final double disabledLat;
  final double disabledLng;
  final String severity;
  final List<String> needs;
  final String? acceptedByUid;
  final AmbulanceSnapshot? acceptedAmbulance;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;

  const ReliefRequest({
    required this.id,
    required this.originalRequestId,
    required this.requesterUid,
    required this.requesterAmbulance,
    required this.reason,
    required this.status,
    required this.wave,
    required this.radiusKm,
    required this.offerExpiresAt,
    required this.disabledLat,
    required this.disabledLng,
    required this.severity,
    required this.needs,
    this.acceptedByUid,
    this.acceptedAmbulance,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
  });

  bool get isExpired => DateTime.now().isAfter(offerExpiresAt);

  String get formattedReason {
    switch (reason.toLowerCase().trim()) {
      case 'breakdown':
      case 'mechanical_breakdown':
        return 'Mechanical Breakdown';
      case 'accident':
      case 'traffic_accident':
        return 'Traffic Accident';
      case 'flat_tyre':
        return 'Flat Tyre';
      case 'fuel':
      case 'fuel_depletion':
        return 'Fuel Depletion';
      case 'other':
      default:
        return 'Emergency / Other';
    }
  }

  factory ReliefRequest.fromJson(Map<String, dynamic> json, String id) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    final disabledLoc = json['disabledLocation'] as Map<String, dynamic>? ?? {};

    return ReliefRequest(
      id: id,
      originalRequestId: json['originalRequestId'] as String? ?? '',
      requesterUid: json['requesterUid'] as String? ?? '',
      requesterAmbulance: AmbulanceSnapshot.fromJson(
        Map<String, dynamic>.from(json['requesterAmbulance'] as Map? ?? {}),
      ),
      reason: json['reason'] as String? ?? 'breakdown',
      status: json['status'] as String? ?? 'searching',
      wave: (json['wave'] as num?)?.toInt() ?? 0,
      radiusKm: (json['radiusKm'] as num?)?.toInt() ?? 5,
      offerExpiresAt: parseDate(json['offerExpiresAt']) ??
          DateTime.now().add(const Duration(seconds: 60)),
      disabledLat: (disabledLoc['lat'] as num?)?.toDouble() ?? 0.0,
      disabledLng: (disabledLoc['lng'] as num?)?.toDouble() ?? 0.0,
      severity: json['severity'] as String? ?? 'serious',
      needs: List<String>.from(json['needs'] as List<dynamic>? ?? []),
      acceptedByUid: json['acceptedByUid'] as String?,
      acceptedAmbulance: json['acceptedAmbulance'] != null
          ? AmbulanceSnapshot.fromJson(
              Map<String, dynamic>.from(json['acceptedAmbulance'] as Map))
          : null,
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
      completedAt: parseDate(json['completedAt']),
    );
  }
}

/// Representation of a candidate offer in `reliefRequests/{id}/offers/{candidateUid}`.
class ReliefCandidateOffer {
  final String candidateUid;
  final String ambulanceId;
  final String ais125Tier;
  final double lat;
  final double lng;
  final double distanceKm;
  final int etaMin;
  final String status; // 'pending' | 'accepted' | 'rejected' | 'expired' | 'taken'
  final String? reason;
  final DateTime? sentAt;
  final DateTime? respondedAt;

  const ReliefCandidateOffer({
    required this.candidateUid,
    required this.ambulanceId,
    required this.ais125Tier,
    required this.lat,
    required this.lng,
    required this.distanceKm,
    required this.etaMin,
    required this.status,
    this.reason,
    this.sentAt,
    this.respondedAt,
  });

  String get formattedTier {
    final upper = ais125Tier.toUpperCase().replaceAll('_', ' ');
    if (upper.contains('TYPE B')) return 'Type B (BLS)';
    if (upper.contains('TYPE C')) return 'Type C (ALS)';
    if (upper.contains('TYPE D')) return 'Type D (MICU)';
    if (upper.contains('TYPE A')) return 'Type A';
    return ais125Tier;
  }

  factory ReliefCandidateOffer.fromJson(
      Map<String, dynamic> json, String candidateUid) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return ReliefCandidateOffer(
      candidateUid: candidateUid,
      ambulanceId: json['ambulanceId'] as String? ?? 'BL-AMB-???',
      ais125Tier: json['ais125Tier'] as String? ?? 'Type B',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0.0,
      etaMin: (json['etaMin'] as num?)?.toInt() ?? 5,
      status: json['status'] as String? ?? 'pending',
      reason: json['reason'] as String?,
      sentAt: parseDate(json['sentAt']),
      respondedAt: parseDate(json['respondedAt']),
    );
  }
}
