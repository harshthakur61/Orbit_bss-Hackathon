import * as admin from 'firebase-admin';

export type AmbulanceVerificationStatus = 'PENDING' | 'VERIFIED' | 'REJECTED' | 'NEEDS_REVIEW';

export interface VehicleVerificationResult {
  vehicleClass: string;
  rcStatus: string;
  fitnessValidUpto: Date | null;
  ownerName: string;
  rawResponse?: Record<string, unknown>;
}

export interface LicenseVerificationResult {
  holderName: string;
  status: string;
  expiry: Date | null;
  classesOfVehicle: string[];
  transportEndorsement: boolean;
  rawResponse?: Record<string, unknown>;
}

export interface RuleCheckResult {
  passed: boolean;
  errors: string[];
}

export interface VerificationEngineResult {
  status: AmbulanceVerificationStatus;
  rejectionReason: string | null;
  reviewReason: string | null;
  verifiedAt: Date | null;
  vehicleData?: {
    vehicleClass: string;
    ownerName: string;
    fitnessValidUpto: Date | null;
  };
  licenseData?: {
    driverLegalName: string;
    dlStatus: string;
    dlHasTransportEndorsement: boolean;
  };
}

export interface SubmitRegistrationInput {
  vehicleNumber: string;
  chassisEngineNumber?: string;
  rcPhotoStoragePath?: string;
  dlNumber: string;
  dob: string;
  driverLegalName: string;
  password: string;
  contactNumber: string;
  ais125Tier?: string;
  ambulanceType?: string;
}

// -------------------------------------------------------------
// Phase 11A: Clinic & Diagnostic Lab Appointments & Slots
// -------------------------------------------------------------

export type SlotStatus = 'held' | 'booked';

export interface SlotDoc {
  clinicId: string;
  dateKey: string; // YYYYMMDD
  startTime: admin.firestore.Timestamp;
  status: SlotStatus;
  holdExpiresAt: admin.firestore.Timestamp | null;
  appointmentId: string;
}

export type AppointmentStatus =
  | 'pending_payment'
  | 'confirmed'
  | 'payment_failed'
  | 'expired'
  | 'refunded';

export interface AppointmentDoc {
  patientUid: string;
  patientName: string;
  patientPhone: string;
  clinicId: string;
  clinicName: string;
  clinicType: string;
  slotId: string;
  startTime: admin.firestore.Timestamp;
  status: AppointmentStatus;
  amountPaise: number;
  razorpayOrderId?: string;
  razorpayPaymentId?: string | null;
  razorpaySignature?: string | null;
  createdAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
  confirmedAt?: admin.firestore.FieldValue | admin.firestore.Timestamp | null;
  refundedAt?: admin.firestore.FieldValue | admin.firestore.Timestamp | null;
  refundId?: string | null;
}

export interface CreateAppointmentOrderInput {
  clinicId: string;
  startTime: string; // ISO 8601 string e.g. "2026-10-28T09:30:00+05:30"
  patientName: string;
  patientPhone: string;
}

export interface CreateAppointmentOrderOutput {
  appointmentId: string;
  orderId: string;
  amountPaise: number;
  keyId: string;
  holdExpiresAt: string;
}

export interface VerifyAppointmentPaymentInput {
  appointmentId: string;
  razorpayOrderId: string;
  razorpayPaymentId: string;
  razorpaySignature: string;
}

export interface ReleaseAppointmentHoldInput {
  appointmentId: string;
}

export interface GetClinicDaySlotsInput {
  clinicId: string;
  dateKey: string; // YYYYMMDD
}

export interface DaySlotItem {
  slotId: string;
  time: string; // "HH:mm"
  startTimeIso: string;
  status: 'free' | 'booked' | 'past';
}
