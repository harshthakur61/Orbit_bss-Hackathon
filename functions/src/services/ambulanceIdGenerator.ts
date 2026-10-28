import { Firestore } from 'firebase-admin/firestore';

/**
 * Generates a collision-safe Ambulance ID formatted as BL-AMB-XXXXXX
 * Uses a Firestore atomic transaction on the sequence counter.
 */
export async function generateUniqueAmbulanceId(db: Firestore): Promise<string> {
  const counterRef = db.collection('counters').doc('ambulances');

  return db.runTransaction(async (transaction) => {
    const snap = await transaction.get(counterRef);
    let nextSeq = 100001;

    if (snap.exists) {
      const current = snap.data()?.lastSeq;
      if (typeof current === 'number') {
        nextSeq = current + 1;
      }
    }

    transaction.set(counterRef, { lastSeq: nextSeq }, { merge: true });
    return `BL-AMB-${nextSeq}`;
  });
}
