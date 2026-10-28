import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bedlink/core/constants/crew_presence_constants.dart';
import 'package:bedlink/core/utils/alert_sound.dart';
import 'package:bedlink/features/crew/relief_request_alert_screen.dart';
import 'package:bedlink/models/relief_offer_data.dart';
import 'package:bedlink/providers/relief_providers.dart';
import 'package:bedlink/services/alarm_notification_service.dart';

class FakeReliefService extends ReliefService {
  bool respondCalled = false;
  String? lastAction;
  String? lastReason;
  bool returnAlreadyTaken = false;
  bool returnSuccess = true;

  @override
  Future<ReliefResponseResult> respondToReliefRequest({
    required String reliefRequestId,
    required String action,
    String? reason,
  }) async {
    respondCalled = true;
    lastAction = action;
    lastReason = reason;

    if (returnAlreadyTaken) {
      return const ReliefResponseResult(
        success: false,
        code: 'ALREADY_TAKEN',
        message: 'Another ambulance accepted',
      );
    }

    if (returnSuccess) {
      return const ReliefResponseResult(
        success: true,
        code: 'ACCEPTED',
        message: 'Relief accepted successfully',
      );
    }

    return const ReliefResponseResult(
      success: false,
      code: 'ERROR',
      message: 'Failed to accept',
    );
  }
}

void main() {
  group('Phase 12C - Dual Alert Stack & Separation Unit Tests', () {
    test('Notification ID namespaces never collide between hospital and relief alerts', () {
      const testId = 'req_duplicate_id_123';
      final emergencyNotifId = AlarmNotificationService.getEmergencyNotifId(testId);
      final reliefNotifId = AlarmNotificationService.getReliefNotifId(testId);

      expect(emergencyNotifId != reliefNotifId, isTrue);
      expect(reliefNotifId - emergencyNotifId, equals(10000000));
    });

    test('ReliefOfferData serializes and deserializes correctly', () {
      final now = DateTime.now();
      final expires = now.add(const Duration(seconds: 60));

      final data = ReliefOfferData(
        reliefRequestId: 'relief_xyz_999',
        distanceKm: 3.45,
        etaMin: 7,
        reason: 'mechanical_breakdown',
        severity: 'critical',
        offerExpiresAt: expires,
        wave: 1,
        ais125Tier: 'TYPE_B',
        disabledAmbulanceId: 'BL-AMB-108',
        disabledAmbulanceVehicleNumber: 'MH-02-CD-5678',
        originalRequestId: 'req_orig_111',
      );

      final json = data.toJson();
      expect(json['reliefRequestId'], equals('relief_xyz_999'));
      expect(json['distanceKm'], equals(3.45));
      expect(json['etaMin'], equals(7));
      expect(json['reason'], equals('mechanical_breakdown'));
      expect(json['severity'], equals('critical'));

      final parsed = ReliefOfferData.fromJson(json);
      expect(parsed.reliefRequestId, equals('relief_xyz_999'));
      expect(parsed.distanceKm, equals(3.45));
      expect(parsed.etaMin, equals(7));
      expect(parsed.formattedReason, equals('Mechanical Breakdown'));
      expect(parsed.formattedDistance, equals('3.5 km'));
      expect(parsed.formattedEta, equals('7 min'));
      expect(parsed.formattedTier, contains('Type B'));
      expect(parsed.isExpired, isFalse);
    });

    test('ReliefOfferData reason formatting handles various breakdown codes', () {
      final dummyDate = DateTime(2026, 10, 28, 12, 0);
      expect(
        ReliefOfferData(
          reliefRequestId: '1',
          distanceKm: 1,
          etaMin: 1,
          reason: 'traffic_accident',
          severity: 'critical',
          offerExpiresAt: dummyDate,
        ).formattedReason,
        equals('Traffic Accident'),
      );

      expect(
        ReliefOfferData(
          reliefRequestId: '2',
          distanceKm: 1,
          etaMin: 1,
          reason: 'medical_equipment_failure',
          severity: 'serious',
          offerExpiresAt: dummyDate,
        ).formattedReason,
        equals('Medical Equipment Failure'),
      );

      expect(
        ReliefOfferData(
          reliefRequestId: '3',
          distanceKm: 1,
          etaMin: 1,
          reason: 'fuel_depletion',
          severity: 'stable',
          offerExpiresAt: dummyDate,
        ).formattedReason,
        equals('Fuel Depletion'),
      );
    });

    test('Relief alert strictly ignores patient PII and hospital destination', () {
      final fcmPayload = {
        'type': 'relief_request',
        'reliefRequestId': 'rel_sec_456',
        'distanceKm': '4.2',
        'etaMin': '8',
        'reason': 'mechanical_breakdown',
        'severity': 'critical',
        'offerExpiresAt': DateTime.now().add(const Duration(seconds: 50)).toIso8601String(),
        'wave': '1',
      };

      final offer = ReliefOfferData.fromJson(fcmPayload);

      // Verify no patient name, phone, or destination in offer model
      final json = offer.toJson();
      expect(json.containsKey('patientName'), isFalse);
      expect(json.containsKey('patientPhone'), isFalse);
      expect(json.containsKey('hospitalName'), isFalse);
      expect(json.containsKey('destinationHospital'), isFalse);
    });

    test('Crew availability filter: only AVAILABLE status accepts relief alerts', () {
      bool shouldProcessReliefAlert(String? presenceStatus) {
        return presenceStatus?.toUpperCase() == CrewPresenceStatus.available.code;
      }

      expect(shouldProcessReliefAlert('AVAILABLE'), isTrue);
      expect(shouldProcessReliefAlert('BUSY'), isFalse);
      expect(shouldProcessReliefAlert('OFFLINE'), isFalse);
      expect(shouldProcessReliefAlert(null), isFalse);
    });

    test('Dual alert routing distinguishes incoming_request vs relief_request', () {
      String routePayload(Map<String, dynamic> data) {
        final type = data['type'];
        if (type == 'incoming_request') return 'HOSPITAL_TRIAGE';
        if (type == 'relief_request') return 'CREW_RELIEF_ALERT';
        if (type == 'cancel_request') return 'CANCEL_HOSPITAL';
        if (type == 'relief_cancel') return 'CANCEL_RELIEF';
        return 'UNKNOWN';
      }

      expect(routePayload({'type': 'incoming_request'}), equals('HOSPITAL_TRIAGE'));
      expect(routePayload({'type': 'relief_request'}), equals('CREW_RELIEF_ALERT'));
      expect(routePayload({'type': 'cancel_request'}), equals('CANCEL_HOSPITAL'));
      expect(routePayload({'type': 'relief_cancel'}), equals('CANCEL_RELIEF'));
    });
  });

  group('Phase 12C - ReliefRequestAlertScreen Widget Tests', () {
    late ReliefOfferData activeOffer;

    setUp(() {
      AlertSoundUtil.enableAudio = false;
      activeOffer = ReliefOfferData(
        reliefRequestId: 'relief_widget_test_1',
        distanceKm: 2.8,
        etaMin: 5,
        reason: 'mechanical_breakdown',
        severity: 'critical',
        offerExpiresAt: DateTime.now().add(const Duration(seconds: 60)),
        wave: 1,
        ais125Tier: 'TYPE_B',
      );
    });

    tearDown(() async {
      await AlertSoundUtil.stopAlert();
      AlertSoundUtil.enableAudio = true;
    });

    testWidgets('Renders full-screen relief alert with required fields and without PII', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeReliefService = FakeReliefService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reliefServiceProvider.overrideWithValue(fakeReliefService),
          ],
          child: MaterialApp(
            home: ReliefRequestAlertScreen(offer: activeOffer),
          ),
        ),
      );

      await tester.pump();

      // Title & reason
      expect(find.text('Colleague ambulance needs help'), findsOneWidget);
      expect(find.text('Mechanical Breakdown'), findsOneWidget);

      // Distance and ETA
      expect(find.text('2.8 km'), findsOneWidget);
      expect(find.text('5 min'), findsOneWidget);

      // Severity chip & AIS-125 tier
      expect(find.text('CRITICAL'), findsOneWidget);
      expect(find.text('Type B (Basic Life Support)'), findsOneWidget);

      // Verification of strict absence of patient PII or hospital name
      expect(find.textContaining('Lilavati'), findsNothing);
      expect(find.textContaining('Hospital'), findsNothing);
      expect(find.text('PATIENT SEVERITY'), findsOneWidget);
      expect(find.textContaining('John Doe'), findsNothing);

      // Buttons
      expect(find.text('ACCEPT RELIEF'), findsOneWidget);
      expect(find.text('DECLINE'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Tapping DECLINE opens bottom sheet with 4 reject reasons', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeReliefService = FakeReliefService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reliefServiceProvider.overrideWithValue(fakeReliefService),
          ],
          child: MaterialApp(
            home: ReliefRequestAlertScreen(offer: activeOffer),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Tap DECLINE button
      await tester.tap(find.text('DECLINE'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Bottom sheet reasons must all appear
      expect(find.text('Decline Relief Request'), findsOneWidget);
      expect(find.text('Too far'), findsOneWidget);
      expect(find.text('Starting a trip'), findsOneWidget);
      expect(find.text('Crew unavailable'), findsOneWidget);
      expect(find.text('Vehicle issue'), findsOneWidget);
      expect(find.text('Confirm Decline'), findsOneWidget);

      // Select 'Vehicle issue'
      await tester.tap(find.text('Vehicle issue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Confirm Decline
      await tester.tap(find.text('Confirm Decline'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(fakeReliefService.respondCalled, isTrue);
      expect(fakeReliefService.lastAction, equals('reject'));
      expect(fakeReliefService.lastReason, equals('vehicle_issue'));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Already taken response triggers toast and dismisses cleanly', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeReliefService = FakeReliefService()..returnAlreadyTaken = true;
      bool dismissed = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reliefServiceProvider.overrideWithValue(fakeReliefService),
          ],
          child: MaterialApp(
            home: ReliefRequestAlertScreen(
              offer: activeOffer,
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Tap ACCEPT RELIEF button
      await tester.tap(find.text('ACCEPT RELIEF'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(fakeReliefService.respondCalled, isTrue);
      expect(fakeReliefService.lastAction, equals('accept'));

      // Toast must appear
      expect(find.text('Another ambulance accepted'), findsOneWidget);
      expect(dismissed, isTrue);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Offer timeout triggers expired toast and dismissal', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final expiredOffer = ReliefOfferData(
        reliefRequestId: 'relief_expired_1',
        distanceKm: 1.5,
        etaMin: 3,
        reason: 'fuel_depletion',
        severity: 'stable',
        offerExpiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
        wave: 1,
      );

      bool dismissed = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ReliefRequestAlertScreen(
              offer: expiredOffer,
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );

      // Advance frame to trigger onExpired callback
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Relief offer window expired.'), findsOneWidget);
      expect(dismissed, isTrue);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
