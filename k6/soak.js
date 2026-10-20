import { hitRandomEndpoint, defaultThresholds } from './lib/traffic.js';

// Soak: moderate load for a long time to expose leaks and slow degradation.
// Override the duration with: -e SOAK_DURATION=2h
export const options = {
  stages: [
    { duration: '2m', target: 15 },
    { duration: __ENV.SOAK_DURATION || '30m', target: 15 },
    { duration: '1m', target: 0 },
  ],
  thresholds: defaultThresholds,
  tags: { testid: 'soak' },
};

export default hitRandomEndpoint;
