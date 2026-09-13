// Persistent POSIX host adapter. Never put this journal on Edge /tmp: that is
// ephemeral. The private directory must be provisioned on durable storage.
import { constants } from 'node:fs';
import { open, link, unlink, readdir, realpath, lstat } from 'node:fs/promises';
import { isAbsolute, join, resolve } from 'node:path';
import { randomUUID } from 'node:crypto';
import { type Receipt, type Repository, type WorkerPorts, validOutcome, runNotificationJob } from './notification-worker.ts';

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
function canonical(receipt: Receipt): string {
  if (!receipt || !uuid.test(receipt.job_id) || !uuid.test(receipt.dispatch_token) ||
    !['apns', 'fcm'].includes(receipt.provider) || !validOutcome(receipt) ||
    typeof receipt.now !== 'string' || !/^\d{4}-\d{2}-\d{2}T/.test(receipt.now) || !Number.isFinite(Date.parse(receipt.now)))
    throw Error('JOURNAL_RECEIPT_INVALID');
  // Deliberately project: no title/body, device token, credential, or arbitrary metadata.
  return JSON.stringify({ job_id: receipt.job_id, dispatch_token: receipt.dispatch_token,
    provider: receipt.provider, state: receipt.state, failure: receipt.failure, now: receipt.now,
    ...(receipt.retry_after_seconds === undefined ? {} : { retry_after_seconds: receipt.retry_after_seconds }) });
}
export type ReceiptJournal = {
  save(receipt: Receipt): Promise<void>;
  acknowledge(receipt: Receipt): Promise<void>;
  pending(limit: number): Promise<Receipt[]>;
};
export async function openNotificationJournal(directory: string): Promise<ReceiptJournal> {
  if (!isAbsolute(directory) || await realpath(directory) !== resolve(directory)) throw Error('JOURNAL_DIRECTORY_INVALID');
  const stat = await lstat(directory);
  if (!stat.isDirectory() || (stat.mode & 0o077) !== 0) throw Error('JOURNAL_DIRECTORY_NOT_PRIVATE');
  const read = async (name: string) => {
    const file = await open(join(directory, name), constants.O_RDONLY | constants.O_NOFOLLOW);
    try {
      const info = await file.stat();
      if (!info.isFile() || info.size > 2048 || (info.mode & 0o077) !== 0) throw Error('JOURNAL_FILE_INVALID');
      return await file.readFile('utf8');
    } finally { await file.close(); }
  };
  const syncDirectory = async () => {
    const handle = await open(directory, constants.O_RDONLY | constants.O_NOFOLLOW);
    try { await handle.sync(); } finally { await handle.close(); }
  };
  const persist = async (name: string, body: string) => {
    const temporary = join(directory, `.pending-${randomUUID()}`);
    const handle = await open(temporary, 'wx', 0o600);
    try { await handle.writeFile(body); await handle.sync(); }
    finally { await handle.close(); }
    try {
      try { await link(temporary, join(directory, name)); }
      catch (error) {
        if ((error as { code?: string }).code !== 'EEXIST') throw error;
        if (await read(name) !== body) throw Error('JOURNAL_RECEIPT_CONFLICT');
      }
      await syncDirectory();
    } finally { await unlink(temporary); }
  };
  return {
    async save(receipt) {
      const body = canonical(receipt);
      await persist(`${receipt.dispatch_token}.receipt`, body);
    },
    async acknowledge(receipt) {
      const body = canonical(receipt);
      if (await read(`${receipt.dispatch_token}.receipt`) !== body) throw Error('JOURNAL_RECEIPT_CONFLICT');
      await persist(`${receipt.dispatch_token}.ack`, body);
    },
    async pending(limit) {
      if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw Error('JOURNAL_LIMIT_INVALID');
      const names = await readdir(directory);
      const set = new Set(names), result: Receipt[] = [];
      for (const name of names.sort()) {
        if (!name.endsWith('.receipt')) continue;
        const token = name.slice(0, -8);
        if (!uuid.test(token)) throw Error('JOURNAL_FILE_INVALID');
        const body = await read(name), receipt = JSON.parse(body) as Receipt;
        if (canonical(receipt) !== body || receipt.dispatch_token !== token) throw Error('JOURNAL_FILE_INVALID');
        if (set.has(`${token}.ack`)) {
          if (await read(`${token}.ack`) !== body) throw Error('JOURNAL_RECEIPT_CONFLICT');
          continue;
        }
        result.push(receipt);
        if (result.length === limit) break;
      }
      return result;
    },
  };
}

/** Replays SQL only. No credential or provider port is available here. */
export async function reconcileNotificationJournal(journal: ReceiptJournal, repository: Pick<Repository, 'complete'>, limit = 100) {
  let receipts: Receipt[];
  try { receipts = await journal.pending(limit); }
  catch { return { status: 'journal_unavailable', reconciled: 0 }; }
  let reconciled = 0;
  for (const receipt of receipts) {
    try {
      await repository.complete(structuredClone(receipt));
      await journal.acknowledge(receipt);
      reconciled++;
    } catch { return { status: 'reconcile_pending', reconciled }; }
  }
  return { status: receipts.length === limit ? 'reconcile_more' : 'reconciled', reconciled };
}

/** Explicit one-batch runner; no timer, HTTP endpoint, automatic send retry or
 * deployment. Stop the batch on uncertainty. Only aggregate codes escape. */
export async function runNotificationBatch(jobs: readonly string[], mode: 'off' | 'shadow' | 'live',
  ports: WorkerPorts & { journal: ReceiptJournal }) {
  if (mode === 'off') return { status: 'disabled', processed: 0 };
  if (!['live', 'shadow'].includes(mode) || jobs.length > 100 || jobs.some(id => !uuid.test(id)))
    return { status: 'invalid_input', processed: 0 };
  if (mode === 'live') {
    const replay = await reconcileNotificationJournal(ports.journal, ports.repository);
    if (replay.status !== 'reconciled') return { status: replay.status, processed: 0 };
  }
  let processed = 0;
  for (const job of new Set(jobs)) {
    const result = await runNotificationJob(job, mode, ports);
    processed++;
    if (!['recorded', 'not_claimed', 'unavailable', 'snapshot_changed', 'shadow_no_send'].includes(result.status))
      return { status: result.status, processed };
    // A known uncertain outcome must not allow the batch to become a storm.
    if (result.receipt?.state === 'error') return { status: 'provider_uncertain', processed };
    if (result.receipt?.failure === 'RATE_LIMITED') return { status: 'provider_rate_limited', processed };
  }
  return { status: 'batch_complete', processed };
}
