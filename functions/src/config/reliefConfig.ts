/**
 * Configuration thresholds, tier ranking, and eligibility helpers
 * for Ambulance Crew presence and relief candidate matching (Phase 12A & 12B).
 */

export const RELIEF_CONFIG = {
  /** Maximum age in seconds for a presence update to be considered live for relief dispatch */
  MAX_PRESENCE_AGE_SECONDS: 120,

  /** Expected status for relief candidates */
  ELIGIBLE_STATUS: "AVAILABLE",

  /** Location accuracy threshold in meters */
  MAX_ACCEPTABLE_ACCURACY_METERS: 100.0,

  /** Offer validity window in seconds */
  OFFER_DURATION_SECONDS: 60,

  /** Maximum candidate offers to dispatch in one wave */
  MAX_CANDIDATES_PER_WAVE: 10,

  /** Whether candidate AIS-125 tier must be >= disabled ambulance tier */
  ENFORCE_TIER_MATCH: true,

  /** Wave expansion configuration (0-based) */
  WAVES: [
    { wave: 0, radiusKm: 5 },
    { wave: 1, radiusKm: 10 },
    { wave: 2, radiusKm: 15 },
  ],
} as const;

export type ReliefReason =
  | "breakdown"
  | "accident"
  | "flat_tyre"
  | "fuel"
  | "other";

export type ReliefRequestStatus =
  | "searching"
  | "accepted"
  | "completed"
  | "cancelled"
  | "no_ambulance";

export type ReliefOfferStatus =
  | "pending"
  | "rejected"
  | "accepted"
  | "taken"
  | "expired";

export type ReliefRejectReason =
  | "too_far"
  | "starting_trip"
  | "crew_unavailable"
  | "vehicle_issue";

export interface CrewPresenceData {
  ambulanceId?: string;
  ais125Tier?: string;
  status: "AVAILABLE" | "BUSY" | "OFFLINE";
  lat?: number;
  lng?: number;
  accuracyMeters?: number;
  updatedAt?: FirebaseFirestore.Timestamp | Date;
}

export interface AmbulanceSnapshotData {
  ambulanceId: string;
  vehicleNumber: string;
  driverName: string;
  driverPhone: string;
  ambulanceType: string;
  ais125Tier: string;
}

export interface ReliefOfferData {
  ambulanceId: string;
  ais125Tier: string;
  lat: number;
  lng: number;
  distanceKm: number;
  etaMin: number;
  status: ReliefOfferStatus;
  reason?: string | null;
  sentAt: FirebaseFirestore.Timestamp | Date;
  respondedAt?: FirebaseFirestore.Timestamp | Date | null;
}

export interface ReliefRequestData {
  originalRequestId: string;
  requesterUid: string;
  requesterAmbulance: AmbulanceSnapshotData;
  reason: ReliefReason;
  status: ReliefRequestStatus;
  wave: number;
  radiusKm: number;
  offerExpiresAt: FirebaseFirestore.Timestamp | Date;
  disabledLocation: {
    lat: number;
    lng: number;
    updatedAt: FirebaseFirestore.Timestamp | Date;
  };
  severity: string;
  needs: string[];
  acceptedByUid?: string | null;
  acceptedAmbulance?: AmbulanceSnapshotData | null;
  createdAt: FirebaseFirestore.Timestamp | Date;
  updatedAt?: FirebaseFirestore.Timestamp | Date;
}

/**
 * Normalizes AIS-125 tier string into numeric rank:
 * Type A: 1, Type B: 2, Type C: 3, Type D: 4
 */
export function normalizeAis125Tier(tier?: string | null): number {
  if (!tier) return 2; // Default to Type B
  const upper = tier.toUpperCase();
  if (upper.includes("TYPE_D") || upper.includes("TYPE D")) return 4;
  if (upper.includes("TYPE_C") || upper.includes("TYPE C")) return 3;
  if (upper.includes("TYPE_B") || upper.includes("TYPE B")) return 2;
  if (upper.includes("TYPE_A") || upper.includes("TYPE A")) return 1;
  return 2;
}

/**
 * Checks if candidate tier is >= original tier
 */
export function isTierSufficient(
  candidateTier?: string | null,
  originalTier?: string | null,
  enforce: boolean = RELIEF_CONFIG.ENFORCE_TIER_MATCH
): boolean {
  if (!enforce) return true;
  return normalizeAis125Tier(candidateTier) >= normalizeAis125Tier(originalTier);
}

/**
 * Haversine formula to compute distance in km between two GPS coordinates
 */
export function calculateHaversineDistanceKm(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  const R = 6371; // Earth radius in km
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return Math.round(R * c * 100) / 100;
}

/**
 * Evaluates whether a crew is eligible to receive a relief request.
 */
export function isCrewEligibleForRelief(
  presence: CrewPresenceData | undefined | null,
  activeDeviceTokensCount: number,
  nowDate: Date = new Date()
): boolean {
  if (!presence) return false;

  if (presence.status !== RELIEF_CONFIG.ELIGIBLE_STATUS) {
    return false;
  }

  if (activeDeviceTokensCount <= 0) {
    return false;
  }

  if (!presence.updatedAt) {
    return false;
  }

  const updatedDate =
    typeof (presence.updatedAt as FirebaseFirestore.Timestamp).toDate === "function"
      ? (presence.updatedAt as FirebaseFirestore.Timestamp).toDate()
      : new Date(presence.updatedAt as Date);

  const diffSeconds = (nowDate.getTime() - updatedDate.getTime()) / 1000;
  return diffSeconds >= 0 && diffSeconds <= RELIEF_CONFIG.MAX_PRESENCE_AGE_SECONDS;
}
