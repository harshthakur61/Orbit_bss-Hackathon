/**
 * Indian vehicle registration plate patterns:
 * Standard format: State (2 letters) + RTO (1-2 digits) + optional series (1-3 letters) + unique number (4 digits)
 * Examples: MH02AB1234, DL1CAB1234, KA011234, GJ01AA0001
 * Bharat Series (BH): e.g. 22BH1234AA
 */
const INDIAN_PLATE_REGEX = /^[A-Z]{2}[0-9]{1,2}[A-Z]{0,3}[0-9]{4}$/;
const BHARAT_SERIES_REGEX = /^[0-9]{2}BH[0-9]{4}[A-Z]{1,2}$/;

/**
 * Sanitizes and validates an Indian vehicle registration number.
 * Strips whitespace and hyphens, converts to uppercase, and validates format.
 * Throws an Error if malformed.
 */
export function sanitizeVehicleNumber(raw: string): string {
  if (!raw || typeof raw !== 'string') {
    throw new Error('Vehicle number must be a non-empty string.');
  }

  const clean = raw.trim().toUpperCase().replace(/[\s-]/g, '');

  if (!INDIAN_PLATE_REGEX.test(clean) && !BHARAT_SERIES_REGEX.test(clean)) {
    throw new Error('Invalid vehicle number format. Must be a valid Indian registration plate.');
  }

  return clean;
}

/**
 * Sanitizes a Driving License number.
 * Strips whitespace and hyphens, converts to uppercase.
 */
export function sanitizeDlNumber(raw: string): string {
  if (!raw || typeof raw !== 'string') {
    throw new Error('Driving License number must be a non-empty string.');
  }

  const clean = raw.trim().toUpperCase().replace(/[\s-]/g, '');

  if (clean.length < 8 || clean.length > 20) {
    throw new Error('Invalid Driving License number format.');
  }

  return clean;
}

/**
 * Sanitizes an Application Reference (e.g. "APP-102938")
 */
export function sanitizeApplicationRef(raw: string): string {
  if (!raw || typeof raw !== 'string') {
    throw new Error('Application Reference must be a non-empty string.');
  }
  return raw.trim().toUpperCase();
}
