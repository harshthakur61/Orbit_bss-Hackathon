import 'package:cloud_firestore/cloud_firestore.dart';

enum AmbulanceVerificationStatus {
  pending,
  verified,
  rejected,
  needsReview;

  String toDbString() {
    switch (this) {
      case AmbulanceVerificationStatus.pending:
        return 'PENDING';
      case AmbulanceVerificationStatus.verified:
        return 'VERIFIED';
      case AmbulanceVerificationStatus.rejected:
        return 'REJECTED';
      case AmbulanceVerificationStatus.needsReview:
        return 'NEEDS_REVIEW';
    }
  }

  static AmbulanceVerificationStatus fromDbString(String? val) {
    switch (val?.toUpperCase()) {
      case 'VERIFIED':
        return AmbulanceVerificationStatus.verified;
      case 'REJECTED':
        return AmbulanceVerificationStatus.rejected;
      case 'NEEDS_REVIEW':
        return AmbulanceVerificationStatus.needsReview;
      case 'PENDING':
      default:
        return AmbulanceVerificationStatus.pending;
    }
  }
}

class Ambulance {
  final String uid;
  final String applicationRef;
  final String? ambulanceId; // e.g. "BL-AMB-102938"
  final AmbulanceVerificationStatus verificationStatus;
  final String? rejectionReason;
  final String? reviewReason;

  // Immutable (set once by backend verification)
  final String vehicleNumber; // Normalized, no spaces or hyphens
  final String vehicleClass;
  final String ownerName;
  final DateTime? fitnessValidUpto;
  final String driverLegalName;
  final DateTime? dob;
  final String dlNumber;
  final String dlStatus;
  final bool dlHasTransportEndorsement;
  final DateTime? verifiedAt;

  // Mutable by crew
  final String ais125Tier; // e.g. "TYPE_A", "TYPE_B", "TYPE_C", "TYPE_D"
  final String ambulanceType; // "GOVERNMENT" | "PRIVATE"
  final String contactNumber;

  final DateTime? createdAt;

  const Ambulance({
    required this.uid,
    required this.applicationRef,
    this.ambulanceId,
    this.verificationStatus = AmbulanceVerificationStatus.pending,
    this.rejectionReason,
    this.reviewReason,
    this.vehicleNumber = '',
    this.vehicleClass = '',
    this.ownerName = '',
    this.fitnessValidUpto,
    this.driverLegalName = '',
    this.dob,
    this.dlNumber = '',
    this.dlStatus = '',
    this.dlHasTransportEndorsement = false,
    this.verifiedAt,
    this.ais125Tier = 'TYPE_B',
    this.ambulanceType = 'PRIVATE',
    this.contactNumber = '',
    this.createdAt,
  });

  bool get isVerified => verificationStatus == AmbulanceVerificationStatus.verified;
  bool get isPending => verificationStatus == AmbulanceVerificationStatus.pending;
  bool get isRejected => verificationStatus == AmbulanceVerificationStatus.rejected;
  bool get isNeedsReview => verificationStatus == AmbulanceVerificationStatus.needsReview;

  factory Ambulance.fromJson(Map<String, dynamic> json, String uid) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return Ambulance(
      uid: uid,
      applicationRef: json['applicationRef'] as String? ?? '',
      ambulanceId: json['ambulanceId'] as String?,
      verificationStatus: AmbulanceVerificationStatus.fromDbString(
        json['verificationStatus'] as String?,
      ),
      rejectionReason: json['rejectionReason'] as String?,
      reviewReason: json['reviewReason'] as String?,
      vehicleNumber: json['vehicleNumber'] as String? ?? '',
      vehicleClass: json['vehicleClass'] as String? ?? '',
      ownerName: json['ownerName'] as String? ?? '',
      fitnessValidUpto: parseDate(json['fitnessValidUpto']),
      driverLegalName: json['driverLegalName'] as String? ?? '',
      dob: parseDate(json['dob']),
      dlNumber: json['dlNumber'] as String? ?? '',
      dlStatus: json['dlStatus'] as String? ?? '',
      dlHasTransportEndorsement:
          json['dlHasTransportEndorsement'] as bool? ?? false,
      verifiedAt: parseDate(json['verifiedAt']),
      ais125Tier: json['ais125Tier'] as String? ?? 'TYPE_B',
      ambulanceType: json['ambulanceType'] as String? ?? 'PRIVATE',
      contactNumber: json['contactNumber'] as String? ?? '',
      createdAt: parseDate(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'applicationRef': applicationRef,
      if (ambulanceId != null) 'ambulanceId': ambulanceId,
      'verificationStatus': verificationStatus.toDbString(),
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
      if (reviewReason != null) 'reviewReason': reviewReason,
      'vehicleNumber': vehicleNumber.toUpperCase().replaceAll(RegExp(r'[\s\-]'), ''),
      'vehicleClass': vehicleClass,
      'ownerName': ownerName,
      if (fitnessValidUpto != null)
        'fitnessValidUpto': Timestamp.fromDate(fitnessValidUpto!),
      'driverLegalName': driverLegalName,
      if (dob != null) 'dob': Timestamp.fromDate(dob!),
      'dlNumber': dlNumber,
      'dlStatus': dlStatus,
      'dlHasTransportEndorsement': dlHasTransportEndorsement,
      if (verifiedAt != null) 'verifiedAt': Timestamp.fromDate(verifiedAt!),
      'ais125Tier': ais125Tier,
      'ambulanceType': ambulanceType,
      'contactNumber': contactNumber,
      'createdAt':
          createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    };
  }

  /// Fields that the crew client is allowed to update
  Map<String, dynamic> toCrewMutableUpdateJson() {
    return {
      'ais125Tier': ais125Tier,
      'ambulanceType': ambulanceType,
      'contactNumber': contactNumber,
    };
  }

  Ambulance copyWith({
    String? uid,
    String? applicationRef,
    String? ambulanceId,
    AmbulanceVerificationStatus? verificationStatus,
    String? rejectionReason,
    String? reviewReason,
    String? vehicleNumber,
    String? vehicleClass,
    String? ownerName,
    DateTime? fitnessValidUpto,
    String? driverLegalName,
    DateTime? dob,
    String? dlNumber,
    String? dlStatus,
    bool? dlHasTransportEndorsement,
    DateTime? verifiedAt,
    String? ais125Tier,
    String? ambulanceType,
    String? contactNumber,
    DateTime? createdAt,
  }) {
    return Ambulance(
      uid: uid ?? this.uid,
      applicationRef: applicationRef ?? this.applicationRef,
      ambulanceId: ambulanceId ?? this.ambulanceId,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      reviewReason: reviewReason ?? this.reviewReason,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      vehicleClass: vehicleClass ?? this.vehicleClass,
      ownerName: ownerName ?? this.ownerName,
      fitnessValidUpto: fitnessValidUpto ?? this.fitnessValidUpto,
      driverLegalName: driverLegalName ?? this.driverLegalName,
      dob: dob ?? this.dob,
      dlNumber: dlNumber ?? this.dlNumber,
      dlStatus: dlStatus ?? this.dlStatus,
      dlHasTransportEndorsement:
          dlHasTransportEndorsement ?? this.dlHasTransportEndorsement,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      ais125Tier: ais125Tier ?? this.ais125Tier,
      ambulanceType: ambulanceType ?? this.ambulanceType,
      contactNumber: contactNumber ?? this.contactNumber,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
