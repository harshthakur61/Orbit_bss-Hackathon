import { LicenseVerificationResult, VehicleVerificationResult } from '../types';

export interface VerificationProvider {
  verifyVehicle(vehicleNumber: string): Promise<VehicleVerificationResult>;
  verifyLicense(dlNumber: string, dob: string): Promise<LicenseVerificationResult>;
}
