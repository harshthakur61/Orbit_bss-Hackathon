import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/router.dart';
import '../../core/theme.dart';
import '../../core/utils/alert_sound.dart';
import '../../core/widgets/countdown_ring.dart';
import '../../models/relief_offer_data.dart';
import '../../providers/relief_providers.dart';
import '../../services/alarm_notification_service.dart';
import '../../services/ambulance_auth_service.dart';

/// Full-screen emergency relief alert screen that overrides the crew terminal shell
/// when an inbound relief request offer is dispatched to this ambulance.
/// Strictly sanitized of patient clinical notes and hospital destination.
class ReliefRequestAlertScreen extends ConsumerStatefulWidget {
  final ReliefOfferData offer;
  final VoidCallback? onDismiss;

  const ReliefRequestAlertScreen({
    super.key,
    required this.offer,
    this.onDismiss,
  });

  @override
  ConsumerState<ReliefRequestAlertScreen> createState() =>
      _ReliefRequestAlertScreenState();
}

class _ReliefRequestAlertScreenState
    extends ConsumerState<ReliefRequestAlertScreen> {
  bool _isProcessing = false;
  String _selectedRejectReason = 'too_far';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _reliefDocSub;

  void _showSafeSnackBar(String message, {Color backgroundColor = AppColors.textSecondary}) {
    ScaffoldMessengerState? messenger;
    final navContext = rootNavigatorKey.currentContext;
    if (navContext != null && navContext.mounted) {
      messenger = ScaffoldMessenger.maybeOf(navContext);
    }
    if (messenger == null && mounted) {
      messenger = ScaffoldMessenger.maybeOf(context);
    }
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Start continuous looping sound and vibration alert (single source audio)
    AlertSoundUtil.triggerIncomingAlert();

    // Listen to relief request status to auto-dismiss if another crew accepts or it cancels
    _listenToReliefDoc();
  }

  void _listenToReliefDoc() {
    if (widget.offer.reliefRequestId.isEmpty) return;
    try {
      if (Firebase.apps.isEmpty) return;
      _reliefDocSub = FirebaseFirestore.instance
          .collection('reliefRequests')
          .doc(widget.offer.reliefRequestId)
          .snapshots()
          .listen((snap) {
        if (!mounted || !snap.exists || _isProcessing) return;
        final data = snap.data();
        if (data == null) return;
        final status = data['status'] as String?;
        final acceptedBy = data['acceptedByUid'] as String?;
        final currentUid = AmbulanceAuthService.currentSessionUid;
        if (status != 'searching') {
          // If our own ambulance accepted it, do NOT dismiss or treat as taken by someone else
          if (status == 'accepted' && acceptedBy != null && acceptedBy == currentUid) {
            return;
          }
          // Relief request is no longer active (taken by another crew, aborted, or expired)
          _handleExternalDismiss(
            status == 'accepted'
                ? 'Another ambulance accepted'
                : 'Relief request is no longer active',
          );
        }
      });
    } catch (e) {
      debugPrint('[ReliefAlert] Firestore listener notice: $e');
    }
  }

  void _handleExternalDismiss(String message) {
    if (!mounted || _isProcessing) return;
    AlertSoundUtil.stopAlert();
    AlarmNotificationService.instance
        .cancelReliefAlarmNotification(widget.offer.reliefRequestId);
    _showSafeSnackBar(message);
    ref.read(activeReliefOfferProvider.notifier).clear();
    widget.onDismiss?.call();
  }

  @override
  void dispose() {
    _reliefDocSub?.cancel();
    // Stop siren loop and cancel system notification
    AlertSoundUtil.stopAlert();
    AlarmNotificationService.instance
        .cancelReliefAlarmNotification(widget.offer.reliefRequestId);
    super.dispose();
  }

  void _handleTimeout() {
    if (!mounted || _isProcessing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isProcessing) return;
      AlertSoundUtil.stopAlert();
      AlarmNotificationService.instance
          .cancelReliefAlarmNotification(widget.offer.reliefRequestId);
      _showSafeSnackBar('Relief offer window expired.');
      ref.read(activeReliefOfferProvider.notifier).clear();
      widget.onDismiss?.call();
    });
  }

  Future<void> _handleAccept() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    // Cancel Firestore listener immediately so our own update doesn't race against us!
    await _reliefDocSub?.cancel();
    _reliefDocSub = null;

    final reliefService = ref.read(reliefServiceProvider);
    final reliefRequestId = widget.offer.reliefRequestId;

    try {
      final result = await reliefService.respondToReliefRequest(
        reliefRequestId: reliefRequestId,
        action: 'accept',
      );

      await AlertSoundUtil.stopAlert();
      await AlarmNotificationService.instance
          .cancelReliefAlarmNotification(reliefRequestId);

      if (result.isAlreadyTaken) {
        _showSafeSnackBar('Another ambulance accepted');
        ref.read(activeReliefOfferProvider.notifier).clear();
        widget.onDismiss?.call();
      } else if (result.success) {
        _showSafeSnackBar(
          '✓ RELIEF ACCEPTED! Routing to disabled colleague.',
          backgroundColor: AppColors.success,
        );
        ref.read(activeReliefOfferProvider.notifier).clear();
        widget.onDismiss?.call();

        // Navigate directly via appRouter so widget unmounting cannot cancel route transition
        appRouter.go('/crew/relief_nav?reliefRequestId=$reliefRequestId');
      } else {
        _showSafeSnackBar(
          result.message.isNotEmpty
              ? result.message
              : 'Unable to accept relief request.',
          backgroundColor: AppColors.danger,
        );
        ref.read(activeReliefOfferProvider.notifier).clear();
        widget.onDismiss?.call();
      }
    } catch (e) {
      debugPrint('[ReliefAlertScreen] Error accepting relief: $e');
      _showSafeSnackBar(
        'Error accepting relief: $e',
        backgroundColor: AppColors.danger,
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showRejectReasonSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
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
                        'Decline Relief Request',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Select a reason for declining. Offer will cascade immediately to the next closest ambulance.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  // Radio group: avoid deprecated groupValue/onChanged API by
                  // wrapping in RadioGroup<String> (introduced Flutter 3.32).
                  RadioGroup<String>(
                    groupValue: _selectedRejectReason,
                    onChanged: (val) {
                      if (val != null) setSheetState(() => _selectedRejectReason = val);
                    },
                    child: Column(
                      children: [
                        RadioListTile<String>(
                          title: const Text('Too far',
                              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                          value: 'too_far',
                          activeColor: AppColors.danger,
                        ),
                        RadioListTile<String>(
                          title: const Text('Starting a trip',
                              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                          value: 'starting_trip',
                          activeColor: AppColors.danger,
                        ),
                        RadioListTile<String>(
                          title: const Text('Crew unavailable',
                              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                          value: 'crew_unavailable',
                          activeColor: AppColors.danger,
                        ),
                        RadioListTile<String>(
                          title: const Text('Vehicle issue',
                              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                          value: 'vehicle_issue',
                          activeColor: AppColors.danger,
                        ),
                      ],
                    ),
                  ),

                  ElevatedButton(
                    onPressed: _isProcessing
                        ? null
                        : () async {
                            Navigator.pop(sheetCtx);
                            await _handleReject();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Confirm Decline',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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

  Future<void> _handleReject() async {
    setState(() => _isProcessing = true);
    await _reliefDocSub?.cancel();
    _reliefDocSub = null;
    final reliefService = ref.read(reliefServiceProvider);

    try {
      await AlertSoundUtil.stopAlert();
      await AlarmNotificationService.instance
          .cancelReliefAlarmNotification(widget.offer.reliefRequestId);

      await reliefService.respondToReliefRequest(
        reliefRequestId: widget.offer.reliefRequestId,
        action: 'reject',
        reason: _selectedRejectReason,
      );

      _showSafeSnackBar('Relief request declined.');
      ref.read(activeReliefOfferProvider.notifier).clear();
      widget.onDismiss?.call();
    } catch (e) {
      debugPrint('[ReliefAlert] Error rejecting relief request: $e');
      ref.read(activeReliefOfferProvider.notifier).clear();
      widget.onDismiss?.call();
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase().trim()) {
      case 'critical':
        return AppColors.danger;
      case 'serious':
        return const Color(0xFFD97706);
      case 'stable':
      default:
        return const Color(0xFF1E9E5A);
    }
  }

  @override
  Widget build(BuildContext context) {
    final severityColor = _getSeverityColor(widget.offer.severity);

    return Scaffold(
      backgroundColor: const Color(0xFF111827), // Dark high-urgency aesthetic
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Urgency Badge & Pulsing Indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.danger),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'URGENT BACKUP DISPATCH',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Title
              const Text(
                'Colleague ambulance needs help',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 8),

              // Reason Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF374151)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.build_circle_outlined,
                        color: Color(0xFF9CA3AF), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      widget.offer.formattedReason,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Synchronized 60-second Countdown Ring
              CountdownRing(
                offerExpiresAt: widget.offer.offerExpiresAt,
                totalDurationSeconds: 60,
                onExpired: _handleTimeout,
                isDarkTheme: true,
              ),
              const SizedBox(height: 20),

              // Stat Grid Cards: Distance, ETA, Severity, AIS-125 Tier
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF374151)),
                ),
                child: Column(
                  children: [
                    // Row 1: Distance & ETA
                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoItem(
                            icon: Icons.navigation_rounded,
                            iconColor: AppColors.primary,
                            label: 'DISTANCE',
                            value: widget.offer.formattedDistance,
                          ),
                        ),
                        Container(width: 1, height: 40, color: const Color(0xFF374151)),
                        Expanded(
                          child: _buildInfoItem(
                            icon: Icons.timer_outlined,
                            iconColor: const Color(0xFFF59E0B),
                            label: 'ESTIMATED ETA',
                            value: widget.offer.formattedEta,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24, color: Color(0xFF374151)),

                    // Row 2: Severity Chip & Homologation Tier Chip
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'PATIENT SEVERITY',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF9CA3AF),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: severityColor.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: severityColor),
                                ),
                                child: Text(
                                  widget.offer.severity.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: severityColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'DISABLED VEHICLE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF9CA3AF),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.offer.formattedTier,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Action Buttons: ACCEPT (Green) & REJECT
              Row(
                children: [
                  // REJECT Button
                  Expanded(
                    flex: 4,
                    child: OutlinedButton(
                      onPressed: _isProcessing ? null : _showRejectReasonSheet,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger, width: 1.5),
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'DECLINE',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // ACCEPT Button (Green)
                  Expanded(
                    flex: 6,
                    child: ElevatedButton(
                      onPressed: _isProcessing ? null : _handleAccept,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E9E5A), // Clinical Green
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(56),
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isProcessing
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.check_circle_rounded, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'ACCEPT RELIEF',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Color(0xFF9CA3AF),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
