import { MockProvider } from '../src/providers/mock';
import { runVerification } from '../src/services/verificationEngine';

describe('Verification Engine with MockProvider', () => {
  const provider = new MockProvider();

  test('successfully verifies compliant ambulance and driver', async () => {
    const result = await runVerification(provider, {
      vehicleNumber: 'MH02AB1234',
      dlNumber: 'MH0220180012345',
      dob: '1990-05-15',
      driverLegalName: 'Rahul Ramesh Sharma',
      vendorName: 'KEM Hospital Research Centre',
    });

    expect(result.status).toBe('VERIFIED');
    expect(result.rejectionReason).toBeNull();
    expect(result.reviewReason).toBeNull();
    expect(result.verifiedAt).toBeInstanceOf(Date);
  });

  test('flags institutional ownership for NEEDS_REVIEW instead of rejection', async () => {
    // When driver name is personal but vehicle owner is KEM Hospital
    const result = await runVerification(provider, {
      vehicleNumber: 'MH02AB1234',
      dlNumber: 'MH0220180012345',
      dob: '1990-05-15',
      driverLegalName: 'Rahul Sharma',
    });

    expect(result.status).toBe('NEEDS_REVIEW');
    expect(result.reviewReason).toContain('Flagged for standard institutional credential review');
  });

  test('rejects vehicle ending in 0000 because of TAXICAB class', async () => {
    const result = await runVerification(provider, {
      vehicleNumber: 'MH02AB0000',
      dlNumber: 'MH0220180012345',
      dob: '1990-05-15',
      driverLegalName: 'Rahul Sharma',
    });

    expect(result.status).toBe('REJECTED');
    expect(result.rejectionReason).toContain('Vehicle class is TAXICAB, not Ambulance');
  });

  test('rejects vehicle ending in 9999 because of expired fitness certificate', async () => {
    const result = await runVerification(provider, {
      vehicleNumber: 'MH02AB9999',
      dlNumber: 'MH0220180012345',
      dob: '1990-05-15',
      driverLegalName: 'Rahul Sharma',
    });

    expect(result.status).toBe('REJECTED');
    expect(result.rejectionReason).toContain('Vehicle fitness certificate has expired');
  });

  test('rejects DL ending in 0000 because of missing transport endorsement', async () => {
    const result = await runVerification(provider, {
      vehicleNumber: 'MH02AB1234',
      dlNumber: 'MH0220180000000',
      dob: '1990-05-15',
      driverLegalName: 'Rahul Sharma',
    });

    expect(result.status).toBe('REJECTED');
    expect(result.rejectionReason).toContain(
      'Driving License lacks required commercial Transport (TRANS) endorsement'
    );
  });

  test('rejects DL ending in 9999 because of suspended license', async () => {
    const result = await runVerification(provider, {
      vehicleNumber: 'MH02AB1234',
      dlNumber: 'MH0220180009999',
      dob: '1990-05-15',
      driverLegalName: 'Rahul Sharma',
    });

    expect(result.status).toBe('REJECTED');
    expect(result.rejectionReason).toContain('Driving License status is SUSPENDED, must be ACTIVE');
  });

  test('accumulates multiple failure reasons if both vehicle and DL fail', async () => {
    const result = await runVerification(provider, {
      vehicleNumber: 'MH02AB0000', // TAXICAB
      dlNumber: 'MH0220180000000', // No TRANS endorsement
      dob: '1990-05-15',
      driverLegalName: 'Rahul Sharma',
    });

    expect(result.status).toBe('REJECTED');
    expect(result.rejectionReason).toContain('Vehicle class is TAXICAB, not Ambulance');
    expect(result.rejectionReason).toContain(
      'Driving License lacks required commercial Transport (TRANS) endorsement'
    );
  });
});
