import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../core/utils/alert_sound.dart';
import '../providers/voice_note_providers.dart';

enum VoiceNoteLoadStatus {
  initial,
  loading,
  ready,
  error,
  expired,
}

class VoiceNotePlaybackController extends ChangeNotifier {
  final VoiceNoteClient voiceNoteClient;
  final String requestId;
  final int durationSec;

  late final AudioPlayer _player;
  VoiceNoteLoadStatus _loadStatus = VoiceNoteLoadStatus.initial;
  String? _errorMessage;
  String? _cachedFilePath;

  // Playback state
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;

  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;

  // Callback to check whether offer is still active when playback stops
  bool Function()? isOfferActiveChecker;

  VoiceNoteLoadStatus get loadStatus => _loadStatus;
  String? get errorMessage => _errorMessage;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get totalDuration =>
      _totalDuration.inSeconds > 0 ? _totalDuration : Duration(seconds: durationSec);
  String? get cachedFilePath => _cachedFilePath;

  VoiceNotePlaybackController({
    required this.voiceNoteClient,
    required this.requestId,
    this.durationSec = 0,
    this.isOfferActiveChecker,
  }) {
    _player = AudioPlayer();
    _totalDuration = Duration(seconds: durationSec);
    _configureAudioContext();
    _initListeners();
    prefetch();
  }

  Future<void> _configureAudioContext() async {
    try {
      await _player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.speech,
            usageType: AndroidUsageType.assistanceAccessibility,
            audioFocus: AndroidAudioFocus.gainTransient,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {
              AVAudioSessionOptions.defaultToSpeaker,
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('[VoiceNotePlayback] AudioContext config error: $e');
    }
  }

  void _initListeners() {
    _playerStateSub = _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      notifyListeners();

      if (state == PlayerState.completed) {
        _position = Duration.zero;
        _isPlaying = false;
        notifyListeners();
        _resumeSirenIfOfferActive();
      }
    });

    _positionSub = _player.onPositionChanged.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    _durationSub = _player.onDurationChanged.listen((dur) {
      if (dur.inSeconds > 0) {
        _totalDuration = dur;
        notifyListeners();
      }
    });
  }

  /// Low-latency prefetch: Obtains signed URL and downloads audio to local cache.
  Future<void> prefetch() async {
    if (_loadStatus == VoiceNoteLoadStatus.loading) return;

    _loadStatus = VoiceNoteLoadStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final tempDir = await getTemporaryDirectory();
      final cacheFile = File('${tempDir.path}/cached_vn_$requestId.m4a');

      // Check if already cached locally
      if (await cacheFile.exists() && await cacheFile.length() > 0) {
        _cachedFilePath = cacheFile.path;
        _loadStatus = VoiceNoteLoadStatus.ready;
        notifyListeners();
        return;
      }

      // Fetch signed URL from Cloud Function callable
      final result = await voiceNoteClient.getVoiceNoteUrl(requestId);
      if (result.url.isEmpty) {
        _loadStatus = VoiceNoteLoadStatus.expired;
        _errorMessage = 'Voice note expired or not available.';
        notifyListeners();
        return;
      }

      // Download audio bytes
      final response = await http.get(Uri.parse(result.url));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        await cacheFile.writeAsBytes(response.bodyBytes);
        _cachedFilePath = cacheFile.path;
        _loadStatus = VoiceNoteLoadStatus.ready;
      } else {
        _loadStatus = VoiceNoteLoadStatus.error;
        _errorMessage = 'Could not download audio (HTTP ${response.statusCode})';
      }
    } catch (e) {
      debugPrint('[VoiceNotePlayback] Prefetch error: $e');
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('not-found') || errStr.contains('completed') || errStr.contains('expired')) {
        _loadStatus = VoiceNoteLoadStatus.expired;
        _errorMessage = 'Voice note expired';
      } else {
        _loadStatus = VoiceNoteLoadStatus.error;
        _errorMessage = 'Failed to load voice note. Tap to retry.';
      }
    }
    notifyListeners();
  }

  /// Starts playback, pausing siren audio and vibration.
  Future<void> play() async {
    if (_loadStatus != VoiceNoteLoadStatus.ready || _cachedFilePath == null) {
      return;
    }

    try {
      // 1. Pause siren and vibration
      await AlertSoundUtil.pauseAlert();

      // 2. Play local audio
      await _player.play(DeviceFileSource(_cachedFilePath!));
      _isPlaying = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[VoiceNotePlayback] Play error: $e');
      _resumeSirenIfOfferActive();
    }
  }

  /// Pauses playback and resumes siren audio and vibration if offer is active.
  Future<void> pause() async {
    try {
      await _player.pause();
      _isPlaying = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[VoiceNotePlayback] Pause error: $e');
    }
    _resumeSirenIfOfferActive();
  }

  /// Toggles between play and pause.
  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  /// Seeks to a specific position.
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// Completely stops playback and releases audio focus.
  Future<void> stop() async {
    try {
      await _player.stop();
      _isPlaying = false;
      _position = Duration.zero;
      notifyListeners();
    } catch (_) {}
    _resumeSirenIfOfferActive();
  }

  void _resumeSirenIfOfferActive() {
    final isOfferActive = isOfferActiveChecker?.call() ?? true;
    AlertSoundUtil.resumeAlert(isOfferActive: isOfferActive);
  }

  @override
  void dispose() {
    _resumeSirenIfOfferActive();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}
