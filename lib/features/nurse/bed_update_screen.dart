import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/widgets/freshness_badge.dart';
import '../../core/widgets/bed_tile.dart';
import '../../models/bed_inventory.dart';
import '../../models/emergency_request.dart';
import '../../services/firestore_service.dart';
import '../../providers/hospital_providers.dart';
import '../../providers/request_providers.dart';
import 'incoming_request_screen.dart';

class BedUpdateScreen extends ConsumerStatefulWidget {
  const BedUpdateScreen({super.key});

  @override
  ConsumerState<BedUpdateScreen> createState() => _BedUpdateScreenState();
}

class _BedUpdateScreenState extends ConsumerState<BedUpdateScreen> {
  BedInventory? _editedBeds;
  Timer? _refreshTimer;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Periodically rebuild every 30 seconds to keep FreshnessBadge UI live
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  bool _hasChanges(BedInventory current) {
    if (_editedBeds == null) return false;
    return _editedBeds!.icu.available != current.icu.available ||
        _editedBeds!.ventilator.available != current.ventilator.available ||
        _editedBeds!.oxygen.available != current.oxygen.available ||
        _editedBeds!.cardiac.available != current.cardiac.available ||
        _editedBeds!.burns.available != current.burns.available ||
        _editedBeds!.general.available != current.general.available;
  }

  void _onCountChanged(
      String bedType, int newAvailable, BedInventory current) {
    final active = _editedBeds ?? current;
    final oldCount = active.getForType(bedType);
    final updatedCount = oldCount.copyWith(available: newAvailable);

    setState(() {
      _editedBeds = active.updateForType(bedType, updatedCount);
    });
  }

  void _onToggleFull(String bedType, BedInventory current) {
    final active = _editedBeds ?? current;
    final oldCount = active.getForType(bedType);

    int newAvailable;
    if (oldCount.available > 0) {
      newAvailable = 0; // Set to full
    } else {
      newAvailable = oldCount.total > 0 ? (oldCount.total ~/ 2) : 1; // Restore
    }

    _onCountChanged(bedType, newAvailable, current);
  }

  Widget _buildActiveAcceptedBanner(EmergencyRequest req, FirestoreService firestoreService) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.successTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 24),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'ACTIVE BED HELD FOR AMBULANCE',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.success,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  req.severity.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Beds Reserved: ${req.needs.join(", ")} Bed',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          if (req.note != null && req.note!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Clinical note: "${req.note}"',
              style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () async {
                          setState(() => _isSaving = true);
                          try {
                            await firestoreService.releaseHoldTransaction(req.id);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Hold released.')),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _isSaving = false);
                          }
                        },
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Release'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () async {
                          setState(() => _isSaving = true);
                          try {
                            await firestoreService.markArrivedTransaction(req.id);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('✓ Patient marked Arrived! Hold finalized.'),
                                  backgroundColor: AppColors.success,
                                ),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _isSaving = false);
                          }
                        },
                  icon: const Icon(Icons.check_circle_rounded, size: 20),
                  label: const Text('MARK PATIENT ARRIVED'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = ref.watch(selectedHospitalIdProvider);
    final hospital = ref.watch(selectedHospitalProvider);
    final firestoreService = ref.watch(firestoreServiceProvider);

    if (selectedId == null || hospital == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bed Update')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.local_hospital_outlined, size: 64, color: AppColors.textSecondary),
              const SizedBox(height: 16),
              const Text(
                'No hospital station selected.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => context.go('/'),
                    icon: const Icon(Icons.home_rounded),
                    label: const Text('Landing Page'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => context.go('/nurse/login'),
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Nurse Login'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final activeRequestAsync = ref.watch(activeHospitalRequestProvider(selectedId));

    final activeRequest = activeRequestAsync.value;
    if (activeRequest != null && activeRequest.status == 'offered') {
      return IncomingRequestScreen(request: activeRequest);
    }

    final activeBeds = _editedBeds ?? hospital.beds;
    final isModified = _hasChanges(hospital.beds);

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
            const Text(
              'Nurse Bed Station',
              style: TextStyle(fontSize: 12, color: AppColors.primaryTint),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded),
            tooltip: 'Main Landing Page (Change Role)',
            onPressed: () {
              firestoreService.updateNursePresence(selectedId, false);
              ref.read(selectedHospitalIdProvider.notifier).select(null);
              context.go('/');
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Switch Hospital Login',
            onPressed: () {
              firestoreService.updateNursePresence(selectedId, false);
              ref.read(selectedHospitalIdProvider.notifier).select(null);
              context.go('/nurse/login');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Freshness & Online Status Header Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppColors.surface,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          hospital.isNurseOnline
                              ? Icons.wifi_rounded
                              : Icons.wifi_off_rounded,
                          color: hospital.isNurseOnline
                              ? AppColors.success
                              : AppColors.danger,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          hospital.isNurseOnline
                              ? 'Nurse Terminal ONLINE'
                              : 'Nurse Terminal OFFLINE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: hospital.isNurseOnline
                                ? AppColors.success
                                : AppColors.danger,
                          ),
                        ),
                      ],
                    ),
                    Switch.adaptive(
                      value: hospital.isNurseOnline,
                      activeColor: AppColors.success,
                      onChanged: (val) {
                        firestoreService.updateNursePresence(hospital.id, val);
                      },
                    ),
                  ],
                ),
                const Divider(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FreshnessBadge(lastUpdated: hospital.lastUpdated),
                    ),
                    const SizedBox(width: 8),
                    // 1-Tap "Everything is up to date" Button
                    ElevatedButton.icon(
                      onPressed: _isSaving
                          ? null
                          : () async {
                              try {
                                await firestoreService.touchHospitalTimestamp(hospital.id);
                                setState(() {
                                  _editedBeds = null; // Reset edited draft
                                });
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('✓ Refreshed timestamp! Data marked fresh.'),
                                      backgroundColor: AppColors.success,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error: $e'),
                                      backgroundColor: AppColors.danger,
                                    ),
                                  );
                                }
                              }
                            },
                      icon: const Icon(Icons.check_circle_rounded, size: 18),
                      label: const Text(
                        'Up to Date',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(120, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),


          // Scrollable Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Active Bed Held Banner (if accepted request exists)
                  if (activeRequest != null && activeRequest.status == 'accepted')
                    _buildActiveAcceptedBanner(activeRequest, firestoreService),

                  // ER Load Selector Section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Emergency Room Load',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: hospital.loadLevel == 'low'
                                      ? AppColors.successTint
                                      : (hospital.loadLevel == 'med'
                                          ? AppColors.warningTint
                                          : AppColors.dangerTint),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  hospital.loadLevel.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: hospital.loadLevel == 'low'
                                        ? AppColors.success
                                        : (hospital.loadLevel == 'med'
                                            ? AppColors.warningText
                                            : AppColors.danger),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'low',
                                label: Text('Low'),
                                icon: Icon(Icons.sentiment_satisfied_alt_rounded),
                              ),
                              ButtonSegment(
                                value: 'med',
                                label: Text('Medium'),
                                icon: Icon(Icons.sentiment_neutral_rounded),
                              ),
                              ButtonSegment(
                                value: 'high',
                                label: Text('High'),
                                icon: Icon(Icons.warning_amber_rounded),
                              ),
                            ],
                            selected: {hospital.loadLevel},
                            onSelectionChanged: (newSelection) async {
                              final newLoad = newSelection.first;
                              try {
                                await firestoreService.updateHospitalLoad(
                                  hospital.id,
                                  newLoad,
                                );
                              } catch (e) {
                                debugPrint('Error updating load: $e');
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Text(
                    'Live Bed Counts (Tap tile to toggle Full/Available)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 6 Bed Tiles
                  BedTile(
                    title: 'ICU',
                    icon: Icons.monitor_heart_outlined,
                    bedCount: activeBeds.icu,
                    onCountChanged: (val) =>
                        _onCountChanged('icu', val, hospital.beds),
                    onToggleFull: () => _onToggleFull('icu', hospital.beds),
                  ),
                  const SizedBox(height: 12),

                  BedTile(
                    title: 'Ventilator',
                    icon: Icons.air_rounded,
                    bedCount: activeBeds.ventilator,
                    onCountChanged: (val) =>
                        _onCountChanged('ventilator', val, hospital.beds),
                    onToggleFull: () => _onToggleFull('ventilator', hospital.beds),
                  ),
                  const SizedBox(height: 12),

                  BedTile(
                    title: 'Oxygen Bed',
                    icon: Icons.masks_outlined,
                    bedCount: activeBeds.oxygen,
                    onCountChanged: (val) =>
                        _onCountChanged('oxygen', val, hospital.beds),
                    onToggleFull: () => _onToggleFull('oxygen', hospital.beds),
                  ),
                  const SizedBox(height: 12),

                  BedTile(
                    title: 'Cardiac Care',
                    icon: Icons.favorite_border_rounded,
                    bedCount: activeBeds.cardiac,
                    onCountChanged: (val) =>
                        _onCountChanged('cardiac', val, hospital.beds),
                    onToggleFull: () => _onToggleFull('cardiac', hospital.beds),
                  ),
                  const SizedBox(height: 12),

                  BedTile(
                    title: 'Burns Unit',
                    icon: Icons.local_fire_department_outlined,
                    bedCount: activeBeds.burns,
                    onCountChanged: (val) =>
                        _onCountChanged('burns', val, hospital.beds),
                    onToggleFull: () => _onToggleFull('burns', hospital.beds),
                  ),
                  const SizedBox(height: 12),

                  BedTile(
                    title: 'General Ward',
                    icon: Icons.single_bed_outlined,
                    bedCount: activeBeds.general,
                    onCountChanged: (val) =>
                        _onCountChanged('general', val, hospital.beds),
                    onToggleFull: () => _onToggleFull('general', hospital.beds),
                  ),
                  const SizedBox(height: 80), // Padding for sticky bottom bar
                ],
              ),
            ),
          ),
        ],
      ),

      // Sticky Save Update Button
      bottomSheet: isModified
          ? Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: AppColors.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: ElevatedButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () async {
                          setState(() => _isSaving = true);
                          try {
                            await firestoreService.updateHospitalBeds(
                              hospital.id,
                              activeBeds,
                            );
                            setState(() {
                              _editedBeds = null;
                            });
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('✓ Saved bed inventory updates!'),
                                  backgroundColor: AppColors.success,
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error saving: $e'),
                                  backgroundColor: AppColors.danger,
                                ),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _isSaving = false);
                          }
                        },
                  icon: const Icon(Icons.save_rounded, size: 24),
                  label: Text(_isSaving ? 'Saving…' : 'Save Update'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(60),
                    backgroundColor: AppColors.primary,
                  ),
                ),
              ),
            )
          : null,

      // Bottom Navigation Bar (Beds / Requests)
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          if (index == 1) {
            context.push('/nurse/history');
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
