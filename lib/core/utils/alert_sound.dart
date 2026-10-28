import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../services/alarm_notification_service.dart';

/// Centralized Controller for Nurse Emergency Alert Siren & Vibration.
/// Controls both in-app siren audio looping, repeating vibration pattern,
/// and silences system notification channel sound to prevent double-siren echo.
class AlertSoundUtil {
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static Timer? _vibrationLoopTimer;
  static bool _isPlaying = false;
  static bool _isPaused = false;
  static bool enableAudio = true;
  static String? _activeRequestId;

  static bool get isPlaying => _isPlaying;
  static bool get isPaused => _isPaused;

  /// Starts or restarts the continuous looping siren audio & vibration.
  /// If [requestId] is provided, silences the system notification tray sound
  /// so only this controller produces alert audio.
  static Future<void> triggerIncomingAlert([String? requestId]) async {
    if (!enableAudio) return;
    if (_isPlaying) return;

    _activeRequestId = requestId ?? _activeRequestId;
    _isPlaying = true;
    _isPaused = false;

    // Silence background/system notification to prevent double siren
    if (_activeRequestId != null) {
      try {
        await AlarmNotificationService.instance
            .dismissNotificationTrayItem(_activeRequestId!);
      } catch (_) {}
    }

    try {
      // 1. Audio looping
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      try {
        await _audioPlayer.play(AssetSource('audio/siren.mp3'));
      } catch (assetErr) {
        debugPrint('[AlertSoundUtil] Fallback to remote siren URL: $assetErr');
        await _audioPlayer.play(
          UrlSource('https://assets.mixkit.co/active_storage/sfx/2869/2869-preview.mp3'),
        );
      }

      // 2. Vibration looping
      await _startVibrationLoop();
    } catch (e) {
      debugPrint('[AlertSoundUtil] Error triggering incoming alert loop: $e');
    }
  }

  /// Pauses the in-app siren and vibration immediately (e.g. while voice note plays).
  static Future<void> pauseAlert() async {
    if (!enableAudio) return;
    if (!_isPlaying && !_isPaused) return;

    _isPlaying = false;
    _isPaused = true;

    // Stop vibration loop immediately
    _vibrationLoopTimer?.cancel();
    _vibrationLoopTimer = null;

    try {
      await _audioPlayer.pause();
      await Vibration.cancel();
    } catch (e) {
      debugPrint('[AlertSoundUtil] Error pausing alert: $e');
    }
  }

  /// Resumes the in-app siren and vibration, but ONLY if [isOfferActive] is true.
  static Future<void> resumeAlert({required bool isOfferActive}) async {
    if (!_isPaused || !isOfferActive || !enableAudio) {
      return;
    }

    _isPaused = false;
    _isPlaying = true;

    try {
      await _audioPlayer.resume();
      await _startVibrationLoop();
    } catch (e) {
      debugPrint('[AlertSoundUtil] Error resuming alert: $e');
      // If resume fails, attempt full replay
      try {
        await _audioPlayer.play(AssetSource('audio/siren.mp3'));
        await _startVibrationLoop();
      } catch (_) {}
    }
  }

  /// Permanently stops the in-app siren, cancels vibration, and clears all state.
  static Future<void> stopAlert() async {
    _isPlaying = false;
    _isPaused = false;
    _activeRequestId = null;
    _vibrationLoopTimer?.cancel();
    _vibrationLoopTimer = null;

    if (!enableAudio) return;

    try {
      await _audioPlayer.stop();
      await Vibration.cancel();
    } catch (e) {
      debugPrint('[AlertSoundUtil] Error stopping alert: $e');
    }
  }

  static Future<void> _startVibrationLoop() async {
    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      Vibration.vibrate(pattern: [500, 1000, 500, 1000]);

      _vibrationLoopTimer?.cancel();
      _vibrationLoopTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
        if (!_isPlaying || _isPaused) return;
        try {
          Vibration.vibrate(pattern: [500, 1000, 500, 1000]);
        } catch (e) {
          debugPrint('[AlertSoundUtil] Vibration loop error: $e');
        }
      });
    }
  }
}
