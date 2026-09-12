#!/usr/bin/env node
import { createReadStream, readFileSync, readdirSync, realpathSync, lstatSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { createInterface } from 'node:readline';
import { spawnSync } from 'node:child_process';
import { relative, resolve, sep } from 'node:path';
import { ROOT } from './lib.mjs';

// Fixed read-only checkpoint; no SQL execution, extraction, PII rows, or secret output.
const dir = resolve(ROOT, 'backups/riskdetected-change-point-20260912-182850');
const within = p => p.startsWith(`${realpathSync(dir)}${sep}`);
async function hashFile(path) { const h = createHash('sha256'); for await (const chunk of createReadStream(path)) h.update(chunk); return h.digest('hex'); }
const report = { schema_version: 1, captured_at: new Date().toISOString(), checks: [], failures: [], restore_proven: false };
try {
  for (const filename of ['SHA256SUMS', 'storage-file-sha256sums.txt']) {
    let count = 0;
    for (const line of readFileSync(resolve(dir, filename), 'utf8').trim().split('\n')) {
      const match = line.match(/^([a-f0-9]{64})\s+(.+)$/);
      if (!match) throw new Error('MANIFEST_FORMAT_INVALID');
      const file = resolve(ROOT, match[2]);
      if (!within(realpathSync(file)) || lstatSync(file).isSymbolicLink()) throw new Error('MANIFEST_PATH_OUTSIDE_CHECKPOINT');
      if (await hashFile(file) !== match[1]) report.failures.push({ code: 'HASH_MISMATCH', manifest: filename, entry_index: count });
      count++;
    }
    report.checks.push({ kind: 'sha256', manifest: filename, count });
  }
  const counts = {}; let table = null;
  const stream = createInterface({ input: createReadStream(resolve(dir, 'supabase-data.sql')), crlfDelay: Infinity });
  for await (const line of stream) {
    const m = line.match(/^COPY "([^"]+)"\."([^"]+)" /);
    if (m) { table = `${m[1]}.${m[2]}`; counts[table] = 0; }
    else if (line === '\\.') table = null;
    else if (table) counts[table]++;
  }
  report.checks.push({ kind: 'sql_copy_inventory', tables: Object.keys(counts).length, auth_users: counts['auth.users'], auth_identities: counts['auth.identities'], storage_objects: counts['storage.objects'] });
  if (counts['auth.users'] !== 208 || counts['storage.objects'] !== 588) report.failures.push({ code: 'CHECKPOINT_COUNT_MISMATCH' });
  for (const filename of readdirSync(dir).filter(n => n.endsWith('.tar.zst'))) {
    const result = spawnSync('zstd', ['--quiet', '-t', resolve(dir, filename)], { timeout: 120_000, encoding: 'utf8' });
    report.checks.push({ kind: 'archive_integrity', file: filename, ok: result.status === 0 });
    if (result.status !== 0) report.failures.push({ code: 'ARCHIVE_CHECK_FAILED', file: filename });
  }
  const bundle = spawnSync('git', ['bundle', 'verify', resolve(dir, 'repository-history.bundle')], { cwd: ROOT, encoding: 'utf8', timeout: 120_000 });
  report.checks.push({ kind: 'git_bundle', ok: bundle.status === 0 });
  if (bundle.status !== 0) report.failures.push({ code: 'GIT_BUNDLE_INVALID' });
  report.backup_root = relative(ROOT, dir);
} catch (error) {
  // Filesystem/child stderr can include sensitive paths. Emit only controlled codes.
  report.failures.push({ code: /^MANIFEST_/.test(error.message) ? error.message : 'BACKUP_VERIFICATION_FAILED' });
}
report.ok = report.failures.length === 0;
console.log(JSON.stringify(report, null, 2));
process.exitCode = report.ok ? 0 : 1;
