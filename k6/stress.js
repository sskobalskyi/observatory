import { hitRandomEndpoint } from './lib/traffic.js';

// Stress: increase load in steps beyond normal capacity to find the breaking point.
export const options = {
  stages: [
    { duration: '1m', target: 25 },
    { duration: '1m', target: 75 },
    { duration: '1m', target: 150 },
    { duration: '1m', target: 250 },
    { duration: '3m', target: 400 },
    { duration: '1m', target: 0 },
  ],
  // Loose thresholds: the point is to observe degradation, not to fail fast.
  thresholds: {
    http_req_failed: [{ threshold: 'rate<0.50', abortOnFail: false }],
    http_req_duration: ['p(95)<5000'],
  },
  tags: { testid: 'stress' },
};

export default hitRandomEndpoint;
