import 'package:cloud_firestore/cloud_firestore.dart';
import 'attempt.dart';

class AmbulanceSnapshot {
  final String ambulanceId;
  final String vehicleNumber;
  final String driverName;
  final String driverPhone;
  final String ambulanceType;
  final String ais125Tier;

  const AmbulanceSnapshot({
    required this.ambulanceId,
    required this.vehicleNumber,
    required this.driverName,
    required this.driverPhone,
    required this.ambulanceType,
    required this.ais125Tier,
  });

  factory AmbulanceSnapshot.fromJson(Map<String, dynamic> json) {
    return AmbulanceSnapshot(
      ambulanceId: json['ambulanceId'] as String? ?? '',
      vehicleNumber: json['vehicleNumber'] as String? ?? '',
      driverName: json['driverName'] as String? ?? '',
      driverPhone: json['driverPhone'] as String? ?? '',
      ambulanceType: json['ambulanceType'] as String? ?? 'Basic Life Support (BLS)',
      ais125Tier: json['ais125Tier'] as String? ?? 'Type B',
    );
  }

  Map<String, dynamic> toJson() => {
        'ambulanceId': ambulanceId,
        'vehicleNumber': vehicleNumber,
        'driverName': driverName,
        'driverPhone': driverPhone,
        'ambulanceType': ambulanceType,
        'ais125Tier': ais125Tier,
      };

  AmbulanceSnapshot copyWith({
    String? ambulanceId,
    String? vehicleNumber,
    String? driverName,
    String? driverPhone,
    String? ambulanceType,
    String? ais125Tier,
  }) {
    return AmbulanceSnapshot(
      ambulanceId: ambulanceId ?? this.ambulanceId,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      driverName: driverName ?? this.driverName,
      driverPhone: driverPhone ?? this.driverPhone,
      ambulanceType: ambulanceType ?? this.ambulanceType,
      ais125Tier: ais125Tier ?? this.ais125Tier,
    );
  }
}

class AmbulanceLiveLocation {
  final double lat;
  final double lng;
  final double heading;
  final double speedKmh;
  final double accuracyMeters;
  final String? ambulanceId;
  final String? hospitalId;
  final DateTime? updatedAt;

  const AmbulanceLiveLocation({
    required this.lat,
    required this.lng,
    this.heading = 0.0,
    this.speedKmh = 0.0,
    this.accuracyMeters = 0.0,
    this.ambulanceId,
    this.hospitalId,
    this.updatedAt,
  });

  factory AmbulanceLiveLocation.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return AmbulanceLiveLocation(
      lat: (map['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (map['lng'] as num?)?.toDouble() ?? 0.0,
      heading: (map['heading'] as num?)?.toDouble() ?? 0.0,
      speedKmh: (map['speedKmh'] as num?)?.toDouble() ?? 0.0,
      accuracyMeters: (map['accuracyMeters'] as num?)?.toDouble() ?? 0.0,
      ambulanceId: map['ambulanceId'] as String?,
      hospitalId: map['hospitalId'] as String?,
      updatedAt: parseDate(map['updatedAt']),
    );
  }

  factory AmbulanceLiveLocation.fromJson(Map<String, dynamic> json) =>
      AmbulanceLiveLocation.fromMap(json);

  Map<String, dynamic> toMap() => {
        'lat': lat,
        'lng': lng,
        'heading': heading,
        'speedKmh': speedKmh,
        'accuracyMeters': accuracyMeters,
        if (ambulanceId != null) 'ambulanceId': ambulanceId,
        if (hospitalId != null) 'hospitalId': hospitalId,
        'updatedAt': updatedAt != null
            ? Timestamp.fromDate(updatedAt!)
            : FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> toJson() => toMap();

  AmbulanceLiveLocation copyWith({
    double? lat,
    double? lng,
    double? heading,
    double? speedKmh,
    double? accuracyMeters,
    String? ambulanceId,
    String? hospitalId,
    DateTime? updatedAt,
  }) {
    return AmbulanceLiveLocation(
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      heading: heading ?? this.heading,
      speedKmh: speedKmh ?? this.speedKmh,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      ambulanceId: ambulanceId ?? this.ambulanceId,
      hospitalId: hospitalId ?? this.hospitalId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class HandoverRecord {
  final DateTime at;
  final String fromAmbulanceId;
  final String toAmbulanceId;
  final String reliefRequestId;
  final bool override;
  final String? fromCrewUid;
  final String? toCrewUid;

  const HandoverRecord({
    required this.at,
    required this.fromAmbulanceId,
    required this.toAmbulanceId,
    required this.reliefRequestId,
    this.override = false,
    this.fromCrewUid,
    this.toCrewUid,
  });

  factory HandoverRecord.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return HandoverRecord(
      at: parseDate(json['at']),
      fromAmbulanceId: json['fromAmbulanceId'] as String? ?? '',
      toAmbulanceId: json['toAmbulanceId'] as String? ?? '',
      reliefRequestId: json['reliefRequestId'] as String? ?? '',
      override: json['override'] == true,
      fromCrewUid: json['fromCrewUid'] as String?,
      toCrewUid: json['toCrewUid'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'at': Timestamp.fromDate(at),
        'fromAmbulanceId': fromAmbulanceId,
        'toAmbulanceId': toAmbulanceId,
        'reliefRequestId': reliefRequestId,
        'override': override,
        if (fromCrewUid != null) 'fromCrewUid': fromCrewUid,
        if (toCrewUid != null) 'toCrewUid': toCrewUid,
      };
}

class VoiceNoteMetadata {
  final String storagePath;
  final int durationSec;
  final int sizeBytes;
  final DateTime uploadedAt;

  const VoiceNoteMetadata({
    required this.storagePath,
    required this.durationSec,
    required this.sizeBytes,
    required this.uploadedAt,
  });

  factory VoiceNoteMetadata.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return VoiceNoteMetadata(
      storagePath: json['storagePath'] as String? ?? '',
      durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      uploadedAt: parseDate(json['uploadedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'storagePath': storagePath,
        'durationSec': durationSec,
        'sizeBytes': sizeBytes,
        'uploadedAt': Timestamp.fromDate(uploadedAt),
      };

  VoiceNoteMetadata copyWith({
    String? storagePath,
    int? durationSec,
    int? sizeBytes,
    DateTime? uploadedAt,
  }) {
    return VoiceNoteMetadata(
      storagePath: storagePath ?? this.storagePath,
      durationSec: durationSec ?? this.durationSec,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      uploadedAt: uploadedAt ?? this.uploadedAt,
    );
  }
}

class EmergencyRequest {
  final String id;
  final double patientLat;
  final double patientLng;
  final List<String> needs;
  final String severity; // 'critical' | 'serious' | 'stable'
  final String? note;
  final String status; // 'searching' | 'offered' | 'accepted' | 'cancelled' | 'failed' | 'arrived'
  final List<String> rankedHospitalIds;
  final int currentIndex;
  final String currentHospitalId;
  final DateTime? offerExpiresAt;
  final DateTime? createdAt;
  final List<Attempt> attempts;
  final String? rejectReason;
  final String? crewUid;
  final AmbulanceSnapshot? ambulance;
  final AmbulanceLiveLocation? ambulanceLive;
  final DateTime? alertDeliveredAt;
  final String? reliefState; // 'searching' | 'accepted' | 'completed' | null
  final String? reliefRequestId;
  final AmbulanceSnapshot? previousAmbulance;
  final HandoverRecord? handover;
  final VoiceNoteMetadata? voiceNote;
  final String? voiceNoteStatus; // null | 'arriving' | 'uploaded'

  const EmergencyRequest({
    required this.id,
    required this.patientLat,
    required this.patientLng,
    required this.needs,
    required this.severity,
    this.note,
    required this.status,
    required this.rankedHospitalIds,
    required this.currentIndex,
    required this.currentHospitalId,
    this.offerExpiresAt,
    this.createdAt,
    required this.attempts,
    this.rejectReason,
    this.crewUid,
    this.ambulance,
    this.ambulanceLive,
    this.alertDeliveredAt,
    this.reliefState,
    this.reliefRequestId,
    this.previousAmbulance,
    this.handover,
    this.voiceNote,
    this.voiceNoteStatus,
  });

  factory EmergencyRequest.fromJson(Map<String, dynamic> json, String id) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    final rawAttempts = json['attempts'] as List<dynamic>? ?? [];
    final parsedAttempts = rawAttempts
        .map((a) => Attempt.fromJson(Map<String, dynamic>.from(a)))
        .toList();

    return EmergencyRequest(
      id: id,
      patientLat: (json['patientLat'] as num?)?.toDouble() ?? 0.0,
      patientLng: (json['patientLng'] as num?)?.toDouble() ?? 0.0,
      needs: List<String>.from(json['needs'] as List<dynamic>? ?? []),
      severity: json['severity'] as String? ?? 'serious',
      note: json['note'] as String?,
      status: json['status'] as String? ?? 'searching',
      rankedHospitalIds:
          List<String>.from(json['rankedHospitalIds'] as List<dynamic>? ?? []),
      currentIndex: (json['currentIndex'] as num?)?.toInt() ?? 0,
      currentHospitalId: json['currentHospitalId'] as String? ?? '',
      offerExpiresAt: parseDate(json['offerExpiresAt']),
      createdAt: parseDate(json['createdAt']),
      attempts: parsedAttempts,
      rejectReason: json['rejectReason'] as String?,
      crewUid: json['crewUid'] as String?,
      ambulance: json['ambulance'] != null
          ? AmbulanceSnapshot.fromJson(
              Map<String, dynamic>.from(json['ambulance'] as Map))
          : null,
      ambulanceLive: json['ambulanceLive'] != null
          ? AmbulanceLiveLocation.fromJson(
              Map<String, dynamic>.from(json['ambulanceLive'] as Map))
          : null,
      alertDeliveredAt: parseDate(json['alertDeliveredAt']),
      reliefState: json['reliefState'] as String?,
      reliefRequestId: json['reliefRequestId'] as String?,
      previousAmbulance: json['previousAmbulance'] != null
          ? AmbulanceSnapshot.fromJson(
              Map<String, dynamic>.from(json['previousAmbulance'] as Map))
          : null,
      handover: json['handover'] != null
          ? HandoverRecord.fromJson(
              Map<String, dynamic>.from(json['handover'] as Map))
          : null,
      voiceNote: json['voiceNote'] != null
          ? VoiceNoteMetadata.fromJson(
              Map<String, dynamic>.from(json['voiceNote'] as Map))
          : null,
      voiceNoteStatus: json['voiceNoteStatus'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'patientLat': patientLat,
        'patientLng': patientLng,
        'needs': needs,
        'severity': severity,
        'note': note,
        'status': status,
        'rankedHospitalIds': rankedHospitalIds,
        'currentIndex': currentIndex,
        'currentHospitalId': currentHospitalId,
        'offerExpiresAt': offerExpiresAt != null
            ? Timestamp.fromDate(offerExpiresAt!)
            : null,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
        'attempts': attempts.map((a) => a.toJson()).toList(),
        'rejectReason': rejectReason,
        if (crewUid != null) 'crewUid': crewUid,
        if (ambulance != null) 'ambulance': ambulance!.toJson(),
        if (alertDeliveredAt != null)
          'alertDeliveredAt': Timestamp.fromDate(alertDeliveredAt!),
        if (reliefState != null) 'reliefState': reliefState,
        if (reliefRequestId != null) 'reliefRequestId': reliefRequestId,
        if (previousAmbulance != null)
          'previousAmbulance': previousAmbulance!.toJson(),
        if (handover != null) 'handover': handover!.toJson(),
        if (voiceNote != null) 'voiceNote': voiceNote!.toJson(),
        if (voiceNoteStatus != null) 'voiceNoteStatus': voiceNoteStatus,
      };

  EmergencyRequest copyWith({
    String? id,
    double? patientLat,
    double? patientLng,
    List<String>? needs,
    String? severity,
    String? note,
    String? status,
    List<String>? rankedHospitalIds,
    int? currentIndex,
    String? currentHospitalId,
    DateTime? offerExpiresAt,
    DateTime? createdAt,
    List<Attempt>? attempts,
    String? rejectReason,
    String? crewUid,
    AmbulanceSnapshot? ambulance,
    AmbulanceLiveLocation? ambulanceLive,
    DateTime? alertDeliveredAt,
    String? reliefState,
    String? reliefRequestId,
    AmbulanceSnapshot? previousAmbulance,
    HandoverRecord? handover,
    VoiceNoteMetadata? voiceNote,
    String? voiceNoteStatus,
  }) {
    return EmergencyRequest(
      id: id ?? this.id,
      patientLat: patientLat ?? this.patientLat,
      patientLng: patientLng ?? this.patientLng,
      needs: needs ?? this.needs,
      severity: severity ?? this.severity,
      note: note ?? this.note,
      status: status ?? this.status,
      rankedHospitalIds: rankedHospitalIds ?? this.rankedHospitalIds,
      currentIndex: currentIndex ?? this.currentIndex,
      currentHospitalId: currentHospitalId ?? this.currentHospitalId,
      offerExpiresAt: offerExpiresAt ?? this.offerExpiresAt,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
      rejectReason: rejectReason ?? this.rejectReason,
      crewUid: crewUid ?? this.crewUid,
      ambulance: ambulance ?? this.ambulance,
      ambulanceLive: ambulanceLive ?? this.ambulanceLive,
      alertDeliveredAt: alertDeliveredAt ?? this.alertDeliveredAt,
      reliefState: reliefState ?? this.reliefState,
      reliefRequestId: reliefRequestId ?? this.reliefRequestId,
      previousAmbulance: previousAmbulance ?? this.previousAmbulance,
      handover: handover ?? this.handover,
      voiceNote: voiceNote ?? this.voiceNote,
      voiceNoteStatus: voiceNoteStatus ?? this.voiceNoteStatus,
    );
  }
}
