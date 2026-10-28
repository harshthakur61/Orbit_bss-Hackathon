import { evaluateVehicleRules } from '../src/rules/vehicleRules';
import { VehicleVerificationResult } from '../src/types';

describe('Vehicle Verification Rules', () => {
  const baseVehicle: VehicleVerificationResult = {
    vehicleClass: 'AMBULANCE',
    rcStatus: 'ACTIVE',
    fitnessValidUpto: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000), // 1 year future
    ownerName: 'KEM HOSPITAL',
  };

  test('passes for valid active ambulance with future fitness certificate', () => {
    const result = evaluateVehicleRules(baseVehicle);
    expect(result.passed).toBe(true);
    expect(result.errors).toHaveLength(0);
  });

  test('passes for SPECIAL PURPOSE VEHICLE (AMBULANCE) class', () => {
    const result = evaluateVehicleRules({
      ...baseVehicle,
      vehicleClass: 'SPECIAL PURPOSE VEHICLE (AMBULANCE)',
    });
    expect(result.passed).toBe(true);
  });

  test('rejects if vehicleClass is TAXICAB', () => {
    const result = evaluateVehicleRules({
      ...baseVehicle,
      vehicleClass: 'TAXICAB',
    });
    expect(result.passed).toBe(false);
    expect(result.errors).toContain('Vehicle class is TAXICAB, not Ambulance');
  });

  test('rejects if rcStatus is SUSPENDED or INACTIVE', () => {
    const result = evaluateVehicleRules({
      ...baseVehicle,
      rcStatus: 'SUSPENDED',
    });
    expect(result.passed).toBe(false);
    expect(result.errors).toContain('Vehicle registration status is SUSPENDED, must be ACTIVE');
  });

  test('rejects if fitness certificate has expired', () => {
    const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const result = evaluateVehicleRules({
      ...baseVehicle,
      fitnessValidUpto: yesterday,
    });
    expect(result.passed).toBe(false);
    expect(result.errors).toContain('Vehicle fitness certificate has expired');
  });

  test('accumulates multiple vehicle failure reasons simultaneously', () => {
    const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const result = evaluateVehicleRules({
      vehicleClass: 'MOTOR CAR',
      rcStatus: 'INACTIVE',
      fitnessValidUpto: yesterday,
      ownerName: 'XYZ',
    });
    expect(result.passed).toBe(false);
    expect(result.errors).toHaveLength(3);
  });
});
