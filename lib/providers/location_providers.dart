import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../services/fcm_service.dart';
import '../services/live_location_service.dart';
import '../services/location_service.dart';
import '../services/routing_service.dart';
import '../services/ranking_service.dart';

final fcmServiceProvider = Provider<FcmService>((ref) {
  final service = FcmService();
  ref.onDispose(() => service.dispose());
  return service;
});

final liveLocationServiceProvider = Provider<LiveLocationService>((ref) {
  final service = LiveLocationService();
  ref.onDispose(() => service.dispose());
  return service;
});

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

final routingServiceProvider = Provider<RoutingService>((ref) {
  return RoutingService();
});

final rankingServiceProvider = Provider<RankingService>((ref) {
  final routingService = ref.watch(routingServiceProvider);
  return RankingService(routingService: routingService);
});

class LocationNotifier extends Notifier<LocationResult> {
  @override
  LocationResult build() {
    return const LocationResult(
      latitude: AppConstants.defaultLat,
      longitude: AppConstants.defaultLng,
      isGps: false,
    );
  }

  void updateLocation(double lat, double lng, {bool isGps = false}) {
    state = LocationResult(latitude: lat, longitude: lng, isGps: isGps);
  }
}

final currentLocationProvider =
    NotifierProvider<LocationNotifier, LocationResult>(LocationNotifier.new);

class RequestDraft {
  final List<String> needs;
  final String severity;
  final String note;
  final String? voiceNotePath;
  final int voiceNoteDurationSec;
  final int voiceNoteSizeBytes;

  const RequestDraft({
    required this.needs,
    required this.severity,
    required this.note,
    this.voiceNotePath,
    this.voiceNoteDurationSec = 0,
    this.voiceNoteSizeBytes = 0,
  });

  bool get hasVoiceNote => voiceNotePath != null && voiceNotePath!.isNotEmpty;

  RequestDraft copyWith({
    List<String>? needs,
    String? severity,
    String? note,
    String? voiceNotePath,
    int? voiceNoteDurationSec,
    int? voiceNoteSizeBytes,
    bool clearVoiceNote = false,
  }) {
    return RequestDraft(
      needs: needs ?? this.needs,
      severity: severity ?? this.severity,
      note: note ?? this.note,
      voiceNotePath: clearVoiceNote ? null : (voiceNotePath ?? this.voiceNotePath),
      voiceNoteDurationSec:
          clearVoiceNote ? 0 : (voiceNoteDurationSec ?? this.voiceNoteDurationSec),
      voiceNoteSizeBytes:
          clearVoiceNote ? 0 : (voiceNoteSizeBytes ?? this.voiceNoteSizeBytes),
    );
  }
}

class RequestDraftNotifier extends Notifier<RequestDraft> {
  @override
  RequestDraft build() {
    return const RequestDraft(
      needs: ['ICU'],
      severity: 'serious',
      note: '',
    );
  }

  void setNeeds(List<String> needs) {
    state = state.copyWith(needs: needs);
  }

  void toggleNeed(String need) {
    final current = List<String>.from(state.needs);
    if (current.contains(need)) {
      if (current.length > 1) current.remove(need);
    } else {
      current.add(need);
    }
    state = state.copyWith(needs: current);
  }

  void setSeverity(String severity) {
    state = state.copyWith(severity: severity);
  }

  void setNote(String note) {
    state = state.copyWith(note: note);
  }

  void setVoiceNote({
    required String? path,
    required int durationSec,
    required int sizeBytes,
  }) {
    state = state.copyWith(
      voiceNotePath: path,
      voiceNoteDurationSec: durationSec,
      voiceNoteSizeBytes: sizeBytes,
    );
  }

  void clearVoiceNote() {
    state = state.copyWith(clearVoiceNote: true);
  }

  void reset() {
    state = const RequestDraft(
      needs: ['ICU'],
      severity: 'serious',
      note: '',
    );
  }
}

final requestDraftProvider =
    NotifierProvider<RequestDraftNotifier, RequestDraft>(
        RequestDraftNotifier.new);

