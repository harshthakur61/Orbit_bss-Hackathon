import * as admin from 'firebase-admin';
import { HttpsError } from 'firebase-functions/v2/https';
import {
  RELIEF_CONFIG,
  ReliefReason,
  ReliefRejectReason,
  AmbulanceSnapshotData,
  calculateHaversineDistanceKm,
  isCrewEligibleForRelief,
  isTierSufficient,
} from '../config/reliefConfig';
import {
  sendReliefRequestAlert,
  sendReliefCancelAlert,
  sendHandoverNurseAlert,
} from './fcmAlertService';

interface CandidateInfo {
  uid: string;
  ambulanceId: string;
  ais125Tier: string;
  lat: number;
  lng: number;
  distanceKm: number;
  etaMin: number;
  tokensWithDocs: { token: string; docId: string }[];
}

/**
 * Helper to query available candidates within a given radius
 */
async function findEligibleCandidates(
  db: FirebaseFirestore.Firestore,
  disabledLat: number,
  disabledLng: number,
  radiusKm: number,
  requesterUid: string,
  requesterTier: string,
  excludeUids: Set<string>
): Promise<CandidateInfo[]> {
  const presenceSnap = await db
    .collection('crewPresence')
    .where('status', '==', RELIEF_CONFIG.ELIGIBLE_STATUS)
    .get();

  const candidates: CandidateInfo[] = [];

  for (const doc of presenceSnap.docs) {
    const candidateUid = doc.id;
    if (candidateUid === requesterUid || excludeUids.has(candidateUid)) {
      continue;
    }

    const data = doc.data();
    const lat = data.lat;
    const lng = data.lng;

    if (typeof lat !== 'number' || typeof lng !== 'number') {
      continue;
    }

    // Accuracy check
    if (
      typeof data.accuracyMeters === 'number' &&
      data.accuracyMeters > RELIEF_CONFIG.MAX_ACCEPTABLE_ACCURACY_METERS
    ) {
      continue;
    }

    // Tier sufficiency check
    if (!isTierSufficient(data.ais125Tier, requesterTier)) {
      continue;
    }

    // Distance calculation
    const distanceKm = calculateHaversineDistanceKm(disabledLat, disabledLng, lat, lng);
    if (distanceKm > radiusKm) {
      continue;
    }

    // Check device tokens
    const devicesSnap = await db
      .collection('ambulances')
      .doc(candidateUid)
      .collection('devices')
      .where('loggedIn', '==', true)
      .get();

    const tokensWithDocs: { token: string; docId: string }[] = [];
    devicesSnap.forEach((d) => {
      const t = d.data().token;
      if (t && typeof t === 'string') {
        tokensWithDocs.push({ token: t, docId: d.id });
      }
    });

    // Check relief eligibility with active device token count
    if (!isCrewEligibleForRelief(data as any, tokensWithDocs.length)) {
      continue;
    }

    const etaMin = Math.max(1, Math.round((distanceKm / 25) * 60));

    candidates.push({
      uid: candidateUid,
      ambulanceId: data.ambulanceId || '',
      ais125Tier: data.ais125Tier || 'Type B',
      lat,
      lng,
      distanceKm,
      etaMin,
      tokensWithDocs,
    });
  }

  // Sort by closest distance first
  candidates.sort((a, b) => a.distanceKm - b.distanceKm);

  return candidates.slice(0, RELIEF_CONFIG.MAX_CANDIDATES_PER_WAVE);
}

/**
 * 1. createReliefRequest
 * Caller must be the owning VERIFIED crew of an accepted/en_route request.
 * Finds candidates, expands wave immediately if wave 0 is empty, creates offers,
 * updates requests/{id}, and dispatches FCM alerts.
 */
export async function createReliefRequestHandler(
  db: FirebaseFirestore.Firestore,
  messaging: admin.messaging.Messaging,
  callerUid: string,
  data: {
    originalRequestId: string;
    reason: ReliefReason;
  }
) {
  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const { originalRequestId, reason } = data;
  if (!originalRequestId || !reason) {
    throw new HttpsError('invalid-argument', 'originalRequestId and reason are required.');
  }

  const validReasons: ReliefReason[] = ['breakdown', 'accident', 'flat_tyre', 'fuel', 'other'];
  if (!validReasons.includes(reason)) {
    throw new HttpsError('invalid-argument', `Invalid relief reason: ${reason}`);
  }

  // 1. Verify caller is VERIFIED crew
  const ambulanceDoc = await db.collection('ambulances').doc(callerUid).get();
  if (!ambulanceDoc.exists || ambulanceDoc.data()?.verificationStatus !== 'VERIFIED') {
    throw new HttpsError('permission-denied', 'Caller must be a verified ambulance crew member.');
  }
  const ambData = ambulanceDoc.data()!;
  const requesterSnapshot: AmbulanceSnapshotData = {
    ambulanceId: ambData.ambulanceId || '',
    vehicleNumber: ambData.vehicleNumber || '',
    driverName: ambData.driverLegalName || '',
    driverPhone: ambData.contactNumber || '',
    ambulanceType: ambData.ambulanceType || 'Basic Life Support (BLS)',
    ais125Tier: ambData.ais125Tier || 'Type B',
  };

  // 2. Verify original emergency request
  const requestRef = db.collection('requests').doc(originalRequestId);
  const requestDoc = await requestRef.get();
  if (!requestDoc.exists) {
    throw new HttpsError('not-found', 'Emergency request does not exist.');
  }

  const reqData = requestDoc.data()!;
  if (reqData.crewUid !== callerUid) {
    throw new HttpsError('permission-denied', 'Caller does not own this emergency request.');
  }

  if (reqData.status !== 'accepted' && reqData.status !== 'en_route') {
    throw new HttpsError(
      'failed-precondition',
      'Relief request can only be created for an accepted active trip.'
    );
  }

  if (reqData.reliefState === 'searching' || reqData.reliefState === 'accepted') {
    throw new HttpsError(
      'failed-precondition',
      'An active relief request is already in progress for this trip.'
    );
  }

  // 3. Resolve disabled ambulance coordinates
  let disabledLat = 0.0;
  let disabledLng = 0.0;
  let coordsFound = false;

  // Try liveLocations first
  const liveLocationDoc = await db.collection('liveLocations').doc(originalRequestId).get();
  if (liveLocationDoc.exists) {
    const loc = liveLocationDoc.data();
    if (typeof loc?.lat === 'number' && typeof loc?.lng === 'number') {
      disabledLat = loc.lat;
      disabledLng = loc.lng;
      coordsFound = true;
    }
  }

  // Try crewPresence next
  if (!coordsFound) {
    const presenceDoc = await db.collection('crewPresence').doc(callerUid).get();
    if (presenceDoc.exists) {
      const p = presenceDoc.data();
      if (typeof p?.lat === 'number' && typeof p?.lng === 'number') {
        disabledLat = p.lat;
        disabledLng = p.lng;
        coordsFound = true;
      }
    }
  }

  // Fallback to patient coordinates from original request
  if (!coordsFound) {
    if (typeof reqData.patientLat === 'number' && typeof reqData.patientLng === 'number') {
      disabledLat = reqData.patientLat;
      disabledLng = reqData.patientLng;
      coordsFound = true;
    }
  }

  if (!coordsFound || disabledLat === 0.0 || disabledLng === 0.0) {
    throw new HttpsError(
      'failed-precondition',
      'Unable to locate disabled ambulance coordinates.'
    );
  }

  // 4. Wave expansion candidate search
  const waves = RELIEF_CONFIG.WAVES;
  let selectedWave: number = 0;
  let selectedRadiusKm: number = waves[0].radiusKm;
  let candidates: CandidateInfo[] = [];

  for (let w = 0; w < waves.length; w++) {
    selectedWave = waves[w].wave;
    selectedRadiusKm = waves[w].radiusKm;

    candidates = await findEligibleCandidates(
      db,
      disabledLat,
      disabledLng,
      selectedRadiusKm,
      callerUid,
      requesterSnapshot.ais125Tier,
      new Set()
    );

    if (candidates.length > 0) {
      break;
    }
  }

  const reliefRequestsRef = db.collection('reliefRequests').doc();
  const reliefRequestId = reliefRequestsRef.id;
  const now = admin.firestore.Timestamp.now();

  // If 0 candidates found after exhausting all waves: status is no_ambulance
  if (candidates.length === 0) {
    await reliefRequestsRef.set({
      originalRequestId,
      requesterUid: callerUid,
      requesterAmbulance: requesterSnapshot,
      reason,
      status: 'no_ambulance',
      wave: waves.length - 1,
      radiusKm: waves[waves.length - 1].radiusKm,
      offerExpiresAt: now,
      disabledLocation: {
        lat: disabledLat,
        lng: disabledLng,
        updatedAt: now,
      },
      severity: reqData.severity || 'serious',
      needs: Array.isArray(reqData.needs) ? reqData.needs : [],
      acceptedByUid: null,
      acceptedAmbulance: null,
      createdAt: now,
      updatedAt: now,
    });

    await requestRef.update({
      reliefState: 'completed',
      reliefRequestId,
    });

    return {
      success: true,
      reliefRequestId,
      status: 'no_ambulance',
      candidateCount: 0,
      wave: waves.length - 1,
      radiusKm: waves[waves.length - 1].radiusKm,
    };
  }

  // Candidates found in wave: create offers & set offerExpiresAt = now + 60s
  const offerExpiresAt = admin.firestore.Timestamp.fromMillis(
    Date.now() + RELIEF_CONFIG.OFFER_DURATION_SECONDS * 1000
  );

  const batch = db.batch();

  batch.set(reliefRequestsRef, {
    originalRequestId,
    requesterUid: callerUid,
    requesterAmbulance: requesterSnapshot,
    reason,
    status: 'searching',
    wave: selectedWave,
    radiusKm: selectedRadiusKm,
    offerExpiresAt,
    disabledLocation: {
      lat: disabledLat,
      lng: disabledLng,
      updatedAt: now,
    },
    severity: reqData.severity || 'serious',
    needs: Array.isArray(reqData.needs) ? reqData.needs : [],
    acceptedByUid: null,
    acceptedAmbulance: null,
    createdAt: now,
    updatedAt: now,
  });

  for (const c of candidates) {
    const offerRef = reliefRequestsRef.collection('offers').doc(c.uid);
    batch.set(offerRef, {
      ambulanceId: c.ambulanceId,
      ais125Tier: c.ais125Tier,
      lat: c.lat,
      lng: c.lng,
      distanceKm: c.distanceKm,
      etaMin: c.etaMin,
      status: 'pending',
      reason: null,
      sentAt: now,
      respondedAt: null,
    });
  }

  batch.update(requestRef, {
    reliefState: 'searching',
    reliefRequestId,
  });

  await batch.commit();

  // Dispatch FCM alerts asynchronously to candidate crews
  const offerExpiresIso = offerExpiresAt.toDate().toISOString();
  await Promise.allSettled(
    candidates.map((c) =>
      sendReliefRequestAlert(db, messaging, c.uid, c.tokensWithDocs, {
        reliefRequestId,
        distanceKm: c.distanceKm,
        etaMin: c.etaMin,
        reason,
        severity: reqData.severity || 'serious',
        offerExpiresAt: offerExpiresIso,
        wave: selectedWave,
      })
    )
  );

  return {
    success: true,
    reliefRequestId,
    status: 'searching',
    wave: selectedWave,
    radiusKm: selectedRadiusKm,
    candidateCount: candidates.length,
    offerExpiresAt: offerExpiresIso,
  };
}

/**
 * 2. respondToReliefRequest
 * Caller responds with accept or reject.
 * Reject: Updates candidate offer doc.
 * Accept: Runs Firestore transaction to ensure strictly one winning crew,
 * marks all other offers 'taken', and updates caller's presence to 'BUSY'.
 */
export async function respondToReliefRequestHandler(
  db: FirebaseFirestore.Firestore,
  messaging: admin.messaging.Messaging,
  callerUid: string,
  data: {
    reliefRequestId: string;
    action: 'accept' | 'reject';
    reason?: ReliefRejectReason;
  }
) {
  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const { reliefRequestId, action, reason } = data;
  if (!reliefRequestId || !action) {
    throw new HttpsError('invalid-argument', 'reliefRequestId and action are required.');
  }

  const reliefReqRef = db.collection('reliefRequests').doc(reliefRequestId);
  const offerRef = reliefReqRef.collection('offers').doc(callerUid);

  if (action === 'reject') {
    const validRejectReasons: ReliefRejectReason[] = [
      'too_far',
      'starting_trip',
      'crew_unavailable',
      'vehicle_issue',
    ];
    const rejectReason = reason && validRejectReasons.includes(reason) ? reason : 'crew_unavailable';

    const offerDoc = await offerRef.get();
    if (!offerDoc.exists) {
      throw new HttpsError('not-found', 'Offer document not found for this crew.');
    }

    await offerRef.update({
      status: 'rejected',
      reason: rejectReason,
      respondedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true, action: 'rejected', reason: rejectReason };
  }

  if (action === 'accept') {
    // Read caller ambulance snapshot
    const ambDoc = await db.collection('ambulances').doc(callerUid).get();
    if (!ambDoc.exists) {
      throw new HttpsError('permission-denied', 'Ambulance profile not found.');
    }
    const ambData = ambDoc.data()!;
    const candidateSnapshot: AmbulanceSnapshotData = {
      ambulanceId: ambData.ambulanceId || '',
      vehicleNumber: ambData.vehicleNumber || '',
      driverName: ambData.driverLegalName || '',
      driverPhone: ambData.contactNumber || '',
      ambulanceType: ambData.ambulanceType || 'Basic Life Support (BLS)',
      ais125Tier: ambData.ais125Tier || 'Type B',
    };

    let originalRequestId = '';
    let otherCandidateUids: string[] = [];

    // Run transaction: Atomic First-Accept Wins
    const txResult = await db.runTransaction(async (transaction) => {
      const reliefDoc = await transaction.get(reliefReqRef);
      if (!reliefDoc.exists) {
        throw new HttpsError('not-found', 'Relief request not found.');
      }

      const rData = reliefDoc.data()!;
      if (rData.status !== 'searching') {
        return {
          success: false,
          code: 'ALREADY_TAKEN',
          message: 'Relief request was already accepted by another ambulance crew.',
        };
      }

      const offerDoc = await transaction.get(offerRef);
      if (!offerDoc.exists) {
        throw new HttpsError('not-found', 'No offer found for this crew.');
      }

      const oData = offerDoc.data()!;
      if (oData.status !== 'pending') {
        return {
          success: false,
          code: 'INVALID_OFFER',
          message: `Offer status is ${oData.status}; cannot accept.`,
        };
      }

      // Verify expiration
      const expiresAt = rData.offerExpiresAt?.toMillis
        ? rData.offerExpiresAt.toMillis()
        : new Date(rData.offerExpiresAt).getTime();

      if (Date.now() > expiresAt) {
        return {
          success: false,
          code: 'OFFER_EXPIRED',
          message: 'The relief offer window has expired.',
        };
      }

      originalRequestId = rData.originalRequestId;

      const now = admin.firestore.Timestamp.now();

      // Accept this relief request
      transaction.update(reliefReqRef, {
        status: 'accepted',
        acceptedByUid: callerUid,
        acceptedAmbulance: candidateSnapshot,
        updatedAt: now,
      });

      // Accept caller's offer
      transaction.update(offerRef, {
        status: 'accepted',
        respondedAt: now,
      });

      // Update original emergency request
      if (originalRequestId) {
        const originalReqRef = db.collection('requests').doc(originalRequestId);
        transaction.update(originalReqRef, {
          reliefState: 'accepted',
        });
      }

      // Update caller's presence to BUSY
      const presenceRef = db.collection('crewPresence').doc(callerUid);
      transaction.set(
        presenceRef,
        {
          status: 'BUSY',
          updatedAt: now,
        },
        { merge: true }
      );

      return { success: true, code: 'ACCEPTED' };
    });

    if (!txResult.success) {
      return txResult;
    }

    // Post-transaction: Mark other offers as 'taken' and send relief_cancel alert
    const offersSnap = await reliefReqRef.collection('offers').get();
    const otherOffersBatch = db.batch();

    offersSnap.forEach((doc) => {
      if (doc.id !== callerUid && doc.data().status === 'pending') {
        otherOffersBatch.update(doc.ref, {
          status: 'taken',
          respondedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        otherCandidateUids.push(doc.id);
      }
    });

    if (otherCandidateUids.length > 0) {
      await otherOffersBatch.commit();
      // Silently cancel device rings for other candidate crews
      await sendReliefCancelAlert(db, messaging, otherCandidateUids, reliefRequestId, 'taken');
    }

    return {
      success: true,
      code: 'ACCEPTED',
      reliefRequestId,
      acceptedByUid: callerUid,
    };
  }

  throw new HttpsError('invalid-argument', `Invalid action: ${action}`);
}

/**
 * 3. advanceReliefWave
 * Called by requester when 60s offer timer expires.
 * Validates offerExpiresAt has passed, marks pending offers as 'expired',
 * advances wave [5, 10, 15] km, or sets 'no_ambulance' if exhausted.
 */
export async function advanceReliefWaveHandler(
  db: FirebaseFirestore.Firestore,
  messaging: admin.messaging.Messaging,
  callerUid: string,
  data: {
    reliefRequestId: string;
  }
) {
  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const { reliefRequestId } = data;
  if (!reliefRequestId) {
    throw new HttpsError('invalid-argument', 'reliefRequestId is required.');
  }

  const reliefReqRef = db.collection('reliefRequests').doc(reliefRequestId);
  const reliefDoc = await reliefReqRef.get();
  if (!reliefDoc.exists) {
    throw new HttpsError('not-found', 'Relief request not found.');
  }

  const rData = reliefDoc.data()!;
  if (rData.requesterUid !== callerUid) {
    throw new HttpsError('permission-denied', 'Caller is not the requester of this relief request.');
  }

  if (rData.status !== 'searching') {
    return {
      success: false,
      code: 'NOT_SEARCHING',
      message: `Relief request is already in status: ${rData.status}`,
    };
  }

  // Server timestamp check: offerExpiresAt must have actually passed
  const expiresAtMillis = rData.offerExpiresAt?.toMillis
    ? rData.offerExpiresAt.toMillis()
    : new Date(rData.offerExpiresAt).getTime();

  if (Date.now() < expiresAtMillis) {
    throw new HttpsError(
      'failed-precondition',
      'Cannot advance wave before offerExpiresAt has expired.'
    );
  }

  // 1. Mark existing pending offers as expired
  const existingOffersSnap = await reliefReqRef.collection('offers').get();
  const expiredCandidateUids: string[] = [];
  const contactedUids = new Set<string>();
  const expireBatch = db.batch();

  existingOffersSnap.forEach((doc) => {
    contactedUids.add(doc.id);
    if (doc.data().status === 'pending') {
      expireBatch.update(doc.ref, {
        status: 'expired',
        respondedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      expiredCandidateUids.push(doc.id);
    }
  });

  if (expiredCandidateUids.length > 0) {
    await expireBatch.commit();
    await sendReliefCancelAlert(db, messaging, expiredCandidateUids, reliefRequestId, 'expired');
  }

  const currentWave = rData.wave ?? 0;
  const nextWaveIndex = currentWave + 1;
  const waves = RELIEF_CONFIG.WAVES;

  // 2. Check if all waves are exhausted
  if (nextWaveIndex >= waves.length) {
    await reliefReqRef.update({
      status: 'no_ambulance',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    if (rData.originalRequestId) {
      await db.collection('requests').doc(rData.originalRequestId).update({
        reliefState: 'completed',
      });
    }

    return {
      success: true,
      status: 'no_ambulance',
      wave: nextWaveIndex,
      candidateCount: 0,
    };
  }

  // 3. Find candidates in next wave radius (excluding already contacted crews)
  const nextRadiusKm = waves[nextWaveIndex].radiusKm;
  let candidates = await findEligibleCandidates(
    db,
    rData.disabledLocation.lat,
    rData.disabledLocation.lng,
    nextRadiusKm,
    callerUid,
    rData.requesterAmbulance.ais125Tier,
    contactedUids
  );

  // If 0 candidates in this wave, check remaining waves
  let finalWave: number = nextWaveIndex;
  let finalRadius: number = nextRadiusKm;

  if (candidates.length === 0) {
    for (let w = nextWaveIndex + 1; w < waves.length; w++) {
      finalWave = waves[w].wave;
      finalRadius = waves[w].radiusKm;
      candidates = await findEligibleCandidates(
        db,
        rData.disabledLocation.lat,
        rData.disabledLocation.lng,
        finalRadius,
        callerUid,
        rData.requesterAmbulance.ais125Tier,
        contactedUids
      );
      if (candidates.length > 0) break;
    }
  }

  if (candidates.length === 0) {
    // Exhausted all waves with zero candidates
    await reliefReqRef.update({
      status: 'no_ambulance',
      wave: waves.length - 1,
      radiusKm: waves[waves.length - 1].radiusKm,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    if (rData.originalRequestId) {
      await db.collection('requests').doc(rData.originalRequestId).update({
        reliefState: 'completed',
      });
    }

    return {
      success: true,
      status: 'no_ambulance',
      wave: waves.length - 1,
      candidateCount: 0,
    };
  }

  // Candidates found in advanced wave
  const offerExpiresAt = admin.firestore.Timestamp.fromMillis(
    Date.now() + RELIEF_CONFIG.OFFER_DURATION_SECONDS * 1000
  );
  const now = admin.firestore.Timestamp.now();

  const waveBatch = db.batch();
  waveBatch.update(reliefReqRef, {
    wave: finalWave,
    radiusKm: finalRadius,
    offerExpiresAt,
    updatedAt: now,
  });

  for (const c of candidates) {
    const offerRef = reliefReqRef.collection('offers').doc(c.uid);
    waveBatch.set(offerRef, {
      ambulanceId: c.ambulanceId,
      ais125Tier: c.ais125Tier,
      lat: c.lat,
      lng: c.lng,
      distanceKm: c.distanceKm,
      etaMin: c.etaMin,
      status: 'pending',
      reason: null,
      sentAt: now,
      respondedAt: null,
    });
  }

  await waveBatch.commit();

  // Dispatch FCM alerts to newly contacted candidates
  const offerExpiresIso = offerExpiresAt.toDate().toISOString();
  await Promise.allSettled(
    candidates.map((c) =>
      sendReliefRequestAlert(db, messaging, c.uid, c.tokensWithDocs, {
        reliefRequestId,
        distanceKm: c.distanceKm,
        etaMin: c.etaMin,
        reason: rData.reason,
        severity: rData.severity,
        offerExpiresAt: offerExpiresIso,
        wave: finalWave,
      })
    )
  );

  return {
    success: true,
    status: 'searching',
    wave: finalWave,
    radiusKm: finalRadius,
    candidateCount: candidates.length,
    offerExpiresAt: offerExpiresIso,
  };
}

/**
 * 4. cancelReliefRequest
 * Handled either by:
 * - Requester: If disabled vehicle recovered, cancels searching or accepted relief request.
 * - Accepted Relief Crew: If aborting before arrival, returns request to 'searching' at current wave.
 */
export async function cancelReliefRequestHandler(
  db: FirebaseFirestore.Firestore,
  messaging: admin.messaging.Messaging,
  callerUid: string,
  data: {
    reliefRequestId: string;
    action?: string;
  }
) {
  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const { reliefRequestId, action } = data;
  if (!reliefRequestId) {
    throw new HttpsError('invalid-argument', 'reliefRequestId is required.');
  }

  const reliefReqRef = db.collection('reliefRequests').doc(reliefRequestId);
  const reliefDoc = await reliefReqRef.get();
  if (!reliefDoc.exists) {
    throw new HttpsError('not-found', 'Relief request not found.');
  }

  const rData = reliefDoc.data()!;
  const isRequester = rData.requesterUid === callerUid;
  const isAcceptedCrew = rData.acceptedByUid === callerUid;

  if (!isRequester && !isAcceptedCrew) {
    throw new HttpsError(
      'permission-denied',
      'Only the requester or the accepted relief crew can cancel this request.'
    );
  }

  const now = admin.firestore.Timestamp.now();

  // PATH 1: Requester cancels (vehicle running again / false alarm)
  if (isRequester) {
    const wasAccepted = rData.status === 'accepted';
    const previousAcceptedUid = rData.acceptedByUid;

    // PATH 1B: Requester cancels accepted crew due to lost signal & re-broadcasts
    if (wasAccepted && action === 'find_another') {
      if (previousAcceptedUid) {
        await db.collection('crewPresence').doc(previousAcceptedUid).set(
          {
            status: 'AVAILABLE',
            updatedAt: now,
          },
          { merge: true }
        );
        await reliefReqRef.collection('offers').doc(previousAcceptedUid).update({
          status: 'rejected',
          reason: 'signal_lost',
          respondedAt: now,
        });
      }

      const newOfferExpiresAt = admin.firestore.Timestamp.fromMillis(
        Date.now() + RELIEF_CONFIG.OFFER_DURATION_SECONDS * 1000
      );

      await reliefReqRef.update({
        status: 'searching',
        acceptedByUid: null,
        acceptedAmbulance: null,
        offerExpiresAt: newOfferExpiresAt,
        updatedAt: now,
      });

      if (rData.originalRequestId) {
        await db.collection('requests').doc(rData.originalRequestId).update({
          reliefState: 'searching',
        });
      }

      return {
        success: true,
        status: 'searching',
        message: 'Acceptance cancelled due to signal loss. Re-broadcasting relief request.',
      };
    }

    await reliefReqRef.update({
      status: 'cancelled',
      updatedAt: now,
    });

    // Reset original request relief state
    if (rData.originalRequestId) {
      await db.collection('requests').doc(rData.originalRequestId).update({
        reliefState: null,
        reliefRequestId: null,
      });
    }

    // If it was accepted, restore accepted crew status back to AVAILABLE
    if (wasAccepted && previousAcceptedUid) {
      await db.collection('crewPresence').doc(previousAcceptedUid).set(
        {
          status: 'AVAILABLE',
          updatedAt: now,
        },
        { merge: true }
      );
    }

    // Cancel any still-pending offers and notify devices
    const offersSnap = await reliefReqRef.collection('offers').where('status', '==', 'pending').get();
    const pendingUids: string[] = [];
    const cancelBatch = db.batch();

    offersSnap.forEach((doc) => {
      cancelBatch.update(doc.ref, {
        status: 'expired',
        respondedAt: now,
      });
      pendingUids.push(doc.id);
    });

    if (pendingUids.length > 0) {
      await cancelBatch.commit();
      await sendReliefCancelAlert(db, messaging, pendingUids, reliefRequestId, 'cancelled');
    }

    return {
      success: true,
      status: 'cancelled',
      message: 'Relief request cancelled by requester.',
    };
  }

  // PATH 2: Accepted Relief Crew aborts mission before reaching disabled ambulance
  if (isAcceptedCrew) {
    if (rData.status !== 'accepted') {
      throw new HttpsError(
        'failed-precondition',
        'Crew can only abort a relief request currently in accepted status.'
      );
    }

    // Restore aborting crew to AVAILABLE
    await db.collection('crewPresence').doc(callerUid).set(
      {
        status: 'AVAILABLE',
        updatedAt: now,
      },
      { merge: true }
    );

    // Revert relief request back to searching at current wave radius with fresh 60s window
    const newOfferExpiresAt = admin.firestore.Timestamp.fromMillis(
      Date.now() + RELIEF_CONFIG.OFFER_DURATION_SECONDS * 1000
    );

    await reliefReqRef.update({
      status: 'searching',
      acceptedByUid: null,
      acceptedAmbulance: null,
      offerExpiresAt: newOfferExpiresAt,
      updatedAt: now,
    });

    // Update aborting crew offer status to rejected
    await reliefReqRef.collection('offers').doc(callerUid).update({
      status: 'rejected',
      reason: 'vehicle_issue',
      respondedAt: now,
    });

    // Update original emergency request state back to searching
    if (rData.originalRequestId) {
      await db.collection('requests').doc(rData.originalRequestId).update({
        reliefState: 'searching',
      });
    }

    return {
      success: true,
      status: 'searching',
      message: 'Relief mission aborted. Request returned to searching.',
    };
  }

  throw new HttpsError('internal', 'Unhandled cancellation state.');
}

/**
 * 5. confirmHelpReached
 * Callable invoked by the accepted relief crew when reaching the disabled ambulance.
 * Validates caller is accepted relief crew and proximity <= 200m (or override: true).
 * In one atomic transaction:
 * - requests/{originalRequestId}: crewUid = relief crew uid, ambulance = relief snapshot,
 *   previousAmbulance = old snapshot, handover = { at, fromAmbulanceId, toAmbulanceId, reliefRequestId, override, fromCrewUid, toCrewUid },
 *   reliefState = 'completed'.
 * - liveLocations/{originalRequestId}: updates ambulanceId to new relief ambulance.
 * - reliefRequests/{reliefRequestId}: status = 'completed', completedAt = now.
 * - crewPresence/{requesterUid}: status = 'OFFLINE'.
 * - crewPresence/{callerUid}: status = 'BUSY'.
 * - Sends high-priority notification to nurse station devices.
 * - Cleans up liveLocations/relief_{reliefRequestId}.
 */
export async function confirmHelpReachedHandler(
  db: FirebaseFirestore.Firestore,
  messaging: admin.messaging.Messaging,
  callerUid: string,
  data: {
    reliefRequestId: string;
    override?: boolean;
  }
) {
  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }

  const { reliefRequestId, override } = data;
  if (!reliefRequestId) {
    throw new HttpsError('invalid-argument', 'reliefRequestId is required.');
  }

  const reliefReqRef = db.collection('reliefRequests').doc(reliefRequestId);
  const reliefDoc = await reliefReqRef.get();
  if (!reliefDoc.exists) {
    throw new HttpsError('not-found', 'Relief request not found.');
  }

  const rData = reliefDoc.data()!;
  if (rData.acceptedByUid !== callerUid) {
    throw new HttpsError('permission-denied', 'Caller is not the accepted relief crew for this request.');
  }

  if (rData.status !== 'accepted') {
    throw new HttpsError(
      'failed-precondition',
      `Relief request is not in accepted status (current status: ${rData.status}).`
    );
  }

  const originalRequestId = rData.originalRequestId;
  if (!originalRequestId) {
    throw new HttpsError('failed-precondition', 'Relief request has no associated originalRequestId.');
  }

  // 1. Proximity Validation (<= ~200 m, unless override == true)
  if (!override) {
    let reliefLat = 0.0;
    let reliefLng = 0.0;
    let reliefFound = false;

    // Check relief live location first
    const reliefLocDoc = await db.collection('liveLocations').doc(`relief_${reliefRequestId}`).get();
    if (reliefLocDoc.exists) {
      const loc = reliefLocDoc.data();
      if (typeof loc?.lat === 'number' && typeof loc?.lng === 'number') {
        reliefLat = loc.lat;
        reliefLng = loc.lng;
        reliefFound = true;
      }
    }

    // Fallback to crew presence
    if (!reliefFound) {
      const presenceDoc = await db.collection('crewPresence').doc(callerUid).get();
      if (presenceDoc.exists) {
        const p = presenceDoc.data();
        if (typeof p?.lat === 'number' && typeof p?.lng === 'number') {
          reliefLat = p.lat;
          reliefLng = p.lng;
          reliefFound = true;
        }
      }
    }

    let disabledLat = rData.disabledLocation?.lat ?? 0.0;
    let disabledLng = rData.disabledLocation?.lng ?? 0.0;

    // Try liveLocations doc for disabled ambulance
    const disabledLocDoc = await db.collection('liveLocations').doc(originalRequestId).get();
    if (disabledLocDoc.exists) {
      const dLoc = disabledLocDoc.data();
      if (typeof dLoc?.lat === 'number' && typeof dLoc?.lng === 'number') {
        disabledLat = dLoc.lat;
        disabledLng = dLoc.lng;
      }
    }

    if (reliefFound && disabledLat !== 0.0 && disabledLng !== 0.0) {
      const distKm = calculateHaversineDistanceKm(reliefLat, reliefLng, disabledLat, disabledLng);
      // Threshold 200m = 0.2 km
      if (distKm > 0.20) {
        throw new HttpsError(
          'failed-precondition',
          `Proximity check failed: distance is ${(distKm * 1000).toFixed(0)}m. Must be within 200m or confirm override.`
        );
      }
    }
  }

  const now = admin.firestore.Timestamp.now();

  // 2. Fetch relief crew's verified ambulance snapshot
  const reliefAmbDoc = await db.collection('ambulances').doc(callerUid).get();
  if (!reliefAmbDoc.exists) {
    throw new HttpsError('not-found', 'Relief crew ambulance document not found.');
  }
  const ambData = reliefAmbDoc.data()!;
  const reliefAmbulanceSnapshot: AmbulanceSnapshotData = {
    ambulanceId: ambData.ambulanceId || '',
    vehicleNumber: ambData.vehicleNumber || '',
    driverName: ambData.driverLegalName || '',
    driverPhone: ambData.contactNumber || '',
    ambulanceType: ambData.ambulanceType || 'Basic Life Support (BLS)',
    ais125Tier: ambData.ais125Tier || 'Type B',
  };

  const requestRef = db.collection('requests').doc(originalRequestId);
  let hospitalIdToAlert = '';

  // 3. Atomic Transaction for Handshake
  await db.runTransaction(async (t) => {
    const freshRelief = await t.get(reliefReqRef);
    if (!freshRelief.exists || freshRelief.data()?.status !== 'accepted') {
      throw new HttpsError('failed-precondition', 'Relief request status changed concurrently.');
    }

    const freshReq = await t.get(requestRef);
    if (!freshReq.exists) {
      throw new HttpsError('not-found', 'Emergency request not found.');
    }
    const freshReqData = freshReq.data()!;
    hospitalIdToAlert = freshReqData.currentHospitalId || '';

    // a. Update requests/{originalRequestId}
    t.update(requestRef, {
      crewUid: callerUid,
      ambulance: reliefAmbulanceSnapshot,
      previousAmbulance: rData.requesterAmbulance,
      handover: {
        at: now,
        fromAmbulanceId: rData.requesterAmbulance.ambulanceId,
        toAmbulanceId: reliefAmbulanceSnapshot.ambulanceId,
        reliefRequestId,
        override: override === true,
        fromCrewUid: rData.requesterUid,
        toCrewUid: callerUid,
      },
      reliefState: 'completed',
      updatedAt: now,
    });

    // b. Update liveLocations/{originalRequestId}
    const liveLocRef = db.collection('liveLocations').doc(originalRequestId);
    t.set(
      liveLocRef,
      {
        ambulanceId: reliefAmbulanceSnapshot.ambulanceId,
        updatedAt: now,
      },
      { merge: true }
    );

    // c. Complete relief request
    t.update(reliefReqRef, {
      status: 'completed',
      completedAt: now,
      updatedAt: now,
    });

    // d. Disabled crew presence set OFFLINE
    if (rData.requesterUid) {
      const requesterPresenceRef = db.collection('crewPresence').doc(rData.requesterUid);
      t.set(
        requesterPresenceRef,
        {
          status: 'OFFLINE',
          updatedAt: now,
        },
        { merge: true }
      );
    }

    // e. Relief crew presence remains BUSY
    const reliefPresenceRef = db.collection('crewPresence').doc(callerUid);
    t.set(
      reliefPresenceRef,
      {
        status: 'BUSY',
        updatedAt: now,
      },
      { merge: true }
    );
  });

  // 4. Clean up temporary relief live location doc
  try {
    await db.collection('liveLocations').doc(`relief_${reliefRequestId}`).delete();
  } catch (_) {}

  // 5. Send notification to receiving hospital nurses
  if (hospitalIdToAlert) {
    await sendHandoverNurseAlert(db, messaging, hospitalIdToAlert, {
      requestId: originalRequestId,
      newAmbulanceId: reliefAmbulanceSnapshot.ambulanceId,
      fromAmbulanceId: rData.requesterAmbulance.ambulanceId,
      vehicleNumber: reliefAmbulanceSnapshot.vehicleNumber,
    });
  }

  return {
    success: true,
    status: 'completed',
    originalRequestId,
    newAmbulanceId: reliefAmbulanceSnapshot.ambulanceId,
    message: 'Patient handover completed successfully. Relief crew now owns the trip.',
  };
}

