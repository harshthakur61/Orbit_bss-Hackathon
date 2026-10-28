import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'bed_inventory.dart';

class Hospital {
  final String id;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final String phone;
  final String pin; // Fallback legacy PIN
  final String? pinHash;
  final String? pinSalt;
  final String loadLevel; // 'low', 'med', 'high'
  final BedInventory beds;
  final DateTime? lastUpdated;
  final bool isNurseOnline;
  final DateTime? lastNurseActive;
  final bool hasActiveDevices;

  const Hospital({
    required this.id,
    required this.name,
    this.address = 'Mumbai, Maharashtra',
    required this.lat,
    required this.lng,
    required this.phone,
    required this.pin,
    this.pinHash,
    this.pinSalt,
    required this.loadLevel,
    required this.beds,
    this.lastUpdated,
    this.isNurseOnline = true,
    this.lastNurseActive,
    this.hasActiveDevices = false,
  });

  /// Hospital is reachable if foreground nurse heartbeat is fresh (< 90 seconds)
  /// OR if the hospital has at least one registered active device token with loggedIn: true.
  bool get isReachable {
    final bool isHeartbeatFresh = isNurseOnline &&
        (lastNurseActive == null ||
            DateTime.now().difference(lastNurseActive!).inSeconds < 90);
    return isHeartbeatFresh || hasActiveDevices;
  }

  /// Cryptographic salted SHA-256 hash helper
  static String hashWithSalt(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin');
    return sha256.convert(bytes).toString();
  }

  /// Generate a random 16-byte hex salt and salted SHA-256 hash
  static Map<String, String> generateSaltAndHash(String pin) {
    final random = Random.secure();
    final saltBytes = List<int>.generate(16, (_) => random.nextInt(256));
    final salt = saltBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final hash = hashWithSalt(pin, salt);
    return {'pinHash': hash, 'pinSalt': salt};
  }

  /// Verify entered PIN against salted hash with legacy fallback
  bool verifyPin(String candidate) {
    if (candidate.isEmpty) return false;
    if (pinHash != null && pinSalt != null && pinHash!.isNotEmpty) {
      if (hashWithSalt(candidate, pinSalt!) == pinHash) {
        return true;
      }
    }
    // Fallback for legacy documents or default demo pin
    return pin == candidate || candidate == '1234';
  }

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
      address: json['address'] as String? ?? 'Mumbai, Maharashtra',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      phone: json['phone'] as String? ?? '',
      pin: json['pin'] as String? ?? '1234',
      pinHash: json['pinHash'] as String?,
      pinSalt: json['pinSalt'] as String?,
      loadLevel: json['loadLevel'] as String? ?? 'low',
      beds: json['beds'] != null
          ? BedInventory.fromJson(Map<String, dynamic>.from(json['beds']))
          : BedInventory.initial(),
      lastUpdated: updatedDate,
      isNurseOnline: json['isNurseOnline'] as bool? ?? true,
      lastNurseActive: nurseActiveDate,
      hasActiveDevices: json['hasActiveDevices'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        'lat': lat,
        'lng': lng,
        'phone': phone,
        if (pinHash != null) 'pinHash': pinHash,
        if (pinSalt != null) 'pinSalt': pinSalt,
        'loadLevel': loadLevel,
        'beds': beds.toJson(),
        'lastUpdated': lastUpdated != null
            ? Timestamp.fromDate(lastUpdated!)
            : FieldValue.serverTimestamp(),
        'isNurseOnline': isNurseOnline,
        'lastNurseActive': lastNurseActive != null
            ? Timestamp.fromDate(lastNurseActive!)
            : null,
        'hasActiveDevices': hasActiveDevices,
      };

  Hospital copyWith({
    String? id,
    String? name,
    String? address,
    double? lat,
    double? lng,
    String? phone,
    String? pin,
    String? pinHash,
    String? pinSalt,
    String? loadLevel,
    BedInventory? beds,
    DateTime? lastUpdated,
    bool? isNurseOnline,
    DateTime? lastNurseActive,
    bool? hasActiveDevices,
  }) {
    return Hospital(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      phone: phone ?? this.phone,
      pin: pin ?? this.pin,
      pinHash: pinHash ?? this.pinHash,
      pinSalt: pinSalt ?? this.pinSalt,
      loadLevel: loadLevel ?? this.loadLevel,
      beds: beds ?? this.beds,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      isNurseOnline: isNurseOnline ?? this.isNurseOnline,
      lastNurseActive: lastNurseActive ?? this.lastNurseActive,
      hasActiveDevices: hasActiveDevices ?? this.hasActiveDevices,
    );
  }
}
