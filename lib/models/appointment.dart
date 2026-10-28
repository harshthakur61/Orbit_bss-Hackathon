import 'package:cloud_firestore/cloud_firestore.dart';

enum SlotStatus {
  free,
  booked,
  past,
}

class DaySlotItem {
  final String slotId;
  final String time; // e.g. "09:30"
  final DateTime startTime;
  final SlotStatus status;

  const DaySlotItem({
    required this.slotId,
    required this.time,
    required this.startTime,
    required this.status,
  });

  factory DaySlotItem.fromJson(Map<String, dynamic> json) {
    final statusStr = (json['status'] as String? ?? 'free').toLowerCase();
    SlotStatus status;
    switch (statusStr) {
      case 'booked':
      case 'held':
        status = SlotStatus.booked;
        break;
      case 'past':
        status = SlotStatus.past;
        break;
      case 'free':
      default:
        status = SlotStatus.free;
        break;
    }

    DateTime parsedTime;
    final iso = json['startTimeIso'] as String?;
    if (iso != null && iso.isNotEmpty) {
      parsedTime = DateTime.tryParse(iso)?.toLocal() ?? DateTime.now();
    } else {
      parsedTime = DateTime.now();
    }

    return DaySlotItem(
      slotId: json['slotId'] as String? ?? '',
      time: json['time'] as String? ?? '',
      startTime: parsedTime,
      status: status,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'slotId': slotId,
      'time': time,
      'startTimeIso': startTime.toIso8601String(),
      'status': status.name,
    };
  }

  DaySlotItem copyWith({
    String? slotId,
    String? time,
    DateTime? startTime,
    SlotStatus? status,
  }) {
    return DaySlotItem(
      slotId: slotId ?? this.slotId,
      time: time ?? this.time,
      startTime: startTime ?? this.startTime,
      status: status ?? this.status,
    );
  }
}

class Appointment {
  final String id; // BLA-XXXXXX
  final String patientUid;
  final String patientName;
  final String patientPhone;
  final String clinicId;
  final String clinicName;
  final String clinicType;
  final String slotId;
  final DateTime startTime;
  final String status; // 'pending_payment' | 'confirmed' | 'refunded' | 'payment_failed'
  final int amountPaise;
  final String? razorpayOrderId;
  final String? razorpayPaymentId;
  final DateTime? createdAt;
  final DateTime? confirmedAt;
  final String? clinicAddress;
  final String? clinicPhone;
  final double? clinicLat;
  final double? clinicLng;

  const Appointment({
    required this.id,
    required this.patientUid,
    required this.patientName,
    required this.patientPhone,
    required this.clinicId,
    required this.clinicName,
    required this.clinicType,
    required this.slotId,
    required this.startTime,
    required this.status,
    required this.amountPaise,
    this.razorpayOrderId,
    this.razorpayPaymentId,
    this.createdAt,
    this.confirmedAt,
    this.clinicAddress,
    this.clinicPhone,
    this.clinicLat,
    this.clinicLng,
  });

  int get amountRupees => amountPaise ~/ 100;
  bool get isConfirmed => status == 'confirmed';
  bool get isUpcoming => startTime.isAfter(DateTime.now()) && isConfirmed;
  bool get isPast => !startTime.isAfter(DateTime.now()) || status == 'refunded';

  factory Appointment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Appointment.fromMap(doc.id, data);
  }

  factory Appointment.fromMap(String id, Map<String, dynamic> data) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate().toLocal();
      if (val is String) return DateTime.tryParse(val)?.toLocal() ?? DateTime.now();
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val).toLocal();
      return DateTime.now();
    }

    return Appointment(
      id: id,
      patientUid: data['patientUid'] as String? ?? '',
      patientName: data['patientName'] as String? ?? '',
      patientPhone: data['patientPhone'] as String? ?? '',
      clinicId: data['clinicId'] as String? ?? '',
      clinicName: data['clinicName'] as String? ?? 'Clinic',
      clinicType: data['clinicType'] as String? ?? 'clinic',
      slotId: data['slotId'] as String? ?? '',
      startTime: parseDate(data['startTime']),
      status: data['status'] as String? ?? 'pending_payment',
      amountPaise: (data['amountPaise'] as num?)?.toInt() ?? 0,
      razorpayOrderId: data['razorpayOrderId'] as String?,
      razorpayPaymentId: data['razorpayPaymentId'] as String?,
      createdAt: data['createdAt'] != null ? parseDate(data['createdAt']) : null,
      confirmedAt: data['confirmedAt'] != null ? parseDate(data['confirmedAt']) : null,
      clinicAddress: data['clinicAddress'] as String?,
      clinicPhone: data['clinicPhone'] as String?,
      clinicLat: (data['clinicLat'] as num?)?.toDouble(),
      clinicLng: (data['clinicLng'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'patientUid': patientUid,
      'patientName': patientName,
      'patientPhone': patientPhone,
      'clinicId': clinicId,
      'clinicName': clinicName,
      'clinicType': clinicType,
      'slotId': slotId,
      'startTime': Timestamp.fromDate(startTime),
      'status': status,
      'amountPaise': amountPaise,
      if (razorpayOrderId != null) 'razorpayOrderId': razorpayOrderId,
      if (razorpayPaymentId != null) 'razorpayPaymentId': razorpayPaymentId,
      if (clinicAddress != null) 'clinicAddress': clinicAddress,
      if (clinicPhone != null) 'clinicPhone': clinicPhone,
      if (clinicLat != null) 'clinicLat': clinicLat,
      if (clinicLng != null) 'clinicLng': clinicLng,
    };
  }

  Appointment copyWith({
    String? id,
    String? patientUid,
    String? patientName,
    String? patientPhone,
    String? clinicId,
    String? clinicName,
    String? clinicType,
    String? slotId,
    DateTime? startTime,
    String? status,
    int? amountPaise,
    String? razorpayOrderId,
    String? razorpayPaymentId,
    DateTime? createdAt,
    DateTime? confirmedAt,
    String? clinicAddress,
    String? clinicPhone,
    double? clinicLat,
    double? clinicLng,
  }) {
    return Appointment(
      id: id ?? this.id,
      patientUid: patientUid ?? this.patientUid,
      patientName: patientName ?? this.patientName,
      patientPhone: patientPhone ?? this.patientPhone,
      clinicId: clinicId ?? this.clinicId,
      clinicName: clinicName ?? this.clinicName,
      clinicType: clinicType ?? this.clinicType,
      slotId: slotId ?? this.slotId,
      startTime: startTime ?? this.startTime,
      status: status ?? this.status,
      amountPaise: amountPaise ?? this.amountPaise,
      razorpayOrderId: razorpayOrderId ?? this.razorpayOrderId,
      razorpayPaymentId: razorpayPaymentId ?? this.razorpayPaymentId,
      createdAt: createdAt ?? this.createdAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      clinicAddress: clinicAddress ?? this.clinicAddress,
      clinicPhone: clinicPhone ?? this.clinicPhone,
      clinicLat: clinicLat ?? this.clinicLat,
      clinicLng: clinicLng ?? this.clinicLng,
    );
  }
}
