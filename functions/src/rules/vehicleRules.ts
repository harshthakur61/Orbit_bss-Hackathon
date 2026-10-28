import { RuleCheckResult, VehicleVerificationResult } from '../types';

export const ACCEPTED_VEHICLE_CLASSES = [
  'AMBULANCE',
  'SPECIAL PURPOSE VEHICLE (AMBULANCE)',
  'SPECIAL PURPOSE VEHICLE(AMBULANCE)',
  'AMBULANCE (PATIENT TRANSPORT)',
  'AMBULANCE (ADVANCED LIFE SUPPORT)',
];

/**
 * Validates vehicle against RTO compliance rules:
 * - vehicleClass must be "AMBULANCE" or "SPECIAL PURPOSE VEHICLE (AMBULANCE)"
 * - rcStatus must be "ACTIVE"
 * - fitnessValidUpto must be later than today
 */
export function evaluateVehicleRules(
  vehicle: VehicleVerificationResult,
  now: Date = new Date()
): RuleCheckResult {
  const errors: string[] = [];

  // 1. Vehicle Class check
  const vClass = vehicle.vehicleClass.trim().toUpperCase();
  const isAmbulanceClass = ACCEPTED_VEHICLE_CLASSES.some(
    (accepted) => vClass === accepted || vClass.includes('AMBULANCE')
  );

  if (!isAmbulanceClass) {
    errors.push(`Vehicle class is ${vehicle.vehicleClass || 'UNKNOWN'}, not Ambulance`);
  }

  // 2. RC Status check
  const status = vehicle.rcStatus.trim().toUpperCase();
  if (status !== 'ACTIVE') {
    errors.push(`Vehicle registration status is ${vehicle.rcStatus || 'INACTIVE'}, must be ACTIVE`);
  }

  // 3. Fitness Validity check
  if (!vehicle.fitnessValidUpto) {
    errors.push('Vehicle fitness certificate date is missing or invalid');
  } else if (vehicle.fitnessValidUpto.getTime() <= now.getTime()) {
    errors.push('Vehicle fitness certificate has expired');
  }

  return {
    passed: errors.length === 0,
    errors,
  };
}
