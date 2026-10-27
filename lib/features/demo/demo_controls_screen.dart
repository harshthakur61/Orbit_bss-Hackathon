import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../providers/hospital_providers.dart';

class DemoControlsScreen extends ConsumerStatefulWidget {
  const DemoControlsScreen({super.key});

  @override
  ConsumerState<DemoControlsScreen> createState() => _DemoControlsScreenState();
}

class _DemoControlsScreenState extends ConsumerState<DemoControlsScreen> {
  String? _selectedAgeHospitalId;
  int _ageMinutes = 50;

  String? _selectedRejectHospitalId;
  String _rejectReason = 'No bed available';

  bool _isLoading = false;

  void _showMessage(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.danger : AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hospitalsAsync = ref.watch(hospitalsStreamProvider);
    final firestoreService = ref.watch(firestoreServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hidden Demo Controls'),
        backgroundColor: AppColors.primaryDark,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header card
            Card(
              color: AppColors.primaryTint,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const Icon(Icons.tune_rounded, color: AppColors.primary, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hackathon Demo Utilities',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: AppColors.primaryDark,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Manipulate Firestore data live for judges.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Section 1: Seed & Reset
            Text(
              'Database Reset & Seeding',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () async {
                            setState(() => _isLoading = true);
                            try {
                              await firestoreService.seedHospitals();
                              await firestoreService.seedClinics();
                              _showMessage('Successfully seeded Hospitals & Clinics!');
                            } catch (e) {
                              _showMessage('Failed to seed: $e', isError: true);
                            } finally {
                              if (mounted) setState(() => _isLoading = false);
                            }
                          },
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Seed All Data'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      backgroundColor: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () async {
                            setState(() => _isLoading = true);
                            try {
                              await firestoreService.resetAllData();
                              await firestoreService.seedClinics();
                              _showMessage('All requests cleared, Hospitals & Clinics re-seeded!');
                            } catch (e) {
                              _showMessage('Failed to reset: $e', isError: true);
                            } finally {
                              if (mounted) setState(() => _isLoading = false);
                            }
                          },
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Reset All Data'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                    ),
                  ),
                ),
              ],
            ),

            const Divider(height: 40),

            // Section 2: Age Hospital Data
            Text(
              'Age Hospital Data (Simulate Stale Data)',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    hospitalsAsync.when(
                      data: (hospitals) {
                        return DropdownButtonFormField<String>(
                          initialValue: _selectedAgeHospitalId,
                          decoration: const InputDecoration(
                            labelText: 'Select Hospital',
                            border: OutlineInputBorder(),
                          ),
                          items: hospitals.map((h) {
                            return DropdownMenuItem(
                              value: h.id,
                              child: Text(h.name, overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() => _selectedAgeHospitalId = val);
                          },
                        );
                      },
                      loading: () => const CircularProgressIndicator(),
                      error: (err, _) => Text('Error loading hospitals: $err'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          'Age by: $_ageMinutes min',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Expanded(
                          child: Slider(
                            value: _ageMinutes.toDouble(),
                            min: 5,
                            max: 120,
                            divisions: 23,
                            label: '$_ageMinutes min',
                            onChanged: (val) {
                              setState(() => _ageMinutes = val.toInt());
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: (_selectedAgeHospitalId == null || _isLoading)
                          ? null
                          : () async {
                              setState(() => _isLoading = true);
                              try {
                                await firestoreService.ageHospitalData(
                                  _selectedAgeHospitalId!,
                                  _ageMinutes,
                                );
                                _showMessage('Hospital data aged by $_ageMinutes minutes!');
                              } catch (e) {
                                _showMessage('Error aging data: $e', isError: true);
                              } finally {
                                if (mounted) setState(() => _isLoading = false);
                              }
                            },
                      icon: const Icon(Icons.history_toggle_off_rounded),
                      label: const Text('Apply Timestamp Aging'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.warningText,
                        minimumSize: const Size.fromHeight(56),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 40),

            // Section 3: Auto-Reject as Hospital
            Text(
              'Simulate Hospital Auto-Reject',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    hospitalsAsync.when(
                      data: (hospitals) {
                        return DropdownButtonFormField<String>(
                          initialValue: _selectedRejectHospitalId,
                          decoration: const InputDecoration(
                            labelText: 'Select Hospital to Reject',
                            border: OutlineInputBorder(),
                          ),
                          items: hospitals.map((h) {
                            return DropdownMenuItem(
                              value: h.id,
                              child: Text(h.name, overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() => _selectedRejectHospitalId = val);
                          },
                        );
                      },
                      loading: () => const CircularProgressIndicator(),
                      error: (err, _) => Text('Error loading hospitals: $err'),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _rejectReason,
                      decoration: const InputDecoration(
                        labelText: 'Reject Reason',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'No bed available', child: Text('No bed available')),
                        DropdownMenuItem(
                            value: 'Staff busy', child: Text('Staff busy')),
                        DropdownMenuItem(
                            value: 'Equipment down', child: Text('Equipment down')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _rejectReason = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: (_selectedRejectHospitalId == null || _isLoading)
                          ? null
                          : () async {
                              setState(() => _isLoading = true);
                              try {
                                await firestoreService.autoRejectAsHospital(
                                  _selectedRejectHospitalId!,
                                  _rejectReason,
                                );
                                _showMessage('Triggered auto-reject for hospital!');
                              } catch (e) {
                                _showMessage('Error triggering reject: $e', isError: true);
                              } finally {
                                if (mounted) setState(() => _isLoading = false);
                              }
                            },
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Trigger Reject & Cascade'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        minimumSize: const Size.fromHeight(56),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 40),

            // Section 4: Toggle Hospital Nurse Terminal Presence
            Text(
              'Toggle Hospital Nurse Terminal (Online / Offline)',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Hospitals set to Offline will be automatically skipped in 0 seconds during emergency hold requests.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: hospitalsAsync.when(
                  data: (hospitals) {
                    return Column(
                      children: hospitals.map((h) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  h.name,
                                  style: const TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    h.isNurseOnline ? 'ONLINE' : 'OFFLINE',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: h.isNurseOnline
                                          ? AppColors.success
                                          : AppColors.danger,
                                    ),
                                  ),
                                  Switch.adaptive(
                                    value: h.isNurseOnline,
                                    activeColor: AppColors.success,
                                    onChanged: (val) async {
                                      await firestoreService.updateNursePresence(
                                          h.id, val);
                                      _showMessage(
                                          '${h.name} nurse terminal is now ${val ? "ONLINE 🟢" : "OFFLINE 🔴 (0s Auto-Skip)"}');
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                  loading: () => const CircularProgressIndicator(),
                  error: (err, _) => Text('Error: $err'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
