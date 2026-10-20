import { hitRandomEndpoint, defaultThresholds } from './lib/traffic.js';

// Smoke: a minimal run that proves the system works. Used as a CI gate.
export const options = {
  vus: 1,
  duration: '30s',
  thresholds: defaultThresholds,
  tags: { testid: 'smoke' },
};

export default hitRandomEndpoint;
