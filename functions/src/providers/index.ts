import { MockProvider } from './mock';
import { SandboxProvider } from './sandbox';
import { VerificationProvider } from './types';

export * from './mapping';
export * from './mock';
export * from './sandbox';
export * from './types';

export function getVerificationProvider(): VerificationProvider {
  const mode = (process.env.VERIFICATION_MODE || 'mock').toLowerCase().trim();

  if (mode === 'sandbox') {
    return new SandboxProvider();
  }

  return new MockProvider();
}
