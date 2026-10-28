import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../models/hospital.dart';
import '../../providers/hospital_providers.dart';
import '../../providers/location_providers.dart';
import '../../providers/request_providers.dart';
import '../../providers/ambulance_auth_provider.dart';
import '../../providers/crew_presence_providers.dart';

class TripCompleteScreen extends ConsumerWidget {
  const TripCompleteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestAsync = ref.watch(currentRequestProvider);
    final hospitalsAsync = ref.watch(hospitalsStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Trip Complete'),
        backgroundColor: AppColors.primaryDark,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              // Success Graphic
              Center(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: const BoxDecoration(
                    color: AppColors.successTint,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    size: 64,
                    color: AppColors.success,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Emergency Handshake Complete!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryDark,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Patient safely delivered to hospital bed station.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 32),

              // Summary Card
              requestAsync.when(
                data: (req) {
                  if (req == null) return const SizedBox.shrink();
                  final List<Hospital> hospitals = hospitalsAsync.value ?? [];
                  Hospital? hospital;
                  try {
                    hospital = hospitals
                        .firstWhere((h) => h.id == req.currentHospitalId);
                  } catch (_) {}

                  final hospitalName = hospital?.name ?? 'Hospital Station';
                  final hospitalPhone = hospital?.phone ?? '';

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TRIP SUMMARY',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.local_hospital_rounded,
                                  color: AppColors.primary, size: 24),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  hospitalName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (hospitalPhone.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Phone: $hospitalPhone',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                          const Divider(height: 24),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Reserved Beds:',
                                  style: TextStyle(fontWeight: FontWeight.w600)),
                              Text(
                                req.needs.join(', '),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.success,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Patient Triage Severity:',
                                  style: TextStyle(fontWeight: FontWeight.w600)),
                              Text(
                                req.severity.toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Handshake Attempts:',
                                  style: TextStyle(fontWeight: FontWeight.w600)),
                              Text(
                                '${req.attempts.length} hospital(s) contacted',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => const SizedBox.shrink(),
              ),

              const Spacer(),

              // Primary New Emergency Button
              ElevatedButton.icon(
                onPressed: () {
                  final currentAmb = ref.read(currentAmbulanceProvider).value;
                  if (currentAmb != null) {
                    try {
                      ref.read(crewPresenceServiceProvider).restorePreviousStatus(
                            currentAmb.uid,
                            ambulance: currentAmb,
                          );
                    } catch (_) {}
                  }

                  ref.read(selectedRequestIdProvider.notifier).select(null);
                  ref
                      .read(requestDraftProvider.notifier)
                      .setNeeds(['ICU']);
                  if (!ref.read(isPatientModeProvider)) {
                    context.go('/crew/home');
                  } else {
                    context.go('/dispatch/new');
                  }
                },
                icon: const Icon(Icons.add_location_alt_rounded, size: 28),
                label: const Text('Start New Emergency Request'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(68),
                  backgroundColor: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
