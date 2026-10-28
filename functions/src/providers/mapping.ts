import { LicenseVerificationResult, VehicleVerificationResult } from '../types';

/**
 * Maps Sandbox.co.in RC/Vehicle verification API payload to internal VehicleVerificationResult.
 * Adjust here if Sandbox or another aggregator updates their schema.
 */
export function mapSandboxVehicleResponse(raw: Record<string, any>): VehicleVerificationResult {
  const data = raw?.data || raw?.result || raw;

  // Extract class: e.g. data.vehicle_class, data.vh_class, data.class
  const rawClass = data?.vehicle_class || data?.vh_class || data?.vehicleClass || data?.class || 'UNKNOWN';

  // Extract status: e.g. data.rc_status, data.status
  const rawStatus = data?.rc_status || data?.status || 'ACTIVE';

  // Extract fitness: e.g. data.fit_up_to, data.fitness_upto, data.fitnessValidUpto
  const rawFitness = data?.fit_up_to || data?.fitness_upto || data?.fitness_valid_upto || data?.fitnessValidUpto;
  let fitnessDate: Date | null = null;
  if (rawFitness) {
    const parsed = new Date(rawFitness);
    if (!isNaN(parsed.getTime())) {
      fitnessDate = parsed;
    }
  }

  // Extract owner: e.g. data.owner_name, data.ownerName
  const rawOwner = data?.owner_name || data?.ownerName || data?.registered_owner || '';

  return {
    vehicleClass: String(rawClass).trim().toUpperCase(),
    rcStatus: String(rawStatus).trim().toUpperCase(),
    fitnessValidUpto: fitnessDate,
    ownerName: String(rawOwner).trim().toUpperCase(),
  };
}

/**
 * Maps Sandbox.co.in DL verification API payload to internal LicenseVerificationResult.
 */
export function mapSandboxLicenseResponse(raw: Record<string, any>): LicenseVerificationResult {
  const data = raw?.data || raw?.result || raw;

  const rawName = data?.name || data?.holder_name || data?.holderName || '';
  const rawStatus = data?.status || data?.dl_status || 'ACTIVE';

  const rawExpiry = data?.expiry_date || data?.valid_till || data?.expiryDate || data?.nt_validity_to;
  let expiryDate: Date | null = null;
  if (rawExpiry) {
    const parsed = new Date(rawExpiry);
    if (!isNaN(parsed.getTime())) {
      expiryDate = parsed;
    }
  }

  // Classes of vehicle: array or comma-separated string
  let classes: string[] = [];
  const rawCov = data?.cov || data?.classes || data?.class_of_vehicle || data?.vehicle_classes;
  if (Array.isArray(rawCov)) {
    classes = rawCov.map((c: any) => String(c?.cov || c).trim().toUpperCase());
  } else if (typeof rawCov === 'string') {
    classes = rawCov.split(',').map((s) => s.trim().toUpperCase());
  }

  // Check transport endorsement
  const hasTransEndorsement = Boolean(
    data?.transport_endorsement ||
      data?.tr_endorsement ||
      data?.has_transport_endorsement ||
      classes.some((c) => ['TRANS', 'TRANSPORT', 'LMV-TR', 'HMV', 'HGV', 'PSVBUS'].includes(c))
  );

  return {
    holderName: String(rawName).trim().toUpperCase(),
    status: String(rawStatus).trim().toUpperCase(),
    expiry: expiryDate,
    classesOfVehicle: classes,
    transportEndorsement: hasTransEndorsement,
  };
}
