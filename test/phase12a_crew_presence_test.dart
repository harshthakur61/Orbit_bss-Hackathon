import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bedlink/core/constants/crew_presence_constants.dart';
import 'package:bedlink/models/ambulance.dart';
import 'package:bedlink/models/crew_presence.dart';
import 'package:bedlink/services/crew_presence_service.dart';
import 'package:bedlink/providers/ambulance_auth_provider.dart';
import 'package:bedlink/providers/crew_presence_providers.dart';
import 'package:bedlink/features/crew/crew_profile_tab.dart';
import 'package:bedlink/features/crew/widgets/crew_status_pill.dart';

/// Fake CrewPresenceService for testing without live Firebase/Geolocator
class FakeCrewPresenceService extends CrewPresenceService {
  CrewPresenceStatus testStatus = CrewPresenceStatus.offline;
  bool testLocationDenied = false;
  String? lastSetStatusUid;
  CrewPresenceStatus? lastSetStatus;
  bool restorePreviousCalled = false;

  @override
  CrewPresenceStatus get currentStatus => testStatus;

  @override
  bool get isLocationPermissionDenied => testLocationDenied;

  @override
  Future<void> initializeStatus(String uid) async {}

  @override
  Future<void> setCrewStatus(
    String uid,
    CrewPresenceStatus newStatus, {
    required Ambulance? ambulance,
    bool recordPrevious = true,
  }) async {
    lastSetStatusUid = uid;
    lastSetStatus = newStatus;
    testStatus = newStatus;
    notifyListeners();
  }

  @override
  Future<void> restorePreviousStatus(
    String uid, {
    required Ambulance? ambulance,
  }) async {
    restorePreviousCalled = true;
    testStatus = CrewPresenceStatus.available;
    notifyListeners();
  }
}

void main() {
  const testAmbulance = Ambulance(
    uid: 'crew_test_123',
    applicationRef: 'APP-123456',
    ambulanceId: 'BL-AMB-100001',
    vehicleNumber: 'MH01AB1234',
    driverLegalName: 'Ramesh Kumar',
    dlNumber: 'DL-0420110012345',
    ais125Tier: 'TYPE_C',
    ambulanceType: 'GOVERNMENT',
    contactNumber: '+919876543210',
    verificationStatus: AmbulanceVerificationStatus.verified,
  );

  group('Phase 12A - Crew Presence Data Model & Relief Eligibility Tests', () {
    test('CrewPresence roundtrip serialization preserves all presence fields', () {
      final now = DateTime.utc(2026, 10, 28, 10, 30);
      final presence = CrewPresence(
        uid: 'crew_test_123',
        ambulanceId: 'BL-AMB-100001',
        ais125Tier: 'TYPE_C',
        status: CrewPresenceStatus.available,
        lat: 19.0760,
        lng: 72.8777,
        accuracyMeters: 12.5,
        updatedAt: now,
      );

      final json = presence.toJson();
      expect(json['ambulanceId'], equals('BL-AMB-100001'));
      expect(json['ais125Tier'], equals('TYPE_C'));
      expect(json['status'], equals('AVAILABLE'));
      expect(json['lat'], equals(19.0760));
      expect(json['lng'], equals(72.8777));
      expect(json['accuracyMeters'], equals(12.5));

      final deserialized = CrewPresence.fromJson(json, 'crew_test_123');
      expect(deserialized.uid, equals('crew_test_123'));
      expect(deserialized.status, equals(CrewPresenceStatus.available));
      expect(deserialized.lat, equals(19.0760));
      expect(deserialized.lng, equals(72.8777));
      expect(deserialized.accuracyMeters, equals(12.5));
    });

    test('isCrewEligibleForRelief strictly validates status, 120s recency, and device tokens', () {
      final baseNow = DateTime.utc(2026, 10, 28, 12, 0, 0);

      // Eligible: AVAILABLE, 30s old, 1 active token
      expect(
        CrewPresenceConstants.isCrewEligibleForRelief(
          status: CrewPresenceStatus.available,
          updatedAt: baseNow.subtract(const Duration(seconds: 30)),
          activeDeviceTokensCount: 1,
          now: baseNow,
        ),
        isTrue,
      );

      // Ineligible: status is BUSY
      expect(
        CrewPresenceConstants.isCrewEligibleForRelief(
          status: CrewPresenceStatus.busy,
          updatedAt: baseNow.subtract(const Duration(seconds: 30)),
          activeDeviceTokensCount: 1,
          now: baseNow,
        ),
        isFalse,
      );

      // Ineligible: status is OFFLINE
      expect(
        CrewPresenceConstants.isCrewEligibleForRelief(
          status: CrewPresenceStatus.offline,
          updatedAt: baseNow.subtract(const Duration(seconds: 30)),
          activeDeviceTokensCount: 1,
          now: baseNow,
        ),
        isFalse,
      );

      // Ineligible: stale presence (121 seconds old > 120s threshold)
      expect(
        CrewPresenceConstants.isCrewEligibleForRelief(
          status: CrewPresenceStatus.available,
          updatedAt: baseNow.subtract(const Duration(seconds: 121)),
          activeDeviceTokensCount: 1,
          now: baseNow,
        ),
        isFalse,
      );

      // Eligible: exactly at boundary (120 seconds old)
      expect(
        CrewPresenceConstants.isCrewEligibleForRelief(
          status: CrewPresenceStatus.available,
          updatedAt: baseNow.subtract(const Duration(seconds: 120)),
          activeDeviceTokensCount: 1,
          now: baseNow,
        ),
        isTrue,
      );

      // Ineligible: 0 device tokens registered
      expect(
        CrewPresenceConstants.isCrewEligibleForRelief(
          status: CrewPresenceStatus.available,
          updatedAt: baseNow.subtract(const Duration(seconds: 30)),
          activeDeviceTokensCount: 0,
          now: baseNow,
        ),
        isFalse,
      );

      // Ineligible: null updatedAt
      expect(
        CrewPresenceConstants.isCrewEligibleForRelief(
          status: CrewPresenceStatus.available,
          updatedAt: null,
          activeDeviceTokensCount: 1,
          now: baseNow,
        ),
        isFalse,
      );
    });
  });

  group('Phase 12A - Status Selector Widget & Amber Warning Tests', () {
    testWidgets('CrewProfileTab renders 3-option selector chips with descriptions', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeService = FakeCrewPresenceService();
      fakeService.testStatus = CrewPresenceStatus.offline;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentAmbulanceProvider.overrideWith((ref) => Stream.value(testAmbulance)),
            crewPresenceServiceProvider.overrideWithValue(fakeService),
          ],
          child: const MaterialApp(
            home: CrewProfileTab(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify "Availability Status" header
      expect(find.text('Availability Status'), findsOneWidget);

      // Verify all 3 option chips are present
      expect(find.text('Available'), findsWidgets);
      expect(find.text('Online – Busy'), findsOneWidget);
      expect(find.text('Offline'), findsWidgets);

      // Verify Offline description is rendered initially
      expect(find.text(CrewPresenceStatus.offline.description), findsOneWidget);

      // Tap "Available" chip
      await tester.tap(find.text('Available').first);
      await tester.pumpAndSettle();

      expect(fakeService.lastSetStatus, equals(CrewPresenceStatus.available));
      expect(fakeService.lastSetStatusUid, equals('crew_test_123'));
      expect(find.text(CrewPresenceStatus.available.description), findsOneWidget);

      // Tap "Online – Busy" chip
      await tester.tap(find.text('Online – Busy'));
      await tester.pumpAndSettle();

      expect(fakeService.lastSetStatus, equals(CrewPresenceStatus.busy));
      expect(find.text(CrewPresenceStatus.busy.description), findsOneWidget);
    });

    testWidgets('Renders amber location warning when Available and location is denied', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeService = FakeCrewPresenceService();
      fakeService.testStatus = CrewPresenceStatus.available;
      fakeService.testLocationDenied = true;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentAmbulanceProvider.overrideWith((ref) => Stream.value(testAmbulance)),
            crewPresenceServiceProvider.overrideWithValue(fakeService),
          ],
          child: const MaterialApp(
            home: CrewProfileTab(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Amber warning banner must appear
      expect(
        find.text("Location off – you won't receive relief requests"),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });
  });

  group('Phase 12A - CrewStatusPill & Header Shell Tests', () {
    testWidgets('CrewStatusPill renders correct colors and responds to tap', (tester) async {
      final fakeService = FakeCrewPresenceService();
      fakeService.testStatus = CrewPresenceStatus.available;

      bool tapped = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            crewPresenceServiceProvider.overrideWithValue(fakeService),
          ],
          child: MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                actions: [
                  CrewStatusPill(onTap: () => tapped = true),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Available'), findsOneWidget);

      await tester.tap(find.byType(CrewStatusPill));
      await tester.pump();
      expect(tapped, isTrue);

      // Change status to Busy and verify label update
      fakeService.testStatus = CrewPresenceStatus.busy;
      fakeService.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Online – Busy'), findsOneWidget);

      // Change status to Offline and verify label update
      fakeService.testStatus = CrewPresenceStatus.offline;
      fakeService.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Offline'), findsOneWidget);
    });

    test('restorePreviousStatus restores previous available state', () async {
      final fakeService = FakeCrewPresenceService();
      fakeService.testStatus = CrewPresenceStatus.busy;

      await fakeService.restorePreviousStatus('crew_test_123', ambulance: testAmbulance);
      expect(fakeService.restorePreviousCalled, isTrue);
      expect(fakeService.currentStatus, equals(CrewPresenceStatus.available));
    });
  });
}
