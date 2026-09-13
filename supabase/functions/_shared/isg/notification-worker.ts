// Internal orchestration only. No HTTP entry point, scheduler, env lookup or
// database credentials. Production binding requires a restricted repository.
export type Device = { owner_id: string; app_build: number; category_enabled: boolean; os_authorized: boolean };
export type Snapshot = { job_id: string; device: Device; provider: 'apns' | 'fcm'; token: string; title: string; body: string };
export type Claim = { job_id: string; allowed: boolean; dispatch_token?: string; expires_at?: string; resolved_route?: string; channel?: string };
export type Outcome = { state: 'accepted' | 'rejected' | 'error'; failure: string | null; retry_after_seconds?: number };
export type Receipt = Outcome & { job_id: string; dispatch_token: string; provider: 'apns' | 'fcm'; now: string };
export type Repository = {
  load(job: string): Promise<Snapshot | null>;
  claim(job: string, device: Device, now: string): Promise<Claim>;
  complete(receipt: Receipt): Promise<unknown>;
};
export type Prepared = { send(route: string, token: string, signal: AbortSignal): Promise<Outcome> };
export type WorkerPorts = {
  repository: Repository;
  prepare(snapshot: Snapshot): Promise<Prepared>;
  enabled(): Promise<boolean>;
  now(): number;
};
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export function validSnapshot(s: Snapshot, job: string): boolean {
  return s?.job_id === job && uuid.test(job) && !!s.device && uuid.test(s.device.owner_id) &&
    Number.isSafeInteger(s.device.app_build) && s.device.app_build > 0 && s.device.app_build <= 2147483647 &&
    typeof s.device.category_enabled === 'boolean' && typeof s.device.os_authorized === 'boolean' &&
    ['apns', 'fcm'].includes(s.provider) && typeof s.token === 'string' && s.token.length > 0 && s.token.length <= 4096 &&
    typeof s.title === 'string' && s.title.length > 0 && s.title.length <= 120 &&
    typeof s.body === 'string' && s.body.length > 0 && s.body.length <= 500;
}
function normalized(s: Snapshot): string {
  return JSON.stringify([s.job_id, s.provider, s.token, s.title, s.body, s.device.owner_id,
    s.device.app_build, s.device.category_enabled, s.device.os_authorized]);
}
const unknown: Outcome = { state: 'error', failure: 'TRANSPORT_UNKNOWN' };
export function validOutcome(o: Outcome): boolean {
  return !!o && ['accepted', 'rejected', 'error'].includes(o.state) &&
    (o.state === 'accepted' ? o.failure === null : typeof o.failure === 'string' && /^[A-Z][A-Z0-9_]{2,49}$/.test(o.failure)) &&
    (o.retry_after_seconds === undefined || (o.state === 'rejected' &&
      ['RATE_LIMITED','PROVIDER_UNAVAILABLE','TEMPORARY_FAILURE'].includes(o.failure ?? '') &&
      Number.isInteger(o.retry_after_seconds) && o.retry_after_seconds >= 1 && o.retry_after_seconds <= 86400));
}

/** One invocation, one job, at most ONE network request. Never retry send on
 * a receipt failure. All returned diagnostics are finite codes, not raw errors. */
export async function runNotificationJob(job: string, mode: 'off' | 'shadow' | 'live', ports: WorkerPorts,
  timeoutMs = 15000): Promise<{ status: string; receipt?: Receipt }> {
  if (mode === 'off') return { status: 'disabled' };
  if (!['shadow', 'live'].includes(mode) || !uuid.test(job) || !Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 15000)
    return { status: 'invalid_input' };
  let snapshot: Snapshot, prepared: Prepared, claim: Claim;
  try {
    if (await ports.enabled() !== true) return { status: 'disabled' };
    const loaded = await ports.repository.load(job);
    if (!loaded || !validSnapshot(loaded, job)) return { status: 'unavailable' };
    snapshot = structuredClone(loaded);
    if (mode === 'shadow') return { status: 'shadow_no_send' };
    prepared = await ports.prepare(structuredClone(snapshot));
    // Credentials can take time to refresh. Re-read trusted device/token state
    // before acquiring permission, not after provider IO has started.
    const latest = await ports.repository.load(job);
    if (!latest || !validSnapshot(latest, job) || normalized(snapshot) !== normalized(latest)) return { status: 'snapshot_changed' };
    if (await ports.enabled() !== true) return { status: 'disabled' };
    const now = ports.now();
    if (!Number.isFinite(now)) return { status: 'invalid_clock' };
    claim = await ports.repository.claim(job, latest.device, new Date(now).toISOString());
  } catch { return { status: 'preflight_failed' }; }
  if (claim?.allowed !== true) return { status: 'not_claimed' };
  const expiry = Date.parse(claim.expires_at ?? '');
  if (claim.job_id !== job || claim.channel !== 'push' || !uuid.test(claim.dispatch_token ?? '') ||
    !/^[a-z][a-z0-9_/-]{2,120}$/.test(claim.resolved_route ?? '') || !Number.isFinite(expiry))
    return { status: 'invalid_claim_reconcile' };
  const sendTime = ports.now();
  if (!Number.isFinite(sendTime) || expiry - sendTime < timeoutMs + 1000) return { status: 'expired_claim_reconcile' };
  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  let outcome: Outcome;
  try {
    const deadline = new Promise<Outcome>((resolve) => {
      timer = setTimeout(() => { controller.abort(); resolve(unknown); }, timeoutMs);
    });
    outcome = await Promise.race([prepared.send(claim.resolved_route!, claim.dispatch_token!, controller.signal), deadline]);
    if (!validOutcome(outcome)) outcome = unknown;
  } catch { outcome = unknown; }
  finally { clearTimeout(timer); controller.abort(); }
  let completedTime = sendTime;
  try { const sampled = ports.now(); if (Number.isFinite(sampled) && Math.abs(sampled) <= 8640000000000000) completedTime = Math.max(sendTime, sampled); } catch { /* retain the known valid send time */ }
  const receipt: Receipt = { ...outcome, job_id: job, dispatch_token: claim.dispatch_token!, provider: snapshot.provider,
    now: new Date(completedTime).toISOString() };
  try {
    await ports.repository.complete(receipt);
    return { status: 'recorded', receipt };
  } catch {
    // Persist/replay this exact receipt at the future repository binding. Do not
    // invoke prepare/send again. If the process dies, the DB lease stays uncertain.
    return { status: 'receipt_pending_reconcile', receipt };
  }
}
