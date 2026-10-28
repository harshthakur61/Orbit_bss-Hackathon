import { LicenseVerificationResult, RuleCheckResult } from '../types';
import { DEFAULT_NAME_SIMILARITY_THRESHOLD, fuzzyMatchNames } from '../utils/fuzzyName';

export const ACCEPTED_TRANSPORT_CLASSES = [
  'TRANS',
  'TRANSPORT',
  'LMV-TR',
  'LMV_TR',
  'HMV',
  'HGV',
  'PSVBUS',
  'AMB',
  'AMBULANCE',
];

/**
 * Validates driver license against RTO transport compliance rules:
 * - status must be ACTIVE (reject expired/suspended)
 * - has Transport endorsement (TRANS)
 * - holder name fuzzy-matches driverLegalName
 */
export function evaluateLicenseRules(
  license: LicenseVerificationResult,
  driverLegalName: string,
  now: Date = new Date(),
  nameThreshold: number = DEFAULT_NAME_SIMILARITY_THRESHOLD
): RuleCheckResult {
  const errors: string[] = [];

  // 1. DL Status check
  const status = license.status.trim().toUpperCase();
  if (status !== 'ACTIVE') {
    errors.push(`Driving License status is ${license.status || 'INACTIVE'}, must be ACTIVE`);
  }

  // 2. Expiry check
  if (license.expiry && license.expiry.getTime() <= now.getTime()) {
    errors.push('Driving License validity has expired');
  }

  // 3. Transport Endorsement check
  const hasTransClass = license.classesOfVehicle.some((cov) =>
    ACCEPTED_TRANSPORT_CLASSES.includes(cov.trim().toUpperCase())
  );

  const hasEndorsement = license.transportEndorsement || hasTransClass;
  if (!hasEndorsement) {
    errors.push('Driving License lacks required commercial Transport (TRANS) endorsement');
  }

  // 4. Fuzzy Name match
  if (!fuzzyMatchNames(license.holderName, driverLegalName, nameThreshold)) {
    errors.push('Driver legal name does not match the name on the Driving License');
  }

  return {
    passed: errors.length === 0,
    errors,
  };
}
