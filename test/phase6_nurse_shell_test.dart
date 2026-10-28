import 'package:flutter_test/flutter_test.dart';
import 'package:bedlink/models/hospital.dart';
import 'package:bedlink/models/bed_inventory.dart';

void main() {
  group('Phase 6 - Nurse Profile, Security & Hospital Model Tests', () {
    test('Hospital model parses address with fallback', () {
      final json = <String, dynamic>{
        'name': 'Lilavati Hospital',
        'address': 'Bandra Reclamation, Mumbai',
        'lat': 19.0512,
        'lng': 72.8285,
        'phone': '+91 22 2675 1000',
        'pin': '1234',
        'loadLevel': 'med',
      };

      final hospital = Hospital.fromJson(json, 'lilavati_bandra');
      expect(hospital.name, 'Lilavati Hospital');
      expect(hospital.address, 'Bandra Reclamation, Mumbai');
      expect(hospital.phone, '+91 22 2675 1000');
    });

    test('Hospital model provides default address fallback if omitted', () {
      final json = <String, dynamic>{
        'name': 'City Hospital',
        'lat': 19.0000,
        'lng': 72.8000,
        'phone': '+91 22 0000 0000',
        'pin': '1234',
        'loadLevel': 'low',
      };

      final hospital = Hospital.fromJson(json, 'city_hosp');
      expect(hospital.address, 'Mumbai, Maharashtra');
    });

    test('Salted SHA-256 PIN generation and verification', () {
      final creds = Hospital.generateSaltAndHash('5678');
      final salt = creds['pinSalt']!;
      final hash = creds['pinHash']!;

      expect(salt, isNotEmpty);
      expect(hash, isNotEmpty);
      expect(salt.length, 32); // 16 bytes hex = 32 chars

      final hospital = Hospital(
        id: 'test_hosp',
        name: 'Test Hospital',
        address: 'Test Address',
        lat: 19.0,
        lng: 72.8,
        phone: '+91 22 1111 2222',
        pin: '1234',
        pinHash: hash,
        pinSalt: salt,
        loadLevel: 'low',
        beds: BedInventory.initial(),
      );

      // Candidate matches
      expect(hospital.verifyPin('5678'), isTrue);

      // Wrong candidate fails
      expect(hospital.verifyPin('0000'), isFalse);
      expect(hospital.verifyPin('12345'), isFalse);
      expect(hospital.verifyPin(''), isFalse);
    });

    test('Hospital legacy fallback PIN verification works when hash is absent', () {
      const hospital = Hospital(
        id: 'legacy_hosp',
        name: 'Legacy Hospital',
        lat: 19.0,
        lng: 72.8,
        phone: '+91 22 1111 2222',
        pin: '9876',
        loadLevel: 'low',
        beds: BedInventory(
          icu: BedCount(available: 2, total: 5),
          ventilator: BedCount(available: 1, total: 2),
          oxygen: BedCount(available: 5, total: 10),
          cardiac: BedCount(available: 1, total: 3),
          burns: BedCount(available: 0, total: 1),
          general: BedCount(available: 10, total: 20),
        ),
      );

      // Matches explicit legacy PIN or universal demo PIN
      expect(hospital.verifyPin('9876'), isTrue);
      expect(hospital.verifyPin('1234'), isTrue);
      expect(hospital.verifyPin('5555'), isFalse);
    });

    test('toJson excludes plaintext pin and includes pinHash, pinSalt, and address', () {
      final creds = Hospital.generateSaltAndHash('4321');
      final hospital = Hospital(
        id: 'hosp_sec',
        name: 'Secure Hospital',
        address: 'Marine Lines, Mumbai',
        lat: 18.94,
        lng: 72.82,
        phone: '+91 22 9999 8888',
        pin: '1234',
        pinHash: creds['pinHash'],
        pinSalt: creds['pinSalt'],
        loadLevel: 'low',
        beds: BedInventory.initial(),
      );

      final json = hospital.toJson();
      expect(json.containsKey('pin'), isFalse); // Plaintext PIN must NOT be in JSON
      expect(json['address'], 'Marine Lines, Mumbai');
      expect(json['pinHash'], creds['pinHash']);
      expect(json['pinSalt'], creds['pinSalt']);
    });
  });
}
