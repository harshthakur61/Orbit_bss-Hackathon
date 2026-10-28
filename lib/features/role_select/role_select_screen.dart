import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../providers/request_providers.dart';
import '../../providers/patient_auth_provider.dart';

class RoleSelectScreen extends ConsumerWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              // Logo with long press shortcut for Demo Controls
              GestureDetector(
                onLongPress: () {
                  context.push('/demo');
                },
                child: Column(
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: AppColors.primaryTint,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primary, width: 2),
                      ),
                      child: const Icon(
                        Icons.local_hospital_rounded,
                        size: 56,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'BedLink',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: AppColors.primaryDark,
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Real-Time Emergency Bed Allocation',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Role selection header
              Text(
                'Select Your Role',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              // Nurse Button
              ElevatedButton.icon(
                onPressed: () {
                  context.push('/nurse/login');
                },
                icon: const Icon(Icons.local_hospital_outlined, size: 28),
                label: const Text("I'm a Hospital Nurse"),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(60),
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              // Ambulance Button
              OutlinedButton.icon(
                onPressed: () {
                  ref.read(isPatientModeProvider.notifier).setPatientMode(false);
                  context.push('/crew/login');
                },
                icon: const Icon(Icons.airport_shuttle_outlined, size: 28),
                label: const Text("I'm an Ambulance Crew"),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(60),
                  side: const BorderSide(color: AppColors.primary, width: 2),
                ),
              ),
              const SizedBox(height: 12),
              // Patient Button
              FilledButton.tonalIcon(
                onPressed: () {
                  ref.read(isPatientModeProvider.notifier).setPatientMode(true);
                  final auth = ref.read(patientAuthProvider);
                  if (auth.isAuthenticated) {
                    context.push('/patient/hub');
                  } else {
                    context.push('/patient/login');
                  }
                },
                icon: const Icon(Icons.person_outline_rounded, size: 28, color: AppColors.primaryDark),
                label: const Text(
                  "Continue as Patient",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryDark,
                  ),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(60),
                  backgroundColor: AppColors.primaryTint,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Subtitle hint
              Text(
                'Hold logo for Demo Controls',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 12,
                      color: AppColors.textSecondary.withValues(alpha: 0.6),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
