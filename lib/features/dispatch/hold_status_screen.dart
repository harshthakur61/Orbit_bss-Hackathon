import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../core/widgets/countdown_ring.dart';
import '../../models/emergency_request.dart';
import '../../models/hospital.dart';
import '../../services/firestore_service.dart';
import '../../services/live_location_service.dart';
import '../../providers/hospital_providers.dart';
import '../../providers/location_providers.dart';
import '../../providers/request_providers.dart';
import '../../providers/ambulance_auth_provider.dart';
import '../../providers/crew_presence_providers.dart';
import '../../providers/relief_providers.dart';

class HoldStatusScreen extends ConsumerStatefulWidget {
  const HoldStatusScreen({super.key});

  @override
  ConsumerState<HoldStatusScreen> createState() => _HoldStatusScreenState();
}

class _HoldStatusScreenState extends ConsumerState<HoldStatusScreen> {
  bool _isProcessing = false;
  bool _rationaleDialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLocationPermissions();
      try {
        ref.read(liveLocationServiceProvider).addListener(_onLiveLocationChanged);
      } catch (_) {}
    });
  }

  void _onLiveLocationChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    try {
      ref.read(liveLocationServiceProvider).removeListener(_onLiveLocationChanged);
    } catch (_) {}
    super.dispose();
  }

  Future<void> _checkLocationPermissions() async {
    final liveService = ref.read(liveLocationServiceProvider);
    final hasPermission = await liveService.checkAndRequestPermission();
    if (!hasPermission && !_rationaleDialogShown && mounted) {
      _rationaleDialogShown = true;
      _showPermissionRationaleDialog();
    }
  }

  void _showPermissionRationaleDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.share_location_rounded,
            color: AppColors.primary, size: 40),
        title: const Text('Live Location Sharing'),
        content: const Text(
          'Hospitals can see your arrival in real time. BedLink shares your ambulance GPS coordinates so receiving emergency teams can prepare equipment before you arrive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Continue Without Live GPS'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(liveLocationServiceProvider).checkAndRequestPermission();
            },
            child: const Text('Enable Location'),
          ),
        ],
      ),
    );
  }

  Future<void> _makeCall(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final Uri phoneUri = Uri.parse('tel:$cleanPhone');
    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        _showToast('Could not launch dialer for $phone');
      }
    } catch (e) {
      _showToast('Dialer error: $e');
    }
  }

  Future<void> _openGoogleMaps(double lat, double lng, String name) async {
    final encodedName = Uri.encodeComponent(name);
    final Uri mapsDirUri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&destination_place_id=$encodedName');
    final Uri geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng($encodedName)');

    try {
      if (await canLaunchUrl(mapsDirUri)) {
        await launchUrl(mapsDirUri, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri);
      } else {
        await launchUrl(mapsDirUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      _showToast('Navigation error: $e');
    }
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _buildStepper(String status, String hospitalName, {String? reliefState}) {
    final bool isAcceptedOrArrived = status == 'accepted' || status == 'arrived';
    final bool isArrived = status == 'arrived';
    final bool hasRelief = reliefState != null;

    final steps = [
      {'title': 'Requested', 'done': true},
      {
        'title': isAcceptedOrArrived
            ? 'Accepted'
            : 'Offered to $hospitalName',
        'done': isAcceptedOrArrived,
        'active': status == 'offered',
      },
      {
        'title': 'Bed Held',
        'done': isAcceptedOrArrived,
      },
      if (hasRelief)
        {
          'title': reliefState == 'accepted'
              ? 'Relief En Route'
              : (reliefState == 'completed' ? 'Relief Done' : 'Relief Requested'),
          'done': reliefState == 'accepted' || reliefState == 'completed',
          'active': reliefState == 'searching',
        },
      {'title': 'En route', 'done': isArrived},
      {'title': 'Arrived', 'done': isArrived},
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Status Stepper',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                if (hasRelief)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: reliefState == 'accepted'
                          ? AppColors.successTint
                          : (reliefState == 'completed'
                              ? AppColors.primaryTint
                              : AppColors.dangerTint),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.emergency_rounded,
                          size: 12,
                          color: reliefState == 'accepted'
                              ? AppColors.success
                              : (reliefState == 'completed'
                                  ? AppColors.primary
                                  : AppColors.danger),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          reliefState == 'accepted'
                              ? 'Relief En Route'
                              : (reliefState == 'completed'
                                  ? 'Relief Handover Done'
                                  : 'Relief Requested'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: reliefState == 'accepted'
                                ? AppColors.success
                                : (reliefState == 'completed'
                                    ? AppColors.primaryDark
                                    : AppColors.danger),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: steps.map((step) {
                final bool isDone = step['done'] as bool;
                final bool isActive = step['active'] as bool? ?? false;

                Color circleBg;
                Color textColor;
                if (isDone) {
                  circleBg = AppColors.success;
                  textColor = AppColors.success;
                } else if (isActive) {
                  circleBg = AppColors.warning;
                  textColor = AppColors.warningText;
                } else {
                  circleBg = AppColors.divider;
                  textColor = AppColors.textSecondary;
                }

                return Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: circleBg,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: isDone
                              ? const Icon(Icons.check,
                                  size: 14, color: Colors.white)
                              : (isActive
                                  ? const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : null),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        step['title'] as String,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              isDone || isActive ? FontWeight.bold : FontWeight.normal,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final liveLocationService = ref.watch(liveLocationServiceProvider);

    // Listen for live Firestore updates on the current request
    ref.listen<AsyncValue<EmergencyRequest?>>(currentRequestProvider,
        (previous, next) {
      final req = next.value;
      if (req == null) return;

      final liveService = ref.read(liveLocationServiceProvider);

      if (req.status == 'arrived' || req.status == 'cancelled' || req.status == 'failed') {
        liveService.stopPublishing(deleteDoc: true);

        // Auto-rule: Restore crew previous availability status when trip completes or cancels
        final currentAmb = ref.read(currentAmbulanceProvider).value;
        final crewUid = req.crewUid ?? currentAmb?.uid;
        if (crewUid != null) {
          try {
            ref.read(crewPresenceServiceProvider).restorePreviousStatus(
                  crewUid,
                  ambulance: currentAmb,
                );
          } catch (_) {}
        }

        if (req.status == 'arrived' && mounted) {
          context.go('/dispatch/complete');
        }
      } else if (req.status == 'accepted' || req.status == 'en_route') {
        final ambId = req.ambulance?.ambulanceId.isNotEmpty == true
            ? req.ambulance!.ambulanceId
            : (req.crewUid ?? 'AMB-UNKNOWN');

        if (!liveService.isPublishing) {
          liveService.startPublishing(
            requestId: req.id,
            hospitalId: req.currentHospitalId,
            ambulanceId: ambId,
          );
        } else if (liveService.activeHospitalId != req.currentHospitalId) {
          liveService.updateHospitalId(req.currentHospitalId);
        }
      }
    });

    final requestId = ref.watch(selectedRequestIdProvider);
    final requestAsync = ref.watch(currentRequestProvider);
    final hospitalsAsync = ref.watch(hospitalsStreamProvider);
    final firestoreService = ref.watch(firestoreServiceProvider);

    // Edge-case recovery: if app was restarted mid-trip while accepted/en-route, resume publishing automatically
    final activeReq = requestAsync.value;
    if (activeReq != null && (activeReq.status == 'accepted' || activeReq.status == 'en_route')) {
      if (!liveLocationService.isPublishing && !liveLocationService.isSimulating) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !liveLocationService.isPublishing && !liveLocationService.isSimulating) {
            final ambId = activeReq.ambulance?.ambulanceId.isNotEmpty == true
                ? activeReq.ambulance!.ambulanceId
                : (activeReq.crewUid ?? 'AMB-UNKNOWN');
            liveLocationService.startPublishing(
              requestId: activeReq.id,
              hospitalId: activeReq.currentHospitalId,
              ambulanceId: ambId,
            );
          }
        });
      }
    }

    if (requestId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Confirm & Hold Status')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.airport_shuttle_outlined,
                  size: 64, color: AppColors.textSecondary),
              const SizedBox(height: 16),
              const Text('No active emergency request.'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/dispatch/new'),
                child: const Text('Start New Request'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Hold Status & Live Handshake'),
        backgroundColor: AppColors.primaryDark,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Demo Controls',
            onPressed: () => context.push('/demo'),
          ),
        ],
      ),
      body: requestAsync.when(
        data: (req) {
          if (req == null) {
            return const Center(child: Text('Request not found.'));
          }

          final List<Hospital> hospitals = hospitalsAsync.value ?? [];
          Hospital? targetHospital;
          try {
            targetHospital = hospitals
                .firstWhere((h) => h.id == req.currentHospitalId);
          } catch (_) {}

          final targetName = targetHospital?.name ?? 'Hospital';
          final targetPhone = targetHospital?.phone ?? '+91 22 0000 0000';

          // If arrived status, immediately redirect to complete screen
          if (req.status == 'arrived') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                context.go('/dispatch/complete');
              }
            });
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Patient arrived! Loading completion summary...'),
                ],
              ),
            );
          }

          // Check if targeted hospital should be auto-skipped (Hospital Unreachable OR 0 Available Beds)
          final bool isHospitalUnreachable = targetHospital != null && !targetHospital.isReachable;
          final bool hasZeroRequestedBeds = targetHospital != null &&
              req.needs.any((need) => targetHospital!.beds.getForType(need).available <= 0);

          if (req.status == 'offered' &&
              targetHospital != null &&
              (isHospitalUnreachable || hasZeroRequestedBeds) &&
              !_isProcessing) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (mounted && !_isProcessing) {
                setState(() => _isProcessing = true);
                final skipReason = isHospitalUnreachable
                    ? 'Hospital unreachable via terminal or background push (0s auto-skip)'
                    : '0 ${req.needs.join(", ")} beds available (0s auto-skip)';

                _showToast(
                    '⚡ $skipReason at ${targetHospital!.name}. Auto-skipping (0s delay)...');
                await firestoreService.handleAutoSkip(
                    req.id, targetHospital.id, skipReason);
                if (mounted) setState(() => _isProcessing = false);
              }
            });
          }

          // Check if request was accepted by current or previous attempt
          final bool isAccepted = req.status == 'accepted' ||
              req.attempts.any((a) =>
                  a.hospitalId == req.currentHospitalId &&
                  a.result == 'accepted');

          if (req.status == 'failed') {
            return _buildFailedState(req, firestoreService);
          }

          if (isAccepted) {
            return _buildAcceptedState(
                req, targetHospital, targetName, targetPhone, firestoreService, liveLocationService);
          }

          // Default Waiting / Offered State
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildLocationDisabledBanner(liveLocationService),
                // Stepper
                _buildStepper(req.status, targetName, reliefState: req.reliefState),
                const SizedBox(height: 16),

                // Target Hospital Header Card
                Card(
                  color: AppColors.primaryTint,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'OFFER SENT TO:',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textSecondary,
                                letterSpacing: 1.0,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isHospitalUnreachable
                                    ? AppColors.dangerTint
                                    : (hasZeroRequestedBeds
                                        ? AppColors.warningTint
                                        : AppColors.successTint),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isHospitalUnreachable
                                      ? AppColors.danger
                                      : (hasZeroRequestedBeds
                                          ? AppColors.warning
                                          : AppColors.success),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isHospitalUnreachable
                                        ? Icons.sensors_off_rounded
                                        : (hasZeroRequestedBeds
                                            ? Icons.event_busy_rounded
                                            : Icons.sensors_rounded),
                                    size: 12,
                                    color: isHospitalUnreachable
                                        ? AppColors.danger
                                        : (hasZeroRequestedBeds
                                            ? AppColors.warningText
                                            : AppColors.success),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isHospitalUnreachable
                                        ? 'Unreachable (Auto-Skip)'
                                        : (hasZeroRequestedBeds
                                            ? '0 Beds Avail (Auto-Skip)'
                                            : (targetHospital?.isNurseOnline == true
                                                ? 'Nurse Online'
                                                : 'Reachable via Push')),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isHospitalUnreachable
                                          ? AppColors.danger
                                          : (hasZeroRequestedBeds
                                              ? AppColors.warningText
                                              : AppColors.success),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          targetName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Requested beds: ${req.needs.join(", ")} (${req.severity.toUpperCase()})',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Center Countdown
                Center(
                  child: CountdownRing(
                    offerExpiresAt: req.offerExpiresAt,
                    onExpired: () async {
                      await firestoreService.handleTimeoutCascade(
                        req.id,
                        req.currentHospitalId,
                      );
                    },
                  ),
                ),
                if (req.alertDeliveredAt != null) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primaryTint,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.primary, width: 1.2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.mark_email_read_rounded, size: 14, color: AppColors.primary),
                          SizedBox(width: 6),
                          Text(
                            'Alert delivered to hospital',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                // Live Attempt Log
                if (req.attempts.isNotEmpty) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Live Handshake Attempt Log',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...req.attempts.map((attempt) {
                            IconData iconData;
                            Color iconColor;
                            if (attempt.result == 'accepted') {
                              iconData = Icons.check_circle;
                              iconColor = AppColors.success;
                            } else if (attempt.result == 'rejected') {
                              iconData = Icons.cancel;
                              iconColor = AppColors.danger;
                            } else if (attempt.result == 'offline_skip') {
                              iconData = Icons.flash_off_rounded;
                              iconColor = AppColors.danger;
                            } else {
                              iconData = Icons.timer_off;
                              iconColor = AppColors.warning;
                            }

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4.0),
                              child: Row(
                                children: [
                                  Icon(iconData, color: iconColor, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${attempt.hospitalName}: ${attempt.result.toUpperCase()}${attempt.reason != null ? " (${attempt.reason})" : ""}',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isProcessing
                            ? null
                            : () async {
                                setState(() => _isProcessing = true);
                                try {
                                  await firestoreService.rejectRequestTransaction(
                                    req.id,
                                    req.currentHospitalId,
                                    'Skipped by ambulance crew',
                                  );
                                } finally {
                                  if (mounted) {
                                    setState(() => _isProcessing = false);
                                  }
                                }
                              },
                        icon: const Icon(Icons.skip_next_rounded),
                        label: const Text('Skip Hospital'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _makeCall(targetPhone),
                        icon: const Icon(Icons.phone),
                        label: const Text('Call Hospital'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _isProcessing
                      ? null
                      : () async {
                          setState(() => _isProcessing = true);
                          try {
                            await ref.read(liveLocationServiceProvider).stopPublishing(deleteDoc: true);
                            await firestoreService.releaseHoldTransaction(req.id);
                            ref.read(selectedRequestIdProvider.notifier).select(null);
                            if (mounted) {
                              // ignore: use_build_context_synchronously
                              context.go('/dispatch/new');
                            }
                          } finally {
                            if (mounted) setState(() => _isProcessing = false);
                          }
                        },
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Cancel Emergency Request'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _buildLocationDisabledBanner(LiveLocationService liveService) {
    if (!liveService.isPermissionDenied && !liveService.isLocationServiceDisabled) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.15),
        border: Border.all(color: AppColors.warning, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_off_rounded, color: AppColors.warning, size: 24),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              "Live location is off – hospital can't see you approaching",
              style: TextStyle(
                color: Color(0xFF8A5A00),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(
            onPressed: () => liveService.checkAndRequestPermission(),
            child: const Text('Enable', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveLocationIndicator(LiveLocationService liveService) {
    if (!liveService.isPublishing) return const SizedBox.shrink();
    final isSim = liveService.isSimulating;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        border: Border.all(color: AppColors.success, width: 1.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isSim
                ? 'Simulating drive (${liveService.simulationSpeedMultiplier.toInt()}x)'
                : 'Sharing live location',
            style: const TextStyle(
              color: AppColors.success,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveTelemetryDebug(LiveLocationService liveService) {
    final loc = liveService.lastPublishedLocation;
    if (loc == null) return const SizedBox.shrink();

    final lastWriteSecondsAgo = liveService.lastWriteTime != null
        ? DateTime.now().difference(liveService.lastWriteTime!).inSeconds
        : 0;

    return Card(
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.satellite_alt_rounded, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                const Text(
                  'Live Telemetry Debug (liveLocations collection)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
                const Spacer(),
                Text(
                  '${lastWriteSecondsAgo}s ago',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Lat: ${loc.lat.toStringAsFixed(5)}  Lng: ${loc.lng.toStringAsFixed(5)}  '
              'Speed: ${loc.speedKmh.toStringAsFixed(1)} km/h  Acc: ±${loc.accuracyMeters.toStringAsFixed(1)}m',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriveSimulatorDebugCard({
    required EmergencyRequest req,
    required Hospital? targetHospital,
    required LiveLocationService liveService,
  }) {
    if (!kDebugMode) return const SizedBox.shrink();
    if (targetHospital == null) return const SizedBox.shrink();

    final isSimulating = liveService.isSimulating;
    final currentMultiplier = liveService.simulationSpeedMultiplier;

    return Card(
      elevation: 0,
      color: AppColors.primary.withAlpha(12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.primary.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.speed_rounded, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Debug Route Simulator',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: isSimulating,
                  activeTrackColor: AppColors.primary,
                  onChanged: (enabled) async {
                    if (enabled) {
                      final ambId = req.ambulance?.ambulanceId.isNotEmpty == true
                          ? req.ambulance!.ambulanceId
                          : (req.crewUid ?? 'AMB-UNKNOWN');

                      final routingService = ref.read(routingServiceProvider);
                      final routeResult = await routingService.getDrivingRouteWithGeometry(
                        startLat: req.patientLat,
                        startLng: req.patientLng,
                        endLat: targetHospital.lat,
                        endLng: targetHospital.lng,
                      );

                      await liveService.startSimulation(
                        requestId: req.id,
                        hospitalId: req.currentHospitalId,
                        ambulanceId: ambId,
                        routePoints: routeResult.points,
                        speedMultiplier: currentMultiplier,
                      );
                    } else {
                      liveService.stopSimulation();
                      final ambId = req.ambulance?.ambulanceId.isNotEmpty == true
                          ? req.ambulance!.ambulanceId
                          : (req.crewUid ?? 'AMB-UNKNOWN');
                      await liveService.startPublishing(
                        requestId: req.id,
                        hospitalId: req.currentHospitalId,
                        ambulanceId: ambId,
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              isSimulating
                  ? 'Replaying drive to ${targetHospital.name}. Telemetry writes directly to liveLocations/${req.id}.'
                  : 'Toggle to simulate ambulance GPS movement along the OSRM route for judge demo.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
            if (isSimulating) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Speed: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Wrap(
                    spacing: 6,
                    children: [1.0, 2.0, 4.0].map((mult) {
                      final isSelected = (currentMultiplier - mult).abs() < 0.1;
                      return ChoiceChip(
                        label: Text('${mult.toInt()}x', style: const TextStyle(fontSize: 11)),
                        selected: isSelected,
                        selectedColor: AppColors.primary.withAlpha(40),
                        labelStyle: TextStyle(
                          color: isSelected ? AppColors.primary : Colors.grey.shade700,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (_) {
                          liveService.setSimulationSpeedMultiplier(mult);
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAcceptedState(
    EmergencyRequest req,
    Hospital? targetHospital,
    String targetName,
    String targetPhone,
    FirestoreService firestoreService,
    LiveLocationService liveLocationService,
  ) {
    final currentContext = context;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Live Location Indicator or Warning Banner
          _buildLocationDisabledBanner(liveLocationService),
          if (liveLocationService.isPublishing)
            Center(child: _buildLiveLocationIndicator(liveLocationService)),

          // Big Green BED HELD Banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.success,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Icon(Icons.check_circle_rounded,
                    size: 56, color: Colors.white),
                const SizedBox(height: 8),
                const Text(
                  'BED HELD SUCCESSFULLY',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  targetName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Stepper
          _buildStepper('accepted', targetName, reliefState: req.reliefState),
          const SizedBox(height: 20),

          // Details Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hospital: $targetName',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text('Phone: $targetPhone',
                      style: const TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text('Needs reserved: ${req.needs.join(", ")}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Live Telemetry Debug Panel (Confirm Firestore Writes)
          _buildLiveTelemetryDebug(liveLocationService),
          const SizedBox(height: 12),

          // Debug Route Simulator Toggle (Debug/Demo Builds)
          _buildDriveSimulatorDebugCard(
            req: req,
            targetHospital: targetHospital,
            liveService: liveLocationService,
          ),
          const SizedBox(height: 24),

          // Actions: Navigate & Mark Arrived
          ElevatedButton.icon(
            onPressed: () {
              if (targetHospital != null) {
                _openGoogleMaps(
                    targetHospital.lat, targetHospital.lng, targetName);
              }
            },
            icon: const Icon(Icons.navigation_rounded, size: 28),
            label: const Text('Navigate with Google Maps'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
              backgroundColor: AppColors.info,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _isProcessing
                ? null
                : () async {
                    setState(() => _isProcessing = true);
                    try {
                      await ref.read(liveLocationServiceProvider).stopPublishing(deleteDoc: true);
                      await firestoreService.markArrivedTransaction(req.id);
                      if (currentContext.mounted) {
                        currentContext.go('/dispatch/complete');
                      }
                    } finally {
                      if (mounted) setState(() => _isProcessing = false);
                    }
                  },
            icon: const Icon(Icons.flag_rounded, size: 28),
            label: const Text('Mark Patient Arrived'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
              backgroundColor: AppColors.success,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _makeCall(targetPhone),
            icon: const Icon(Icons.phone),
            label: const Text('Call Hospital Station'),
          ),
          const SizedBox(height: 12),

          // 4th Button: Disabled Emergency (Phase 12D)
          _buildDisabledEmergencyButton(req),
        ],
      ),
    );
  }

  Widget _buildDisabledEmergencyButton(EmergencyRequest req) {
    final bool isReliefActive =
        req.reliefState == 'searching' || req.reliefState == 'accepted';

    if (isReliefActive) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: req.reliefState == 'accepted'
              ? AppColors.successTint
              : AppColors.warningTint,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: req.reliefState == 'accepted'
                ? AppColors.success
                : AppColors.warning,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.emergency_rounded,
              color: req.reliefState == 'accepted'
                  ? AppColors.success
                  : AppColors.warningText,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    req.reliefState == 'accepted'
                        ? 'Relief Ambulance Approaching'
                        : 'Relief Request Active',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: req.reliefState == 'accepted'
                          ? AppColors.success
                          : AppColors.warningText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Tap to view live radar and approaching crew.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () => context.push('/dispatch/relief'),
              style: ElevatedButton.styleFrom(
                backgroundColor: req.reliefState == 'accepted'
                    ? AppColors.success
                    : AppColors.warning,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              child: const Text('View Radar'),
            ),
          ],
        ),
      );
    }

    // Enabled Disabled Emergency Button (Emergency Red allowed per rule 1)
    return ElevatedButton.icon(
      onPressed: _isProcessing ? null : () => _showDisabledEmergencySheet(req),
      icon: const Icon(Icons.car_crash_rounded, size: 28, color: Colors.white),
      label: const Text(
        'Disabled Emergency',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(60),
        backgroundColor: AppColors.danger,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  void _showDisabledEmergencySheet(EmergencyRequest req) {
    String selectedReason = 'breakdown';
    bool sheetProcessing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final reasons = [
              {'code': 'breakdown', 'label': 'Breakdown'},
              {'code': 'accident', 'label': 'Accident'},
              {'code': 'flat_tyre', 'label': 'Flat tyre'},
              {'code': 'fuel', 'label': 'Fuel'},
              {'code': 'other', 'label': 'Other'},
            ];

            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.dangerTint,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.report_problem_rounded,
                          color: AppColors.danger,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Vehicle Disabled Emergency',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'This alerts nearby available ambulances',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.danger,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'Select Breakdown Reason:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Reason Chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: reasons.map((r) {
                      final isSelected = selectedReason == r['code'];
                      return ChoiceChip(
                        label: Text(r['label']!),
                        selected: isSelected,
                        selectedColor: AppColors.dangerTint,
                        labelStyle: TextStyle(
                          color: isSelected ? AppColors.danger : AppColors.textPrimary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        side: BorderSide(
                          color: isSelected ? AppColors.danger : AppColors.divider,
                        ),
                        onSelected: sheetProcessing
                            ? null
                            : (val) {
                                if (val) {
                                  setSheetState(() => selectedReason = r['code']!);
                                }
                              },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 18, color: AppColors.primary),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Your patient hold at the hospital will remain reserved. Available AIS-125 ambulances will be alerted immediately.',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Confirm Button
                  ElevatedButton(
                    onPressed: sheetProcessing
                        ? null
                        : () async {
                            setSheetState(() => sheetProcessing = true);
                            final result = await ref
                                .read(reliefServiceProvider)
                                .createReliefRequest(
                                  originalRequestId: req.id,
                                  reason: selectedReason,
                                );

                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                            }

                            if (result.success) {
                              if (mounted) {
                                context.push('/dispatch/relief');
                              }
                            } else {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Failed to alert ambulances: ${result.message}'),
                                    backgroundColor: AppColors.danger,
                                  ),
                                );
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: sheetProcessing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Alert Nearby Ambulances Now',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFailedState(
    EmergencyRequest req,
    FirestoreService firestoreService,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.danger,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: const [
                Icon(Icons.error_outline_rounded, size: 56, color: Colors.white),
                SizedBox(height: 8),
                Text(
                  'NO HOSPITAL ACCEPTED REQUEST',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'All ranked hospitals rejected or timed out.',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Attempts Breakdown
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Handshake Attempts Summary',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ...req.attempts.map((attempt) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          const Icon(Icons.close_rounded,
                              color: AppColors.danger, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${attempt.hospitalName}: ${attempt.result.toUpperCase()}${attempt.reason != null ? " (${attempt.reason})" : ""}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          ElevatedButton.icon(
            onPressed: () {
              ref.read(selectedRequestIdProvider.notifier).select(null);
              context.go('/dispatch/new');
            },
            icon: const Icon(Icons.refresh_rounded, size: 28),
            label: const Text('Retry with Broader Criteria'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
              backgroundColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
