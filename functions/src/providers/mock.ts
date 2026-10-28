import { LicenseVerificationResult, VehicleVerificationResult } from '../types';
import { VerificationProvider } from './types';

export class MockProvider implements VerificationProvider {
  async verifyVehicle(vehicleNumber: string): Promise<VehicleVerificationResult> {
    const cleanNumber = vehicleNumber.trim().toUpperCase().replace(/[\s-]/g, '');

    // Controllable failure: ending with "0000" -> class TAXICAB
    if (cleanNumber.endsWith('0000')) {
      return {
        vehicleClass: 'TAXICAB',
        rcStatus: 'ACTIVE',
        fitnessValidUpto: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000), // 1 year future
        ownerName: 'MUMBAI METRO TAXI SERVICES',
      };
    }

    // Controllable failure: ending with "9999" -> expired fitness
    if (cleanNumber.endsWith('9999')) {
      const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000);
      return {
        vehicleClass: 'AMBULANCE',
        rcStatus: 'ACTIVE',
        fitnessValidUpto: yesterday,
        ownerName: 'LILAVATI HOSPITAL & RESEARCH CENTRE',
      };
    }

    // Default success case
    const futureDate = new Date(Date.now() + 2 * 365 * 24 * 60 * 60 * 1000);
    return {
      vehicleClass: 'AMBULANCE',
      rcStatus: 'ACTIVE',
      fitnessValidUpto: futureDate,
      ownerName: 'KEM HOSPITAL RESEARCH CENTRE',
    };
  }

  async verifyLicense(dlNumber: string, dob: string): Promise<LicenseVerificationResult> {
    const cleanDl = dlNumber.trim().toUpperCase().replace(/[\s-]/g, '');

    // Controllable failure: ending with "0000" -> no transport endorsement
    if (cleanDl.endsWith('0000')) {
      return {
        holderName: 'RAHUL RAMESH SHARMA',
        status: 'ACTIVE',
        expiry: new Date(Date.now() + 5 * 365 * 24 * 60 * 60 * 1000),
        classesOfVehicle: ['LMV', 'MCWG'],
        transportEndorsement: false,
      };
    }

    // Controllable failure: ending with "9999" -> suspended/expired
    if (cleanDl.endsWith('9999')) {
      const pastDate = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
      return {
        holderName: 'RAHUL RAMESH SHARMA',
        status: 'SUSPENDED',
        expiry: pastDate,
        classesOfVehicle: ['LMV', 'TRANS'],
        transportEndorsement: true,
      };
    }

    // Default success case
    const futureExpiry = new Date(Date.now() + 5 * 365 * 24 * 60 * 60 * 1000);
    return {
      holderName: 'RAHUL RAMESH SHARMA',
      status: 'ACTIVE',
      expiry: futureExpiry,
      classesOfVehicle: ['LMV', 'TRANS', 'AMB'],
      transportEndorsement: true,
    };
  }
}
