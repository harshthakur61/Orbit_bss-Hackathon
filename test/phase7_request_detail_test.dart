import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bedlink/models/emergency_request.dart';
import 'package:bedlink/features/nurse/widgets/ambulance_info_section.dart';

void main() {
  group('Phase 7 - Requests Tab Detail & Shared Ambulance Widget Tests', () {
    testWidgets('AmbulanceInfoSection handles legacy requests with no ambulance snapshot',
        (tester) async {
      // Legacy request without ambulance snapshot
      final legacyReq = EmergencyRequest(
        id: 'legacy_001',
        patientLat: 19.05,
        patientLng: 72.82,
        needs: ['ICU Bed', 'Ventilator'],
        severity: 'critical',
        note: 'Legacy test emergency note',
        status: 'arrived',
        rankedHospitalIds: ['lilavati_bandra'],
        currentIndex: 0,
        currentHospitalId: 'lilavati_bandra',
        attempts: [],
        ambulance: null,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AmbulanceInfoSection(
              request: legacyReq,
              showCallButton: true,
            ),
          ),
        ),
      );

      // Verify fallback text is rendered cleanly without crashing
      expect(find.text('Not available'), findsWidgets);
      expect(find.text('ICU Bed'), findsOneWidget);
      expect(find.text('Ventilator'), findsOneWidget);
      expect(find.text('CRITICAL'), findsOneWidget);
      expect(find.text('"Legacy test emergency note"'), findsOneWidget);
      // No call button rendered when phone is not available
      expect(find.byIcon(Icons.phone_in_talk_rounded), findsNothing);
    });

    testWidgets('AmbulanceInfoSection displays full ambulance and driver details when present',
        (tester) async {
      final activeReq = EmergencyRequest(
        id: 'active_002',
        patientLat: 19.05,
        patientLng: 72.82,
        needs: ['Cardiac Bed'],
        severity: 'serious',
        status: 'accepted',
        rankedHospitalIds: ['lilavati_bandra'],
        currentIndex: 0,
        currentHospitalId: 'lilavati_bandra',
        attempts: [],
        ambulance: const AmbulanceSnapshot(
          ambulanceId: 'BL-AMB-202020',
          vehicleNumber: 'MH02XY9999',
          driverName: 'Rohan Sharma',
          driverPhone: '+919876543210',
          ambulanceType: 'Advanced Life Support (ALS)',
          ais125Tier: 'Type C',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AmbulanceInfoSection(
              request: activeReq,
              showCallButton: true,
            ),
          ),
        ),
      );

      expect(find.text('MH02XY9999'), findsOneWidget);
      expect(find.text('Rohan Sharma • Type C (Advanced Life Support (ALS))'), findsOneWidget);
      expect(find.text('Driver Contact: +919876543210'), findsOneWidget);
      expect(find.text('Cardiac Bed'), findsOneWidget);
      expect(find.text('SERIOUS'), findsOneWidget);
      expect(find.byIcon(Icons.phone_in_talk_rounded), findsOneWidget);
    });
  });
}
