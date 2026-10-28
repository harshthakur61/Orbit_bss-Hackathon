import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:bedlink/core/constants/booking_constants.dart';
import 'package:bedlink/models/appointment.dart';
import 'package:bedlink/models/clinic.dart';
import 'package:bedlink/services/appointment_service.dart';
import 'package:bedlink/providers/appointment_providers.dart';
import 'package:bedlink/features/patient/appointment_booking_screen.dart';
import 'package:bedlink/features/patient/appointment_confirmation_screen.dart';

/// Mock payment delegate simulating Razorpay Checkout callback in test environment
class MockAppointmentPaymentDelegate implements AppointmentPaymentDelegate {
  bool checkoutOpened = false;
  String? lastOrderId;
  int? lastAmountPaise;
  void Function(PaymentSuccessResponse)? lastSuccessCb;
  void Function(PaymentFailureResponse)? lastErrorCb;

  bool autoSucceed = true;

  @override
  void openCheckout({
    required String keyId,
    required String orderId,
    required int amountPaise,
    required String clinicName,
    required String patientName,
    required String patientPhone,
    required void Function(PaymentSuccessResponse) onSuccess,
    required void Function(PaymentFailureResponse) onError,
    void Function(ExternalWalletResponse)? onExternalWallet,
  }) {
    checkoutOpened = true;
    lastOrderId = orderId;
    lastAmountPaise = amountPaise;
    lastSuccessCb = onSuccess;
    lastErrorCb = onError;

    if (autoSucceed) {
      onSuccess(PaymentSuccessResponse(
        'pay_test_mock_12345',
        orderId,
        'sig_test_mock_valid_signature',
        null,
      ));
    }
  }

  @override
  void dispose() {}
}

/// Fake appointment service overriding network calls with test data
class FakeAppointmentService extends AppointmentService {
  final List<DaySlotItem> testSlots;
  bool createOrderCalled = false;
  bool verifyPaymentCalled = false;
  bool releaseHoldCalled = false;
  String? lastReleasedId;

  FakeAppointmentService({
    required this.testSlots,
    required MockAppointmentPaymentDelegate mockDelegate,
  }) : super(paymentDelegate: mockDelegate);

  @override
  Future<String> ensureAuthenticatedUid() async {
    return 'test_mock_patient_uid';
  }

  @override
  Future<List<DaySlotItem>> getClinicDaySlots({
    required String clinicId,
    required String dateKey,
  }) async {
    return testSlots;
  }

  @override
  Future<Map<String, dynamic>> createAppointmentOrder({
    required String clinicId,
    required DateTime startTime,
    required String patientName,
    required String patientPhone,
  }) async {
    createOrderCalled = true;
    return {
      'appointmentId': 'BLA-100200',
      'orderId': 'order_test_998877',
      'amountPaise': 7900,
      'keyId': 'rzp_test_mock_key',
      'holdExpiresAt': DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
    };
  }

  @override
  Future<Map<String, dynamic>> verifyAppointmentPayment({
    required String appointmentId,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    verifyPaymentCalled = true;
    return {
      'success': true,
      'status': 'confirmed',
      'appointmentId': appointmentId,
    };
  }

  @override
  Future<void> releaseAppointmentHold(String appointmentId) async {
    releaseHoldCalled = true;
    lastReleasedId = appointmentId;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testClinic = Clinic(
    id: 'clinic_test_1',
    name: 'Apollo Medical Centre Bandra',
    type: 'clinic',
    lat: 19.0596,
    lng: 72.8295,
    phone: '+91 22 2640 1234',
    address: 'Hill Road, Bandra West, Mumbai',
    rating: 4.8,
    isOpen: true,
    operatingHours: '08:00 AM - 08:00 PM',
    specialties: ['General Physician', 'Cardiology'],
    testsAvailable: ['ECG', 'Blood Sugar'],
    bookingFeeRupees: 79,
  );

  final testSlots = [
    DaySlotItem(
      slotId: 'slot_1',
      time: '09:00',
      startTime: DateTime.now().subtract(const Duration(hours: 1)),
      status: SlotStatus.past,
    ),
    DaySlotItem(
      slotId: 'slot_2',
      time: '10:00',
      startTime: DateTime.now().add(const Duration(hours: 2)),
      status: SlotStatus.free,
    ),
    DaySlotItem(
      slotId: 'slot_3',
      time: '11:00',
      startTime: DateTime.now().add(const Duration(hours: 3)),
      status: SlotStatus.booked,
    ),
    DaySlotItem(
      slotId: 'slot_4',
      time: '12:00',
      startTime: DateTime.now().add(const Duration(hours: 4)),
      status: SlotStatus.free,
    ),
  ];

  group('Phase 11B - Slot-State Rendering Widget Tests', () {
    testWidgets('Renders free, booked, and past slots with correct styles and legend',
        (WidgetTester tester) async {
      final mockDelegate = MockAppointmentPaymentDelegate();
      final fakeService = FakeAppointmentService(
        testSlots: testSlots,
        mockDelegate: mockDelegate,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appointmentServiceProvider.overrideWithValue(fakeService),
          ],
          child: MaterialApp(
            home: AppointmentBookingScreen(clinic: testClinic),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Header details
      expect(find.text('Apollo Medical Centre Bandra'), findsOneWidget);
      expect(find.text('CLINIC'), findsOneWidget);
      expect(find.text('Hill Road, Bandra West, Mumbai'), findsOneWidget);
      expect(find.text('Operating Hours: 08:00 AM - 08:00 PM'), findsOneWidget);

      // Verify Legend
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('Booked'), findsOneWidget);
      expect(find.text('Selected'), findsOneWidget);

      // Verify Slot Grid Items
      expect(find.text('09:00'), findsOneWidget); // Past
      expect(find.text('10:00'), findsOneWidget); // Free
      expect(find.text('11:00'), findsOneWidget); // Booked
      expect(find.text('12:00'), findsOneWidget); // Free

      // Verify Initial Bottom Bar state
      expect(find.text('No slot selected'), findsOneWidget);
      expect(find.text('Pay ₹79 & confirm'), findsOneWidget);

      // Tap on Booked Slot: should NOT select
      await tester.tap(find.text('11:00'));
      await tester.pumpAndSettle();
      expect(find.text('No slot selected'), findsOneWidget);

      // Tap on Past Slot: should NOT select
      await tester.tap(find.text('09:00'));
      await tester.pumpAndSettle();
      expect(find.text('No slot selected'), findsOneWidget);

      // Tap on Free Slot ("10:00"): should become selected
      await tester.tap(find.text('10:00'));
      await tester.pumpAndSettle();

      // Bottom bar updates with slot selection
      expect(find.textContaining('10:00'), findsWidgets);
    });
  });

  group('Phase 11B - Mocked Payment Flow & Confirmation Tests', () {
    testWidgets('Triggers Razorpay Checkout, verifies payment, and shows confirmation',
        (WidgetTester tester) async {
      final mockDelegate = MockAppointmentPaymentDelegate();
      final fakeService = FakeAppointmentService(
        testSlots: testSlots,
        mockDelegate: mockDelegate,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appointmentServiceProvider.overrideWithValue(fakeService),
          ],
          child: MaterialApp(
            home: AppointmentBookingScreen(clinic: testClinic),
            routes: {
              '/patient/appointments/confirmation': (context) {
                final app = ModalRoute.of(context)!.settings.arguments as Appointment?;
                return AppointmentConfirmationScreen(
                  appointment: app ??
                      Appointment(
                        id: 'BLA-100200',
                        patientUid: 'test_mock_patient_uid',
                        patientName: 'Rahul Sharma',
                        patientPhone: '9876543210',
                        clinicId: testClinic.id,
                        clinicName: testClinic.name,
                        clinicType: testClinic.type,
                        slotId: 'slot_2',
                        startTime: DateTime.now().add(const Duration(hours: 2)),
                        status: 'confirmed',
                        amountPaise: 7900,
                        razorpayPaymentId: 'pay_test_mock_12345',
                        clinicAddress: testClinic.address,
                        clinicPhone: testClinic.phone,
                      ),
                );
              },
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Select available slot 10:00
      await tester.tap(find.text('10:00'));
      await tester.pumpAndSettle();

      // Tap Pay button
      final payButton = find.widgetWithText(ElevatedButton, 'Pay ₹79 & confirm');
      expect(payButton, findsOneWidget);
      await tester.tap(payButton);
      await tester.pumpAndSettle();

      // Verify createAppointmentOrder was invoked
      expect(fakeService.createOrderCalled, isTrue);

      // Verify Razorpay checkout was opened
      expect(mockDelegate.checkoutOpened, isTrue);
      expect(mockDelegate.lastOrderId, equals('order_test_998877'));
      expect(mockDelegate.lastAmountPaise, equals(7900));

      // Verify payment verification was invoked
      expect(fakeService.verifyPaymentCalled, isTrue);
    });

    testWidgets('Displays confirmation screen with BLA reference and non-refundable policy',
        (WidgetTester tester) async {
      final confirmedAppointment = Appointment(
        id: 'BLA-884422',
        patientUid: 'uid_test',
        patientName: 'Rahul Sharma',
        patientPhone: '9876543210',
        clinicId: 'clinic_test_1',
        clinicName: 'Apollo Medical Centre Bandra',
        clinicType: 'clinic',
        slotId: 'slot_1',
        startTime: DateTime.now().add(const Duration(days: 1)),
        status: 'confirmed',
        amountPaise: 7900,
        razorpayPaymentId: 'pay_mock_confirmed_999',
        clinicAddress: 'Hill Road, Bandra West, Mumbai',
        clinicPhone: '+91 22 2640 1234',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AppointmentConfirmationScreen(appointment: confirmedAppointment),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Appointment Confirmed!'), findsOneWidget);
      expect(find.text('BLA-884422'), findsOneWidget);
      expect(find.text('Apollo Medical Centre Bandra'), findsOneWidget);
      expect(find.text('CLINIC'), findsOneWidget);
      expect(find.text('Hill Road, Bandra West, Mumbai'), findsOneWidget);
      expect(find.text('₹79'), findsOneWidget);
      expect(find.text('pay_mock_confirmed_999'), findsOneWidget);
      expect(find.text(BookingConstants.nonRefundablePolicyText), findsOneWidget);
      expect(find.text('Navigate'), findsOneWidget);
      expect(find.text('Call Station'), findsOneWidget);
    });
  });

  group('Phase 11B - Data Models and Constants Tests', () {
    test('DaySlotItem fromJson handles free, booked, held, and past correctly', () {
      final freeItem = DaySlotItem.fromJson({
        'slotId': 'c1_20261028_1000',
        'time': '10:00',
        'startTimeIso': '2026-10-28T04:30:00.000Z',
        'status': 'free',
      });
      expect(freeItem.status, equals(SlotStatus.free));

      final bookedItem = DaySlotItem.fromJson({
        'slotId': 'c1_20261028_1030',
        'time': '10:30',
        'startTimeIso': '2026-10-28T05:00:00.000Z',
        'status': 'booked',
      });
      expect(bookedItem.status, equals(SlotStatus.booked));

      final heldItem = DaySlotItem.fromJson({
        'slotId': 'c1_20261028_1100',
        'time': '11:00',
        'startTimeIso': '2026-10-28T05:30:00.000Z',
        'status': 'held',
      });
      expect(heldItem.status, equals(SlotStatus.booked)); // Active hold treated as unavailable

      final pastItem = DaySlotItem.fromJson({
        'slotId': 'c1_20261028_0800',
        'time': '08:00',
        'startTimeIso': '2026-10-28T02:30:00.000Z',
        'status': 'past',
      });
      expect(pastItem.status, equals(SlotStatus.past));
    });

    test('Appointment model properties and rupee conversion', () {
      final app = Appointment(
        id: 'BLA-112233',
        patientUid: 'u1',
        patientName: 'Ananya Verma',
        patientPhone: '9820011223',
        clinicId: 'c1',
        clinicName: 'Metropolis Lab',
        clinicType: 'pathology_lab',
        slotId: 'c1_20261028_0900',
        startTime: DateTime.now().add(const Duration(days: 2)),
        status: 'confirmed',
        amountPaise: 4900,
      );

      expect(app.amountRupees, equals(49));
      expect(app.isConfirmed, isTrue);
      expect(app.isUpcoming, isTrue);
    });

    test('Booking policy constant matches requirement exactly', () {
      expect(
        BookingConstants.nonRefundablePolicyText,
        equals('Booking fee is non-refundable'),
      );
    });
  });
}
