import { fuzzyMatchNames } from '../utils/fuzzyName';

export interface OwnerCheckResult {
  matches: boolean;
  reviewReason: string | null;
}

/**
 * Validates vehicle owner against driver or vendor name.
 * If owner does not match, does NOT hard reject; flags for NEEDS_REVIEW.
 * Government, hospital, trust, and fleet-owned ambulances are legitimate.
 */
export function evaluateOwnerRule(
  ownerName: string,
  driverLegalName: string,
  vendorName?: string
): OwnerCheckResult {
  if (!ownerName || !ownerName.trim()) {
    return {
      matches: false,
      reviewReason: 'Vehicle owner name is not present in registration records (Flagged for review)',
    };
  }

  // 1. Matches driver
  if (fuzzyMatchNames(ownerName, driverLegalName)) {
    return { matches: true, reviewReason: null };
  }

  // 2. Matches vendor / provider name if provided
  if (vendorName && fuzzyMatchNames(ownerName, vendorName)) {
    return { matches: true, reviewReason: null };
  }

  // 3. Known institutional keywords (hospital, trust, govt, medical, health)
  const institutionalKeywords = ['hospital', 'trust', 'health', 'medical', 'foundation', 'ambulance', 'govt', 'government', 'society'];
  const cleanOwner = ownerName.toLowerCase();
  const isInstitutional = institutionalKeywords.some((keyword) => cleanOwner.includes(keyword));

  if (isInstitutional) {
    return {
      matches: false,
      reviewReason: `Vehicle is registered to institutional owner (${ownerName}). Flagged for standard institutional credential review.`,
    };
  }

  return {
    matches: false,
    reviewReason: `Vehicle registered owner (${ownerName}) does not match driver legal name. Flagged for manual review.`,
  };
}
