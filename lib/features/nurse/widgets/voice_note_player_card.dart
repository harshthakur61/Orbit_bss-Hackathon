import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme.dart';
import '../../../models/emergency_request.dart';
import '../../../providers/voice_note_providers.dart';
import '../../../services/voice_note_playback_service.dart';

class VoiceNotePlayerCard extends ConsumerStatefulWidget {
  final String requestId;
  final VoiceNoteMetadata? voiceNote;
  final String? voiceNoteStatus;
  final bool Function()? isOfferActiveChecker;
  final bool isHistoryMode;

  const VoiceNotePlayerCard({
    super.key,
    required this.requestId,
    this.voiceNote,
    this.voiceNoteStatus,
    this.isOfferActiveChecker,
    this.isHistoryMode = false,
  });

  @override
  ConsumerState<VoiceNotePlayerCard> createState() => _VoiceNotePlayerCardState();
}

class _VoiceNotePlayerCardState extends ConsumerState<VoiceNotePlayerCard> {
  VoiceNotePlaybackController? _controller;
  String? _initializedRequestId;

  @override
  void initState() {
    super.initState();
    _checkAndInitController();
  }

  @override
  void didUpdateWidget(covariant VoiceNotePlayerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestId != widget.requestId ||
        oldWidget.voiceNote != widget.voiceNote) {
      _checkAndInitController();
    }
  }

  void _checkAndInitController() {
    if (widget.voiceNote == null) return;
    if (_initializedRequestId == widget.requestId && _controller != null) return;

    _controller?.dispose();
    _initializedRequestId = widget.requestId;

    final client = ref.read(voiceNoteClientProvider);
    _controller = VoiceNotePlaybackController(
      voiceNoteClient: client,
      requestId: widget.requestId,
      durationSec: widget.voiceNote!.durationSec,
      isOfferActiveChecker: widget.isHistoryMode ? () => false : widget.isOfferActiveChecker,
    );
    _controller!.addListener(_onControllerUpdate);
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // 1. If voice note is null and not arriving -> show nothing
    if (widget.voiceNote == null) {
      if (widget.voiceNoteStatus == 'arriving') {
        return _buildArrivingCard();
      }
      return const SizedBox.shrink();
    }

    // 2. Controller is available
    final ctrl = _controller;
    if (ctrl == null) {
      return _buildArrivingCard();
    }

    // 3. Handle load status
    switch (ctrl.loadStatus) {
      case VoiceNoteLoadStatus.initial:
      case VoiceNoteLoadStatus.loading:
        return _buildLoadingCard();

      case VoiceNoteLoadStatus.error:
        return _buildErrorCard(ctrl);

      case VoiceNoteLoadStatus.expired:
        return _buildExpiredCard();

      case VoiceNoteLoadStatus.ready:
        return _buildPlayerCard(ctrl);
    }
  }

  Widget _buildArrivingCard() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.infoTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.4)),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.info),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Voice note arriving from ambulance...',
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingCard() {
    final durSec = widget.voiceNote?.durationSec ?? 0;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Text(
            'Loading voice note (${_formatTime(durSec)})...',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(VoiceNotePlaybackController ctrl) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningText.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warningText.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.warningText, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ctrl.errorMessage ?? 'Could not load audio file.',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => ctrl.prefetch(),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpiredCard() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: const Row(
        children: [
          Icon(Icons.history_toggle_off_rounded, color: AppColors.textSecondary, size: 18),
          SizedBox(width: 8),
          Text(
            'Voice note expired (deleted per 3-day retention policy)',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerCard(VoiceNotePlaybackController ctrl) {
    final curSec = ctrl.position.inSeconds;
    final totSec = ctrl.totalDuration.inSeconds > 0
        ? ctrl.totalDuration.inSeconds
        : (widget.voiceNote?.durationSec ?? 0);

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ctrl.isPlaying ? AppColors.primary : AppColors.primary.withValues(alpha: 0.35),
          width: ctrl.isPlaying ? 2.0 : 1.2,
        ),
        boxShadow: ctrl.isPlaying
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.mic_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Voice note from paramedic (${_formatTime(totSec)})',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ctrl.isPlaying
                          ? 'Playing on loud speaker'
                          : 'Recorded clinical audio handover',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Player Slider & Large Play/Pause Button
          Row(
            children: [
              Material(
                color: AppColors.primary,
                shape: const CircleBorder(),
                elevation: 2,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => ctrl.togglePlayPause(),
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Icon(
                      ctrl.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Progress Bar
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    activeTrackColor: AppColors.primary,
                    thumbColor: AppColors.primary,
                    inactiveTrackColor: AppColors.primary.withValues(alpha: 0.2),
                  ),
                  child: Slider(
                    value: ctrl.position.inMilliseconds
                        .toDouble()
                        .clamp(0.0, ctrl.totalDuration.inMilliseconds.toDouble()),
                    min: 0.0,
                    max: ctrl.totalDuration.inMilliseconds > 0
                        ? ctrl.totalDuration.inMilliseconds.toDouble()
                        : 1.0,
                    onChanged: (val) {
                      ctrl.seek(Duration(milliseconds: val.toInt()));
                    },
                  ),
                ),
              ),
              const SizedBox(width: 6),

              Text(
                '${_formatTime(curSec)} / ${_formatTime(totSec)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),

          // Siren Paused Caption
          if (ctrl.isPlaying && !widget.isHistoryMode) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.volume_off_rounded,
                  size: 14,
                  color: AppColors.warningText.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 6),
                Text(
                  'Siren paused while the voice note plays',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                    color: AppColors.warningText.withValues(alpha: 0.95),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
