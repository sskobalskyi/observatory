import { hitRandomEndpoint, defaultThresholds } from './lib/traffic.js';

// Load: expected normal-to-peak traffic. Ramp up, hold, ramp down.
export const options = {
  stages: [
    { duration: '1m', target: 25 },
    { duration: '3m', target: 25 },
    { duration: '30s', target: 0 },
  ],
  thresholds: defaultThresholds,
  tags: { testid: 'load' },
};

export default hitRandomEndpoint;
