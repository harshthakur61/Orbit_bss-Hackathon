import * as crypto from 'crypto';
import {
  createAppointmentOrderHandler,
  getClinicDaySlotsHandler,
  getRevenueSnapshotHandler,
  handleRazorpayWebhook,
  isDeterministicDemoSlot,
  releaseAppointmentHoldHandler,
  resetDemoBookingsHandler,
  seedDemoBookingsHandler,
  verifyAppointmentPaymentHandler,
} from '../src/services/appointmentService';
import { RazorpayClient } from '../src/services/razorpayClient';
import {
  generateDaySlotIntervals,
  getKolkataComponents,
  parseKolkataDateTime,
} from '../src/utils/kolkataTime';

// -------------------------------------------------------------
// In-Memory Deterministic Mock Firestore for Transactional Testing
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
    const existing = this.store.get(this.path);
    if (!existing) throw new Error(`Document ${this.path} does not exist`);
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

  limit(n: number): MockQuery {
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
        const id = path.substring(this.name.length + 1);
        let matches = true;
        for (const [f, v] of this.filters) {
          if (data[f] !== v) {
            matches = false;
            break;
          }
        }
        if (matches) {
          docs.push(new MockDocSnapshot(id, true, data, path, this.store));
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

  doc(id: string): MockDocRef {
    return new MockDocRef(id, `${this.name}/${id}`, this.store);
  }

  where(field: string, op: string, value: any): MockQuery {
    return new MockQuery(this.name, this.store, [[field, value]]);
  }

  async get(): Promise<{
    empty: boolean;
    docs: MockDocSnapshot[];
    forEach: (cb: (doc: MockDocSnapshot) => void) => void;
  }> {
    return new MockQuery(this.name, this.store, []).get();
  }
}

class MockFirestore {
  public store = new Map<string, any>();

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
    const staged = new Map(this.store);

    const transaction = {
      get: async (ref: MockDocRef) => {
        const data = staged.get(ref.path);
        return new MockDocSnapshot(ref.id, !!data, data);
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
        const ex = staged.get(ref.path);
        if (!ex) throw new Error(`Document ${ref.path} does not exist`);
        staged.set(ref.path, { ...ex, ...JSON.parse(JSON.stringify(data)) });
      },
      delete: (ref: MockDocRef) => {
        staged.delete(ref.path);
      },
    };

    const result = await updateFunction(transaction);
    // Commit transaction to store
    for (const [k, v] of staged.entries()) {
      this.store.set(k, v);
    }
    for (const k of this.store.keys()) {
      if (!staged.has(k)) {
        this.store.delete(k);
      }
    }
    return result;
  }
}

describe('Phase 11A – Clinic & Lab Appointment Booking Tests', () => {
  let db: MockFirestore;
  let mockRazorpay: RazorpayClient;
  const testKeyId = 'rzp_test_1234567890';
  const testKeySecret = 'test_secret_key_abcdef';
  const testWebhookSecret = 'test_webhook_secret_xyz';

  beforeEach(() => {
    db = new MockFirestore();
    process.env.MOCK_RAZORPAY = 'true';

    mockRazorpay = new RazorpayClient({
      keyId: testKeyId,
      keySecret: testKeySecret,
      webhookSecret: testWebhookSecret,
    });

    // Seed test clinic
    db.store.set('clinics/test_clinic_1', {
      name: 'Test Family Clinic',
      type: 'clinic',
      openTime: '08:00',
      closeTime: '20:00',
      slotDurationMin: 30,
      bookingFeeRupees: 79,
      weeklyOffDays: [7], // Sunday closed
    });

    // Seed test lab
    db.store.set('clinics/test_lab_1', {
      name: 'Test Pathology Lab',
      type: 'pathology_lab',
      openTime: '07:00',
      closeTime: '21:00',
      slotDurationMin: 30,
      bookingFeeRupees: 49,
      weeklyOffDays: [],
    });
  });

  afterAll(() => {
    delete process.env.MOCK_RAZORPAY;
  });

  // 1. Asia/Kolkata timezone math and slot generation
  test('Asia/Kolkata timezone math and interval generation', () => {
    const slots = generateDaySlotIntervals('08:00', '10:00', 30);
    expect(slots).toEqual(['08:00', '08:30', '09:00', '09:30']);

    // Parse Kolkata date
    const dt = parseKolkataDateTime('20261030', '10:00');
    const comp = getKolkataComponents(dt);
    expect(comp.dateKey).toBe('20261030');
    expect(comp.timeFormatted).toBe('10:00');
    expect(comp.timeKey).toBe('1000');
  });

  // 2. getClinicDaySlots returns slot grid with status (free/booked/past)
  test('getClinicDaySlots returns slot grid correctly without exposing slots collection', async () => {
    // Seed an already booked slot on future date
    db.store.set('slots/test_clinic_1_20261030_1000', {
      clinicId: 'test_clinic_1',
      dateKey: '20261030',
      status: 'booked',
    });

    const res = await getClinicDaySlotsHandler(db as any, {
      clinicId: 'test_clinic_1',
      dateKey: '20261030',
    });

    expect(res.clinicId).toBe('test_clinic_1');
    expect(res.dateKey).toBe('20261030');
    expect(res.slots.length).toBeGreaterThan(0);

    const bookedSlot = res.slots.find((s) => s.time === '10:00');
    expect(bookedSlot?.status).toBe('booked');

    const freeSlot = res.slots.find((s) => s.time === '11:00');
    expect(freeSlot?.status).toBe('free');
  });

  // 3. createAppointmentOrder ignores client-supplied amount & uses server fee
  test('createAppointmentOrder ignores any client amount and enforces server fee', async () => {
    // 2 days in the future at 10:00 AM Kolkata
    const targetDate = new Date(Date.now() + 2 * 24 * 60 * 60 * 1000);
    const kolkata = getKolkataComponents(targetDate);
    const slotDate = parseKolkataDateTime(kolkata.dateKey, '10:00');

    const result = await createAppointmentOrderHandler(
      db as any,
      'patient_alice',
      {
        clinicId: 'test_clinic_1',
        startTime: slotDate.toISOString(),
        patientName: 'Alice Kumar',
        patientPhone: '+91 9876543210',
        // Client maliciously supplies 1 rupee amount
        ...({ amount: 1 } as any),
      },
      mockRazorpay
    );

    expect(result.appointmentId).toMatch(/^BLA-\d{6}$/);
    // Server clinic fee is 79 Rs => 7900 paise
    expect(result.amountPaise).toBe(7900);

    // Verify appointment was written to appointments collection
    const appDoc = db.store.get(`appointments/${result.appointmentId}`);
    expect(appDoc).toBeDefined();
    expect(appDoc.amountPaise).toBe(7900);
    expect(appDoc.status).toBe('pending_payment');
  });

  // 4. Concurrent bookings of the same slot: exactly one wins
  test('concurrent bookings of the same slot: exactly one wins', async () => {
    const targetDate = new Date(Date.now() + 2 * 24 * 60 * 60 * 1000);
    const kolkata = getKolkataComponents(targetDate);
    const slotDate = parseKolkataDateTime(kolkata.dateKey, '11:00');

    // First patient books slot
    const order1 = await createAppointmentOrderHandler(
      db as any,
      'patient_alice',
      {
        clinicId: 'test_clinic_1',
        startTime: slotDate.toISOString(),
        patientName: 'Alice Kumar',
        patientPhone: '+91 9876543210',
      },
      mockRazorpay
    );
    expect(order1.appointmentId).toBeDefined();

    // Second patient attempts to book the identical slot simultaneously
    await expect(
      createAppointmentOrderHandler(
        db as any,
        'patient_bob',
        {
          clinicId: 'test_clinic_1',
          startTime: slotDate.toISOString(),
          patientName: 'Bob Singh',
          patientPhone: '+91 9123456780',
        },
        mockRazorpay
      )
    ).rejects.toThrow(/temporary hold|already booked/i);
  });

  // 5. Expired hold is re-bookable by another patient
  test('expired hold is re-bookable by another patient', async () => {
    const targetDate = new Date(Date.now() + 2 * 24 * 60 * 60 * 1000);
    const kolkata = getKolkataComponents(targetDate);
    const slotDate = parseKolkataDateTime(kolkata.dateKey, '12:00');
    const slotId = `test_clinic_1_${kolkata.dateKey}_1200`;

    // Seed an expired hold (expired 10 minutes ago)
    db.store.set(`slots/${slotId}`, {
      clinicId: 'test_clinic_1',
      dateKey: kolkata.dateKey,
      status: 'held',
      holdExpiresAt: { toMillis: () => Date.now() - 10 * 60 * 1000 },
      appointmentId: 'BLA-OLD123',
    });

    // Patient Bob should be able to claim the expired slot
    const order2 = await createAppointmentOrderHandler(
      db as any,
      'patient_bob',
      {
        clinicId: 'test_clinic_1',
        startTime: slotDate.toISOString(),
        patientName: 'Bob Singh',
        patientPhone: '+91 9123456780',
      },
      mockRazorpay
    );

    expect(order2.appointmentId).toBeDefined();
    const updatedSlot = db.store.get(`slots/${slotId}`);
    expect(updatedSlot.appointmentId).toBe(order2.appointmentId);
  });

  // 6. Bad Razorpay payment signature rejected
  test('verifyAppointmentPayment rejects invalid or tampered signature', async () => {
    const appointmentId = 'BLA-998877';
    db.store.set(`appointments/${appointmentId}`, {
      patientUid: 'patient_alice',
      slotId: 'test_clinic_1_20261030_1000',
      status: 'pending_payment',
      amountPaise: 7900,
    });

    await expect(
      verifyAppointmentPaymentHandler(
        db as any,
        {
          appointmentId,
          razorpayOrderId: 'order_123',
          razorpayPaymentId: 'pay_123',
          razorpaySignature: 'invalid_bad_signature_hex_00000000000000000000000000000000',
        },
        mockRazorpay
      )
    ).rejects.toThrow(/invalid.*signature/i);
  });

  // 7. Valid signature confirms appointment and is idempotent
  test('valid signature confirms appointment and repeated calls are idempotent', async () => {
    const appointmentId = 'BLA-554433';
    const slotId = 'test_clinic_1_20261030_1400';
    const orderId = 'order_valid_123';
    const paymentId = 'pay_valid_456';

    // Compute genuine HMAC signature using test secret
    const signature = crypto
      .createHmac('sha256', testKeySecret)
      .update(`${orderId}|${paymentId}`)
      .digest('hex');

    db.store.set(`slots/${slotId}`, {
      clinicId: 'test_clinic_1',
      dateKey: '20261030',
      status: 'held',
      appointmentId,
    });

    db.store.set(`appointments/${appointmentId}`, {
      patientUid: 'patient_alice',
      clinicId: 'test_clinic_1',
      slotId,
      status: 'pending_payment',
      amountPaise: 7900,
    });

    // 1st verification call: succeeds and confirms
    const res1 = await verifyAppointmentPaymentHandler(
      db as any,
      {
        appointmentId,
        razorpayOrderId: orderId,
        razorpayPaymentId: paymentId,
        razorpaySignature: signature,
      },
      mockRazorpay
    );

    expect(res1.success).toBe(true);
    expect(res1.status).toBe('confirmed');

    const appDoc = db.store.get(`appointments/${appointmentId}`);
    expect(appDoc.status).toBe('confirmed');
    const slotDoc = db.store.get(`slots/${slotId}`);
    expect(slotDoc.status).toBe('booked');

    // 2nd verification call: idempotent returns same confirmed result
    const res2 = await verifyAppointmentPaymentHandler(
      db as any,
      {
        appointmentId,
        razorpayOrderId: orderId,
        razorpayPaymentId: paymentId,
        razorpaySignature: signature,
      },
      mockRazorpay
    );

    expect(res2.success).toBe(true);
    expect(res2.status).toBe('confirmed');
  });

  // 8. Refund on conflict: slot was taken by someone else after hold expired
  test('refund on conflict when slot was claimed by another patient', async () => {
    const appointmentId = 'BLA-LATE123';
    const slotId = 'test_clinic_1_20261030_1500';
    const orderId = 'order_late_123';
    const paymentId = 'pay_late_456';

    const signature = crypto
      .createHmac('sha256', testKeySecret)
      .update(`${orderId}|${paymentId}`)
      .digest('hex');

    // Slot was claimed and booked by BLA-WINNER
    db.store.set(`slots/${slotId}`, {
      clinicId: 'test_clinic_1',
      dateKey: '20261030',
      status: 'booked',
      appointmentId: 'BLA-WINNER',
    });

    db.store.set(`appointments/${appointmentId}`, {
      patientUid: 'patient_alice',
      clinicId: 'test_clinic_1',
      slotId,
      status: 'pending_payment',
      amountPaise: 7900,
    });

    const res = await verifyAppointmentPaymentHandler(
      db as any,
      {
        appointmentId,
        razorpayOrderId: orderId,
        razorpayPaymentId: paymentId,
        razorpaySignature: signature,
      },
      mockRazorpay
    );

    expect(res.success).toBe(false);
    expect(res.status).toBe('refunded');

    const appDoc = db.store.get(`appointments/${appointmentId}`);
    expect(appDoc.status).toBe('refunded');
    // Winning slot remains intact
    const slotDoc = db.store.get(`slots/${slotId}`);
    expect(slotDoc.appointmentId).toBe('BLA-WINNER');
  });

  // 9. releaseAppointmentHold releases held slot
  test('releaseAppointmentHold releases held slot when payment cancelled', async () => {
    const appointmentId = 'BLA-CANCEL1';
    const slotId = 'test_clinic_1_20261030_1600';

    db.store.set(`slots/${slotId}`, {
      clinicId: 'test_clinic_1',
      status: 'held',
      appointmentId,
    });

    db.store.set(`appointments/${appointmentId}`, {
      patientUid: 'patient_alice',
      slotId,
      status: 'pending_payment',
    });

    await releaseAppointmentHoldHandler(db as any, 'patient_alice', { appointmentId });

    expect(db.store.has(`slots/${slotId}`)).toBe(false);
    expect(db.store.get(`appointments/${appointmentId}`).status).toBe('payment_failed');
  });

  // 10. Webhook signature validation and handling
  test('razorpayWebhook verifies HMAC signature and confirms appointment', async () => {
    const appointmentId = 'BLA-WH999';
    const orderId = 'order_webhook_123';
    const slotId = 'test_clinic_1_20261030_1700';

    db.store.set(`slots/${slotId}`, {
      clinicId: 'test_clinic_1',
      status: 'held',
      appointmentId,
    });

    db.store.set(`appointments/${appointmentId}`, {
      patientUid: 'patient_alice',
      clinicId: 'test_clinic_1',
      slotId,
      status: 'pending_payment',
      razorpayOrderId: orderId,
      amountPaise: 7900,
    });

    const rawPayload = JSON.stringify({
      event: 'payment.captured',
      payload: {
        payment: {
          entity: {
            id: 'pay_wh_888',
            order_id: orderId,
            amount: 7900,
          },
        },
      },
    });

    const webhookSignature = crypto
      .createHmac('sha256', testWebhookSecret)
      .update(rawPayload)
      .digest('hex');

    const webhookRes = await handleRazorpayWebhook(
      db as any,
      rawPayload,
      webhookSignature,
      JSON.parse(rawPayload),
      mockRazorpay
    );

    expect(webhookRes.received).toBe(true);
    expect(webhookRes.action).toBe('confirmed_or_refunded');

    const appDoc = db.store.get(`appointments/${appointmentId}`);
    expect(appDoc.status).toBe('confirmed');
  });

  it('Phase 11C: isDeterministicDemoSlot produces consistent deterministic distribution', () => {
    const val1 = isDeterministicDemoSlot('clinic_1', '20261028', '1000');
    const val2 = isDeterministicDemoSlot('clinic_1', '20261028', '1000');
    expect(val1).toBe(val2);

    let bookedCount = 0;
    const totalSamples = 100;
    for (let i = 0; i < totalSamples; i++) {
      const timeKey = (800 + i * 15).toString().padStart(4, '0');
      if (isDeterministicDemoSlot('clinic_test', '20261028', timeKey)) {
        bookedCount++;
      }
    }
    // Approximately 30-40% booked
    expect(bookedCount).toBeGreaterThan(20);
    expect(bookedCount).toBeLessThan(50);
  });

  it('Phase 11C: seedDemoBookingsHandler and resetDemoBookingsHandler manage demo data cleanly', async () => {
    const db = new MockFirestore();
    db.store.set('clinics/c1', {
      name: 'Bandra Clinic',
      type: 'clinic',
      openTime: '09:00',
      closeTime: '17:00',
      slotDurationMin: 30,
      bookingFeeRupees: 79,
    });
    db.store.set('clinics/lab1', {
      name: 'Suburban Lab',
      type: 'pathology_lab',
      openTime: '08:00',
      closeTime: '20:00',
      slotDurationMin: 30,
      bookingFeeRupees: 49,
    });

    // 1. Seed demo bookings
    const seedRes = await seedDemoBookingsHandler(db as any);
    expect(seedRes.success).toBe(true);
    expect(seedRes.seededCount).toBeGreaterThan(0);

    // Verify slots and appointments were created with isDemo: true
    let demoSlotFound = false;
    let demoAppFound = false;
    for (const [k, v] of db.store.entries()) {
      if (k.startsWith('slots/') && v.isDemo) demoSlotFound = true;
      if (k.startsWith('appointments/') && v.isDemo) demoAppFound = true;
    }
    expect(demoSlotFound).toBe(true);
    expect(demoAppFound).toBe(true);

    // 2. Reset demo bookings
    const resetRes = await resetDemoBookingsHandler(db as any);
    expect(resetRes.success).toBe(true);
    expect(resetRes.clearedCount).toBeGreaterThan(0);

    // Verify all demo items deleted
    for (const [k, v] of db.store.entries()) {
      if (k.startsWith('slots/') || k.startsWith('appointments/')) {
        expect(v.isDemo).toBeFalsy();
      }
    }
  });

  it('Phase 11C: getRevenueSnapshotHandler aggregates bookings, revenue, and clinic vs lab breakdown', async () => {
    const db = new MockFirestore();
    const now = new Date();

    // Seed 2 clinic appointments (₹79 each) and 1 lab appointment (₹49)
    db.store.set('appointments/app1', {
      status: 'confirmed',
      amountPaise: 7900,
      clinicType: 'clinic',
      startTime: now.toISOString(),
    });
    db.store.set('appointments/app2', {
      status: 'confirmed',
      amountPaise: 7900,
      clinicType: 'clinic',
      startTime: now.toISOString(),
    });
    db.store.set('appointments/app3', {
      status: 'confirmed',
      amountPaise: 4900,
      clinicType: 'pathology_lab',
      startTime: now.toISOString(),
    });
    db.store.set('appointments/app4', {
      status: 'pending_payment',
      amountPaise: 7900,
      clinicType: 'clinic',
    });

    const snapshot = await getRevenueSnapshotHandler(db as any);

    expect(snapshot.totalBookings).toBe(3);
    expect(snapshot.totalRevenueRupees).toBe(79 + 79 + 49); // 207
    expect(snapshot.breakdown.clinic.bookings).toBe(2);
    expect(snapshot.breakdown.clinic.revenueRupees).toBe(158);
    expect(snapshot.breakdown.lab.bookings).toBe(1);
    expect(snapshot.breakdown.lab.revenueRupees).toBe(49);
    expect(snapshot.averagePerDay).toBe(207);
  });

  it('Phase 11C: rejects slot that extends past clinic closing time', async () => {
    const db = new MockFirestore();
    db.store.set('clinics/c1', {
      name: 'Bandra Clinic',
      type: 'clinic',
      openTime: '08:00',
      closeTime: '18:00',
      slotDurationMin: 30,
      bookingFeeRupees: 79,
    });

    const futureDate = new Date(Date.now() + 2 * 24 * 60 * 60 * 1000);
    const dateComp = getKolkataComponents(futureDate);

    // Slot starting at 17:45 extends to 18:15 which exceeds closeTime 18:00
    const spillSlotTime = parseKolkataDateTime(dateComp.dateKey, '17:45');

    await expect(
      createAppointmentOrderHandler(db as any, 'patient_test', {
        clinicId: 'c1',
        startTime: spillSlotTime.toISOString(),
        patientName: 'Test Patient',
        patientPhone: '9876543210',
      })
    ).rejects.toThrow('Selected slot is outside clinic operating hours.');
  });
});
