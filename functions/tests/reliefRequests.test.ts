import {
  createReliefRequestHandler,
  respondToReliefRequestHandler,
  advanceReliefWaveHandler,
  cancelReliefRequestHandler,
} from '../src/services/reliefService';
import {
  calculateHaversineDistanceKm,
  isTierSufficient,
  normalizeAis125Tier,
} from '../src/config/reliefConfig';

// -------------------------------------------------------------
// In-Memory Mock Firestore for Transactional & Subcollection Testing
// -------------------------------------------------------------

class MockDocSnapshot {
  public readonly ref: MockDocRef;
  constructor(
    public readonly id: string,
    public readonly exists: boolean,
    private readonly _data: any,
    path?: string,
    store?: Map<string, any>
  ) {
    this.ref = new MockDocRef(id, path || id, store || new Map());
  }

  data(): any {
    return this._data ? JSON.parse(JSON.stringify(this._data)) : undefined;
  }
}

class MockDocRef {
  constructor(
    public readonly id: string,
    public readonly path: string,
    private readonly store: Map<string, any>
  ) {}

  collection(name: string): MockCollectionRef {
    return new MockCollectionRef(`${this.path}/${name}`, this.store);
  }

  async get(): Promise<MockDocSnapshot> {
    const data = this.store.get(this.path);
    return new MockDocSnapshot(this.id, !!data, data, this.path, this.store);
  }

  async set(data: any, options?: { merge?: boolean }): Promise<void> {
    if (options?.merge) {
      const existing = this.store.get(this.path) || {};
      this.store.set(this.path, { ...existing, ...JSON.parse(JSON.stringify(data)) });
    } else {
      this.store.set(this.path, JSON.parse(JSON.stringify(data)));
    }
  }

  async update(data: any): Promise<void> {
    const existing = this.store.get(this.path) || {};
    this.store.set(this.path, { ...existing, ...JSON.parse(JSON.stringify(data)) });
  }

  async delete(): Promise<void> {
    this.store.delete(this.path);
  }
}

class MockQuery {
  constructor(
    private readonly name: string,
    private readonly store: Map<string, any>,
    private readonly filters: [string, any][] = []
  ) {}

  where(field: string, op: string, value: any): MockQuery {
    return new MockQuery(this.name, this.store, [...this.filters, [field, value]]);
  }

  limit(_n: number): MockQuery {
    return this;
  }

  async get(): Promise<{
    empty: boolean;
    docs: MockDocSnapshot[];
    forEach: (cb: (doc: MockDocSnapshot) => void) => void;
  }> {
    const docs: MockDocSnapshot[] = [];
    for (const [path, data] of this.store.entries()) {
      if (path.startsWith(`${this.name}/`)) {
        const sub = path.substring(this.name.length + 1);
        if (sub.includes('/')) continue; // nested subcollection document, skip

        let matches = true;
        for (const [f, v] of this.filters) {
          if (data[f] !== v) {
            matches = false;
            break;
          }
        }
        if (matches) {
          docs.push(new MockDocSnapshot(sub, true, data, path, this.store));
        }
      }
    }
    return {
      empty: docs.length === 0,
      docs,
      forEach: (cb: (doc: MockDocSnapshot) => void) => docs.forEach(cb),
    };
  }
}

class MockCollectionRef {
  constructor(
    public readonly name: string,
    private readonly store: Map<string, any>
  ) {}

  doc(id?: string): MockDocRef {
    const docId = id || `auto_${Math.random().toString(36).substring(2, 9)}`;
    return new MockDocRef(docId, `${this.name}/${docId}`, this.store);
  }

  where(field: string, op: string, value: any): MockQuery {
    return new MockQuery(this.name, this.store, [[field, value]]);
  }

  async get() {
    return new MockQuery(this.name, this.store, []).get();
  }
}

class MockFirestore {
  public store = new Map<string, any>();
  private txMutex = Promise.resolve();

  collection(name: string): MockCollectionRef {
    return new MockCollectionRef(name, this.store);
  }

  batch() {
    const ops: Array<() => void> = [];
    return {
      set: (ref: any, data: any, options?: any) => {
        ops.push(() => {
          if (options?.merge) {
            const ex = this.store.get(ref.path) || {};
            this.store.set(ref.path, { ...ex, ...JSON.parse(JSON.stringify(data)) });
          } else {
            this.store.set(ref.path, JSON.parse(JSON.stringify(data)));
          }
        });
      },
      update: (ref: any, data: any) => {
        ops.push(() => {
          const ex = this.store.get(ref.path) || {};
          this.store.set(ref.path, { ...ex, ...JSON.parse(JSON.stringify(data)) });
        });
      },
      delete: (ref: any) => {
        ops.push(() => {
          this.store.delete(ref.path);
        });
      },
      commit: async () => {
        for (const op of ops) op();
      },
    };
  }

  async runTransaction<T>(updateFunction: (transaction: any) => Promise<T>): Promise<T> {
    const run = async () => {
      const staged = new Map(this.store);

      const transaction = {
        get: async (ref: MockDocRef) => {
          const data = staged.get(ref.path);
          return new MockDocSnapshot(ref.id, !!data, data, ref.path, staged);
        },
        set: (ref: MockDocRef, data: any, options?: { merge?: boolean }) => {
          if (options?.merge) {
            const ex = staged.get(ref.path) || {};
            staged.set(ref.path, { ...ex, ...JSON.parse(JSON.stringify(data)) });
          } else {
            staged.set(ref.path, JSON.parse(JSON.stringify(data)));
          }
        },
        update: (ref: MockDocRef, data: any) => {
          const ex = staged.get(ref.path) || {};
          staged.set(ref.path, { ...ex, ...JSON.parse(JSON.stringify(data)) });
        },
      };

      const result = await updateFunction(transaction);
      this.store = staged;
      return result;
    };

    const next = this.txMutex.then(run, run);
    this.txMutex = next.then(() => {}, () => {});
    return next;
  }
}

// Mock Messaging
const mockMessaging: any = {
  sendEachForMulticast: jest.fn().mockResolvedValue({
    successCount: 1,
    failureCount: 0,
    responses: [{ success: true }],
  }),
};

describe('Phase 12B – Disabled Emergency Relief Engine Tests', () => {
  let db: MockFirestore;

  beforeEach(() => {
    db = new MockFirestore();
    jest.clearAllMocks();
  });

  // 1. Non-owner or unverified crew cannot create relief request
  test('non-owner or unverified crew cannot create relief request', async () => {
    // Seed unverified ambulance
    db.store.set('ambulances/crew_unverified', {
      verificationStatus: 'PENDING',
    });

    await expect(
      createReliefRequestHandler(db as any, mockMessaging, 'crew_unverified', {
        originalRequestId: 'req_123',
        reason: 'breakdown',
      })
    ).rejects.toThrow('Caller must be a verified ambulance crew member.');

    // Seed verified ambulance but different owner of the request
    db.store.set('ambulances/crew_verified', {
      verificationStatus: 'VERIFIED',
      vehicleNumber: 'MH02AB1234',
    });

    db.store.set('requests/req_other_owner', {
      crewUid: 'different_crew_owner',
      status: 'accepted',
    });

    await expect(
      createReliefRequestHandler(db as any, mockMessaging, 'crew_verified', {
        originalRequestId: 'req_other_owner',
        reason: 'breakdown',
      })
    ).rejects.toThrow('Caller does not own this emergency request.');

    // Request not in accepted or en_route status
    db.store.set('requests/req_not_accepted', {
      crewUid: 'crew_verified',
      status: 'offered',
    });

    await expect(
      createReliefRequestHandler(db as any, mockMessaging, 'crew_verified', {
        originalRequestId: 'req_not_accepted',
        reason: 'breakdown',
      })
    ).rejects.toThrow('Relief request can only be created for an accepted active trip.');
  });

  // 2. Stale presence (>120s) and inaccurate location (>100m) excluded
  test('stale presence (>120s) and inaccurate location (>100m) excluded from candidates', async () => {
    const disabledLat = 19.076;
    const disabledLng = 72.8777;

    db.store.set('ambulances/crew_owner', {
      verificationStatus: 'VERIFIED',
      ais125Tier: 'Type B',
    });

    db.store.set('requests/req_active', {
      crewUid: 'crew_owner',
      status: 'accepted',
      patientLat: disabledLat,
      patientLng: disabledLng,
      needs: ['ICU'],
      severity: 'critical',
    });

    // Stale candidate (updated 200s ago)
    const staleDate = new Date(Date.now() - 200 * 1000);
    db.store.set('crewPresence/candidate_stale', {
      status: 'AVAILABLE',
      lat: 19.08,
      lng: 72.88,
      accuracyMeters: 20,
      updatedAt: staleDate,
      ais125Tier: 'Type B',
    });
    db.store.set('ambulances/candidate_stale/devices/dev1', {
      token: 'fcm_stale',
      loggedIn: true,
    });

    // Inaccurate candidate (accuracy 150m > 100m)
    db.store.set('crewPresence/candidate_inaccurate', {
      status: 'AVAILABLE',
      lat: 19.08,
      lng: 72.88,
      accuracyMeters: 150,
      updatedAt: new Date(),
      ais125Tier: 'Type B',
    });
    db.store.set('ambulances/candidate_inaccurate/devices/dev2', {
      token: 'fcm_inacc',
      loggedIn: true,
    });

    // Fresh & accurate candidate (1.2 km away)
    db.store.set('crewPresence/candidate_valid', {
      ambulanceId: 'BL-AMB-VALID',
      status: 'AVAILABLE',
      lat: 19.082,
      lng: 72.882,
      accuracyMeters: 15,
      updatedAt: new Date(),
      ais125Tier: 'Type B',
    });
    db.store.set('ambulances/candidate_valid/devices/dev3', {
      token: 'fcm_valid',
      loggedIn: true,
    });

    const res = await createReliefRequestHandler(db as any, mockMessaging, 'crew_owner', {
      originalRequestId: 'req_active',
      reason: 'breakdown',
    });

    expect(res.success).toBe(true);
    expect(res.candidateCount).toBe(1);

    // Verify valid candidate was offered
    const offerDoc = db.store.get(`reliefRequests/${res.reliefRequestId}/offers/candidate_valid`);
    expect(offerDoc).toBeDefined();
    expect(offerDoc.status).toBe('pending');
    expect(offerDoc.ambulanceId).toBe('BL-AMB-VALID');

    // Stale and inaccurate were not offered
    expect(db.store.get(`reliefRequests/${res.reliefRequestId}/offers/candidate_stale`)).toBeUndefined();
    expect(
      db.store.get(`reliefRequests/${res.reliefRequestId}/offers/candidate_inaccurate`)
    ).toBeUndefined();
  });

  // 3. AIS-125 Tier filter: Candidate tier must be >= disabled ambulance tier
  test('tier filter: candidate tier must be >= disabled ambulance tier', () => {
    // Type C requires Type C or Type D; rejects Type A or Type B
    expect(isTierSufficient('Type C', 'Type C')).toBe(true);
    expect(isTierSufficient('Type D', 'Type C')).toBe(true);
    expect(isTierSufficient('Type B', 'Type C')).toBe(false);
    expect(isTierSufficient('Type A', 'Type C')).toBe(false);

    // Type B accepts Type B, Type C, Type D; rejects Type A
    expect(isTierSufficient('Type B', 'Type B')).toBe(true);
    expect(isTierSufficient('Type C', 'Type B')).toBe(true);
    expect(isTierSufficient('Type A', 'Type B')).toBe(false);

    // Normalizer tests
    expect(normalizeAis125Tier('Type C - Mobile Intensive Care Unit')).toBe(3);
    expect(normalizeAis125Tier('TYPE_D')).toBe(4);
    expect(normalizeAis125Tier('Type B')).toBe(2);
    expect(normalizeAis125Tier('Type A')).toBe(1);
    expect(normalizeAis125Tier(null)).toBe(2);
  });

  // 4. Wave expansion: Wave 0 -> Wave 1 -> Wave 2 -> no_ambulance
  test('wave expansion: expands wave radius when 0 candidates found in inner radius', async () => {
    const centerLat = 19.076;
    const centerLng = 72.8777;

    db.store.set('ambulances/crew_wave_owner', {
      verificationStatus: 'VERIFIED',
      ais125Tier: 'Type B',
    });

    db.store.set('requests/req_wave', {
      crewUid: 'crew_wave_owner',
      status: 'accepted',
      patientLat: centerLat,
      patientLng: centerLng,
      needs: ['ICU'],
    });

    // Candidate 8 km away (outside wave 0 [5km], inside wave 1 [10km])
    // 1 deg lat is ~111 km, 0.072 deg lat is ~8.0 km
    const farLat = centerLat + 0.072;
    db.store.set('crewPresence/candidate_far', {
      ambulanceId: 'BL-AMB-FAR',
      status: 'AVAILABLE',
      lat: farLat,
      lng: centerLng,
      accuracyMeters: 20,
      updatedAt: new Date(),
      ais125Tier: 'Type B',
    });
    db.store.set('ambulances/candidate_far/devices/dev_far', {
      token: 'fcm_far',
      loggedIn: true,
    });

    const res = await createReliefRequestHandler(db as any, mockMessaging, 'crew_wave_owner', {
      originalRequestId: 'req_wave',
      reason: 'accident',
    });

    expect(res.success).toBe(true);
    expect(res.wave).toBe(1); // Auto-expanded to wave 1!
    expect(res.radiusKm).toBe(10);
    expect(res.candidateCount).toBe(1);
  });

  // 5. Exhausting all waves with zero candidates sets status to no_ambulance
  test('exhausting all waves with zero candidates sets status to no_ambulance', async () => {
    db.store.set('ambulances/crew_alone', {
      verificationStatus: 'VERIFIED',
      ais125Tier: 'Type B',
    });

    db.store.set('requests/req_alone', {
      crewUid: 'crew_alone',
      status: 'accepted',
      patientLat: 19.076,
      patientLng: 72.8777,
    });

    // No candidates in crewPresence
    const res = await createReliefRequestHandler(db as any, mockMessaging, 'crew_alone', {
      originalRequestId: 'req_alone',
      reason: 'fuel',
    });

    expect(res.success).toBe(true);
    expect(res.status).toBe('no_ambulance');
    expect(res.candidateCount).toBe(0);

    const doc = db.store.get(`reliefRequests/${res.reliefRequestId}`);
    expect(doc.status).toBe('no_ambulance');

    const reqDoc = db.store.get('requests/req_alone');
    expect(reqDoc.reliefState).toBe('completed');
  });

  // 6. Exactly-one-winner under simultaneous accepts (transaction locking)
  test('simultaneous accepts: exactly one crew wins the offer and other is marked taken', async () => {
    const reliefRequestId = 'relief_concurrent_1';

    db.store.set(`reliefRequests/${reliefRequestId}`, {
      status: 'searching',
      originalRequestId: 'req_orig_1',
      offerExpiresAt: new Date(Date.now() + 60000),
    });

    db.store.set('ambulances/candidate_A', {
      ambulanceId: 'BL-AMB-A',
      driverLegalName: 'Driver A',
      ais125Tier: 'Type B',
    });
    db.store.set(`reliefRequests/${reliefRequestId}/offers/candidate_A`, {
      status: 'pending',
      ambulanceId: 'BL-AMB-A',
    });

    db.store.set('ambulances/candidate_B', {
      ambulanceId: 'BL-AMB-B',
      driverLegalName: 'Driver B',
      ais125Tier: 'Type B',
    });
    db.store.set(`reliefRequests/${reliefRequestId}/offers/candidate_B`, {
      status: 'pending',
      ambulanceId: 'BL-AMB-B',
    });

    // Execute concurrently
    const [resA, resB] = await Promise.all([
      respondToReliefRequestHandler(db as any, mockMessaging, 'candidate_A', {
        reliefRequestId,
        action: 'accept',
      }),
      respondToReliefRequestHandler(db as any, mockMessaging, 'candidate_B', {
        reliefRequestId,
        action: 'accept',
      }),
    ]);

    const results = [resA, resB];
    const acceptedCount = results.filter((r) => r.code === 'ACCEPTED').length;
    const takenCount = results.filter((r) => r.code === 'ALREADY_TAKEN').length;

    expect(acceptedCount).toBe(1);
    expect(takenCount).toBe(1);

    const reliefDoc = db.store.get(`reliefRequests/${reliefRequestId}`);
    expect(reliefDoc.status).toBe('accepted');
    expect(['candidate_A', 'candidate_B']).toContain(reliefDoc.acceptedByUid);

    // Winner's presence is BUSY
    const winningUid = reliefDoc.acceptedByUid;
    const winningPresence = db.store.get(`crewPresence/${winningUid}`);
    expect(winningPresence.status).toBe('BUSY');
  });

  // 7. Expiry validation on accept
  test('cannot accept an expired relief offer', async () => {
    const reliefRequestId = 'relief_expired_1';

    // Offer expired 10 seconds ago
    db.store.set(`reliefRequests/${reliefRequestId}`, {
      status: 'searching',
      originalRequestId: 'req_orig_2',
      offerExpiresAt: new Date(Date.now() - 10000),
    });

    db.store.set('ambulances/candidate_late', {
      ambulanceId: 'BL-AMB-LATE',
      driverLegalName: 'Driver Late',
      ais125Tier: 'Type B',
    });

    db.store.set(`reliefRequests/${reliefRequestId}/offers/candidate_late`, {
      status: 'pending',
      ambulanceId: 'BL-AMB-LATE',
    });

    const res = await respondToReliefRequestHandler(db as any, mockMessaging, 'candidate_late', {
      reliefRequestId,
      action: 'accept',
    });

    expect(res.success).toBe(false);
    expect(res.code).toBe('OFFER_EXPIRED');
  });

  // 8. advanceReliefWave expires pending offers and advances to next wave
  test('advanceReliefWave validates expiry and advances to wave 1', async () => {
    const reliefRequestId = 'relief_adv_1';
    const requesterUid = 'crew_adv_req';

    db.store.set(`reliefRequests/${reliefRequestId}`, {
      requesterUid,
      status: 'searching',
      wave: 0,
      radiusKm: 5,
      disabledLocation: { lat: 19.076, lng: 72.8777 },
      requesterAmbulance: { ais125Tier: 'Type B' },
      reason: 'breakdown',
      severity: 'serious',
      // Offer expired 5s ago
      offerExpiresAt: new Date(Date.now() - 5000),
    });

    db.store.set(`reliefRequests/${reliefRequestId}/offers/cand_1`, {
      status: 'pending',
    });

    // Candidate in wave 1 (8km away)
    db.store.set('crewPresence/cand_w1', {
      ambulanceId: 'BL-AMB-W1',
      status: 'AVAILABLE',
      lat: 19.076 + 0.072,
      lng: 72.8777,
      accuracyMeters: 20,
      updatedAt: new Date(),
      ais125Tier: 'Type B',
    });
    db.store.set('ambulances/cand_w1/devices/dev', {
      token: 'fcm_w1',
      loggedIn: true,
    });

    const res = await advanceReliefWaveHandler(db as any, mockMessaging, requesterUid, {
      reliefRequestId,
    });

    expect(res.success).toBe(true);
    expect(res.status).toBe('searching');
    expect(res.wave).toBe(1);
    expect(res.radiusKm).toBe(10);

    // Prior offer in wave 0 was expired
    const oldOffer = db.store.get(`reliefRequests/${reliefRequestId}/offers/cand_1`);
    expect(oldOffer.status).toBe('expired');

    // New offer created for cand_w1
    const newOffer = db.store.get(`reliefRequests/${reliefRequestId}/offers/cand_w1`);
    expect(newOffer).toBeDefined();
    expect(newOffer.status).toBe('pending');
  });

  // 9. Cancel by requester restores accepted crew status
  test('requester cancellation restores accepted relief crew status', async () => {
    const reliefRequestId = 'relief_cancel_1';
    const requesterUid = 'crew_cancel_requester';
    const acceptedByUid = 'crew_relief_hero';

    db.store.set(`reliefRequests/${reliefRequestId}`, {
      requesterUid,
      status: 'accepted',
      acceptedByUid,
      originalRequestId: 'req_cancel_orig',
    });

    db.store.set(`crewPresence/${acceptedByUid}`, {
      status: 'BUSY',
    });

    db.store.set('requests/req_cancel_orig', {
      reliefState: 'accepted',
      reliefRequestId,
    });

    const res = await cancelReliefRequestHandler(db as any, mockMessaging, requesterUid, {
      reliefRequestId,
    });

    expect(res.success).toBe(true);
    expect(res.status).toBe('cancelled');

    // Hero crew status restored back to AVAILABLE
    const presenceDoc = db.store.get(`crewPresence/${acceptedByUid}`);
    expect(presenceDoc.status).toBe('AVAILABLE');

    // Original request relief state reset to null
    const reqDoc = db.store.get('requests/req_cancel_orig');
    expect(reqDoc.reliefState).toBeNull();
  });

  // 10. Abort by accepted relief crew returns request to searching
  test('accepted relief crew aborting mission returns request to searching', async () => {
    const reliefRequestId = 'relief_abort_1';
    const requesterUid = 'crew_waiting';
    const acceptedByUid = 'crew_aborted';

    db.store.set(`reliefRequests/${reliefRequestId}`, {
      requesterUid,
      status: 'accepted',
      acceptedByUid,
      originalRequestId: 'req_abort_orig',
    });

    db.store.set(`crewPresence/${acceptedByUid}`, {
      status: 'BUSY',
    });

    db.store.set(`reliefRequests/${reliefRequestId}/offers/${acceptedByUid}`, {
      status: 'accepted',
    });

    const res = await cancelReliefRequestHandler(db as any, mockMessaging, acceptedByUid, {
      reliefRequestId,
    });

    expect(res.success).toBe(true);
    expect(res.status).toBe('searching');

    // Relief request returned to searching with acceptedBy cleared
    const reliefDoc = db.store.get(`reliefRequests/${reliefRequestId}`);
    expect(reliefDoc.status).toBe('searching');
    expect(reliefDoc.acceptedByUid).toBeNull();

    // Aborting crew presence restored to AVAILABLE
    const presenceDoc = db.store.get(`crewPresence/${acceptedByUid}`);
    expect(presenceDoc.status).toBe('AVAILABLE');

    // Aborting crew's offer marked rejected
    const offerDoc = db.store.get(`reliefRequests/${reliefRequestId}/offers/${acceptedByUid}`);
    expect(offerDoc.status).toBe('rejected');
    expect(offerDoc.reason).toBe('vehicle_issue');
  });

  // 11. Distance calculation accuracy
  test('calculateHaversineDistanceKm computes realistic distance', () => {
    // Mumbai Lilavati Hospital (19.0519, 72.8290) to Bandra Station (19.0544, 72.8402) ~1.2 km
    const dist = calculateHaversineDistanceKm(19.0519, 72.829, 19.0544, 72.8402);
    expect(dist).toBeGreaterThan(1.0);
    expect(dist).toBeLessThan(1.5);
  });
});
