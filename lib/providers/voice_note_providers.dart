import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class VoiceNoteUrlResult {
  final String url;
  final int durationSec;
  final int sizeBytes;
  final String storagePath;

  const VoiceNoteUrlResult({
    required this.url,
    required this.durationSec,
    required this.sizeBytes,
    required this.storagePath,
  });

  factory VoiceNoteUrlResult.fromJson(Map<String, dynamic> json) {
    return VoiceNoteUrlResult(
      url: json['url'] as String? ?? '',
      durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      storagePath: json['storagePath'] as String? ?? '',
    );
  }
}

final voiceNoteClientProvider = Provider<VoiceNoteClient>((ref) {
  return VoiceNoteClient(functions: FirebaseFunctions.instance);
});

class VoiceNoteClient {
  final FirebaseFunctions _functions;

  VoiceNoteClient({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  /// Invokes getVoiceNoteUrl callable to obtain a 10-minute signed playback URL.
  Future<VoiceNoteUrlResult> getVoiceNoteUrl(String requestId) async {
    final callable = _functions.httpsCallable('getVoiceNoteUrl');
    final result = await callable.call<Map<String, dynamic>>({
      'requestId': requestId,
    });
    return VoiceNoteUrlResult.fromJson(Map<String, dynamic>.from(result.data));
  }
}
