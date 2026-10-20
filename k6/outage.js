import http from 'k6/http';
import { check, sleep } from 'k6';
import { BASE_URL } from './lib/traffic.js';

// Outage: a dependency starts failing half of all requests. Burns the availability error
// budget quickly, so the fast-burn SLO alert fires. Override the failure rate with: -e FAILURE_RATE=0.3
const failureRate = __ENV.FAILURE_RATE || '0.5';

export const options = {
  stages: [
    { duration: '30s', target: 20 },
    { duration: '3m', target: 20 },
    { duration: '10s', target: 0 },
  ],
  // Failures are the point of this scenario, so nothing here should fail the run.
  thresholds: {},
  tags: { testid: 'outage' },
};

export default function () {
  const response = http.get(`${BASE_URL}/api/flaky?rate=${failureRate}`, { tags: { endpoint: 'flaky' } });
  check(response, { 'status is 200 or simulated 500': (r) => r.status === 200 || r.status === 500 });
  sleep(0.1);
}
