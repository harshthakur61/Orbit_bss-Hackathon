import * as admin from 'firebase-admin';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';

/**
 * Cloud Function Trigger: onEmergencyRequestWrite
 * 1. Dispatches data-only FCM alerts to receiving hospital devices when an emergency request is offered.
 * 2. Silences ringing nurse devices (type: "cancel_request") when an offer is resolved.
 * 3. Notifies ambulance crew devices when their offer is accepted or cascades to the next hospital.
 * 4. Cleans up invalid/unregistered device tokens automatically.
 */
export const onEmergencyRequestWrite = onDocumentWritten(
  {
    document: 'requests/{requestId}',
    region: 'us-central1',
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    const requestId = event.params.requestId;

    if (!after) return; // Document was deleted

    const db = admin.firestore();
    const messaging = admin.messaging();

    const isOffered = after.status === 'offered';
    const currentHospitalId = after.currentHospitalId;
    const attemptIndex = after.currentIndex ?? 0;
    const idempotencyKey = `${currentHospitalId}_${attemptIndex}`;

    // -------------------------------------------------------------
    // 1. HOSPITAL ALERT: Request is offered to currentHospitalId
    // -------------------------------------------------------------
    if (
      isOffered &&
      currentHospitalId &&
      after.lastDispatchedOffer !== idempotencyKey
    ) {
      // Query all logged-in devices for the targeted hospital
      const devicesSnap = await db
        .collection('hospitals')
        .doc(currentHospitalId)
        .collection('devices')
        .where('loggedIn', '==', true)
        .get();

      if (!devicesSnap.empty) {
        const tokens: string[] = [];
        const tokenDocIds: { [token: string]: string } = {};

        devicesSnap.forEach((doc) => {
          const t = doc.data().token;
          if (t && typeof t === 'string') {
            tokens.push(t);
            tokenDocIds[t] = doc.id;
          }
        });

        if (tokens.length > 0) {
          const offerExpiresIso = after.offerExpiresAt?.toDate
            ? after.offerExpiresAt.toDate().toISOString()
            : String(after.offerExpiresAt || '');

          const needsStr = Array.isArray(after.needs)
            ? after.needs.join(', ')
            : String(after.needs || '');

          // Data-only message with high priority & 120s TTL (matches offer window)
          const message: admin.messaging.MulticastMessage = {
            tokens,
            data: {
              type: 'incoming_request',
              requestId,
              severity: String(after.severity || 'serious'),
              needs: needsStr,
              hospitalId: currentHospitalId,
              offerExpiresAt: offerExpiresIso,
            },
            android: {
              priority: 'high',
              ttl: 120 * 1000,
            },
            apns: {
              headers: {
                'apns-priority': '10',
                'apns-push-type': 'alert',
                'apns-expiration': String(Math.floor(Date.now() / 1000) + 120),
              },
              payload: {
                aps: {
                  alert: {
                    title: 'Emergency Bed Hold Offer',
                    body: `Inbound ${String(after.severity || 'serious').toUpperCase()} patient requesting ${needsStr}`,
                  },
                  sound: 'default',
                  'interruption-level': 'time-sensitive',
                },
              },
            },
          };

          try {
            const batchResponse = await messaging.sendEachForMulticast(message);

            // Clean up invalid or unregistered tokens
            const deadTokenDocIds: string[] = [];
            batchResponse.responses.forEach((resp, idx) => {
              if (
                !resp.success &&
                (resp.error?.code === 'messaging/registration-token-not-registered' ||
                  resp.error?.code === 'messaging/invalid-registration-token')
              ) {
                const deadToken = tokens[idx];
                const docId = tokenDocIds[deadToken];
                if (docId) deadTokenDocIds.push(docId);
              }
            });

            if (deadTokenDocIds.length > 0) {
              const batch = db.batch();
              deadTokenDocIds.forEach((dId) => {
                batch.delete(
                  db
                    .collection('hospitals')
                    .doc(currentHospitalId)
                    .collection('devices')
                    .doc(dId)
                );
              });
              await batch.commit();
            }
          } catch (err) {
            console.error('[fcmAlertService] Failed to send hospital alert multicast:', err);
          }
        }
      }

      // Mark idempotency key to prevent double-dispatch for same attempt
      await db.collection('requests').doc(requestId).update({
        lastDispatchedOffer: idempotencyKey,
      });
    }

    // -------------------------------------------------------------
    // 2. CANCEL ALERT: Offer was resolved, rejected, or cascaded away
    // -------------------------------------------------------------
    const wasOffered = before?.status === 'offered';
    const targetChanged = before?.currentHospitalId !== currentHospitalId;
    const isNowResolved = after.status !== 'offered';

    if (wasOffered && (targetChanged || isNowResolved) && before?.currentHospitalId) {
      const prevHospitalId = before.currentHospitalId;
      const prevDevicesSnap = await db
        .collection('hospitals')
        .doc(prevHospitalId)
        .collection('devices')
        .where('loggedIn', '==', true)
        .get();

      if (!prevDevicesSnap.empty) {
        const prevTokens: string[] = [];
        prevDevicesSnap.forEach((doc) => {
          const t = doc.data().token;
          if (t && typeof t === 'string') prevTokens.push(t);
        });

        if (prevTokens.length > 0) {
          const cancelMsg: admin.messaging.MulticastMessage = {
            tokens: prevTokens,
            data: {
              type: 'cancel_request',
              requestId,
            },
            android: {
              priority: 'high',
              ttl: 60 * 1000,
            },
          };
          try {
            await messaging.sendEachForMulticast(cancelMsg);
          } catch (err) {
            console.error('[fcmAlertService] Failed to send cancel multicast:', err);
          }
        }
      }
    }

    // -------------------------------------------------------------
    // 3. CREW NOTIFICATIONS: Notify crew when backgrounded
    // -------------------------------------------------------------
    const crewUid = after.crewUid;
    if (crewUid) {
      const statusChanged = before?.status !== after.status;
      const hospitalChanged = before?.currentHospitalId !== after.currentHospitalId;

      let crewTitle: string | null = null;
      let crewBody: string | null = null;

      if (statusChanged && after.status === 'accepted') {
        crewTitle = 'Bed Held Successfully! 🟢';
        crewBody = `Hospital accepted emergency hold. Tap to navigate.`;
      } else if (hospitalChanged && isOffered) {
        crewTitle = 'Offer Cascading to Next Hospital ⚡';
        crewBody = `Auto-cascaded to next best hospital in ranking.`;
      } else if (statusChanged && after.status === 'failed') {
        crewTitle = 'Emergency Hold Failed';
        crewBody = 'All ranked hospitals were exhausted. Tap to view options.';
      }

      if (crewTitle && crewBody) {
        const crewDevicesSnap = await db
          .collection('ambulances')
          .doc(crewUid)
          .collection('devices')
          .where('loggedIn', '==', true)
          .get();

        if (!crewDevicesSnap.empty) {
          const crewTokens: string[] = [];
          crewDevicesSnap.forEach((doc) => {
            const t = doc.data().token;
            if (t && typeof t === 'string') crewTokens.push(t);
          });

          if (crewTokens.length > 0) {
            const crewMsg: admin.messaging.MulticastMessage = {
              tokens: crewTokens,
              notification: {
                title: crewTitle,
                body: crewBody,
              },
              data: {
                requestId,
                status: after.status,
              },
              android: {
                priority: 'high',
              },
              apns: {
                payload: {
                  aps: {
                    sound: 'default',
                    'interruption-level': 'time-sensitive',
                  },
                },
              },
            };

            try {
              await messaging.sendEachForMulticast(crewMsg);
            } catch (err) {
              console.error('[fcmAlertService] Failed to notify crew devices:', err);
            }
          }
        }
      }
    }
  }
);

/**
 * Debug Callable: sendTestFcmAlert
 * Allows testing FCM push delivery to a single device token or hospital in emulator / staging.
 */
export const sendTestFcmAlert = onCall<{
  token?: string;
  hospitalId?: string;
  title?: string;
  body?: string;
}>(async (request) => {
  const { token, hospitalId, title = 'BedLink Test Alert', body = 'Test notification from Cloud Functions' } =
    request.data || {};

  const messaging = admin.messaging();

  if (token) {
    const res = await messaging.send({
      token,
      notification: { title, body },
      data: { type: 'test_alert', timestamp: String(Date.now()) },
      android: { priority: 'high' },
      apns: {
        payload: {
          aps: { sound: 'default', 'interruption-level': 'time-sensitive' },
        },
      },
    });
    return { success: true, messageId: res };
  }

  if (hospitalId) {
    const db = admin.firestore();
    const snap = await db
      .collection('hospitals')
      .doc(hospitalId)
      .collection('devices')
      .where('loggedIn', '==', true)
      .get();

    const tokens: string[] = [];
    snap.forEach((d) => {
      const t = d.data().token;
      if (t) tokens.push(t);
    });

    if (tokens.length === 0) {
      throw new HttpsError('not-found', `No active device tokens found for hospital: ${hospitalId}`);
    }

    const res = await messaging.sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: { type: 'test_alert', hospitalId },
      android: { priority: 'high' },
    });

    return {
      success: true,
      deliveredCount: res.successCount,
      failureCount: res.failureCount,
    };
  }

  throw new HttpsError('invalid-argument', 'Either token or hospitalId must be provided.');
});

/**
 * Phase 12B: Send data-only high-priority relief_request alert to candidate crew devices.
 * TTL: 60s. Strictly excludes patient name, clinical note, and hospital destination.
 * Automatically cleans up invalid/unregistered device tokens.
 */
export async function sendReliefRequestAlert(
  db: FirebaseFirestore.Firestore,
  messaging: admin.messaging.Messaging,
  candidateUid: string,
  tokensWithDocs: { token: string; docId: string }[],
  payload: {
    reliefRequestId: string;
    distanceKm: number;
    etaMin: number;
    reason: string;
    severity: string;
    offerExpiresAt: string;
    wave: number;
  }
): Promise<{ success: boolean; sentCount: number }> {
  if (!tokensWithDocs || tokensWithDocs.length === 0) {
    return { success: false, sentCount: 0 };
  }

  const tokens = tokensWithDocs.map((t) => t.token);
  const tokenDocMap: { [token: string]: string } = {};
  tokensWithDocs.forEach((t) => {
    tokenDocMap[t.token] = t.docId;
  });

  const message: admin.messaging.MulticastMessage = {
    tokens,
    data: {
      type: 'relief_request',
      reliefRequestId: payload.reliefRequestId,
      distanceKm: String(payload.distanceKm),
      etaMin: String(payload.etaMin),
      reason: payload.reason,
      severity: payload.severity,
      offerExpiresAt: payload.offerExpiresAt,
      wave: String(payload.wave),
    },
    android: {
      priority: 'high',
      ttl: 60 * 1000,
    },
    apns: {
      headers: {
        'apns-priority': '10',
        'apns-push-type': 'alert',
        'apns-expiration': String(Math.floor(Date.now() / 1000) + 60),
      },
      payload: {
        aps: {
          alert: {
            title: 'Emergency Relief Request 🚨',
            body: `Disabled ambulance ${payload.distanceKm} km away needs backup (${payload.reason}).`,
          },
          sound: 'default',
          'interruption-level': 'time-sensitive',
        },
      },
    },
  };

  try {
    const res = await messaging.sendEachForMulticast(message);
    const deadTokenDocIds: string[] = [];

    res.responses.forEach((resp, idx) => {
      if (
        !resp.success &&
        (resp.error?.code === 'messaging/registration-token-not-registered' ||
          resp.error?.code === 'messaging/invalid-registration-token')
      ) {
        const deadToken = tokens[idx];
        const docId = tokenDocMap[deadToken];
        if (docId) deadTokenDocIds.push(docId);
      }
    });

    if (deadTokenDocIds.length > 0) {
      const batch = db.batch();
      deadTokenDocIds.forEach((dId) => {
        batch.delete(
          db
            .collection('ambulances')
            .doc(candidateUid)
            .collection('devices')
            .doc(dId)
        );
      });
      await batch.commit();
    }

    return { success: true, sentCount: res.successCount };
  } catch (err) {
    console.error(`[fcmAlertService] Failed to send relief_request to crew ${candidateUid}:`, err);
    return { success: false, sentCount: 0 };
  }
}

/**
 * Phase 12B: Send data-only high-priority relief_cancel alert to candidate crews
 * whose offers became taken, expired, or cancelled.
 */
export async function sendReliefCancelAlert(
  db: FirebaseFirestore.Firestore,
  messaging: admin.messaging.Messaging,
  candidateUids: string[],
  reliefRequestId: string,
  reason: 'taken' | 'expired' | 'cancelled' | 'aborted' = 'taken'
): Promise<void> {
  if (!candidateUids || candidateUids.length === 0) return;

  const allTokens: string[] = [];

  for (const uid of candidateUids) {
    const snap = await db
      .collection('ambulances')
      .doc(uid)
      .collection('devices')
      .where('loggedIn', '==', true)
      .get();

    snap.forEach((doc) => {
      const t = doc.data().token;
      if (t && typeof t === 'string') {
        allTokens.push(t);
      }
    });
  }

  if (allTokens.length === 0) return;

  const message: admin.messaging.MulticastMessage = {
    tokens: allTokens,
    data: {
      type: 'relief_cancel',
      reliefRequestId,
      reason,
    },
    android: {
      priority: 'high',
      ttl: 60 * 1000,
    },
  };

  try {
    await messaging.sendEachForMulticast(message);
  } catch (err) {
    console.error('[fcmAlertService] Failed to send relief_cancel alert:', err);
  }
}

/**
 * Sends a high-priority normal notification (not siren) to nurse station devices
 * informing them of the relief ambulance handover.
 */
export async function sendHandoverNurseAlert(
  db: FirebaseFirestore.Firestore,
  messaging: admin.messaging.Messaging,
  hospitalId: string,
  data: {
    requestId: string;
    newAmbulanceId: string;
    fromAmbulanceId: string;
    vehicleNumber: string;
  }
): Promise<void> {
  if (!hospitalId) return;

  const devicesSnap = await db
    .collection('hospitals')
    .doc(hospitalId)
    .collection('devices')
    .where('loggedIn', '==', true)
    .get();

  if (devicesSnap.empty) return;

  const tokens: string[] = [];
  devicesSnap.forEach((doc) => {
    const t = doc.data().token;
    if (t && typeof t === 'string') tokens.push(t);
  });

  if (tokens.length === 0) return;

  const message: admin.messaging.MulticastMessage = {
    tokens,
    notification: {
      title: 'Ambulance Changed 🔄',
      body: `Ambulance changed: patient now arriving in ${data.newAmbulanceId} (${data.vehicleNumber}).`,
    },
    data: {
      type: 'ambulance_handover',
      requestId: data.requestId,
      hospitalId,
      newAmbulanceId: data.newAmbulanceId,
      fromAmbulanceId: data.fromAmbulanceId,
    },
    android: {
      priority: 'high',
      notification: {
        channelId: 'bedlink_emergency_alerts',
        priority: 'high',
        defaultSound: true,
      },
    },
  };

  try {
    await messaging.sendEachForMulticast(message);
  } catch (err) {
    console.error('[fcmAlertService] Failed to send handover notification to nurse:', err);
  }
}

