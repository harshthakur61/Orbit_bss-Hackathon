import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme.dart';
import '../../providers/hospital_providers.dart';
import '../../providers/location_providers.dart';

class HospitalLoginScreen extends ConsumerStatefulWidget {
  final String? pendingRequestId;

  const HospitalLoginScreen({super.key, this.pendingRequestId});

  @override
  ConsumerState<HospitalLoginScreen> createState() => _HospitalLoginScreenState();
}

class _HospitalLoginScreenState extends ConsumerState<HospitalLoginScreen> {
  String? _selectedHospitalId;
  final TextEditingController _pinController = TextEditingController();
  bool _obscurePin = true;
  String? _errorMessage;

  void _login() {
    if (_selectedHospitalId == null) {
      setState(() => _errorMessage = 'Please select a hospital');
      return;
    }

    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      setState(() => _errorMessage = 'Please enter 4-digit PIN');
      return;
    }

    final hospitalsAsync = ref.read(hospitalsStreamProvider);
    hospitalsAsync.whenData((hospitals) {
      try {
        final hospital = hospitals.firstWhere((h) => h.id == _selectedHospitalId);
        if (hospital.verifyPin(pin)) {
          // Success: Mark nurse online & register FCM device token for background wakeups
          ref.read(firestoreServiceProvider).updateNursePresence(_selectedHospitalId!, true);
          ref.read(fcmServiceProvider).registerNurseDevice(_selectedHospitalId!);
          ref.read(selectedHospitalIdProvider.notifier).select(_selectedHospitalId);

          if (widget.pendingRequestId != null) {
            // Verify if the pending emergency request is still offered
            FirebaseFirestore.instance
                .collection('requests')
                .doc(widget.pendingRequestId)
                .get()
                .then((doc) {
              if (doc.exists &&
                  doc.data()?['status'] == 'offered' &&
                  doc.data()?['currentHospitalId'] == _selectedHospitalId) {
                if (mounted) context.go('/nurse/home');
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('This request is no longer active'),
                      backgroundColor: AppColors.textSecondary,
                    ),
                  );
                  context.go('/nurse/beds');
                }
              }
            }).catchError((_) {
              if (mounted) context.go('/nurse/beds');
            });
          } else {
            context.go('/nurse/beds');
          }
        } else {
          setState(() => _errorMessage = 'Invalid PIN (Default is 1234)');
        }
      } catch (_) {
        setState(() => _errorMessage = 'Hospital not found');
      }
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hospitalsAsync = ref.watch(hospitalsStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Hospital Nurse Login'),
        backgroundColor: AppColors.primaryDark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Role Selection',
          onPressed: () => context.go('/'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              // Header Icon & Title
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryTint,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.local_hospital_rounded,
                    size: 44,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Nurse Station Access',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryDark,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Select your hospital and enter PIN to manage live bed inventory.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),

              // Hospital Selector Dropdown
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select Hospital',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      hospitalsAsync.when(
                        data: (hospitals) {
                          if (hospitals.isEmpty) {
                            return Column(
                              children: [
                                const Text(
                                  'No hospitals found in database.',
                                  style: TextStyle(color: AppColors.danger),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton(
                                  onPressed: () => context.push('/demo'),
                                  child: const Text('Open Demo Controls to Seed'),
                                ),
                              ],
                            );
                          }
                          return DropdownButtonFormField<String>(
                            initialValue: _selectedHospitalId,
                            decoration: const InputDecoration(
                              hintText: 'Choose your hospital…',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                            items: hospitals.map((h) {
                              return DropdownMenuItem(
                                value: h.id,
                                child: Text(
                                  h.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 15),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setState(() {
                                _selectedHospitalId = val;
                                _errorMessage = null;
                              });
                            },
                          );
                        },
                        loading: () => const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        error: (err, _) => Text(
                          'Error loading hospitals: $err',
                          style: const TextStyle(color: AppColors.danger),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // PIN Input Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '4-Digit Station PIN',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _pinController,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        obscureText: _obscurePin,
                        decoration: InputDecoration(
                          hintText: 'Default PIN is 1234',
                          border: const OutlineInputBorder(),
                          counterText: '',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePin
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() => _obscurePin = !_obscurePin);
                            },
                          ),
                        ),
                        onChanged: (_) {
                          if (_errorMessage != null) {
                            setState(() => _errorMessage = null);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.dangerTint,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.danger),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.danger),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Continue Button
              ElevatedButton.icon(
                onPressed: _login,
                icon: const Icon(Icons.login_rounded, size: 24),
                label: const Text('Continue to Bed Station'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(64),
                  backgroundColor: AppColors.primary,
                ),
              ),

              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => context.push('/demo'),
                  child: const Text('Need seed data? Open Demo Controls'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
