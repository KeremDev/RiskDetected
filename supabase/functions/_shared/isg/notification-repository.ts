import { type Claim, type Receipt, type Repository, type Snapshot, validOutcome, validSnapshot } from './notification-worker.ts';
// Driver adapter must bind values, return the single JSON scalar, and throw on
// SQL errors. No SQL interpolation, credentials, connections or public RPC here.
export type QueryPort = (statement: string, values: readonly unknown[]) => Promise<unknown>;
const CLAIM = 'SELECT private_isg.dispatch_bound_notification($1::uuid,$2::jsonb,$3::timestamptz)';
const COMPLETE = 'SELECT private_isg.complete_notification_delivery_with_retry($1::uuid,$2::uuid,$3::text,$4::text,$5::text,$6::timestamptz,$7::integer)';
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const object = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === 'object' && !Array.isArray(v);
const stamp = (v: string) => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}T/.test(v) && Number.isFinite(Date.parse(v));
export function createNotificationRepository(query: QueryPort, loadTrusted: (job: string) => Promise<Snapshot | null>): Repository {
  const execute = async (sql: string, args: readonly unknown[]) => {
    let result: unknown;
    try { result = await query(sql, args); } catch { throw Error('NOTIFICATION_DATABASE_UNAVAILABLE'); }
    if (!object(result) || result.error !== undefined || result.schema_version !== 1) throw Error('NOTIFICATION_DATABASE_RESPONSE_INVALID');
    return result;
  };
  return {
    async load(job) {
      if (!uuid.test(job)) throw Error('NOTIFICATION_SCOPE_INVALID');
      const value = await loadTrusted(job);
      if (value === null) return null;
      if (!validSnapshot(value, job)) throw Error('NOTIFICATION_SNAPSHOT_INVALID');
      return structuredClone(value);
    },
    async claim(job, device, now) {
      if (!uuid.test(job) || !uuid.test(device.owner_id) ||
        (device.installation_id !== undefined && !uuid.test(device.installation_id)) || !stamp(now) || !Number.isInteger(device.app_build) ||
        device.app_build < 1 || device.app_build > 2147483647 || typeof device.category_enabled !== 'boolean' || typeof device.os_authorized !== 'boolean') throw Error('NOTIFICATION_SCOPE_INVALID');
      const r = await execute(CLAIM, [job, JSON.stringify(device), now]);
      if (r.job_id !== job || typeof r.allowed !== 'boolean') throw Error('NOTIFICATION_CLAIM_INVALID');
      if (r.allowed && (!uuid.test(String(r.dispatch_token ?? '')) || typeof r.expires_at !== 'string' || !stamp(r.expires_at) ||
        r.channel !== 'push' || typeof r.resolved_route !== 'string' || !/^[a-z][a-z0-9_/-]{2,120}$/.test(r.resolved_route))) throw Error('NOTIFICATION_CLAIM_INVALID');
      return r as Claim;
    },
    async complete(receipt: Receipt) {
      if (!uuid.test(receipt.job_id) || !uuid.test(receipt.dispatch_token) || !['apns','fcm'].includes(receipt.provider) || !stamp(receipt.now) || !validOutcome(receipt)) throw Error('NOTIFICATION_RECEIPT_INVALID');
      const r = await execute(COMPLETE, [receipt.job_id, receipt.dispatch_token, receipt.provider, receipt.state, receipt.failure, receipt.now, receipt.retry_after_seconds ?? null]);
      if (r.job_id !== receipt.job_id || r.dispatch_token !== receipt.dispatch_token || !uuid.test(String(r.attempt_id ?? '')) ||
        typeof r.replayed !== 'boolean' || !['sent','failed','dead','uncertain','dispatching','suppressed','cancelled'].includes(String(r.job_state)) ||
        r.delivery_confirmed !== false || r.read_confirmed !== false || r.retry_after_seconds !== (receipt.retry_after_seconds ?? null)) throw Error('NOTIFICATION_RECEIPT_RESPONSE_INVALID');
      return r;
    },
  };
}
