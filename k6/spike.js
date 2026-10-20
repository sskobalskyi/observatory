import { hitRandomEndpoint } from './lib/traffic.js';

// Spike: a sudden surge of traffic, then recovery. Shows how fast the system bounces back.
export const options = {
  stages: [
    { duration: '30s', target: 10 },
    { duration: '10s', target: 300 },
    { duration: '1m', target: 300 },
    { duration: '10s', target: 10 },
    { duration: '1m', target: 10 },
    { duration: '10s', target: 0 },
  ],
  thresholds: {
    http_req_failed: [{ threshold: 'rate<0.30', abortOnFail: false }],
    http_req_duration: ['p(95)<3000'],
  },
  tags: { testid: 'spike' },
};

export default hitRandomEndpoint;
