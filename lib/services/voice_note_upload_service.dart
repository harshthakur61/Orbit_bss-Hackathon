import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/emergency_request.dart';

final voiceNoteUploadServiceProvider = Provider<VoiceNoteUploadService>((ref) {
  return VoiceNoteUploadService(
    storage: FirebaseStorage.instance,
    firestore: FirebaseFirestore.instance,
  );
});

class VoiceNoteUploadService {
  final FirebaseStorage _storage;
  final FirebaseFirestore _firestore;

  VoiceNoteUploadService({
    FirebaseStorage? storage,
    FirebaseFirestore? firestore,
  })  : _storage = storage ?? FirebaseStorage.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  /// Uploads a voice note for [requestId] with a bounded wait time (default 10s).
  ///
  /// If the upload finishes within [timeoutDuration], returns the [VoiceNoteMetadata]
  /// so it can be committed synchronously during request creation.
  ///
  /// If the upload exceeds [timeoutDuration], it completes asynchronously in the
  /// background, writing the metadata directly to `requests/{requestId}` when done,
  /// without blocking emergency creation.
  Future<VoiceNoteMetadata?> uploadVoiceNoteWithTimeout({
    required String requestId,
    required String filePath,
    required int durationSec,
    required int sizeBytes,
    Duration timeoutDuration = const Duration(seconds: 10),
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('[VoiceNoteUpload] Local file not found: $filePath');
      return null;
    }

    final storagePath = 'voiceNotes/$requestId/note.m4a';
    final storageRef = _storage.ref().child(storagePath);

    final metadata = SettableMetadata(
      contentType: 'audio/m4a',
      customMetadata: {
        'durationSec': durationSec.toString(),
        'sizeBytes': sizeBytes.toString(),
        'uploadedAt': DateTime.now().toIso8601String(),
      },
    );

    // Start upload task
    final uploadTask = storageRef.putFile(file, metadata);

    try {
      // Bounded wait up to 10s
      await uploadTask.timeout(timeoutDuration);

      final voiceMetadata = VoiceNoteMetadata(
        storagePath: storagePath,
        durationSec: durationSec,
        sizeBytes: sizeBytes,
        uploadedAt: DateTime.now(),
      );

      // Clean up local temp file
      _cleanupFile(file);

      return voiceMetadata;
    } on TimeoutException {
      debugPrint(
        '[VoiceNoteUpload] Upload exceeded 10s. Continuing in background for requestId: $requestId',
      );

      // Mark request voiceNoteStatus as 'arriving' in Firestore immediately
      _firestore.collection('requests').doc(requestId).set({
        'voiceNoteStatus': 'arriving',
      }, SetOptions(merge: true)).catchError((e) {
        debugPrint('[VoiceNoteUpload] Error updating status to arriving: $e');
      });

      // Continue upload in background with retry
      _continueUploadInBackground(
        uploadTask: uploadTask,
        requestId: requestId,
        storagePath: storagePath,
        durationSec: durationSec,
        sizeBytes: sizeBytes,
        localFile: file,
      );

      return null;
    } catch (e) {
      debugPrint('[VoiceNoteUpload] Immediate upload error: $e. Queuing background retry.');

      _continueUploadInBackground(
        uploadTask: null,
        requestId: requestId,
        storagePath: storagePath,
        durationSec: durationSec,
        sizeBytes: sizeBytes,
        localFile: file,
      );

      return null;
    }
  }

  /// Handles background upload completion and Firestore doc update with retry.
  void _continueUploadInBackground({
    UploadTask? uploadTask,
    required String requestId,
    required String storagePath,
    required int durationSec,
    required int sizeBytes,
    required File localFile,
  }) {
    Future(() async {
      int retryCount = 0;
      const maxRetries = 3;
      bool succeeded = false;

      while (!succeeded && retryCount < maxRetries) {
        try {
          if (uploadTask != null && retryCount == 0) {
            await uploadTask;
          } else {
            // Re-attempt full putFile
            final storageRef = _storage.ref().child(storagePath);
            final metadata = SettableMetadata(
              contentType: 'audio/m4a',
              customMetadata: {
                'durationSec': durationSec.toString(),
                'sizeBytes': sizeBytes.toString(),
                'uploadedAt': DateTime.now().toIso8601String(),
              },
            );
            await storageRef.putFile(localFile, metadata);
          }

          final voiceMetadata = VoiceNoteMetadata(
            storagePath: storagePath,
            durationSec: durationSec,
            sizeBytes: sizeBytes,
            uploadedAt: DateTime.now(),
          );

          // Update requests/{requestId} in Firestore
          await _firestore.collection('requests').doc(requestId).update({
            'voiceNote': voiceMetadata.toJson(),
            'voiceNoteStatus': 'uploaded',
          });

          debugPrint('[VoiceNoteUpload] Successfully uploaded and linked voiceNote in background.');
          succeeded = true;
          _cleanupFile(localFile);
        } catch (err) {
          retryCount++;
          debugPrint('[VoiceNoteUpload] Background upload attempt $retryCount failed: $err');
          if (retryCount < maxRetries) {
            await Future.delayed(Duration(seconds: 2 * retryCount));
          } else {
            // Mark failed in Firestore
            try {
              await _firestore.collection('requests').doc(requestId).update({
                'voiceNoteStatus': 'failed',
              });
            } catch (_) {}
            _cleanupFile(localFile);
          }
        }
      }
    });
  }

  void _cleanupFile(File file) {
    try {
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }
}
