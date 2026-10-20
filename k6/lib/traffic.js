import http from 'k6/http';
import { check, sleep } from 'k6';

export const BASE_URL = __ENV.BASE_URL || 'http://demo-api:8080';

// Realistic traffic mix: mostly cheap reads, some slow calls, a few failures and CPU work.
// The db endpoint goes through a small connection pool, so it is the first to saturate under stress.
const mix = [
  { weight: 40, path: '/api/fast', name: 'fast' },
  { weight: 20, path: '/api/slow?ms=120', name: 'slow' },
  { weight: 25, path: '/api/db', name: 'db' },
  { weight: 8, path: '/api/flaky?rate=0.05', name: 'flaky' },
  { weight: 7, path: '/api/cpu?iterations=150000', name: 'cpu' },
];

const totalWeight = mix.reduce((sum, item) => sum + item.weight, 0);

function pick() {
  let roll = Math.random() * totalWeight;
  for (const item of mix) {
    roll -= item.weight;
    if (roll <= 0) {
      return item;
    }
  }
  return mix[0];
}

export function hitRandomEndpoint() {
  const endpoint = pick();
  const response = http.get(`${BASE_URL}${endpoint.path}`, {
    tags: { endpoint: endpoint.name },
  });

  // The flaky endpoint is expected to fail sometimes, so only check it loosely.
  check(response, {
    'status is 2xx or expected 500': (r) =>
      (r.status >= 200 && r.status < 300) || (endpoint.name === 'flaky' && r.status === 500),
  });

  sleep(Math.random() * 0.5);
}

// Thresholds shared by scenarios. Individual scenarios may loosen them.
export const defaultThresholds = {
  http_req_failed: [{ threshold: 'rate<0.10', abortOnFail: false }],
  http_req_duration: ['p(95)<800', 'p(99)<1500'],
  'http_req_duration{endpoint:fast}': ['p(95)<100'],
};
