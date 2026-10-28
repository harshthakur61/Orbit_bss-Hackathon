import { evaluateLicenseRules } from '../src/rules/licenseRules';
import { LicenseVerificationResult } from '../src/types';

describe('License Verification Rules', () => {
  const baseLicense: LicenseVerificationResult = {
    holderName: 'RAHUL RAMESH SHARMA',
    status: 'ACTIVE',
    expiry: new Date(Date.now() + 5 * 365 * 24 * 60 * 60 * 1000), // 5 years future
    classesOfVehicle: ['LMV', 'TRANS'],
    transportEndorsement: true,
  };

  test('passes for active license with transport endorsement and matching name', () => {
    const result = evaluateLicenseRules(baseLicense, 'Rahul Sharma');
    expect(result.passed).toBe(true);
    expect(result.errors).toHaveLength(0);
  });

  test('rejects suspended or expired license status', () => {
    const result = evaluateLicenseRules(
      {
        ...baseLicense,
        status: 'SUSPENDED',
      },
      'Rahul Sharma'
    );
    expect(result.passed).toBe(false);
    expect(result.errors).toContain('Driving License status is SUSPENDED, must be ACTIVE');
  });

  test('rejects if transport endorsement is missing from both flag and vehicle classes', () => {
    const result = evaluateLicenseRules(
      {
        ...baseLicense,
        transportEndorsement: false,
        classesOfVehicle: ['LMV', 'MCWG'],
      },
      'Rahul Sharma'
    );
    expect(result.passed).toBe(false);
    expect(result.errors).toContain(
      'Driving License lacks required commercial Transport (TRANS) endorsement'
    );
  });

  test('passes if transport endorsement flag is false but classesOfVehicle has TRANS or HMV', () => {
    const result = evaluateLicenseRules(
      {
        ...baseLicense,
        transportEndorsement: false,
        classesOfVehicle: ['LMV', 'HMV'],
      },
      'Rahul Sharma'
    );
    expect(result.passed).toBe(true);
  });

  test('rejects when driver name does not match license holder', () => {
    const result = evaluateLicenseRules(baseLicense, 'Vikram Malhotra');
    expect(result.passed).toBe(false);
    expect(result.errors).toContain(
      'Driver legal name does not match the name on the Driving License'
    );
  });
});
