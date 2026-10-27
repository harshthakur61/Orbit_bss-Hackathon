import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/role_select/role_select_screen.dart';
import '../features/demo/demo_controls_screen.dart';
import '../features/nurse/hospital_login_screen.dart';
import '../features/nurse/bed_update_screen.dart';
import '../features/dispatch/new_request_screen.dart';
import '../features/dispatch/results_screen.dart';
import '../features/dispatch/hold_status_screen.dart';
import '../features/nurse/request_history_screen.dart';
import '../features/dispatch/trip_complete_screen.dart';
import '../features/patient/patient_hub_screen.dart';
import '../features/patient/patient_login_screen.dart';
import '../features/patient/clinic_search_screen.dart';
import '../features/patient/clinic_results_screen.dart';
import '../features/patient/report_list_screen.dart';
import '../features/patient/report_analysis_screen.dart';
import '../features/patient/doctor_consultation_screen.dart';

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

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const RoleSelectScreen(),
    ),
    GoRoute(
      path: '/nurse/login',
      builder: (context, state) => const HospitalLoginScreen(),
    ),
    GoRoute(
      path: '/nurse/beds',
      builder: (context, state) => const BedUpdateScreen(),
    ),
    GoRoute(
      path: '/nurse/history',
      builder: (context, state) => const RequestHistoryScreen(),
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
  ],
);
