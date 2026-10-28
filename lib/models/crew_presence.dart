import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/crew_presence_constants.dart';

/// Data model representing real-time presence, availability status,
/// and live telemetry of a verified ambulance crew.
class CrewPresence {
  final String uid;
  final String? ambulanceId;
  final String? ais125Tier;
  final CrewPresenceStatus status;
  final double? lat;
  final double? lng;
  final double? accuracyMeters;
  final DateTime? updatedAt;

  const CrewPresence({
    required this.uid,
    this.ambulanceId,
    this.ais125Tier,
    required this.status,
    this.lat,
    this.lng,
    this.accuracyMeters,
    this.updatedAt,
  });

  /// Factory deserializer from Firestore map
  factory CrewPresence.fromJson(Map<String, dynamic> json, String uid) {
    DateTime? parseTimestamp(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }

    return CrewPresence(
      uid: uid,
      ambulanceId: json['ambulanceId'] as String?,
      ais125Tier: json['ais125Tier'] as String?,
      status: CrewPresenceStatus.fromCode(json['status'] as String?),
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble(),
      updatedAt: parseTimestamp(json['updatedAt']),
    );
  }

  /// Serializer to Firestore map
  Map<String, dynamic> toJson({bool useServerTimestamp = false}) {
    return {
      if (ambulanceId != null) 'ambulanceId': ambulanceId,
      if (ais125Tier != null) 'ais125Tier': ais125Tier,
      'status': status.code,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (accuracyMeters != null) 'accuracyMeters': accuracyMeters,
      'updatedAt': useServerTimestamp
          ? FieldValue.serverTimestamp()
          : (updatedAt != null ? Timestamp.fromDate(updatedAt!) : FieldValue.serverTimestamp()),
    };
  }

  CrewPresence copyWith({
    String? uid,
    String? ambulanceId,
    String? ais125Tier,
    CrewPresenceStatus? status,
    double? lat,
    double? lng,
    double? accuracyMeters,
    DateTime? updatedAt,
  }) {
    return CrewPresence(
      uid: uid ?? this.uid,
      ambulanceId: ambulanceId ?? this.ambulanceId,
      ais125Tier: ais125Tier ?? this.ais125Tier,
      status: status ?? this.status,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
