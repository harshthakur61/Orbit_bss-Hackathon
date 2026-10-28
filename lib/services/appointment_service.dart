import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../models/appointment.dart';

/// Abstract delegate to facilitate testing and mock checkout without native platform channels
abstract class AppointmentPaymentDelegate {
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
  });

  void dispose();
}

/// Official Razorpay Checkout implementation using razorpay_flutter
class NativeRazorpayPaymentDelegate implements AppointmentPaymentDelegate {
  Razorpay? _razorpay;

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
    _razorpay?.clear();
    _razorpay = Razorpay();

    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, onSuccess);
    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, onError);
    if (onExternalWallet != null) {
      _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, onExternalWallet);
    }

    final options = {
      'key': keyId,
      'amount': amountPaise,
      'name': 'BedLink Health',
      'description': 'Appointment at $clinicName',
      'order_id': orderId,
      'timeout': 300, // 5 minutes matching hold duration
      'prefill': {
        'contact': patientPhone,
        'name': patientName,
      },
      'theme': {
        'color': '#0E7C86', // BedLink Clinical Teal
      },
    };

    try {
      _razorpay!.open(options);
    } catch (e) {
      onError(PaymentFailureResponse(
        Razorpay.PAYMENT_CANCELLED,
        'Unable to open Razorpay Checkout: $e',
        null,
      ));
    }
  }

  @override
  void dispose() {
    _razorpay?.clear();
    _razorpay = null;
  }
}

/// Service managing clinic slot availability, appointments, and payments
class AppointmentService {
  final FirebaseFunctions? _customFunctions;
  final FirebaseFirestore? _customFirestore;
  final FirebaseAuth? _customAuth;
  AppointmentPaymentDelegate paymentDelegate;

  FirebaseFunctions get _functions => _customFunctions ?? FirebaseFunctions.instance;
  FirebaseFirestore get _firestore => _customFirestore ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _customAuth ?? FirebaseAuth.instance;

  AppointmentService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    AppointmentPaymentDelegate? paymentDelegate,
  })  : _customFunctions = functions,
        _customFirestore = firestore,
        _customAuth = auth,
        paymentDelegate = paymentDelegate ?? NativeRazorpayPaymentDelegate();

  /// Ensures an active Firebase Auth user session (anonymously if not logged in)
  Future<String> ensureAuthenticatedUid() async {
    final current = _auth.currentUser;
    if (current != null) {
      return current.uid;
    }
    final userCred = await _auth.signInAnonymously();
    return userCred.user!.uid;
  }

  /// Fetches available slots for a clinic on a specific date (YYYYMMDD) in Asia/Kolkata
  Future<List<DaySlotItem>> getClinicDaySlots({
    required String clinicId,
    required String dateKey,
  }) async {
    try {
      final callable = _functions.httpsCallable('getClinicDaySlots');
      final result = await callable.call<Map<dynamic, dynamic>>({
        'clinicId': clinicId,
        'dateKey': dateKey,
      });

      final data = Map<String, dynamic>.from(result.data);
      final rawSlots = data['slots'] as List<dynamic>? ?? [];

      return rawSlots
          .map((item) => DaySlotItem.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    } on FirebaseFunctionsException catch (fe) {
      throw Exception(fe.message ?? 'Failed to load clinic slots.');
    } catch (e) {
      throw Exception('Network error fetching slots: $e');
    }
  }

  /// Creates an appointment hold (5 min) and generates a Razorpay Order via Cloud Function
  Future<Map<String, dynamic>> createAppointmentOrder({
    required String clinicId,
    required DateTime startTime,
    required String patientName,
    required String patientPhone,
  }) async {
    await ensureAuthenticatedUid();

    try {
      final callable = _functions.httpsCallable('createAppointmentOrder');
      final result = await callable.call<Map<dynamic, dynamic>>({
        'clinicId': clinicId,
        'startTime': startTime.toUtc().toIso8601String(),
        'patientName': patientName,
        'patientPhone': patientPhone,
      });

      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (fe) {
      if (fe.code == 'already-exists' || fe.code == 'failed-precondition') {
        throw Exception('That slot was just booked. Pick another');
      }
      throw Exception(fe.message ?? 'Failed to reserve appointment slot.');
    } catch (e) {
      if (e.toString().contains('That slot was just booked')) rethrow;
      throw Exception('Error creating appointment: $e');
    }
  }

  /// Verifies Razorpay payment signature and confirms appointment via Cloud Function
  Future<Map<String, dynamic>> verifyAppointmentPayment({
    required String appointmentId,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    try {
      final callable = _functions.httpsCallable('verifyAppointmentPayment');
      final result = await callable.call<Map<dynamic, dynamic>>({
        'appointmentId': appointmentId,
        'razorpayOrderId': razorpayOrderId,
        'razorpayPaymentId': razorpayPaymentId,
        'razorpaySignature': razorpaySignature,
      });

      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (fe) {
      throw Exception(fe.message ?? 'Payment verification failed.');
    } catch (e) {
      throw Exception('Payment verification error: $e');
    }
  }

  /// Releases a held slot when user cancels payment or closes payment sheet
  Future<void> releaseAppointmentHold(String appointmentId) async {
    try {
      await ensureAuthenticatedUid();
      final callable = _functions.httpsCallable('releaseAppointmentHold');
      await callable.call<Map<dynamic, dynamic>>({
        'appointmentId': appointmentId,
      });
    } catch (_) {
      // Best-effort hold release; server-side expiration cleans up automatically
    }
  }

  /// Live Firestore stream of appointments for the current user
  Stream<List<Appointment>> streamPatientAppointments(String patientUid) {
    if (patientUid.isEmpty) {
      return Stream.value([]);
    }

    return _firestore
        .collection('appointments')
        .where('patientUid', isEqualTo: patientUid)
        .snapshots()
        .map((snap) {
          final list = snap.docs.map((d) => Appointment.fromFirestore(d)).toList();
          list.sort((a, b) => b.startTime.compareTo(a.startTime));
          return list;
        });
  }

  /// Fetches a single appointment by reference ID
  Future<Appointment?> getAppointmentById(String appointmentId) async {
    final doc = await _firestore.collection('appointments').doc(appointmentId).get();
    if (!doc.exists) return null;
    return Appointment.fromFirestore(doc);
  }

  /// Seeds ~35% plausible booked slots across clinics for next 3 days via Cloud Function
  Future<Map<String, dynamic>> seedDemoBookings() async {
    try {
      final callable = _functions.httpsCallable('seedDemoBookings');
      final result = await callable.call<Map<dynamic, dynamic>>();
      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (fe) {
      throw Exception(fe.message ?? 'Failed to seed demo bookings.');
    } catch (e) {
      throw Exception('Error seeding demo bookings: $e');
    }
  }

  /// Clears demo-seeded booked slots and demo appointments via Cloud Function
  Future<Map<String, dynamic>> resetDemoBookings() async {
    try {
      final callable = _functions.httpsCallable('resetDemoBookings');
      final result = await callable.call<Map<dynamic, dynamic>>();
      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (fe) {
      throw Exception(fe.message ?? 'Failed to reset demo bookings.');
    } catch (e) {
      throw Exception('Error resetting demo bookings: $e');
    }
  }

  /// Retrieves real-time revenue snapshot across confirmed appointments via Cloud Function
  Future<Map<String, dynamic>> getRevenueSnapshot() async {
    try {
      final callable = _functions.httpsCallable('getRevenueSnapshot');
      final result = await callable.call<Map<dynamic, dynamic>>();
      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (fe) {
      throw Exception(fe.message ?? 'Failed to fetch revenue snapshot.');
    } catch (e) {
      throw Exception('Error fetching revenue snapshot: $e');
    }
  }

  void dispose() {
    paymentDelegate.dispose();
  }
}
