import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../core/widgets/countdown_ring.dart';
import '../../models/emergency_request.dart';
import '../../models/hospital.dart';
import '../../services/firestore_service.dart';
import '../../providers/hospital_providers.dart';
import '../../providers/request_providers.dart';

class HoldStatusScreen extends ConsumerStatefulWidget {
  const HoldStatusScreen({super.key});

  @override
  ConsumerState<HoldStatusScreen> createState() => _HoldStatusScreenState();
}

class _HoldStatusScreenState extends ConsumerState<HoldStatusScreen> {
  bool _isProcessing = false;

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

  Widget _buildStepper(String status, String hospitalName) {
    final bool isAcceptedOrArrived = status == 'accepted' || status == 'arrived';
    final bool isArrived = status == 'arrived';

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
      {'title': 'En route', 'done': isArrived},
      {'title': 'Arrived', 'done': isArrived},
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Status Stepper',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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
    // Listen for live Firestore updates on the current request
    ref.listen<AsyncValue<EmergencyRequest?>>(currentRequestProvider,
        (previous, next) {
      final req = next.value;
      if (req != null && req.status == 'arrived') {
        if (mounted) {
          context.go('/dispatch/complete');
        }
      }
    });

    final requestId = ref.watch(selectedRequestIdProvider);
    final requestAsync = ref.watch(currentRequestProvider);
    final hospitalsAsync = ref.watch(hospitalsStreamProvider);
    final firestoreService = ref.watch(firestoreServiceProvider);

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

          // Check if targeted hospital should be auto-skipped (Nurse Offline OR 0 Available Beds)
          final bool isNurseOffline = targetHospital != null && !targetHospital.isNurseOnline;
          final bool hasZeroRequestedBeds = targetHospital != null &&
              req.needs.any((need) => targetHospital!.beds.getForType(need).available <= 0);

          if (req.status == 'offered' &&
              targetHospital != null &&
              (isNurseOffline || hasZeroRequestedBeds) &&
              !_isProcessing) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (mounted && !_isProcessing) {
                setState(() => _isProcessing = true);
                final skipReason = isNurseOffline
                    ? 'Nurse terminal offline (0s auto-skip)'
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
                req, targetHospital, targetName, targetPhone, firestoreService);
          }

          // Default Waiting / Offered State
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Stepper
                _buildStepper(req.status, targetName),
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
                                color: isNurseOffline
                                    ? AppColors.dangerTint
                                    : (hasZeroRequestedBeds
                                        ? AppColors.warningTint
                                        : AppColors.successTint),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isNurseOffline
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
                                    isNurseOffline
                                        ? Icons.wifi_off_rounded
                                        : (hasZeroRequestedBeds
                                            ? Icons.event_busy_rounded
                                            : Icons.wifi_rounded),
                                    size: 12,
                                    color: isNurseOffline
                                        ? AppColors.danger
                                        : (hasZeroRequestedBeds
                                            ? AppColors.warningText
                                            : AppColors.success),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isNurseOffline
                                        ? 'Nurse Offline (Auto-Skip)'
                                        : (hasZeroRequestedBeds
                                            ? '0 Beds Avail (Auto-Skip)'
                                            : 'Nurse Online'),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isNurseOffline
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
                            await firestoreService.releaseHoldTransaction(req.id);
                            ref.read(selectedRequestIdProvider.notifier).select(null);
                            if (mounted) context.go('/dispatch/new');
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

  Widget _buildAcceptedState(
    EmergencyRequest req,
    Hospital? targetHospital,
    String targetName,
    String targetPhone,
    FirestoreService firestoreService,
  ) {
    final currentContext = context;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          _buildStepper('accepted', targetName),
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
          const SizedBox(height: 32),

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
        ],
      ),
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
