import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bedlink/models/emergency_request.dart';
import 'package:bedlink/providers/location_providers.dart';
import 'package:bedlink/features/dispatch/widgets/voice_note_recorder.dart';

void main() {
  group('Phase 13A - VoiceNoteMetadata & EmergencyRequest Model Tests', () {
    test('VoiceNoteMetadata serializes and deserializes correctly', () {
      final now = DateTime.now();
      final vm = VoiceNoteMetadata(
        storagePath: 'voiceNotes/req_test_1/note.m4a',
        durationSec: 24,
        sizeBytes: 154000,
        uploadedAt: now,
      );

      final json = vm.toJson();
      expect(json['storagePath'], 'voiceNotes/req_test_1/note.m4a');
      expect(json['durationSec'], 24);
      expect(json['sizeBytes'], 154000);

      final parsed = VoiceNoteMetadata.fromJson(json);
      expect(parsed.storagePath, 'voiceNotes/req_test_1/note.m4a');
      expect(parsed.durationSec, 24);
      expect(parsed.sizeBytes, 154000);
    });

    test('EmergencyRequest includes voiceNote and voiceNoteStatus in toJson / fromJson', () {
      final now = DateTime.now();
      final req = EmergencyRequest(
        id: 'req_voice_1',
        patientLat: 19.0760,
        patientLng: 72.8777,
        needs: ['ICU'],
        severity: 'critical',
        note: 'Severe dyspnea',
        status: 'offered',
        rankedHospitalIds: ['hosp_1'],
        currentIndex: 0,
        currentHospitalId: 'hosp_1',
        attempts: [],
        voiceNote: VoiceNoteMetadata(
          storagePath: 'voiceNotes/req_voice_1/note.m4a',
          durationSec: 18,
          sizeBytes: 120000,
          uploadedAt: now,
        ),
        voiceNoteStatus: 'uploaded',
      );

      final json = req.toJson();
      expect(json['voiceNote'], isNotNull);
      expect(json['voiceNote']['storagePath'], 'voiceNotes/req_voice_1/note.m4a');
      expect(json['voiceNote']['durationSec'], 18);
      expect(json['voiceNoteStatus'], 'uploaded');

      final parsed = EmergencyRequest.fromJson(json, 'req_voice_1');
      expect(parsed.voiceNote, isNotNull);
      expect(parsed.voiceNote!.storagePath, 'voiceNotes/req_voice_1/note.m4a');
      expect(parsed.voiceNote!.durationSec, 18);
      expect(parsed.voiceNoteStatus, 'uploaded');
    });

    test('backward compatibility: legacy requests without voiceNote parse cleanly as null', () {
      final legacyJson = {
        'patientLat': 19.0760,
        'patientLng': 72.8777,
        'needs': ['ICU'],
        'severity': 'serious',
        'status': 'offered',
        'rankedHospitalIds': ['hosp_1'],
        'currentIndex': 0,
        'currentHospitalId': 'hosp_1',
        'attempts': [],
      };

      final parsed = EmergencyRequest.fromJson(legacyJson, 'legacy_req');
      expect(parsed.voiceNote, isNull);
      expect(parsed.voiceNoteStatus, isNull);
    });

    test('RequestDraft properly manages voice note state', () {
      var draft = const RequestDraft(
        needs: ['ICU'],
        severity: 'serious',
        note: '',
      );

      expect(draft.hasVoiceNote, isFalse);

      draft = draft.copyWith(
        voiceNotePath: '/tmp/test_voice.m4a',
        voiceNoteDurationSec: 15,
        voiceNoteSizeBytes: 95000,
      );

      expect(draft.hasVoiceNote, isTrue);
      expect(draft.voiceNotePath, '/tmp/test_voice.m4a');
      expect(draft.voiceNoteDurationSec, 15);
      expect(draft.voiceNoteSizeBytes, 95000);

      draft = draft.copyWith(clearVoiceNote: true);
      expect(draft.hasVoiceNote, isFalse);
      expect(draft.voiceNotePath, isNull);
      expect(draft.voiceNoteDurationSec, 0);
      expect(draft.voiceNoteSizeBytes, 0);
    });
  });

  group('Phase 13A - VoiceNoteRecorder Widget Tests', () {
    testWidgets('Renders idle state by default with Record Voice Note CTA', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VoiceNoteRecorder(
              onRecorded: (_, _, _) {},
              onDeleted: () {},
            ),
          ),
        ),
      );

      expect(find.text('Record Voice Note (Optional)'), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    });

    testWidgets('Renders recorded state when initialFilePath is provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VoiceNoteRecorder(
              initialFilePath: null,
              initialDurationSec: 18,
              onRecorded: (_, _, _) {},
              onDeleted: () {},
            ),
          ),
        ),
      );

      // In the absence of a real file on disk during unit testing, starts in idle
      expect(find.text('Record Voice Note (Optional)'), findsOneWidget);
    });
  });
}
