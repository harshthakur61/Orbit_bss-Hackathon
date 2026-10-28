import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../providers/hospital_providers.dart';
import '../../providers/request_providers.dart';
import 'incoming_request_screen.dart';
import 'nurse_home_screen.dart';
import 'bed_update_screen.dart';
import 'request_history_screen.dart';
import 'hospital_profile_screen.dart';

class NurseShellScreen extends ConsumerStatefulWidget {
  final int initialTab;

  const NurseShellScreen({
    super.key,
    this.initialTab = 0,
  });

  @override
  ConsumerState<NurseShellScreen> createState() => _NurseShellScreenState();
}

class _NurseShellScreenState extends ConsumerState<NurseShellScreen> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    final hospital = ref.watch(selectedHospitalProvider);
    final selectedId = ref.watch(selectedHospitalIdProvider);

    // If hospital not selected, redirect to login
    if (hospital == null || selectedId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nurse Terminal')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.local_hospital_outlined,
                  size: 64, color: AppColors.textSecondary),
              const SizedBox(height: 16),
              const Text(
                'No hospital station selected.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/nurse/login'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Go to Nurse Login'),
              ),
            ],
          ),
        ),
      );
    }

    // Critical: Incoming siren alert works across ANY tab
    final activeRequestAsync =
        ref.watch(activeHospitalRequestProvider(selectedId));
    final activeRequest = activeRequestAsync.value;
    if (activeRequest != null && activeRequest.status == 'offered') {
      return IncomingRequestScreen(request: activeRequest);
    }

    String getTabSubtitle() {
      switch (_currentIndex) {
        case 0:
          return 'Live Inbound Ambulances';
        case 1:
          return 'Bed Availability Station';
        case 2:
          return 'Station Emergency History';
        case 3:
          return 'Facility Profile & Security';
        default:
          return 'Nurse Bed Station';
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hospital.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              getTabSubtitle(),
              style: const TextStyle(fontSize: 12, color: AppColors.primaryTint),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded),
            tooltip: 'Main Landing Page (Change Role)',
            onPressed: () {
              ref.read(firestoreServiceProvider).updateNursePresence(selectedId, false);
              ref.read(selectedHospitalIdProvider.notifier).select(null);
              context.go('/');
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          NurseHomeScreen(hospital: hospital),
          BedUpdateScreen(isEmbedded: true, hospital: hospital),
          RequestHistoryScreen(isEmbedded: true, hospital: hospital),
          HospitalProfileScreen(hospital: hospital),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.bed_outlined),
            selectedIcon: Icon(Icons.bed_rounded),
            label: 'Availability',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_toggle_off_rounded),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'Requests',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_hospital_outlined),
            selectedIcon: Icon(Icons.local_hospital_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
