import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/role_select/role_select_screen.dart';
import '../features/demo/demo_controls_screen.dart';
import '../features/nurse/hospital_login_screen.dart';
import '../features/nurse/nurse_shell_screen.dart';
import '../features/dispatch/new_request_screen.dart';
import '../features/dispatch/results_screen.dart';
import '../features/dispatch/hold_status_screen.dart';
import '../features/dispatch/trip_complete_screen.dart';
import '../features/patient/patient_hub_screen.dart';
import '../features/patient/patient_login_screen.dart';
import '../features/patient/clinic_search_screen.dart';
import '../features/patient/clinic_results_screen.dart';
import '../features/patient/report_list_screen.dart';
import '../features/patient/report_analysis_screen.dart';
import '../features/patient/doctor_consultation_screen.dart';
import '../models/clinic.dart';
import '../models/appointment.dart';
import '../features/patient/appointment_booking_screen.dart';
import '../features/patient/appointment_confirmation_screen.dart';
import '../features/patient/my_appointments_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../features/crew/crew_login_screen.dart';
import '../features/crew/crew_register_screen.dart';
import '../features/crew/crew_pending_screen.dart';
import '../features/crew/crew_home_screen.dart';
import '../services/ambulance_auth_service.dart';
import '../features/dispatch/relief_status_screen.dart';
import '../features/crew/relief_navigation_screen.dart';

// Placeholder screens for future phases (to ensure routing compiles in Phase 1)
class NurseLoginPlaceholder extends StatelessWidget {
  const NurseLoginPlaceholder({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hospital Login')),
      body: const Center(child: Text('Nurse Login Screen (Phase 3)')),
    );
  }
}

class NurseBedsPlaceholder extends StatelessWidget {
  const NurseBedsPlaceholder({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bed Update')),
      body: const Center(child: Text('Nurse Bed Update Screen (Phase 3)')),
    );
  }
}

class NurseHistoryPlaceholder extends StatelessWidget {
  const NurseHistoryPlaceholder({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request History')),
      body: const Center(child: Text('Nurse Request History Screen (Phase 6)')),
    );
  }
}

class DispatchNewPlaceholder extends StatelessWidget {
  const DispatchNewPlaceholder({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Emergency')),
      body: const Center(child: Text('Dispatch Form Screen (Phase 4)')),
    );
  }
}

class DispatchResultsPlaceholder extends StatelessWidget {
  const DispatchResultsPlaceholder({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ranked Hospitals')),
      body: const Center(child: Text('Ranked Results Screen (Phase 4)')),
    );
  }
}

class DispatchHoldPlaceholder extends StatelessWidget {
  const DispatchHoldPlaceholder({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hold Status')),
      body: const Center(child: Text('Hold Status Screen (Phase 5)')),
    );
  }
}

class DispatchCompletePlaceholder extends StatelessWidget {
  const DispatchCompletePlaceholder({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trip Complete')),
      body: const Center(child: Text('Trip Complete Screen (Phase 6)')),
    );
  }
}

class DemoControlsPlaceholder extends StatelessWidget {
  const DemoControlsPlaceholder({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Demo Controls')),
      body: const Center(child: Text('Demo Controls Screen (Phase 2)')),
    );
  }
}

class ReliefNavigationPlaceholderScreen extends StatelessWidget {
  final String? reliefRequestId;
  const ReliefNavigationPlaceholderScreen({super.key, this.reliefRequestId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relief Navigation'),
        backgroundColor: const Color(0xFF0E7C86),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.navigation_rounded, size: 64, color: Color(0xFF0E7C86)),
              const SizedBox(height: 16),
              const Text(
                'Relief Route Navigation (Phase 12E)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'En-route to disabled colleague.\nRelief ID: ${reliefRequestId ?? "Active"}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go('/crew/home'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0E7C86),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Back to Terminal'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const RoleSelectScreen(),
    ),
    GoRoute(
      path: '/nurse/login',
      builder: (context, state) {
        final pendingRequestId = state.uri.queryParameters['pendingRequestId'];
        return HospitalLoginScreen(pendingRequestId: pendingRequestId);
      },
    ),
    GoRoute(
      path: '/nurse/home',
      builder: (context, state) => const NurseShellScreen(initialTab: 0),
    ),
    GoRoute(
      path: '/nurse/beds',
      builder: (context, state) => const NurseShellScreen(initialTab: 1),
    ),
    GoRoute(
      path: '/nurse/history',
      builder: (context, state) => const NurseShellScreen(initialTab: 2),
    ),
    GoRoute(
      path: '/nurse/profile',
      builder: (context, state) => const NurseShellScreen(initialTab: 3),
    ),
    GoRoute(
      path: '/nurse/station',
      builder: (context, state) => const NurseShellScreen(initialTab: 0),
    ),
    GoRoute(
      path: '/crew',
      redirect: (context, state) => '/crew/home',
    ),
    GoRoute(
      path: '/crew/login',
      builder: (context, state) => const CrewLoginScreen(),
    ),
    GoRoute(
      path: '/crew/register',
      builder: (context, state) => const CrewRegisterScreen(),
    ),
    GoRoute(
      path: '/crew/pending',
      builder: (context, state) => const CrewPendingScreen(),
      redirect: (context, state) {
        if (!AmbulanceAuthService.hasActiveSession) return '/crew/login';
        return null;
      },
    ),
    GoRoute(
      path: '/crew/home',
      builder: (context, state) => const CrewHomeScreen(),
      redirect: (context, state) async {
        if (!AmbulanceAuthService.hasActiveSession) {
          return '/crew/login';
        }
        final demo = AmbulanceAuthService.activeDemoAmbulance;
        if (demo != null && demo.isVerified) {
          return null;
        }
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          try {
            final doc = await FirebaseFirestore.instance
                .collection('ambulances')
                .doc(user.uid)
                .get();
            if (!doc.exists) {
              return '/crew/pending';
            }
            final status = doc.data()?['verificationStatus'] as String?;
            if (status?.toUpperCase() != 'VERIFIED') {
              return '/crew/pending';
            }
          } catch (_) {
            return '/crew/pending';
          }
        }
        return null;
      },
    ),
    GoRoute(
      path: '/dispatch/new',
      builder: (context, state) => const NewRequestScreen(),
    ),
    GoRoute(
      path: '/dispatch/results',
      builder: (context, state) => const ResultsScreen(),
    ),
    GoRoute(
      path: '/dispatch/hold',
      builder: (context, state) => const HoldStatusScreen(),
    ),
    GoRoute(
      path: '/dispatch/complete',
      builder: (context, state) => const TripCompleteScreen(),
    ),
    GoRoute(
      path: '/dispatch/relief',
      builder: (context, state) {
        final reliefRequestId = state.uri.queryParameters['reliefRequestId'];
        return ReliefStatusScreen(reliefRequestId: reliefRequestId);
      },
    ),
    GoRoute(
      path: '/crew/relief_nav',
      builder: (context, state) {
        final reliefRequestId = state.uri.queryParameters['reliefRequestId'] ?? '';
        return ReliefNavigationScreen(reliefRequestId: reliefRequestId);
      },
    ),
    GoRoute(
      path: '/crew/relief-navigate',
      builder: (context, state) {
        final reliefRequestId = state.uri.queryParameters['reliefRequestId'] ?? '';
        return ReliefNavigationScreen(reliefRequestId: reliefRequestId);
      },
    ),
    GoRoute(
      path: '/demo',
      builder: (context, state) => const DemoControlsScreen(),
    ),
    GoRoute(
      path: '/patient/login',
      builder: (context, state) => const PatientLoginScreen(),
    ),
    GoRoute(
      path: '/patient/hub',
      builder: (context, state) => const PatientHubScreen(),
    ),
    GoRoute(
      path: '/patient/clinics/search',
      builder: (context, state) => const ClinicSearchScreen(),
    ),
    GoRoute(
      path: '/patient/clinics/results',
      builder: (context, state) => const ClinicResultsScreen(),
    ),
    GoRoute(
      path: '/patient/reports',
      builder: (context, state) => const ReportListScreen(),
    ),
    GoRoute(
      path: '/patient/reports/analysis',
      builder: (context, state) => const ReportAnalysisScreen(),
    ),
    GoRoute(
      path: '/patient/consultation',
      builder: (context, state) => const DoctorConsultationScreen(),
    ),
    GoRoute(
      path: '/patient/clinics/book',
      builder: (context, state) {
        final clinic = state.extra as Clinic?;
        if (clinic == null) {
          return const Scaffold(
            body: Center(child: Text('Clinic details not found.')),
          );
        }
        return AppointmentBookingScreen(clinic: clinic);
      },
    ),
    GoRoute(
      path: '/patient/appointments',
      builder: (context, state) => const MyAppointmentsScreen(),
    ),
    GoRoute(
      path: '/patient/appointments/confirmation',
      builder: (context, state) {
        final appointment = state.extra as Appointment?;
        if (appointment == null) {
          return const Scaffold(
            body: Center(child: Text('Appointment not found.')),
          );
        }
        return AppointmentConfirmationScreen(appointment: appointment);
      },
    ),
  ],
);
