import 'package:cloud_firestore/cloud_firestore.dart';
import 'bed_inventory.dart';

class Hospital {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final String phone;
  final String pin;
  final String loadLevel; // 'low', 'med', 'high'
  final BedInventory beds;
  final DateTime? lastUpdated;
  final bool isNurseOnline;
  final DateTime? lastNurseActive;

  const Hospital({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.phone,
    required this.pin,
    required this.loadLevel,
    required this.beds,
    this.lastUpdated,
    this.isNurseOnline = true,
    this.lastNurseActive,
  });

  factory Hospital.fromJson(Map<String, dynamic> json, String id) {
    DateTime? updatedDate;
    if (json['lastUpdated'] != null) {
      if (json['lastUpdated'] is Timestamp) {
        updatedDate = (json['lastUpdated'] as Timestamp).toDate();
      } else if (json['lastUpdated'] is String) {
        updatedDate = DateTime.tryParse(json['lastUpdated']);
      }
    }

    DateTime? nurseActiveDate;
    if (json['lastNurseActive'] != null) {
      if (json['lastNurseActive'] is Timestamp) {
        nurseActiveDate = (json['lastNurseActive'] as Timestamp).toDate();
      } else if (json['lastNurseActive'] is String) {
        nurseActiveDate = DateTime.tryParse(json['lastNurseActive']);
      }
    }

    return Hospital(
      id: id,
      name: json['name'] as String? ?? 'Unknown Hospital',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      phone: json['phone'] as String? ?? '',
      pin: json['pin'] as String? ?? '1234',
      loadLevel: json['loadLevel'] as String? ?? 'low',
      beds: json['beds'] != null
          ? BedInventory.fromJson(Map<String, dynamic>.from(json['beds']))
          : BedInventory.initial(),
      lastUpdated: updatedDate,
      isNurseOnline: json['isNurseOnline'] as bool? ?? true,
      lastNurseActive: nurseActiveDate,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'lat': lat,
        'lng': lng,
        'phone': phone,
        'pin': pin,
        'loadLevel': loadLevel,
        'beds': beds.toJson(),
        'lastUpdated': lastUpdated != null
            ? Timestamp.fromDate(lastUpdated!)
            : FieldValue.serverTimestamp(),
        'isNurseOnline': isNurseOnline,
        'lastNurseActive': lastNurseActive != null
            ? Timestamp.fromDate(lastNurseActive!)
            : null,
      };

  Hospital copyWith({
    String? id,
    String? name,
    double? lat,
    double? lng,
    String? phone,
    String? pin,
    String? loadLevel,
    BedInventory? beds,
    DateTime? lastUpdated,
    bool? isNurseOnline,
    DateTime? lastNurseActive,
  }) {
    return Hospital(
      id: id ?? this.id,
      name: name ?? this.name,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      phone: phone ?? this.phone,
      pin: pin ?? this.pin,
      loadLevel: loadLevel ?? this.loadLevel,
      beds: beds ?? this.beds,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      isNurseOnline: isNurseOnline ?? this.isNurseOnline,
      lastNurseActive: lastNurseActive ?? this.lastNurseActive,
    );
  }
}
