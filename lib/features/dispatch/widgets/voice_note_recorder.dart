import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/theme.dart';

enum RecorderState { idle, recording, recorded }

class VoiceNoteRecorder extends StatefulWidget {
  final String? initialFilePath;
  final int initialDurationSec;
  final void Function(String filePath, int durationSec, int sizeBytes) onRecorded;
  final VoidCallback onDeleted;

  const VoiceNoteRecorder({
    super.key,
    this.initialFilePath,
    this.initialDurationSec = 0,
    required this.onRecorded,
    required this.onDeleted,
  });

  @override
  State<VoiceNoteRecorder> createState() => _VoiceNoteRecorderState();
}

class _VoiceNoteRecorderState extends State<VoiceNoteRecorder>
    with SingleTickerProviderStateMixin {
  late final AudioRecorder _audioRecorder;
  late final AudioPlayer _audioPlayer;

  RecorderState _state = RecorderState.idle;
  String? _recordedFilePath;
  int _durationSec = 0;
  int _fileSizeBytes = 0;

  // Recording timer & amplitude
  Timer? _recordTimer;
  int _recordSeconds = 0;
  static const int _maxRecordSeconds = 60;
  double _currentAmplitude = -40.0;
  StreamSubscription<Amplitude>? _amplitudeSub;

  // Playback state
  bool _isPlaying = false;
  Duration _playbackPosition = Duration.zero;
  Duration _playbackTotal = Duration.zero;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    _audioPlayer = AudioPlayer();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    // Initial state setup
    if (widget.initialFilePath != null &&
        File(widget.initialFilePath!).existsSync()) {
      _state = RecorderState.recorded;
      _recordedFilePath = widget.initialFilePath;
      _durationSec = widget.initialDurationSec;
      _playbackTotal = Duration(seconds: widget.initialDurationSec);
      _fileSizeBytes = File(widget.initialFilePath!).lengthSync();
    }

    _initAudioListeners();
  }

  void _initAudioListeners() {
    _playerStateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
          if (state == PlayerState.completed) {
            _playbackPosition = Duration.zero;
          }
        });
      }
    });

    _positionSub = _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted) {
        setState(() {
          _playbackPosition = pos;
        });
      }
    });

    _durationSub = _audioPlayer.onDurationChanged.listen((dur) {
      if (mounted) {
        setState(() {
          _playbackTotal = dur;
        });
      }
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _amplitudeSub?.cancel();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _pulseController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    // 1. Check & request permission
    final micStatus = await Permission.microphone.request();
    if (micStatus.isDenied || micStatus.isPermanentlyDenied) {
      if (mounted) {
        _showPermissionDeniedDialog();
      }
      return;
    }

    final hasPerm = await _audioRecorder.hasPermission();
    if (!hasPerm) {
      if (mounted) {
        _showPermissionDeniedDialog();
      }
      return;
    }

    // 2. Prepare file destination
    final tempDir = await getTemporaryDirectory();
    final fileName = 'voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final targetPath = '${tempDir.path}/$fileName';

    // Stop preview playback if active
    if (_isPlaying) {
      await _audioPlayer.stop();
    }

    // 3. Configure recorder: AAC-LC, mono, 16 kHz, ~48 kbps target
    const config = RecordConfig(
      encoder: AudioEncoder.aacLc,
      sampleRate: 16000,
      bitRate: 48000,
      numChannels: 1,
    );

    try {
      await _audioRecorder.start(config, path: targetPath);

      if (mounted) {
        setState(() {
          _state = RecorderState.recording;
          _recordSeconds = 0;
          _currentAmplitude = -40.0;
        });
      }

      // 4. Start timer & 60-second limit
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {
          _recordSeconds++;
        });

        if (_recordSeconds >= _maxRecordSeconds) {
          _stopRecording();
        }
      });

      // 5. Amplitude stream for dynamic level indicator
      _amplitudeSub = _audioRecorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amp) {
        if (mounted) {
          setState(() {
            _currentAmplitude = amp.current;
          });
        }
      });
    } catch (e) {
      debugPrint('[VoiceRecorder] Start error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start recording: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    _amplitudeSub?.cancel();

    try {
      final path = await _audioRecorder.stop();
      if (path != null && mounted) {
        final file = File(path);
        final sizeBytes = file.existsSync() ? file.lengthSync() : 0;
        final durationSec = _recordSeconds == 0 ? 1 : _recordSeconds;

        setState(() {
          _state = RecorderState.recorded;
          _recordedFilePath = path;
          _durationSec = durationSec;
          _fileSizeBytes = sizeBytes;
          _playbackTotal = Duration(seconds: durationSec);
          _playbackPosition = Duration.zero;
        });

        widget.onRecorded(path, durationSec, sizeBytes);
      }
    } catch (e) {
      debugPrint('[VoiceRecorder] Stop error: $e');
    }
  }

  Future<void> _togglePlayPreview() async {
    if (_recordedFilePath == null) return;

    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play(DeviceFileSource(_recordedFilePath!));
    }
  }

  Future<void> _deleteRecording() async {
    if (_isPlaying) {
      await _audioPlayer.stop();
    }

    if (_recordedFilePath != null) {
      try {
        final f = File(_recordedFilePath!);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }

    setState(() {
      _state = RecorderState.idle;
      _recordedFilePath = null;
      _durationSec = 0;
      _fileSizeBytes = 0;
      _playbackPosition = Duration.zero;
      _playbackTotal = Duration.zero;
      _recordSeconds = 0;
    });

    widget.onDeleted();
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.mic_off_rounded, color: AppColors.danger),
            SizedBox(width: 8),
            Text('Microphone Permission Needed'),
          ],
        ),
        content: const Text(
          'BedLink needs microphone access so ambulance crews can record clinical audio notes for destination hospital nurses.\n\nPlease enable microphone permissions in App Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  String _formatTime(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case RecorderState.idle:
        return _buildIdleState();
      case RecorderState.recording:
        return _buildRecordingState();
      case RecorderState.recorded:
        return _buildRecordedState();
    }
  }

  Widget _buildIdleState() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.25),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Material(
            color: AppColors.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _startRecording,
              child: const Padding(
                padding: EdgeInsets.all(12.0),
                child: Icon(Icons.mic_rounded, color: Colors.white, size: 24),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Record Voice Note (Optional)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Up to 60s • Transmitted to hospital nurse station',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingState() {
    final progress = _recordSeconds / _maxRecordSeconds;
    // Map decibel amplitude (-60 to 0 dB) to normalized 0.0 - 1.0 range
    final normAmp = ((_currentAmplitude + 60.0) / 60.0).clamp(0.1, 1.0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.danger.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FadeTransition(
                opacity: _pulseController,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: AppColors.danger,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'RECORDING CLINICAL NOTE',
                style: TextStyle(
                  color: AppColors.danger,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              Text(
                '${_formatTime(_recordSeconds)} / ${_formatTime(_maxRecordSeconds)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Audio Level Waveform Indicator
          SizedBox(
            height: 28,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(24, (i) {
                // Pseudo wave heights driven by microphone amplitude
                final offset = ((i - 12).abs() / 12.0);
                final barHeight = (28 * normAmp * (1.0 - (offset * 0.4))).clamp(4.0, 26.0);
                return Container(
                  width: 4,
                  height: barHeight,
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 10),

          // Linear progress towards 60s auto-stop
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: Colors.grey.shade300,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.danger),
            ),
          ),
          const SizedBox(height: 12),

          // Stop Button
          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _stopRecording,
              icon: const Icon(Icons.stop_rounded, size: 22),
              label: const Text('Stop & Review Voice Note'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordedState() {
    final curSec = _playbackPosition.inSeconds;
    final totSec = _playbackTotal.inSeconds > 0 ? _playbackTotal.inSeconds : _durationSec;
    final sizeKb = (_fileSizeBytes / 1024).round();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
              const SizedBox(width: 6),
              const Text(
                'Voice Note Recorded',
                style: TextStyle(
                  color: AppColors.success,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${_formatTime(totSec)} • ${sizeKb}KB (AAC)',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Audio Player Controls & Slider
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                  color: AppColors.primary,
                  size: 38,
                ),
                onPressed: _togglePlayPreview,
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: _playbackPosition.inMilliseconds
                        .toDouble()
                        .clamp(0.0, _playbackTotal.inMilliseconds.toDouble()),
                    min: 0.0,
                    max: _playbackTotal.inMilliseconds > 0
                        ? _playbackTotal.inMilliseconds.toDouble()
                        : 1.0,
                    activeColor: AppColors.primary,
                    inactiveColor: AppColors.primary.withValues(alpha: 0.2),
                    onChanged: (val) {
                      _audioPlayer.seek(Duration(milliseconds: val.toInt()));
                    },
                  ),
                ),
              ),
              Text(
                _formatTime(curSec),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Re-record
              TextButton.icon(
                onPressed: _startRecording,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Re-record', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
              const SizedBox(width: 8),

              // Delete
              TextButton.icon(
                onPressed: _deleteRecording,
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('Delete', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
