import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/crew_strings.dart';
import '../../core/theme.dart';
import '../../models/ambulance.dart';
import '../../providers/ambulance_auth_provider.dart';

class CrewPendingScreen extends ConsumerWidget {
  const CrewPendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ambulanceAsync = ref.watch(currentAmbulanceProvider);

    // Auto-redirect to /crew/home if status flips to VERIFIED live
    ref.listen<AsyncValue<Ambulance?>>(currentAmbulanceProvider, (_, next) {
      next.whenData((amb) {
        if (amb != null && amb.isVerified) {
          context.go('/crew/home');
        }
      });
    });

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text(CrewStrings.verificationStatusTitle),
          backgroundColor: AppColors.primaryDark,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: CrewStrings.signOutButton,
              onPressed: () async {
                await ref.read(ambulanceAuthControllerProvider).signOut();
                if (context.mounted) context.go('/crew/login');
              },
            ),
          ],
        ),
        body: SafeArea(
          child: ambulanceAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
            error: (err, _) => Center(
              child: Text('Error loading status: $err'),
            ),
            data: (ambulance) {
              if (ambulance == null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.account_circle_outlined,
                            size: 64, color: AppColors.textSecondary),
                        const SizedBox(height: 16),
                        const Text(
                          'No active ambulance session found.',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () => context.go('/crew/login'),
                          child: const Text('Back to Login'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final status = ambulance.verificationStatus;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),

                    // Status Header Card
                    _buildStatusBanner(context, ambulance),

                    const SizedBox(height: 20),

                    // Application Reference Card with Copy Action
                    _buildAppRefCard(context, ambulance.applicationRef),

                    const SizedBox(height: 24),

                    // Application Summary Details Card
                    _buildDetailsCard(ambulance),

                    const SizedBox(height: 28),

                    // Action buttons depending on status
                    if (status == AmbulanceVerificationStatus.rejected) ...[
                      ElevatedButton.icon(
                        onPressed: () async {
                          await ref
                              .read(ambulanceAuthControllerProvider)
                              .signOut();
                          if (context.mounted) {
                            context.go('/crew/register');
                          }
                        },
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text(
                          CrewStrings.registerAgainButton,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    OutlinedButton.icon(
                      onPressed: () async {
                        await ref
                            .read(ambulanceAuthControllerProvider)
                            .signOut();
                        if (context.mounted) context.go('/crew/login');
                      },
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text(CrewStrings.signOutButton),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBanner(BuildContext context, Ambulance ambulance) {
    final status = ambulance.verificationStatus;

    Color statusColor;
    Color statusBg;
    IconData statusIcon;
    String statusTitle;
    String statusDescription;

    switch (status) {
      case AmbulanceVerificationStatus.pending:
        statusColor = AppColors.primary;
        statusBg = AppColors.primaryTint;
        statusIcon = Icons.hourglass_top_rounded;
        statusTitle = CrewStrings.notVerifiedYetMessage;
        statusDescription = CrewStrings.liveProgressHint;
        break;
      case AmbulanceVerificationStatus.needsReview:
        statusColor = AppColors.warningText;
        statusBg = AppColors.warningTint;
        statusIcon = Icons.fact_check_outlined;
        statusTitle = CrewStrings.manualReviewMessage;
        statusDescription = ambulance.reviewReason ??
            CrewStrings.defaultReviewDetails;
        break;
      case AmbulanceVerificationStatus.rejected:
        statusColor = AppColors.danger;
        statusBg = AppColors.dangerTint;
        statusIcon = Icons.cancel_outlined;
        statusTitle = CrewStrings.applicationRejectedTitle;
        statusDescription = ambulance.rejectionReason ??
            CrewStrings.defaultRejectionDetails;
        break;
      case AmbulanceVerificationStatus.verified:
        statusColor = AppColors.success;
        statusBg = AppColors.successTint;
        statusIcon = Icons.verified_rounded;
        statusTitle = CrewStrings.verifiedAmbulanceBadge;
        statusDescription = 'Allocated Ambulance ID: ${ambulance.ambulanceId}';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: statusBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          if (status == AmbulanceVerificationStatus.pending) ...[
            const SizedBox(
              width: 50,
              height: 50,
              child: CircularProgressIndicator(
                strokeWidth: 3.5,
                color: AppColors.primary,
              ),
            ),
          ] else ...[
            Icon(statusIcon, size: 52, color: statusColor),
          ],
          const SizedBox(height: 14),
          Text(
            statusTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            statusDescription,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary,
              height: 1.4,
            ),
          ),
          if (status == AmbulanceVerificationStatus.pending) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.sync_rounded, size: 14, color: AppColors.primary),
                SizedBox(width: 6),
                Text(
                  CrewStrings.liveWaitingNotice,
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: AppColors.primaryDark,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAppRefCard(BuildContext context, String applicationRef) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      CrewStrings.appRefLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      applicationRef,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryDark,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: applicationRef));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(CrewStrings.copiedToClipboard),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text(CrewStrings.copyButton),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryTint,
                    foregroundColor: AppColors.primaryDark,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                CrewStrings.appRefSaveGuidance,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsCard(Ambulance ambulance) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Application Specifications',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const Divider(height: 20),
            _buildRow('Operator Type', ambulance.ambulanceType),
            const SizedBox(height: 10),
            _buildRow('AIS-125 Tier', ambulance.ais125Tier),
            if (ambulance.contactNumber.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildRow('Contact Phone', ambulance.contactNumber),
            ],
            if (ambulance.driverLegalName.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildRow('Assigned Driver', ambulance.driverLegalName),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
