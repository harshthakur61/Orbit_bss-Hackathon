import { VerificationProvider } from '../providers/types';
import { evaluateLicenseRules } from '../rules/licenseRules';
import { evaluateOwnerRule } from '../rules/ownerRules';
import { evaluateVehicleRules } from '../rules/vehicleRules';
import { VerificationEngineResult } from '../types';

export interface RunVerificationParams {
  vehicleNumber: string;
  dlNumber: string;
  dob: string;
  driverLegalName: string;
  vendorName?: string;
}

/**
 * Runs the full verification pipeline:
 * 1. Fetches external or mock RTO vehicle and DL records.
 * 2. Checks vehicle rules (class, active status, fitness).
 * 3. Checks license rules (active status, transport endorsement, driver name match).
 * 4. Checks owner name (flags NEEDS_REVIEW if not matching personal driver name).
 * 5. Returns final VerificationEngineResult without exposing extraneous vendor PII.
 */
export async function runVerification(
  provider: VerificationProvider,
  params: RunVerificationParams,
  now: Date = new Date()
): Promise<VerificationEngineResult> {
  const { vehicleNumber, dlNumber, dob, driverLegalName, vendorName } = params;

  // Run vehicle and license queries concurrently
  const [vehicleResult, licenseResult] = await Promise.all([
    provider.verifyVehicle(vehicleNumber),
    provider.verifyLicense(dlNumber, dob),
  ]);

  // Evaluate rules independently
  const vehicleChecks = evaluateVehicleRules(vehicleResult, now);
  const licenseChecks = evaluateLicenseRules(licenseResult, driverLegalName, now);

  // If any vehicle or license rule failed, hard REJECT with all failure reasons
  const allErrors = [...vehicleChecks.errors, ...licenseChecks.errors];
  if (allErrors.length > 0) {
    return {
      status: 'REJECTED',
      rejectionReason: allErrors.join('; '),
      reviewReason: null,
      verifiedAt: null,
      vehicleData: {
        vehicleClass: vehicleResult.vehicleClass,
        ownerName: vehicleResult.ownerName,
        fitnessValidUpto: vehicleResult.fitnessValidUpto,
      },
      licenseData: {
        driverLegalName: licenseResult.holderName,
        dlStatus: licenseResult.status,
        dlHasTransportEndorsement: licenseResult.transportEndorsement,
      },
    };
  }

  // If both vehicle and license rules pass, check owner name
  const ownerCheck = evaluateOwnerRule(vehicleResult.ownerName, driverLegalName, vendorName);
  if (!ownerCheck.matches) {
    return {
      status: 'NEEDS_REVIEW',
      rejectionReason: null,
      reviewReason: ownerCheck.reviewReason,
      verifiedAt: null,
      vehicleData: {
        vehicleClass: vehicleResult.vehicleClass,
        ownerName: vehicleResult.ownerName,
        fitnessValidUpto: vehicleResult.fitnessValidUpto,
      },
      licenseData: {
        driverLegalName: licenseResult.holderName,
        dlStatus: licenseResult.status,
        dlHasTransportEndorsement: licenseResult.transportEndorsement,
      },
    };
  }

  // Full PASS -> VERIFIED
  return {
    status: 'VERIFIED',
    rejectionReason: null,
    reviewReason: null,
    verifiedAt: now,
    vehicleData: {
      vehicleClass: vehicleResult.vehicleClass,
      ownerName: vehicleResult.ownerName,
      fitnessValidUpto: vehicleResult.fitnessValidUpto,
    },
    licenseData: {
      driverLegalName: licenseResult.holderName,
      dlStatus: licenseResult.status,
      dlHasTransportEndorsement: licenseResult.transportEndorsement,
    },
  };
}
