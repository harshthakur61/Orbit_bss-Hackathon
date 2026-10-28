import 'package:flutter_test/flutter_test.dart';
import 'package:bedlink/core/constants/booking_constants.dart';
import 'package:bedlink/models/clinic.dart';

void main() {
  group('Phase 11A - Clinic & Lab Booking Data Model Tests', () {
    test('BookingConstants provides valid clinical defaults', () {
      expect(BookingConstants.defaultClinicBookingFeeRupees, equals(79));
      expect(BookingConstants.defaultLabBookingFeeRupees, equals(49));
      expect(BookingConstants.defaultSlotDurationMinutes, equals(30));
      expect(BookingConstants.slotHoldDurationMinutes, equals(5));
      expect(BookingConstants.minimumLeadMinutes, equals(30));
      expect(BookingConstants.maxAdvanceBookingDays, equals(7));
      expect(BookingConstants.canonicalTimeZone, equals('Asia/Kolkata'));

      expect(BookingConstants.resolveDefaultFeeRupees('clinic'), equals(79));
      expect(BookingConstants.resolveDefaultFeeRupees('pathology_lab'), equals(49));
      expect(BookingConstants.resolveDefaultFeeRupees('diagnostic_center'), equals(49));
    });

    test('Clinic.fromJson handles legacy documents with full null-safe defaults', () {
      final legacyJson = {
        'name': 'Old Legacy Clinic',
        'type': 'clinic',
        'lat': 19.055,
        'lng': 72.832,
        'phone': '+91 22 1234 5678',
        'address': 'Bandra West, Mumbai',
        'rating': 4.5,
        'isOpen': true,
        'operatingHours': '8:00 AM - 8:00 PM',
        'specialties': ['General Physician'],
        'testsAvailable': ['Blood Pressure Check'],
      };

      final clinic = Clinic.fromJson(legacyJson, 'legacy_clinic_1');

      expect(clinic.id, equals('legacy_clinic_1'));
      expect(clinic.openTime, equals('08:00'));
      expect(clinic.closeTime, equals('20:00'));
      expect(clinic.slotDurationMin, equals(30));
      expect(clinic.bookingFeeRupees, equals(79));
      expect(clinic.weeklyOffDays, isEmpty);
    });

    test('Clinic.fromJson and toJson roundtrip preserves all Phase 11A fields', () {
      final fullJson = {
        'name': 'Metropolis Healthcare & Diagnostic Centre',
        'type': 'pathology_lab',
        'lat': 19.1190,
        'lng': 72.8470,
        'phone': '+91 22 2636 8899',
        'address': 'SV Road, Andheri West, Mumbai',
        'rating': 4.7,
        'isOpen': true,
        'operatingHours': '07:30 AM - 08:30 PM',
        'specialties': ['Blood Tests & Pathology', 'Ultrasound'],
        'testsAvailable': ['Lipid Profile', 'Vitamin D'],
        'openTime': '07:30',
        'closeTime': '20:30',
        'slotDurationMin': 20,
        'bookingFeeRupees': 49,
        'weeklyOffDays': [7],
      };

      final clinic = Clinic.fromJson(fullJson, 'metropolis_andheri');

      expect(clinic.id, equals('metropolis_andheri'));
      expect(clinic.type, equals('pathology_lab'));
      expect(clinic.openTime, equals('07:30'));
      expect(clinic.closeTime, equals('20:30'));
      expect(clinic.slotDurationMin, equals(20));
      expect(clinic.bookingFeeRupees, equals(49));
      expect(clinic.weeklyOffDays, equals([7]));

      final serialized = clinic.toJson();
      expect(serialized['openTime'], equals('07:30'));
      expect(serialized['closeTime'], equals('20:30'));
      expect(serialized['slotDurationMin'], equals(20));
      expect(serialized['bookingFeeRupees'], equals(49));
      expect(serialized['weeklyOffDays'], equals([7]));
    });

    test('Clinic.copyWith updates specific fields while retaining others', () {
      const original = Clinic(
        id: 'c1',
        name: 'Original Clinic',
        type: 'clinic',
        lat: 19.0,
        lng: 72.0,
        phone: '123',
        address: 'Mumbai',
        rating: 4.0,
        isOpen: true,
        operatingHours: '9 to 5',
        specialties: [],
        testsAvailable: [],
      );

      final updated = original.copyWith(
        bookingFeeRupees: 99,
        weeklyOffDays: [6, 7],
      );

      expect(updated.bookingFeeRupees, equals(99));
      expect(updated.weeklyOffDays, equals([6, 7]));
      expect(updated.name, equals('Original Clinic'));
      expect(updated.openTime, equals('08:00'));
    });
  });
}
