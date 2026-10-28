import * as admin from 'firebase-admin';
import { HttpsError } from 'firebase-functions/v2/https';
import {
  AppointmentDoc,
  CreateAppointmentOrderInput,
  CreateAppointmentOrderOutput,
  DaySlotItem,
  GetClinicDaySlotsInput,
  ReleaseAppointmentHoldInput,
  SlotDoc,
  VerifyAppointmentPaymentInput,
} from '../types';
import {
  generateDaySlotIntervals,
  getKolkataComponents,
  parseKolkataDateTime,
} from '../utils/kolkataTime';
import { getRazorpayClient, RazorpayClient } from './razorpayClient';

const FIVE_MINUTES_MS = 5 * 60 * 1000;
const THIRTY_MINUTES_MS = 30 * 60 * 1000;
const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;

function toEpochMillis(val: any): number {
  if (!val) return 0;
  if (typeof val.toMillis === 'function') return val.toMillis();
  if (typeof val.getTime === 'function') return val.getTime();
  if (val instanceof Date) return val.getTime();
  if (typeof val._seconds === 'number') {
    return val._seconds * 1000 + Math.floor((val._nanoseconds || 0) / 1000000);
  }
  if (typeof val.seconds === 'number') {
    return val.seconds * 1000 + Math.floor((val.nanoseconds || 0) / 1000000);
  }
  if (typeof val === 'number') return val;
  return 0;
}

/**
 * Returns available and booked slots for a clinic on a specific date (Asia/Kolkata)
 */
export async function getClinicDaySlotsHandler(
  db: admin.firestore.Firestore,
  input: GetClinicDaySlotsInput
): Promise<{ clinicId: string; dateKey: string; slots: DaySlotItem[] }> {
  const { clinicId, dateKey } = input;
  if (!clinicId || !dateKey || !/^\d{8}$/.test(dateKey)) {
    throw new HttpsError('invalid-argument', 'Valid clinicId and dateKey (YYYYMMDD) required.');
  }

  const clinicDoc = await db.collection('clinics').doc(clinicId).get();
  if (!clinicDoc.exists) {
    throw new HttpsError('not-found', `Clinic not found: ${clinicId}`);
  }

  const clinicData = clinicDoc.data() || {};
  const openTime: string = clinicData.openTime || '08:00';
  const closeTime: string = clinicData.closeTime || '20:00';
  const slotDurationMin: number = clinicData.slotDurationMin || 30;
  const weeklyOffDays: number[] = Array.isArray(clinicData.weeklyOffDays)
    ? clinicData.weeklyOffDays
    : [];

  // Parse the date to determine day of week in Kolkata
  const dayStart = parseKolkataDateTime(dateKey, openTime);
  const kolkataComp = getKolkataComponents(dayStart);

  // If the clinic is closed on this day of week, return empty slots
  if (weeklyOffDays.includes(kolkataComp.isoDayOfWeek)) {
    return { clinicId, dateKey, slots: [] };
  }

  // Fetch all existing slots for this clinic & date
  const slotsSnap = await db
    .collection('slots')
    .where('clinicId', '==', clinicId)
    .where('dateKey', '==', dateKey)
    .get();

  const existingSlotsMap = new Map<string, SlotDoc>();
  slotsSnap.forEach((doc) => {
    existingSlotsMap.set(doc.id, doc.data() as SlotDoc);
  });

  const intervals = generateDaySlotIntervals(openTime, closeTime, slotDurationMin);
  const nowMs = Date.now();
  const daySlots: DaySlotItem[] = [];

  for (const timeStr of intervals) {
    const slotDate = parseKolkataDateTime(dateKey, timeStr);
    const slotMs = slotDate.getTime();
    const timeKey = timeStr.replace(':', '');
    const slotId = `${clinicId}_${dateKey}_${timeKey}`;

    let status: 'free' | 'booked' | 'past' = 'free';

    // Slots starting in less than 30 minutes from now (or in the past) are marked past
    if (slotMs < nowMs + THIRTY_MINUTES_MS) {
      status = 'past';
    } else {
      const existing = existingSlotsMap.get(slotId);
      if (existing) {
        if (existing.status === 'booked') {
          status = 'booked';
        } else if (existing.status === 'held') {
          const holdExpiry = toEpochMillis(existing.holdExpiresAt);
          if (holdExpiry > nowMs) {
            status = 'booked'; // Active hold treated as unavailable
          } else {
            status = 'free'; // Expired hold treated as free
          }
        }
      }
    }

    daySlots.push({
      slotId,
      time: timeStr,
      startTimeIso: slotDate.toISOString(),
      status,
    });
  }

  return {
    clinicId,
    dateKey,
    slots: daySlots,
  };
}

/**
 * Creates an appointment with a 5-minute slot hold and generates a Razorpay Order
 */
export async function createAppointmentOrderHandler(
  db: admin.firestore.Firestore,
  callerUid: string,
  input: CreateAppointmentOrderInput,
  razorpay: RazorpayClient = getRazorpayClient()
): Promise<CreateAppointmentOrderOutput> {
  const { clinicId, startTime, patientName, patientPhone } = input;

  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated to book an appointment.');
  }

  if (!clinicId || !startTime || !patientName?.trim() || !patientPhone?.trim()) {
    throw new HttpsError('invalid-argument', 'clinicId, startTime, patientName, and patientPhone are required.');
  }

  const slotDate = new Date(startTime);
  if (isNaN(slotDate.getTime())) {
    throw new HttpsError('invalid-argument', 'Invalid startTime format.');
  }

  const nowMs = Date.now();
  const slotMs = slotDate.getTime();

  // Validate lead time: at least 30 minutes in the future
  if (slotMs < nowMs + THIRTY_MINUTES_MS) {
    throw new HttpsError('invalid-argument', 'Appointments must be booked at least 30 minutes in advance.');
  }

  // Validate maximum booking window: within 7 days
  if (slotMs > nowMs + SEVEN_DAYS_MS) {
    throw new HttpsError('invalid-argument', 'Appointments cannot be booked more than 7 days in advance.');
  }

  // Fetch clinic configuration from Firestore
  const clinicDoc = await db.collection('clinics').doc(clinicId).get();
  if (!clinicDoc.exists) {
    throw new HttpsError('not-found', `Clinic not found: ${clinicId}`);
  }

  const clinicData = clinicDoc.data() || {};
  const clinicType: string = clinicData.type || 'clinic';
  const openTime: string = clinicData.openTime || '08:00';
  const closeTime: string = clinicData.closeTime || '20:00';
  const slotDurationMin: number = clinicData.slotDurationMin || 30;
  const weeklyOffDays: number[] = Array.isArray(clinicData.weeklyOffDays)
    ? clinicData.weeklyOffDays
    : [];

  // Determine server-side fee (ignores any client-supplied amounts)
  const defaultFee = clinicType.toLowerCase().includes('lab') ? 49 : 79;
  const bookingFeeRupees: number =
    typeof clinicData.bookingFeeRupees === 'number' ? clinicData.bookingFeeRupees : defaultFee;
  const amountPaise = bookingFeeRupees * 100;

  // Extract Asia/Kolkata date and time
  const kolkata = getKolkataComponents(slotDate);
  if (weeklyOffDays.includes(kolkata.isoDayOfWeek)) {
    throw new HttpsError('invalid-argument', 'The selected clinic is closed on this day of the week.');
  }

  // Validate clinic open hours
  const slotMinutes = kolkata.hours * 60 + kolkata.minutes;
  const [openH, openM] = openTime.split(':').map((v) => parseInt(v, 10));
  const [closeH, closeM] = closeTime.split(':').map((v) => parseInt(v, 10));
  const openMinutes = openH * 60 + openM;
  const closeMinutes = closeH * 60 + closeM;

  if (slotMinutes < openMinutes || slotMinutes + slotDurationMin > closeMinutes) {
    throw new HttpsError('invalid-argument', 'Selected slot is outside clinic operating hours.');
  }

  const dateKey = kolkata.dateKey;
  const timeKey = kolkata.timeKey;
  const slotId = `${clinicId}_${dateKey}_${timeKey}`;

  // Generate unique appointment reference: BLA-XXXXXX
  const randomSuffix = Math.floor(100000 + Math.random() * 900000);
  const appointmentId = `BLA-${randomSuffix}`;

  const slotRef = db.collection('slots').doc(slotId);
  const appointmentRef = db.collection('appointments').doc(appointmentId);

  const holdExpiresAtDate = new Date(Date.now() + FIVE_MINUTES_MS);
  const holdExpiresAtTimestamp = admin.firestore.Timestamp.fromDate(holdExpiresAtDate);

  // 1. ATOMIC TRANSACTION: Check slot availability and reserve a 5-minute hold
  await db.runTransaction(async (transaction) => {
    const slotSnap = await transaction.get(slotRef);

    if (slotSnap.exists) {
      const slotData = slotSnap.data() as SlotDoc;
      if (slotData.status === 'booked') {
        throw new HttpsError('already-exists', 'This time slot is already booked.');
      }

      if (slotData.status === 'held') {
        const holdExpiry = toEpochMillis(slotData.holdExpiresAt);
        if (holdExpiry > Date.now()) {
          throw new HttpsError(
            'failed-precondition',
            'This time slot is currently on temporary hold. Please select another slot or retry in a few minutes.'
          );
        }
      }
    }

    // Write slot hold
    transaction.set(slotRef, {
      clinicId,
      dateKey,
      startTime: admin.firestore.Timestamp.fromDate(slotDate),
      status: 'held',
      holdExpiresAt: holdExpiresAtTimestamp,
      appointmentId,
    });

    // Write pending appointment
    transaction.set(appointmentRef, {
      patientUid: callerUid,
      patientName: patientName.trim(),
      patientPhone: patientPhone.trim(),
      clinicId,
      clinicName: clinicData.name || 'Clinic',
      clinicType,
      slotId,
      startTime: admin.firestore.Timestamp.fromDate(slotDate),
      status: 'pending_payment',
      amountPaise,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  // 2. Call Razorpay REST API to create an order
  try {
    const order = await razorpay.createOrder({
      amountPaise,
      receipt: appointmentId,
    });

    await appointmentRef.update({
      razorpayOrderId: order.id,
    });

    return {
      appointmentId,
      orderId: order.id,
      amountPaise,
      keyId: razorpay.getKeyId(),
      holdExpiresAt: holdExpiresAtDate.toISOString(),
    };
  } catch (err: any) {
    // If Razorpay order creation fails, roll back the slot hold immediately
    try {
      await db.runTransaction(async (t) => {
        const sSnap = await t.get(slotRef);
        if (sSnap.exists && (sSnap.data() as SlotDoc).appointmentId === appointmentId) {
          t.delete(slotRef);
        }
        t.update(appointmentRef, {
          status: 'payment_failed',
        });
      });
    } catch (_) {}

    throw new HttpsError('internal', `Failed to create payment order: ${err.message}`);
  }
}

/**
 * Verifies Razorpay HMAC-SHA256 signature and confirms or refunds the booking
 */
export async function verifyAppointmentPaymentHandler(
  db: admin.firestore.Firestore,
  input: VerifyAppointmentPaymentInput & { skipSignatureCheck?: boolean },
  razorpay: RazorpayClient = getRazorpayClient()
): Promise<{ success: boolean; status: string; appointmentId: string; reason?: string }> {
  const { appointmentId, razorpayOrderId, razorpayPaymentId, razorpaySignature, skipSignatureCheck } = input;

  if (!appointmentId || !razorpayOrderId || !razorpayPaymentId || (!razorpaySignature && !skipSignatureCheck)) {
    throw new HttpsError('invalid-argument', 'Missing payment verification parameters.');
  }

  // 1. Verify HMAC-SHA256 signature using constant-time comparison unless skipped (e.g. verified webhook)
  if (!skipSignatureCheck) {
    const isValidSig = razorpay.verifyPaymentSignature({
      orderId: razorpayOrderId,
      paymentId: razorpayPaymentId,
      signature: razorpaySignature,
    });

    if (!isValidSig) {
      throw new HttpsError('invalid-argument', 'Invalid Razorpay payment signature.');
    }
  }

  const appointmentRef = db.collection('appointments').doc(appointmentId);

  // 2. Execute confirmation in an atomic transaction
  let needsRefund = false;
  let amountPaiseToRefund = 0;

  const result = await db.runTransaction(async (transaction) => {
    const appSnap = await transaction.get(appointmentRef);
    if (!appSnap.exists) {
      throw new HttpsError('not-found', `Appointment ${appointmentId} not found.`);
    }

    const appData = appSnap.data() as AppointmentDoc;

    // Idempotent return if already confirmed
    if (appData.status === 'confirmed') {
      return { success: true, status: 'confirmed', appointmentId };
    }

    if (appData.status === 'refunded') {
      return { success: false, status: 'refunded', appointmentId, reason: 'Already refunded.' };
    }

    const slotRef = db.collection('slots').doc(appData.slotId);
    const slotSnap = await transaction.get(slotRef);

    let canBook = false;

    if (!slotSnap.exists) {
      // Slot doc doesn't exist, can claim it
      canBook = true;
    } else {
      const slotData = slotSnap.data() as SlotDoc;
      // Valid if still held for this appointment OR hold expired
      if (
        slotData.appointmentId === appointmentId ||
        (slotData.status === 'held' && (slotData.holdExpiresAt?.toMillis() ?? 0) <= Date.now())
      ) {
        canBook = true;
      }
    }

    if (canBook) {
      // Confirm slot
      transaction.set(
        slotRef,
        {
          clinicId: appData.clinicId,
          dateKey: appData.slotId.split('_')[1],
          startTime: appData.startTime,
          status: 'booked',
          holdExpiresAt: null,
          appointmentId,
        },
        { merge: true }
      );

      // Confirm appointment
      transaction.update(appointmentRef, {
        status: 'confirmed',
        razorpayPaymentId,
        razorpaySignature,
        confirmedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return { success: true, status: 'confirmed', appointmentId };
    } else {
      // Conflict: Slot was claimed by another appointment after hold expired
      needsRefund = true;
      amountPaiseToRefund = appData.amountPaise;

      transaction.update(appointmentRef, {
        status: 'refunded',
        razorpayPaymentId,
        razorpaySignature,
        refundedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        success: false,
        status: 'refunded',
        appointmentId,
        reason: 'Hold expired and slot was claimed; payment has been refunded.',
      };
    }
  });

  // If conflict occurred, trigger Razorpay refund API
  if (needsRefund && razorpayPaymentId) {
    try {
      const refund = await razorpay.refundPayment({
        paymentId: razorpayPaymentId,
        amountPaise: amountPaiseToRefund,
        reason: 'Slot hold expired conflict',
      });
      await appointmentRef.update({ refundId: refund.id });
    } catch (refundErr) {
      console.error('[appointmentService] Refund execution error:', refundErr);
    }
  }

  return result;
}

/**
 * Releases a held slot when payment is cancelled or failed in the app
 */
export async function releaseAppointmentHoldHandler(
  db: admin.firestore.Firestore,
  callerUid: string,
  input: ReleaseAppointmentHoldInput
): Promise<{ success: boolean }> {
  const { appointmentId } = input;
  if (!callerUid) {
    throw new HttpsError('unauthenticated', 'User must be authenticated.');
  }
  if (!appointmentId) {
    throw new HttpsError('invalid-argument', 'appointmentId is required.');
  }

  const appointmentRef = db.collection('appointments').doc(appointmentId);

  await db.runTransaction(async (transaction) => {
    const appSnap = await transaction.get(appointmentRef);
    if (!appSnap.exists) return;

    const appData = appSnap.data() as AppointmentDoc;
    if (appData.patientUid !== callerUid) {
      throw new HttpsError('permission-denied', 'You do not have permission to release this appointment.');
    }

    // Only pending payments can be released
    if (appData.status !== 'pending_payment') return;

    const slotRef = db.collection('slots').doc(appData.slotId);
    const slotSnap = await transaction.get(slotRef);
    if (slotSnap.exists) {
      const slotData = slotSnap.data() as SlotDoc;
      if (slotData.appointmentId === appointmentId && slotData.status === 'held') {
        transaction.delete(slotRef);
      }
    }

    transaction.update(appointmentRef, {
      status: 'payment_failed',
    });
  });

  return { success: true };
}

/**
 * Handles incoming Razorpay Webhook events (e.g. payment.captured, order.paid)
 */
export async function handleRazorpayWebhook(
  db: admin.firestore.Firestore,
  rawBody: Buffer | string,
  signature: string,
  eventData: any,
  razorpay: RazorpayClient = getRazorpayClient()
): Promise<{ received: boolean; action?: string }> {
  const isValid = razorpay.verifyWebhookSignature({
    rawBody,
    signature,
  });

  if (!isValid) {
    throw new HttpsError('invalid-argument', 'Invalid webhook signature.');
  }

  const eventName = eventData?.event;
  if (eventName === 'payment.captured' || eventName === 'order.paid') {
    const payment = eventData?.payload?.payment?.entity;
    const orderId = payment?.order_id || eventData?.payload?.order?.entity?.id;
    const paymentId = payment?.id;

    if (!orderId) {
      return { received: true, action: 'ignored_missing_order_id' };
    }

    // Find appointment by razorpayOrderId
    const snap = await db
      .collection('appointments')
      .where('razorpayOrderId', '==', orderId)
      .limit(1)
      .get();

    if (snap.empty) {
      return { received: true, action: 'order_not_found' };
    }

    const appDoc = snap.docs[0];
    const appointmentId = appDoc.id;

    await verifyAppointmentPaymentHandler(
      db,
      {
        appointmentId,
        razorpayOrderId: orderId,
        razorpayPaymentId: paymentId || `pay_wh_${Date.now()}`,
        razorpaySignature: signature,
        skipSignatureCheck: true,
      },
      razorpay
    );

    return { received: true, action: 'confirmed_or_refunded' };
  }

  return { received: true, action: 'ignored_unsupported_event' };
}

/**
 * Deterministically checks whether a slot should be marked as demo-booked (~35% distribution)
 */
export function isDeterministicDemoSlot(clinicId: string, dateKey: string, timeKey: string): boolean {
  let hash = 0;
  const str = `${clinicId}_${dateKey}_${timeKey}`;
  for (let i = 0; i < str.length; i++) {
    hash = (hash * 31 + str.charCodeAt(i)) & 0xffffffff;
  }
  return Math.abs(hash) % 100 < 35;
}

/**
 * Seeds plausible booked slots for the next 3 days across all clinics (Admin/Demo callable)
 */
export async function seedDemoBookingsHandler(
  db: admin.firestore.Firestore
): Promise<{ success: boolean; seededCount: number; message: string }> {
  const clinicsSnap = await db.collection('clinics').get();
  if (clinicsSnap.empty) {
    return { success: false, seededCount: 0, message: 'No clinics found to seed bookings.' };
  }

  const nowMs = Date.now();
  const ONE_DAY_MS = 24 * 60 * 60 * 1000;
  const targetDates: string[] = [];

  for (let i = 0; i < 3; i++) {
    const comp = getKolkataComponents(new Date(nowMs + i * ONE_DAY_MS));
    targetDates.push(comp.dateKey);
  }

  let seededCount = 0;
  const batchOps: Array<{ slotRef: admin.firestore.DocumentReference; slotData: any; appRef: admin.firestore.DocumentReference; appData: any }> = [];

  for (const clinicDoc of clinicsSnap.docs) {
    const clinicId = clinicDoc.id;
    const clinicData = clinicDoc.data();
    const openTime = clinicData.openTime || '08:00';
    const closeTime = clinicData.closeTime || '20:00';
    const slotDurationMin = clinicData.slotDurationMin || 30;
    const weeklyOffDays: number[] = Array.isArray(clinicData.weeklyOffDays) ? clinicData.weeklyOffDays : [];
    const feeRupees: number = clinicData.bookingFeeRupees || (clinicData.type?.includes('lab') ? 49 : 79);

    const intervals = generateDaySlotIntervals(openTime, closeTime, slotDurationMin);

    for (const dateKey of targetDates) {
      const dayStart = parseKolkataDateTime(dateKey, openTime);
      const dayComp = getKolkataComponents(dayStart);

      if (weeklyOffDays.includes(dayComp.isoDayOfWeek)) {
        continue;
      }

      for (const timeStr of intervals) {
        const timeKey = timeStr.replace(':', '');
        if (isDeterministicDemoSlot(clinicId, dateKey, timeKey)) {
          const slotId = `${clinicId}_${dateKey}_${timeKey}`;
          const appointmentId = `BLA-DEMO-${dateKey}-${timeKey}-${clinicId.substring(0, 4).toUpperCase()}`;
          const slotDate = parseKolkataDateTime(dateKey, timeStr);

          const slotRef = db.collection('slots').doc(slotId);
          const slotData = {
            clinicId,
            dateKey,
            startTime: admin.firestore.Timestamp.fromDate(slotDate),
            status: 'booked',
            holdExpiresAt: null,
            appointmentId,
            isDemo: true,
          };

          const appRef = db.collection('appointments').doc(appointmentId);
          const appData = {
            patientUid: 'demo_patient_uid',
            patientName: 'Demo Confirmed Patient',
            patientPhone: '9876543210',
            clinicId,
            clinicName: clinicData.name || 'Clinic',
            clinicType: clinicData.type || 'clinic',
            slotId,
            startTime: admin.firestore.Timestamp.fromDate(slotDate),
            status: 'confirmed',
            amountPaise: feeRupees * 100,
            createdAt: admin.firestore.Timestamp.fromDate(slotDate),
            confirmedAt: admin.firestore.Timestamp.fromDate(slotDate),
            isDemo: true,
            clinicAddress: clinicData.address || '',
            clinicPhone: clinicData.phone || '',
            clinicLat: clinicData.lat,
            clinicLng: clinicData.lng,
          };

          batchOps.push({ slotRef, slotData, appRef, appData });
          seededCount++;
        }
      }
    }
  }

  // Commit in chunks of 250 (max 500 ops per Firestore batch)
  const CHUNK_SIZE = 250;
  for (let i = 0; i < batchOps.length; i += CHUNK_SIZE) {
    const chunk = batchOps.slice(i, i + CHUNK_SIZE);
    const batch = db.batch();
    for (const op of chunk) {
      batch.set(op.slotRef, op.slotData, { merge: true });
      batch.set(op.appRef, op.appData, { merge: true });
    }
    await batch.commit();
  }

  return {
    success: true,
    seededCount,
    message: `Successfully seeded ${seededCount} deterministic demo bookings across 3 days.`,
  };
}

/**
 * Clears all demo-seeded slots and appointments (Admin/Demo callable)
 */
export async function resetDemoBookingsHandler(
  db: admin.firestore.Firestore
): Promise<{ success: boolean; clearedCount: number; message: string }> {
  let clearedCount = 0;

  // Clear demo slots
  const demoSlotsSnap = await db.collection('slots').where('isDemo', '==', true).get();
  if (!demoSlotsSnap.empty) {
    const batch = db.batch();
    demoSlotsSnap.forEach((doc) => {
      batch.delete(doc.ref);
      clearedCount++;
    });
    await batch.commit();
  }

  // Clear demo appointments
  const demoAppsSnap = await db.collection('appointments').where('isDemo', '==', true).get();
  if (!demoAppsSnap.empty) {
    const batch = db.batch();
    demoAppsSnap.forEach((doc) => {
      batch.delete(doc.ref);
      clearedCount++;
    });
    await batch.commit();
  }

  return {
    success: true,
    clearedCount,
    message: `Cleared ${clearedCount} demo slots and appointments.`,
  };
}

/**
 * Calculates current revenue snapshot across confirmed appointments (Demo-mode only)
 */
export async function getRevenueSnapshotHandler(
  db: admin.firestore.Firestore
): Promise<{
  totalBookings: number;
  totalRevenueRupees: number;
  averagePerDay: number;
  activeDaysCount: number;
  breakdown: {
    clinic: { bookings: number; revenueRupees: number };
    lab: { bookings: number; revenueRupees: number };
  };
  timestamp: string;
}> {
  if (process.env.NODE_ENV === 'production' && process.env.DEMO_MODE !== 'true') {
    throw new HttpsError('permission-denied', 'Revenue snapshot is only available in demo/sandbox mode.');
  }

  const confirmedSnap = await db
    .collection('appointments')
    .where('status', '==', 'confirmed')
    .get();

  let totalRevenuePaise = 0;
  let clinicBookings = 0;
  let clinicRevenueRupees = 0;
  let labBookings = 0;
  let labRevenueRupees = 0;
  const activeDates = new Set<string>();

  confirmedSnap.forEach((doc) => {
    const data = doc.data();
    const amountPaise = typeof data.amountPaise === 'number' ? data.amountPaise : 0;
    const amountRupees = Math.round(amountPaise / 100);
    const type = (data.clinicType || 'clinic').toLowerCase();

    totalRevenuePaise += amountPaise;

    if (type.includes('lab') || type.includes('pathology') || type.includes('diagnostic')) {
      labBookings++;
      labRevenueRupees += amountRupees;
    } else {
      clinicBookings++;
      clinicRevenueRupees += amountRupees;
    }

    if (data.startTime) {
      const dt = typeof data.startTime.toDate === 'function' ? data.startTime.toDate() : new Date(data.startTime);
      const kolkata = getKolkataComponents(dt);
      activeDates.add(kolkata.dateKey);
    }
  });

  const totalBookings = confirmedSnap.docs.length;
  const totalRevenueRupees = Math.round(totalRevenuePaise / 100);
  const activeDaysCount = activeDates.size > 0 ? activeDates.size : 1;
  const averagePerDay = Math.round(totalRevenueRupees / activeDaysCount);

  return {
    totalBookings,
    totalRevenueRupees,
    averagePerDay,
    activeDaysCount,
    breakdown: {
      clinic: {
        bookings: clinicBookings,
        revenueRupees: clinicRevenueRupees,
      },
      lab: {
        bookings: labBookings,
        revenueRupees: labRevenueRupees,
      },
    },
    timestamp: new Date().toISOString(),
  };
}
