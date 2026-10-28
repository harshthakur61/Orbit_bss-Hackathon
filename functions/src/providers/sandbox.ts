import { LicenseVerificationResult, VehicleVerificationResult } from '../types';
import { mapSandboxLicenseResponse, mapSandboxVehicleResponse } from './mapping';
import { VerificationProvider } from './types';

export class SandboxProvider implements VerificationProvider {
  private readonly apiKey: string;
  private readonly baseUrl: string;

  constructor(apiKey?: string, baseUrl = 'https://api.sandbox.co.in') {
    this.apiKey = apiKey || process.env.SANDBOX_API_KEY || '';
    this.baseUrl = baseUrl;
  }

  async verifyVehicle(vehicleNumber: string): Promise<VehicleVerificationResult> {
    if (!this.apiKey) {
      throw new Error('SANDBOX_API_KEY is not configured.');
    }

    const cleanPlate = vehicleNumber.trim().toUpperCase().replace(/[\s-]/g, '');
    const url = `${this.baseUrl}/kyc/rc/verify?rc_number=${encodeURIComponent(cleanPlate)}`;

    const response = await fetch(url, {
      method: 'GET',
      headers: {
        'Authorization': this.apiKey,
        'x-api-key': this.apiKey,
        'x-api-version': '1.0',
        'Accept': 'application/json',
      },
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Sandbox vehicle verification failed (${response.status}): ${errorText}`);
    }

    const json = await response.json();
    return mapSandboxVehicleResponse(json);
  }

  async verifyLicense(dlNumber: string, dob: string): Promise<LicenseVerificationResult> {
    if (!this.apiKey) {
      throw new Error('SANDBOX_API_KEY is not configured.');
    }

    const cleanDl = dlNumber.trim().toUpperCase().replace(/[\s-]/g, '');
    const url = `${this.baseUrl}/kyc/dl/verify?dl_number=${encodeURIComponent(cleanDl)}&dob=${encodeURIComponent(dob)}`;

    const response = await fetch(url, {
      method: 'GET',
      headers: {
        'Authorization': this.apiKey,
        'x-api-key': this.apiKey,
        'x-api-version': '1.0',
        'Accept': 'application/json',
      },
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Sandbox license verification failed (${response.status}): ${errorText}`);
    }

    const json = await response.json();
    return mapSandboxLicenseResponse(json);
  }
}
