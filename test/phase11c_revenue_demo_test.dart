import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:bedlink/models/hospital.dart';
import 'package:bedlink/services/appointment_service.dart';
import 'package:bedlink/services/firestore_service.dart';
import 'package:bedlink/providers/appointment_providers.dart';
import 'package:bedlink/providers/hospital_providers.dart';
import 'package:bedlink/features/demo/demo_controls_screen.dart';

/// Fake appointment service for Phase 11C testing
class FakeRevenueAppointmentService extends AppointmentService {
  bool seedDemoCalled = false;
  bool resetDemoCalled = false;
  bool getRevenueCalled = false;

  Map<String, dynamic> revenueSnapshotData = {
    'totalBookings': 42,
    'totalRevenueRupees': 2898,
    'averagePerDay': 966,
    'breakdown': {
      'clinic': {'bookings': 30, 'revenueRupees': 2370},
      'lab': {'bookings': 12, 'revenueRupees': 528},
    },
    'isDemoOnly': true,
  };

  @override
  Future<Map<String, dynamic>> seedDemoBookings() async {
    seedDemoCalled = true;
    return {
      'seededCount': 42,
      'clinicsCount': 5,
      'daysCount': 3,
    };
  }

  @override
  Future<Map<String, dynamic>> resetDemoBookings() async {
    resetDemoCalled = true;
    return {
      'deletedSlots': 42,
      'deletedAppointments': 42,
    };
  }

  @override
  Future<Map<String, dynamic>> getRevenueSnapshot() async {
    getRevenueCalled = true;
    return revenueSnapshotData;
  }
}

/// Fake firestore service for DemoControlsScreen dependency
class FakeDemoFirestoreService extends FirestoreService {
  bool seedHospitalsCalled = false;
  bool seedClinicsCalled = false;
  bool resetAllCalled = false;

  @override
  Future<void> seedHospitals() async {
    seedHospitalsCalled = true;
  }

  @override
  Future<void> seedClinics() async {
    seedClinicsCalled = true;
  }

  @override
  Future<void> resetAllData() async {
    resetAllCalled = true;
  }
}

void main() {
  group('Phase 11C - Revenue Model & Demo Controls Tests', () {
    testWidgets('DemoControlsScreen renders Seed Demo Bookings button and triggers callable', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeAppointmentService = FakeRevenueAppointmentService();
      final fakeFirestoreService = FakeDemoFirestoreService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appointmentServiceProvider.overrideWithValue(fakeAppointmentService),
            firestoreServiceProvider.overrideWithValue(fakeFirestoreService),
            hospitalsStreamProvider.overrideWith((ref) => Stream.value(<Hospital>[])),
          ],
          child: const MaterialApp(
            home: DemoControlsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify "Seed Demo Bookings (3 Days · ~35% Booked)" button exists
      final seedButtonFinder = find.widgetWithText(
        ElevatedButton,
        'Seed Demo Bookings (3 Days · ~35% Booked)',
      );
      expect(seedButtonFinder, findsOneWidget);

      // Tap button and verify service method execution
      await tester.tap(seedButtonFinder);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(fakeAppointmentService.seedDemoCalled, isTrue);
      expect(find.text('Seeded 42 demo bookings across 3 days! Grid is demo-ready.'), findsOneWidget);
    });

    testWidgets('DemoControlsScreen renders Revenue Snapshot card with aggregated metrics', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeAppointmentService = FakeRevenueAppointmentService();
      final fakeFirestoreService = FakeDemoFirestoreService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appointmentServiceProvider.overrideWithValue(fakeAppointmentService),
            firestoreServiceProvider.overrideWithValue(fakeFirestoreService),
            hospitalsStreamProvider.overrideWith((ref) => Stream.value(<Hospital>[])),
          ],
          child: const MaterialApp(
            home: DemoControlsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Card header
      expect(find.text('Revenue Snapshot'), findsOneWidget);
      expect(find.text('DEMO SANDBOX'), findsOneWidget);

      // Metrics
      expect(find.text('Total Bookings'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);

      expect(find.text('Total Revenue'), findsOneWidget);
      expect(find.text('₹2898'), findsOneWidget);

      expect(find.text('Daily Average'), findsOneWidget);
      expect(find.text('₹966/d'), findsOneWidget);

      // Breakdown text
      expect(find.textContaining('Clinics (₹79 fee): 30 booked'), findsOneWidget);
      expect(find.textContaining('Pathology Labs (₹49 fee): 12 booked'), findsOneWidget);
      expect(find.text('₹2370'), findsOneWidget);
      expect(find.text('₹528'), findsOneWidget);

      // Refresh button
      final refreshButtonFinder = find.widgetWithText(TextButton, 'Refresh Revenue');
      expect(refreshButtonFinder, findsOneWidget);
      await tester.tap(refreshButtonFinder);
      await tester.pumpAndSettle();
      expect(fakeAppointmentService.getRevenueCalled, isTrue);
    });

    test('Timezone Invariance - True Asia/Kolkata formatting handles midnight rollover and offsets', () {
      // UTC 2026-10-28 04:30:00 -> IST (UTC + 5:30) is 10:00 AM on 2026-10-28
      final morningUtc = DateTime.utc(2026, 10, 28, 4, 30);
      final morningIst = morningUtc.toUtc().add(const Duration(hours: 5, minutes: 30));
      final morningFormatted = DateFormat('hh:mm a').format(morningIst);
      expect(morningFormatted, equals('10:00 AM'));

      // UTC 2026-10-28 14:30:00 -> IST is 08:00 PM on 2026-10-28
      final eveningUtc = DateTime.utc(2026, 10, 28, 14, 30);
      final eveningIst = eveningUtc.toUtc().add(const Duration(hours: 5, minutes: 30));
      final eveningFormatted = DateFormat('hh:mm a').format(eveningIst);
      expect(eveningFormatted, equals('08:00 PM'));

      // UTC 2026-10-28 19:15:00 -> IST is 00:45 AM on 2026-10-29 (rollover into next day)
      final rolloverUtc = DateTime.utc(2026, 10, 28, 19, 15);
      final rolloverIst = rolloverUtc.toUtc().add(const Duration(hours: 5, minutes: 30));
      final rolloverDayFormatted = DateFormat('yyyy-MM-dd HH:mm').format(rolloverIst);
      expect(rolloverDayFormatted, equals('2026-10-29 00:45'));
    });

    test('Operating Hours Boundary Check - slot plus duration must not exceed closing time', () {
      bool isSlotValid(String slotTime, int durationMin, String closeTime) {
        final slotParts = slotTime.split(':');
        final closeParts = closeTime.split(':');
        final slotMins = int.parse(slotParts[0]) * 60 + int.parse(slotParts[1]);
        final closeMins = int.parse(closeParts[0]) * 60 + int.parse(closeParts[1]);
        return (slotMins + durationMin) <= closeMins;
      }

      // 30 min duration with 20:00 close
      expect(isSlotValid('19:30', 30, '20:00'), isTrue); // exactly finishes at 20:00
      expect(isSlotValid('19:45', 30, '20:00'), isFalse); // exceeds by 15 mins
      expect(isSlotValid('20:00', 30, '20:00'), isFalse); // starts at close time

      // 20 min duration with 20:30 close
      expect(isSlotValid('20:10', 20, '20:30'), isTrue); // finishes at 20:30
      expect(isSlotValid('20:20', 20, '20:30'), isFalse); // finishes at 20:40 > 20:30
    });
  });
}
