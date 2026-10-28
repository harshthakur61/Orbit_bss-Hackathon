// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/widgets/countdown_ring.dart';
import '../../core/utils/alert_sound.dart';
import '../../models/emergency_request.dart';
import '../../providers/hospital_providers.dart';
import '../../providers/request_providers.dart';
import '../../services/alarm_notification_service.dart';
import 'widgets/voice_note_player_card.dart';

class IncomingRequestScreen extends ConsumerStatefulWidget {
  final EmergencyRequest request;

  const IncomingRequestScreen({
    super.key,
    required this.request,
  });

  @override
  ConsumerState<IncomingRequestScreen> createState() =>
      _IncomingRequestScreenState();
}

class _IncomingRequestScreenState
    extends ConsumerState<IncomingRequestScreen> {
  bool _isProcessing = false;
  String _rejectReason = 'No bed available';

  @override
  void initState() {
    super.initState();
    // Start continuous looping sound and vibration alert, silencing system notification
    AlertSoundUtil.triggerIncomingAlert(widget.request.id);
  }

  @override
  void dispose() {
    // Stop sound and vibration loop when screen closes & cancel system notification
    AlertSoundUtil.stopAlert();
    AlarmNotificationService.instance.cancelEmergencyAlarmNotification(widget.request.id);
    super.dispose();
  }

  void _showRejectReasonSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.cancel_outlined, color: AppColors.danger),
                      SizedBox(width: 8),
                      Text(
                        'Select Reject Reason',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  RadioListTile<String>(
                    title: const Text('No bed available',
                        style: TextStyle(color: AppColors.textPrimary)),
                    value: 'No bed available',
                    groupValue: _rejectReason,
                    activeColor: AppColors.danger,
                    onChanged: (val) {
                      if (val != null) setSheetState(() => _rejectReason = val);
                    },
                  ),
                  RadioListTile<String>(
                    title: const Text('Staff busy',
                        style: TextStyle(color: AppColors.textPrimary)),
                    value: 'Staff busy',
                    groupValue: _rejectReason,
                    activeColor: AppColors.danger,
                    onChanged: (val) {
                      if (val != null) setSheetState(() => _rejectReason = val);
                    },
                  ),
                  RadioListTile<String>(
                    title: const Text('Equipment down',
                        style: TextStyle(color: AppColors.textPrimary)),
                    value: 'Equipment down',
                    groupValue: _rejectReason,
                    activeColor: AppColors.danger,
                    onChanged: (val) {
                      if (val != null) setSheetState(() => _rejectReason = val);
                    },
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _isProcessing
                        ? null
                        : () async {
                            Navigator.pop(ctx);
                            await _handleReject();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(56),
                    ),
                    child: const Text('Confirm Rejection'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleAccept() async {
    setState(() => _isProcessing = true);
    final firestoreService = ref.read(firestoreServiceProvider);
    final hospital = ref.read(selectedHospitalProvider);

    if (hospital == null) return;

    try {
      final success = await firestoreService.acceptRequestTransaction(
        widget.request.id,
        hospital.id,
      );

      await AlertSoundUtil.stopAlert();
      await AlarmNotificationService.instance
          .cancelEmergencyAlarmNotification(widget.request.id);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ BED HELD! Request accepted successfully.'),
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bed unavailable or request expired.'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleReject() async {
    setState(() => _isProcessing = true);
    final firestoreService = ref.read(firestoreServiceProvider);
    final hospital = ref.read(selectedHospitalProvider);

    if (hospital == null) return;

    try {
      await firestoreService.rejectRequestTransaction(
        widget.request.id,
        hospital.id,
        _rejectReason,
      );

      await AlertSoundUtil.stopAlert();
      await AlarmNotificationService.instance
          .cancelEmergencyAlarmNotification(widget.request.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request rejected. Cascaded to next hospital.'),
            backgroundColor: AppColors.warningText,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error rejecting: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleTimeout() async {
    await AlertSoundUtil.stopAlert();
    await AlarmNotificationService.instance
        .cancelEmergencyAlarmNotification(widget.request.id);
    final firestoreService = ref.read(firestoreServiceProvider);
    final hospital = ref.read(selectedHospitalProvider);
    if (hospital == null) return;

    try {
      await firestoreService.handleTimeoutCascade(
        widget.request.id,
        hospital.id,
      );
    } catch (e) {
      debugPrint('Timeout cascade error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final requests = ref.watch(requestsStreamProvider).value;
    final liveReq = requests?.firstWhere(
          (r) => r.id == widget.request.id,
          orElse: () => widget.request,
        ) ??
        widget.request;
    final req = liveReq;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Red Emergency Header Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.danger.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: const [
                    Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'INCOMING EMERGENCY REQUEST',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Countdown Ring shifted slightly above center
              Center(
                child: CountdownRing(
                  offerExpiresAt: req.offerExpiresAt,
                  isDarkTheme: false,
                  onExpired: _handleTimeout,
                ),
              ),
              const SizedBox(height: 16),

              // Patient Details Card in Light Palette with Red Accent Border
              Expanded(
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: AppColors.danger, width: 1.5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Required Bed Types',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: req.severity == 'critical'
                                      ? AppColors.dangerTint
                                      : AppColors.warningTint,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: req.severity == 'critical'
                                        ? AppColors.danger
                                        : AppColors.warning,
                                  ),
                                ),
                                child: Text(
                                  req.severity.toUpperCase(),
                                  style: TextStyle(
                                    color: req.severity == 'critical'
                                        ? AppColors.danger
                                        : AppColors.warningText,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: req.needs.map((need) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.successTint,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.success),
                                ),
                                child: Text(
                                  '✓ $need Bed',
                                  style: const TextStyle(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          if (req.note != null && req.note!.isNotEmpty) ...[
                            const Divider(height: 24),
                            const Text(
                              'Patient Clinical Note:',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                req.note!,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                          VoiceNotePlayerCard(
                            requestId: req.id,
                            voiceNote: req.voiceNote,
                            voiceNoteStatus: req.voiceNoteStatus,
                            isOfferActiveChecker: () {
                              final hospital = ref.read(selectedHospitalProvider);
                              final isOfferValid = req.status == 'offered' &&
                                  req.currentHospitalId == hospital?.id &&
                                  (req.offerExpiresAt == null ||
                                      DateTime.now().isBefore(req.offerExpiresAt!));
                              return isOfferValid;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Action Buttons: ACCEPT & REJECT (80dp tall)
              Row(
                children: [
                  // REJECT Button
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _showRejectReasonSheet,
                      icon: const Icon(Icons.close_rounded, size: 28),
                      label: const Text('REJECT'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(80),
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // ACCEPT (HOLD BED) Button
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _handleAccept,
                      icon: const Icon(Icons.check_circle_rounded, size: 28),
                      label: const Text('ACCEPT\n(HOLD BED)'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(80),
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
