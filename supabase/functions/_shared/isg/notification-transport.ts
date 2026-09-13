import { type Outcome, type Prepared, type Snapshot, validSnapshot } from './notification-worker.ts';
export type FetchPort = (url: string, init: RequestInit) => Promise<Response>;
export type Credentials =
  | { provider: 'apns'; bearer: string; topic: string; environment: 'sandbox' | 'production' }
  | { provider: 'fcm'; bearer: string; project: string };
const error = (failure: string): Outcome => ({ state: 'error', failure });
const rejected = (failure: string): Outcome => ({ state: 'rejected', failure });

// Conservative one-minute floor; never truncate a longer provider wait to send
// early. Unrepresentable waits require review instead of automatic retry.
export function parseProviderWait(value: string | null, now: number): number | null {
  if (!Number.isFinite(now)) return null;
  if (value === null) return 60;
  let seconds: number;
  if (/^\d{1,8}$/.test(value)) seconds = Number(value);
  else if (/^(Mon|Tue|Wed|Thu|Fri|Sat|Sun), \d{2} [A-Z][a-z]{2} \d{4} \d{2}:\d{2}:\d{2} GMT$/.test(value))
    seconds = Math.ceil((Date.parse(value) - now) / 1000);
  else return null;
  return Number.isFinite(seconds) && seconds <= 86400 ? Math.max(60, seconds) : null;
}

// Deliberately do not inherit legacy delivery helpers' internal retry loops.
// No implicit global fetch or secret loading; callers must supply both ports.
export function preparePush(snapshot: Snapshot, credentials: Credentials, fetchPort: FetchPort, now = () => Date.now()): Prepared {
  const s = structuredClone(snapshot), c = structuredClone(credentials);
  if (!validSnapshot(s, s.job_id) || c.provider !== s.provider || typeof c.bearer !== 'string' || c.bearer.length > 8192 || !/^[A-Za-z0-9._~+/-]+=*$/.test(c.bearer)) throw Error('INVALID_TRANSPORT_CONFIG');
  let url: string;
  const headers: Record<string, string> = { authorization: `Bearer ${c.bearer}`, 'content-type': 'application/json' };
  if (c.provider === 'apns') {
    if (!/^[a-f0-9]{64,200}$/i.test(s.token) || !/^[A-Za-z0-9.-]{3,200}$/.test(c.topic) || !['sandbox','production'].includes(c.environment)) throw Error('INVALID_APNS_CONFIG');
    url = `https://${c.environment === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com'}/3/device/${s.token}`;
    headers['apns-topic'] = c.topic;
    headers['apns-push-type'] = 'alert';
  } else {
    if (!/^[a-z][a-z0-9-]{4,62}$/.test(c.project) || !/^[A-Za-z0-9_:.-]{1,4096}$/.test(s.token)) throw Error('INVALID_FCM_CONFIG');
    url = `https://fcm.googleapis.com/v1/projects/${c.project}/messages:send`;
  }
  let used = false;
  return { async send(route, token, signal) {
    if (used) throw Error('TRANSPORT_ALREADY_USED');
    used = true;
    if (!/^[a-z][a-z0-9_/-]{2,120}$/.test(route) || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(token)) throw Error('INVALID_SEND_ARGUMENTS');
    if (signal.aborted) return error('TRANSPORT_UNKNOWN');
    // Only allowlisted metadata reaches the provider, not arbitrary domain
    // objects or credentials. The caller must select approved title/body text;
    // length validation here is not a personal-data sanitizer.
    const data = { schema_version: '1', job_id: s.job_id, route };
    const payload = c.provider === 'apns'
      ? { aps: { alert: { title: s.title, body: s.body }, sound: 'default' }, data }
      : { message: { token: s.token, notification: { title: s.title, body: s.body }, data } };
    const requestHeaders = { ...headers, ...(c.provider === 'apns' ? { 'apns-id': token } : {}) };
    try {
      const response = await fetchPort(url, { method: 'POST', headers: requestHeaders,
        body: JSON.stringify(payload), signal, redirect: 'error' });
      // Status is already enough for acceptance. A failed body read must not
      // turn an accepted message into a retryable failure.
      void response.body?.cancel().catch(() => {});
      if (response.status === 200) return { state: 'accepted', failure: null };
      if (response.status === 429) {
        const wait = parseProviderWait(response.headers.get('retry-after'), now());
        return wait === null ? error('PROVIDER_RETRY_POLICY_REQUIRED') : { state: 'rejected', failure: 'RATE_LIMITED', retry_after_seconds: wait };
      }
      if (response.status >= 500 || response.status < 400) return error('PROVIDER_RESULT_UNKNOWN');
      if (response.status === 401 || response.status === 403) return rejected('PROVIDER_AUTH_REQUIRED');
      if (response.status === 410 && c.provider === 'apns') return rejected('TOKEN_INVALID');
      // A bare FCM 404 / APNs 400 does NOT prove token invalidity. Do not
      // disable a device without a verified provider-specific reason envelope.
      return rejected('PROVIDER_REQUEST_REJECTED');
    } catch { return error('TRANSPORT_UNKNOWN'); }
  } };
}
