import {
  isCrewEligibleForRelief,
  CrewPresenceData,
} from "../src/config/reliefConfig";

describe("Phase 12A – Relief Candidate Eligibility Tests", () => {
  const baseNow = new Date("2026-10-28T10:00:00Z");

  test("eligible when AVAILABLE, updated within 120s, and has active device tokens", () => {
    const presence: CrewPresenceData = {
      ambulanceId: "BL-AMB-100001",
      ais125Tier: "TYPE_C",
      status: "AVAILABLE",
      lat: 19.076,
      lng: 72.877,
      accuracyMeters: 15.0,
      updatedAt: new Date("2026-10-28T09:59:30Z"), // 30s ago
    };

    expect(isCrewEligibleForRelief(presence, 1, baseNow)).toBe(true);
    expect(isCrewEligibleForRelief(presence, 2, baseNow)).toBe(true);
  });

  test("ineligible when status is BUSY or OFFLINE", () => {
    const busyPresence: CrewPresenceData = {
      status: "BUSY",
      updatedAt: new Date("2026-10-28T09:59:30Z"),
    };
    expect(isCrewEligibleForRelief(busyPresence, 1, baseNow)).toBe(false);

    const offlinePresence: CrewPresenceData = {
      status: "OFFLINE",
      updatedAt: new Date("2026-10-28T09:59:30Z"),
    };
    expect(isCrewEligibleForRelief(offlinePresence, 1, baseNow)).toBe(false);
  });

  test("ineligible when presence update is older than 120s (stale)", () => {
    const stalePresence: CrewPresenceData = {
      status: "AVAILABLE",
      updatedAt: new Date("2026-10-28T09:57:59Z"), // 121s ago
    };
    expect(isCrewEligibleForRelief(stalePresence, 1, baseNow)).toBe(false);

    // Exactly 120s should pass
    const boundaryPresence: CrewPresenceData = {
      status: "AVAILABLE",
      updatedAt: new Date("2026-10-28T09:58:00Z"), // 120s ago
    };
    expect(isCrewEligibleForRelief(boundaryPresence, 1, baseNow)).toBe(true);
  });

  test("ineligible when no active FCM device tokens are registered", () => {
    const presence: CrewPresenceData = {
      status: "AVAILABLE",
      updatedAt: new Date("2026-10-28T09:59:30Z"),
    };
    expect(isCrewEligibleForRelief(presence, 0, baseNow)).toBe(false);
    expect(isCrewEligibleForRelief(presence, -1, baseNow)).toBe(false);
  });

  test("ineligible when presence or updatedAt is null/undefined", () => {
    expect(isCrewEligibleForRelief(null, 1, baseNow)).toBe(false);
    expect(isCrewEligibleForRelief(undefined, 1, baseNow)).toBe(false);

    const noDatePresence: CrewPresenceData = {
      status: "AVAILABLE",
      updatedAt: undefined,
    };
    expect(isCrewEligibleForRelief(noDatePresence, 1, baseNow)).toBe(false);
  });
});
