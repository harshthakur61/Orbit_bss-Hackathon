import * as admin from 'firebase-admin';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { getVerificationProvider } from './providers';
import { generateUniqueAmbulanceId } from './services/ambulanceIdGenerator';
import { runVerification } from './services/verificationEngine';
import { SubmitRegistrationInput } from './types';
import { sanitizeApplicationRef, sanitizeDlNumber, sanitizeVehicleNumber } from './utils/sanitize';
import {
  createReliefRequestHandler,
  respondToReliefRequestHandler,
  advanceReliefWaveHandler,
  cancelReliefRequestHandler,
  confirmHelpReachedHandler,
} from './services/reliefService';
import { getVoiceNoteUrlHandler, GetVoiceNoteUrlInput } from './services/voiceNoteService';
import { ReliefReason, ReliefRejectReason } from './config/reliefConfig';

admin.initializeApp();
const db = admin.firestore();
const auth = admin.auth();
const messaging = admin.messaging();
const storage = admin.storage();

// In-memory rate limiting map for registration attempts (per IP/caller)
const rateLimitMap = new Map<string, { count: number; lastReset: number }>();
const RATE_LIMIT_WINDOW_MS = 60 * 1000; // 1 minute
const MAX_ATTEMPTS_PER_WINDOW = 5;

function checkRateLimit(ipOrUid: string) {
  const now = Date.now();
  const record = rateLimitMap.get(ipOrUid) || { count: 0, lastReset: now };

  if (now - record.lastReset > RATE_LIMIT_WINDOW_MS) {
    record.count = 1;
    record.lastReset = now;
  } else {
    record.count++;
  }

  rateLimitMap.set(ipOrUid, record);

  if (record.count > MAX_ATTEMPTS_PER_WINDOW) {
    throw new HttpsError(
      'resource-exhausted',
      'Too many registration requests. Please wait a minute before retrying.'
    );
  }
}

/**
 * Callable: submitAmbulanceRegistration
 * Sanitizes input, checks duplicate vehicle and DL, creates Auth user & PENDING doc,
 * executes verification engine, and updates Firestore doc with verified/review/rejected status.
 */
export const submitAmbulanceRegistration = onCall<SubmitRegistrationInput>(
  { cors: true },
  async (request) => {
    const callerId = request.rawRequest.ip || request.auth?.uid || 'anonymous';
    checkRateLimit(callerId);

    const data = request.data;
    if (!data) {
      throw new HttpsError('invalid-argument', 'Missing registration payload.');
    }

    const {
      chassisEngineNumber,
      rcPhotoStoragePath,
      dob,
      driverLegalName,
      password,
      contactNumber,
      ais125Tier = 'TYPE_B',
      ambulanceType = 'PRIVATE',
    } = data;

    // 1. Sanitize input (Never log PII to logs)
    let sanitizedPlate: string;
    let sanitizedDl: string;

    try {
      sanitizedPlate = sanitizeVehicleNumber(data.vehicleNumber);
    } catch {
      throw new HttpsError('invalid-argument', 'Malformed vehicle registration number.');
    }

    try {
      sanitizedDl = sanitizeDlNumber(data.dlNumber);
    } catch {
      throw new HttpsError('invalid-argument', 'Malformed Driving License number.');
    }

    if (!driverLegalName || driverLegalName.trim().length < 2) {
      throw new HttpsError('invalid-argument', 'Driver legal name is required.');
    }

    if (!password || password.length < 6) {
      throw new HttpsError('invalid-argument', 'Password must be at least 6 characters.');
    }

    const ambulancesRef = db.collection('ambulances');

    // 2. Reject duplicates: check if vehicleNumber or dlNumber already attached to VERIFIED or PENDING
    const [existingPlateSnap, existingDlSnap] = await Promise.all([
      ambulancesRef.where('vehicleNumber', '==', sanitizedPlate).get(),
      ambulancesRef.where('dlNumber', '==', sanitizedDl).get(),
    ]);

    const isDuplicatePlate = existingPlateSnap.docs.some((doc) => {
      const st = doc.data().verificationStatus;
      return st === 'VERIFIED' || st === 'PENDING';
    });

    const isDuplicateDl = existingDlSnap.docs.some((doc) => {
      const st = doc.data().verificationStatus;
      return st === 'VERIFIED' || st === 'PENDING';
    });

    if (isDuplicatePlate || isDuplicateDl) {
      throw new HttpsError(
        'already-exists',
        'This vehicle number or Driving License is already registered or pending verification.'
      );
    }

    // 3. Generate unique application reference e.g. APP-XXXXXX
    const randomSuffix = Math.floor(100000 + Math.random() * 900000);
    const applicationRef = `APP-${randomSuffix}`;
    const syntheticEmail = `${applicationRef.toLowerCase()}@crew.bedlink.app`;

    // 4. Create Firebase Auth user
    let userRecord: admin.auth.UserRecord;
    try {
      userRecord = await auth.createUser({
        email: syntheticEmail,
        password: password,
      });
    } catch (e: any) {
      throw new HttpsError('internal', `Failed to create authentication user: ${e.message}`);
    }

    const uid = userRecord.uid;

    // 5. Create initial document with PENDING status
    const initialDocData: Record<string, any> = {
      applicationRef,
      ambulanceId: null,
      verificationStatus: 'PENDING',
      rejectionReason: null,
      reviewReason: null,
      vehicleNumber: sanitizedPlate,
      dlNumber: sanitizedDl,
      driverLegalName: driverLegalName.trim(),
      dob: dob ? new Date(dob) : null,
      ais125Tier,
      ambulanceType,
      contactNumber: contactNumber || '',
      chassisEngineNumber: chassisEngineNumber || null,
      rcPhotoStoragePath: rcPhotoStoragePath || null, // Audit only, never trusted for verification
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await ambulancesRef.doc(uid).set(initialDocData);

    // 6. Run verification asynchronously or before return
    const provider = getVerificationProvider();

    try {
      const result = await runVerification(provider, {
        vehicleNumber: sanitizedPlate,
        dlNumber: sanitizedDl,
        dob,
        driverLegalName: driverLegalName.trim(),
      });

      const updatePayload: Record<string, any> = {
        verificationStatus: result.status,
        rejectionReason: result.rejectionReason,
        reviewReason: result.reviewReason,
      };

      if (result.vehicleData) {
        updatePayload.vehicleClass = result.vehicleData.vehicleClass;
        updatePayload.ownerName = result.vehicleData.ownerName;
        updatePayload.fitnessValidUpto = result.vehicleData.fitnessValidUpto;
      }

      if (result.licenseData) {
        updatePayload.dlStatus = result.licenseData.dlStatus;
        updatePayload.dlHasTransportEndorsement = result.licenseData.dlHasTransportEndorsement;
      }

      if (result.status === 'VERIFIED') {
        const ambulanceId = await generateUniqueAmbulanceId(db);
        updatePayload.ambulanceId = ambulanceId;
        updatePayload.verifiedAt = admin.firestore.FieldValue.serverTimestamp();
      }

      await ambulancesRef.doc(uid).update(updatePayload);

      return {
        applicationRef,
        status: result.status,
        ambulanceId: updatePayload.ambulanceId || null,
        rejectionReason: result.rejectionReason,
        reviewReason: result.reviewReason,
      };
    } catch (err: any) {
      // In case of provider error, keep PENDING and flag for review
      await ambulancesRef.doc(uid).update({
        verificationStatus: 'NEEDS_REVIEW',
        reviewReason: 'Verification provider service temporarily unavailable; queued for automatic retry.',
      });

      return {
        applicationRef,
        status: 'NEEDS_REVIEW',
        ambulanceId: null,
        rejectionReason: null,
        reviewReason: 'Verification provider service temporarily unavailable; queued for automatic retry.',
      };
    }
  }
);

/**
 * Callable: resolveCrewLogin
 * Resolves an identifier (Application Reference e.g. APP-102938 or Ambulance ID e.g. BL-AMB-100001)
 * into the required synthetic Application Reference without leaking other users' PII.
 */
export const resolveCrewLogin = onCall<{ identifier: string }>(
  { cors: true },
  async (request) => {
    const rawIdentifier = request.data?.identifier;
    if (!rawIdentifier || typeof rawIdentifier !== 'string') {
      throw new HttpsError('invalid-argument', 'Identifier is required.');
    }

    let cleanId: string;
    try {
      cleanId = sanitizeApplicationRef(rawIdentifier);
    } catch {
      throw new HttpsError('not-found', 'Invalid Application Reference or Ambulance ID.');
    }

    const ambulancesRef = db.collection('ambulances');

    // Query applicationRef
    let snap = await ambulancesRef.where('applicationRef', '==', cleanId).limit(1).get();

    // If not found by applicationRef, query by ambulanceId
    if (snap.empty) {
      snap = await ambulancesRef.where('ambulanceId', '==', cleanId).limit(1).get();
    }

    if (snap.empty) {
      throw new HttpsError('not-found', 'Invalid Application Reference or Ambulance ID.');
    }

    const doc = snap.docs[0].data();
    return {
      applicationRef: doc.applicationRef,
      ambulanceId: doc.ambulanceId || null,
      status: doc.verificationStatus,
    };
  }
);

// Phase 10A: FCM Alerts, Delivery ACKs, and Device Reachability
export { onEmergencyRequestWrite, sendTestFcmAlert } from './services/fcmAlertService';

// -------------------------------------------------------------
// Phase 11A: Clinic & Diagnostic Lab Appointment Booking & Razorpay
// -------------------------------------------------------------
import { onRequest } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import {
  createAppointmentOrderHandler,
  getClinicDaySlotsHandler,
  getRevenueSnapshotHandler,
  handleRazorpayWebhook,
  releaseAppointmentHoldHandler,
  resetDemoBookingsHandler,
  seedDemoBookingsHandler,
  verifyAppointmentPaymentHandler,
} from './services/appointmentService';
import {
  CreateAppointmentOrderInput,
  GetClinicDaySlotsInput,
  ReleaseAppointmentHoldInput,
  VerifyAppointmentPaymentInput,
} from './types';

export const razorpayKeyIdSecret = defineSecret('RAZORPAY_KEY_ID');
export const razorpayKeySecret = defineSecret('RAZORPAY_KEY_SECRET');
export const razorpayWebhookSecret = defineSecret('RAZORPAY_WEBHOOK_SECRET');

/**
 * Callable: getClinicDaySlots
 * Returns grid of slots for a clinic on a specified date with status (free/booked/past)
 */
export const getClinicDaySlots = onCall<GetClinicDaySlotsInput>(
  { cors: true },
  async (request) => {
    return getClinicDaySlotsHandler(db, request.data);
  }
);

/**
 * Callable: createAppointmentOrder
 * Reserves slot with 5-min hold, writes pending appointment, and creates Razorpay Order via REST
 */
export const createAppointmentOrder = onCall<CreateAppointmentOrderInput>(
  {
    cors: true,
    secrets: [razorpayKeyIdSecret, razorpayKeySecret],
  },
  async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError('unauthenticated', 'User must be authenticated to book an appointment.');
    }
    return createAppointmentOrderHandler(db, callerUid, request.data);
  }
);

/**
 * Callable: verifyAppointmentPayment
 * Verifies HMAC-SHA256 signature, confirms slot & appointment or triggers refund on conflict
 */
export const verifyAppointmentPayment = onCall<VerifyAppointmentPaymentInput>(
  {
    cors: true,
    secrets: [razorpayKeyIdSecret, razorpayKeySecret],
  },
  async (request) => {
    return verifyAppointmentPaymentHandler(db, request.data);
  }
);

/**
 * Callable: releaseAppointmentHold
 * Allows patient to release hold when payment is cancelled or failed in app
 */
export const releaseAppointmentHold = onCall<ReleaseAppointmentHoldInput>(
  { cors: true },
  async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }
    return releaseAppointmentHoldHandler(db, callerUid, request.data);
  }
);

/**
 * HTTPS Endpoint: razorpayWebhook
 * Validates X-Razorpay-Signature and confirms booking in background if app was killed
 */
export const razorpayWebhook = onRequest(
  {
    cors: true,
    secrets: [razorpayKeyIdSecret, razorpayKeySecret, razorpayWebhookSecret],
  },
  async (req, res) => {
    const signature = (req.headers['x-razorpay-signature'] as string) || '';
    if (!signature) {
      res.status(400).send('Missing X-Razorpay-Signature header');
      return;
    }

    try {
      const rawBody = (req as any).rawBody || JSON.stringify(req.body);
      const result = await handleRazorpayWebhook(db, rawBody, signature, req.body);
      res.status(200).json(result);
    } catch (err: any) {
      console.error('[razorpayWebhook] Error handling webhook:', err);
      res.status(400).send(`Webhook processing error: ${err.message}`);
    }
  }
);

/**
 * Callable: seedDemoBookings
 * Seeds deterministic demo booked slots (~35%) across clinics for the next 3 days
 */
export const seedDemoBookings = onCall(
  { cors: true },
  async () => {
    return seedDemoBookingsHandler(db);
  }
);

/**
 * Callable: resetDemoBookings
 * Purges demo-seeded slots and demo appointments
 */
export const resetDemoBookings = onCall(
  { cors: true },
  async () => {
    return resetDemoBookingsHandler(db);
  }
);

/**
 * Callable: getRevenueSnapshot
 * Aggregates live revenue from confirmed clinic and lab appointments (demo-mode only)
 */
export const getRevenueSnapshot = onCall(
  { cors: true },
  async () => {
    return getRevenueSnapshotHandler(db);
  }
);

/**
 * Callable: createReliefRequest
 * Phase 12B: Creates relief request for disabled ambulance on active accepted trip.
 */
export const createReliefRequest = onCall<{ originalRequestId: string; reason: ReliefReason }>(
  { cors: true },
  async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }
    return createReliefRequestHandler(db, messaging, callerUid, request.data);
  }
);

/**
 * Callable: respondToReliefRequest
 * Phase 12B: Allows candidate crew to accept or reject an offer.
 * Accept executes atomic transaction (first-accept wins).
 */
export const respondToReliefRequest = onCall<{
  reliefRequestId: string;
  action: 'accept' | 'reject';
  reason?: ReliefRejectReason;
}>(
  { cors: true },
  async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }
    return respondToReliefRequestHandler(db, messaging, callerUid, request.data);
  }
);

/**
 * Callable: advanceReliefWave
 * Phase 12B: Advances relief request to next radius wave [5, 10, 15] km when timer expires.
 */
export const advanceReliefWave = onCall<{ reliefRequestId: string }>(
  { cors: true },
  async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }
    return advanceReliefWaveHandler(db, messaging, callerUid, request.data);
  }
);

/**
 * Callable: cancelReliefRequest
 * Phase 12B: Requester cancels or accepted crew aborts relief mission.
 */
export const cancelReliefRequest = onCall<{
  reliefRequestId: string;
  action?: string;
}>(
  { cors: true },
  async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }
    return cancelReliefRequestHandler(db, messaging, callerUid, request.data);
  }
);

/**
 * Callable: confirmHelpReached
 * Phase 12E: Accepted relief crew confirms arrival at disabled ambulance and completes patient handover.
 */
export const confirmHelpReached = onCall<{
  reliefRequestId: string;
  override?: boolean;
}>(
  { cors: true },
  async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }
    return confirmHelpReachedHandler(db, messaging, callerUid, request.data);
  }
);

/**
 * Callable: getVoiceNoteUrl
 * Phase 13A: Returns a 10-minute signed URL for the voice note audio file.
 */
export const getVoiceNoteUrl = onCall<GetVoiceNoteUrlInput>(
  { cors: true },
  async (request) => {
    const callerUid = request.auth?.uid;
    if (!callerUid) {
      throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }
    return getVoiceNoteUrlHandler(db, storage, callerUid, request.auth, request.data);
  }
);



