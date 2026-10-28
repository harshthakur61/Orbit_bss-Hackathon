import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../models/hospital.dart';
import '../../providers/hospital_providers.dart';
import '../../providers/request_providers.dart';
import 'widgets/request_detail_sheet.dart';

class RequestHistoryScreen extends ConsumerStatefulWidget {
  final bool isEmbedded;
  final Hospital? hospital;

  const RequestHistoryScreen({
    super.key,
    this.isEmbedded = false,
    this.hospital,
  });

  @override
  ConsumerState<RequestHistoryScreen> createState() =>
      _RequestHistoryScreenState();
}

class _RequestHistoryScreenState extends ConsumerState<RequestHistoryScreen> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final hospital = widget.hospital ?? ref.watch(selectedHospitalProvider);
    final requestsAsync = ref.watch(requestsStreamProvider);
    final firestoreService = ref.watch(firestoreServiceProvider);

    if (hospital == null) {
      if (widget.isEmbedded) {
        return const Center(child: CircularProgressIndicator(color: AppColors.primary));
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Request History')),
        body: Center(
          child: ElevatedButton(
            onPressed: () => context.go('/nurse/login'),
            child: const Text('Go to Nurse Login'),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(hospital.name,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Text('Station Emergency History',
                      style: TextStyle(fontSize: 12, color: AppColors.primaryTint)),
                ],
              ),
        backgroundColor: AppColors.primaryDark,
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded),
            tooltip: 'Main Landing Page',
            onPressed: () {
              ref.read(selectedHospitalIdProvider.notifier).select(null);
              context.go('/');
            },
          ),
        ],
      ),
      body: requestsAsync.when(
        data: (allRequests) {
          // Filter requests relevant to this hospital (either target or in attempts)
          final stationRequests = allRequests.where((r) {
            final isTarget = r.currentHospitalId == hospital.id;
            final inAttempts =
                r.attempts.any((a) => a.hospitalId == hospital.id);
            return isTarget || inAttempts;
          }).toList();

          if (stationRequests.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.history_toggle_off_rounded,
                      size: 64, color: AppColors.textSecondary),
                  SizedBox(height: 16),
                  Text(
                    'No emergency request history yet.',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: stationRequests.length,
            itemBuilder: (context, index) {
              final req = stationRequests[index];
              final isCurrentlyTarget = req.currentHospitalId == hospital.id;

              Color statusBg;
              Color statusText;
              String statusLabel = req.status.toUpperCase();

              if (req.status == 'accepted') {
                statusBg = AppColors.successTint;
                statusText = AppColors.success;
                statusLabel = 'BED HELD';
              } else if (req.status == 'arrived') {
                statusBg = AppColors.primaryTint;
                statusText = AppColors.primaryDark;
                statusLabel = 'PATIENT ARRIVED';
              } else if (req.status == 'offered') {
                statusBg = AppColors.warningTint;
                statusText = AppColors.warningText;
                statusLabel = 'OFFERED (WAITING)';
              } else {
                statusBg = AppColors.dangerTint;
                statusText = AppColors.danger;
              }

              final formattedTime = req.createdAt != null
                  ? DateFormat('MMM dd, hh:mm a').format(req.createdAt!)
                  : 'Recent';

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => RequestDetailSheet.show(
                    context,
                    request: req,
                    hospital: hospital,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusBg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: statusText,
                              ),
                            ),
                          ),
                          Text(
                            formattedTime,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Needs: ${req.needs.join(", ")} Bed',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Severity: ${req.severity.toUpperCase()}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (req.note != null && req.note!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Note: ${req.note}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],

                      // Nurse Action buttons for Accepted Holds
                      if (isCurrentlyTarget && req.status == 'accepted') ...[
                        const Divider(height: 24),
                        Row(
                          children: [
                            // Release Hold Button
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _isProcessing
                                    ? null
                                    : () async {
                                        setState(() => _isProcessing = true);
                                        try {
                                          await firestoreService
                                              .releaseHoldTransaction(req.id);
                                          if (mounted) {
                                            // ignore: use_build_context_synchronously
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'Hold released. Beds restored.'),
                                              ),
                                            );
                                          }
                                        } finally {
                                          if (mounted) {
                                            setState(() => _isProcessing = false);
                                          }
                                        }
                                      },
                                icon: const Icon(Icons.remove_circle_outline),
                                label: const Text('Release Hold'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.danger,
                                  side: const BorderSide(
                                      color: AppColors.danger),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Patient Arrived Button
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isProcessing
                                    ? null
                                    : () async {
                                        setState(() => _isProcessing = true);
                                        try {
                                          await firestoreService
                                              .markArrivedTransaction(req.id);
                                          if (mounted) {
                                            // ignore: use_build_context_synchronously
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'Patient marked Arrived! Hold finalized.'),
                                                backgroundColor:
                                                    AppColors.success,
                                              ),
                                            );
                                          }
                                        } finally {
                                          if (mounted) {
                                            setState(() => _isProcessing = false);
                                          }
                                        }
                                      },
                                icon: const Icon(Icons.check_circle_rounded),
                                label: const Text('Patient Arrived'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error: $err')),
    ),
    bottomNavigationBar: widget.isEmbedded
        ? null
        : NavigationBar(
            selectedIndex: 1,
            onDestinationSelected: (index) {
              if (index == 0) {
                context.go('/nurse/beds');
              }
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.bed_rounded),
                label: 'Beds',
              ),
              NavigationDestination(
                icon: Icon(Icons.history_rounded),
                label: 'Requests',
              ),
            ],
          ),
  );
  }
}
