import * as admin from 'firebase-admin';
import { HttpsError } from 'firebase-functions/v2/https';

export interface GetVoiceNoteUrlInput {
  requestId: string;
}

export interface GetVoiceNoteUrlResult {
  url: string;
  durationSec: number;
  sizeBytes: number;
  storagePath: string;
}

/**
 * Callable handler: getVoiceNoteUrl
 * Phase 13A: Returns a 10-minute signed URL for the voice note audio file in Cloud Storage.
 * Security:
 * - Allowed if caller is the owning crew (crewUid).
 * - Allowed if caller is a nurse whose hospitalId matches currentHospitalId AND request is not terminal.
 */
export async function getVoiceNoteUrlHandler(
  db: admin.firestore.Firestore,
  storage: admin.storage.Storage,
  callerUid: string,
  authContext: any,
  data: GetVoiceNoteUrlInput
): Promise<GetVoiceNoteUrlResult> {
  const { requestId } = data || {};
  if (!requestId || typeof requestId !== 'string') {
    throw new HttpsError('invalid-argument', 'Valid requestId is required.');
  }

  const reqDoc = await db.collection('requests').doc(requestId).get();
  if (!reqDoc.exists) {
    throw new HttpsError('not-found', 'Emergency request not found.');
  }

  const reqData = reqDoc.data() || {};
  const voiceNote = reqData.voiceNote;
  if (!voiceNote || !voiceNote.storagePath) {
    throw new HttpsError('not-found', 'No voice note attached to this request.');
  }

  // 1. Owning crew check
  const isOwningCrew = reqData.crewUid === callerUid;

  // 2. Nurse check
  const tokenHospitalId = authContext?.token?.hospitalId;
  let callerHospitalId = tokenHospitalId;

  if (!callerHospitalId) {
    // Check user / staff profile fallback
    const userDoc = await db.collection('users').doc(callerUid).get();
    if (userDoc.exists) {
      callerHospitalId = userDoc.data()?.hospitalId;
    }
  }

  const isHospitalNurse =
    callerHospitalId &&
    callerHospitalId === reqData.currentHospitalId;

  const terminalStatuses = ['cancelled', 'failed', 'arrived', 'completed'];
  const isTerminal = terminalStatuses.includes(reqData.status);

  if (isHospitalNurse && isTerminal) {
    throw new HttpsError(
      'permission-denied',
      'Cannot access voice note for a completed or cancelled request.'
    );
  }

  if (!isOwningCrew && !isHospitalNurse) {
    throw new HttpsError(
      'permission-denied',
      'Unauthorized: Caller is neither the owning crew nor an active nurse at the destination hospital.'
    );
  }

  try {
    const bucket = storage.bucket();
    const file = bucket.file(voiceNote.storagePath);
    const [exists] = await file.exists();
    if (!exists) {
      throw new HttpsError('not-found', 'Voice note audio file not found in storage.');
    }

    const [signedUrl] = await file.getSignedUrl({
      action: 'read',
      expires: Date.now() + 10 * 60 * 1000, // 10 minutes
    });

    return {
      url: signedUrl,
      durationSec: Number(voiceNote.durationSec) || 0,
      sizeBytes: Number(voiceNote.sizeBytes) || 0,
      storagePath: voiceNote.storagePath,
    };
  } catch (err: any) {
    if (err instanceof HttpsError) throw err;
    throw new HttpsError('internal', `Failed to generate signed URL: ${err.message}`);
  }
}
