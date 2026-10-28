import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/crew_constants.dart';
import '../../core/constants/crew_strings.dart';
import '../../core/theme.dart';
import '../../models/ambulance.dart';
import '../../providers/ambulance_auth_provider.dart';
import '../../providers/crew_presence_providers.dart';
import '../../providers/relief_providers.dart';
import '../dispatch/new_request_screen.dart';
import 'crew_profile_tab.dart';
import 'relief_request_alert_screen.dart';

class CrewHomeScreen extends ConsumerStatefulWidget {
  const CrewHomeScreen({super.key});

  @override
  ConsumerState<CrewHomeScreen> createState() => _CrewHomeScreenState();
}

class _CrewHomeScreenState extends ConsumerState<CrewHomeScreen> {
  late int _currentIndex;
  bool _dialogChecked = false;

  @override
  void initState() {
    super.initState();
    // Default tab configured via kCrewDefaultTab (1 = Dispatch, 0 = Profile)
    _currentIndex = kCrewDefaultTab;
  }

  void _checkFirstTimeVerification(Ambulance ambulance) async {
    if (_dialogChecked) return;
    _dialogChecked = true;

    final ambId = ambulance.ambulanceId;
    if (ambId == null || ambId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final key = 'verified_dialog_shown_$ambId';
    final alreadyShown = prefs.getBool(key) ?? false;

    if (!alreadyShown && mounted) {
      _showFirstTimeDialog(ambulance, prefs, key);
    }
  }

  void _showFirstTimeDialog(
    Ambulance ambulance,
    SharedPreferences prefs,
    String key,
  ) {
    final ambId = ambulance.ambulanceId ?? 'BL-AMB-VERIFIED';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Celebration Icon
                Container(
                  width: 68,
                  height: 68,
                  decoration: const BoxDecoration(
                    color: AppColors.successTint,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.verified_rounded,
                    size: 44,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(height: 16),

                // Badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    CrewStrings.verifiedAmbulanceBadge,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                Text(
                  CrewStrings.congratulationsTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                ),
                const SizedBox(height: 14),

                // Ambulance ID Box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.primary, width: 1.5),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'YOUR OFFICIAL AMBULANCE ID',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            ambId,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryDark,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded,
                                size: 18, color: AppColors.primary),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: ambId));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Ambulance ID copied!'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Guidance notice
                const Text(
                  CrewStrings.firstTimeVerifiedNotice,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: () async {
                    await prefs.setBool(key, true);
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    CrewStrings.proceedToTerminal,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ambulanceAsync = ref.watch(currentAmbulanceProvider);

    return ambulanceAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      ),
      error: (err, _) => Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: Text('Error loading crew terminal: $err')),
      ),
      data: (ambulance) {
        if (ambulance != null && ambulance.isVerified) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkFirstTimeVerification(ambulance);
            ref.read(crewPresenceServiceProvider).initializeStatus(ambulance.uid);
          });
        }

        // Critical: Inbound colleague relief alert overrides the crew terminal across all tabs
        final activeReliefOffer = ref.watch(activeReliefOfferProvider);
        if (activeReliefOffer != null && !activeReliefOffer.isExpired) {
          return ReliefRequestAlertScreen(
            offer: activeReliefOffer,
            onDismiss: () =>
                ref.read(activeReliefOfferProvider.notifier).clear(),
          );
        }

        final activeMissionAsync = ref.watch(activeCrewReliefMissionProvider);
        final activeMission = activeMissionAsync.value;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: Column(
            children: [
              if (activeMission != null)
                SafeArea(
                  bottom: false,
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF0E7C86), width: 1.8),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0E7C86).withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0E7C86).withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.navigation_rounded,
                            color: Color(0xFF0E7C86),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: AppColors.danger,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'ACTIVE BACKUP MISSION',
                                    style: TextStyle(
                                      color: Color(0xFF0E7C86),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'En route to ${activeMission.requesterAmbulance.ambulanceId}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            context.go(
                              '/crew/relief_nav?reliefRequestId=${activeMission.id}',
                            );
                          },
                          icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                          label: const Text(
                            'Track & Go',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0E7C86),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: IndexedStack(
                  index: _currentIndex,
                  children: const [
                    // Tab 1: Profile (index 0)
                    CrewProfileTab(),
                    // Tab 2: New Emergency Dispatch (index 1)
                    NewRequestScreen(),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() => _currentIndex = index);
            },
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            selectedItemColor: AppColors.primary,
            unselectedItemColor: AppColors.textSecondary,
            selectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
            elevation: 8,
            items: const [
              // Tab 1: Profile
              BottomNavigationBarItem(
                icon: Icon(Icons.person_outline_rounded),
                activeIcon: Icon(Icons.person_rounded),
                label: 'Profile',
              ),
              // Tab 2: New Emergency Dispatch
              BottomNavigationBarItem(
                icon: Icon(Icons.emergency_outlined),
                activeIcon: Icon(Icons.emergency_rounded),
                label: 'New Emergency Dispatch',
              ),
            ],
          ),
        );
      },
    );
  }
}
