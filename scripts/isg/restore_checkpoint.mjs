#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { createReadStream, chmodSync, readFileSync, realpathSync, writeFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { createInterface } from 'node:readline';
import { resolve, relative, sep } from 'node:path';
import { ROOT } from './lib.mjs';

const container = 'isg_restore_20260912_db';
const original = resolve(ROOT, 'backups/riskdetected-change-point-20260912-182850');
let target; let stage = 'preflight';
const report = { schema_version: 1, started_at: new Date().toISOString(), container, isolation: 'none-network/no-published-ports/no-host-mounts', steps: [], full_application_restore_proven: false };
function inspect() {
  const r = spawnSync('docker', ['inspect', container], { encoding: 'utf8' });
  if (r.status !== 0) throw new Error('RESTORE_CONTAINER_MISSING');
  const i = JSON.parse(r.stdout)[0];
  if (i.Name !== `/${container}` || i.Config.Labels?.['com.riskdetected.isg-restore'] !== '20260912' ||
    i.HostConfig.NetworkMode !== 'none' || Object.keys(i.NetworkSettings.Ports ?? {}).length || i.Mounts.length ||
    i.HostConfig.Privileged || i.State.Running !== true) throw new Error('RESTORE_ISOLATION_FAILED');
}
function query(sql) {
  inspect();
  const r = spawnSync('docker', ['exec', '-i', container, 'psql', '-X', '-U', 'supabase_admin', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=sqlstate', '-Atq'], { input: sql, encoding: 'utf8', timeout: 180_000, maxBuffer: 4 * 1024 * 1024 });
  if (r.status !== 0) {
    if (target) writeFileSync(resolve(target, `${stage}-error.txt`), r.stderr || 'child failed', { mode: 0o600 });
    const state = r.stderr?.match(/ERROR:\s+([A-Z0-9]{5})\b/)?.[1];
    throw new Error(`RESTORE_SQL_FAILED${state ? `_${state}` : ''}`);
  }
  return r.stdout.trim();
}
function sqlFile(file) { return query(readFileSync(file, 'utf8')); }
try {
  const args = process.argv.slice(2);
  if (args.length !== 1) throw new Error('RESTORE_MANAGED_DIRECTORY_REQUIRED');
  target = realpathSync(resolve(ROOT, args[0]));
  const base = realpathSync(resolve(ROOT, 'backups')) + sep;
  if (!target.startsWith(base + 'isg-managed-schema-20260912-') || target.slice(base.length).includes(sep)) throw new Error('RESTORE_DIRECTORY_NOT_APPROVED');
  if (existsSync(resolve(target, 'RESTORE_STARTED'))) {
    // Fail without replacing the prior run's evidence.
    target = undefined;
    throw new Error('RESTORE_ALREADY_STARTED_USE_REVIEWED_RECOVERY');
  }
  const m = JSON.parse(readFileSync(resolve(target, 'MANIFEST.json'), 'utf8'));
  for (const file of ['managed-pre-data.sql', 'managed-post-data.sql']) {
    const expected = m.files.find(f => f.file === file)?.sha256;
    if (!expected || createHash('sha256').update(readFileSync(resolve(target, file))).digest('hex') !== expected) throw new Error('RESTORE_SUPPLEMENT_HASH_MISMATCH');
  }
  // Validate the immutable source SQL inside the restore preflight as well;
  // do not rely only on a separate earlier backup-verification command.
  const originalHashes = {
    'supabase-data.sql': '118c22fffc32a151e41624938934e517b8a5af26cef3a3666a2708cebd28856a',
    'supabase-roles.sql': '25873cec56a2cc6514e204f420231777f85c03da818caa7090cdcdfa89776ecd',
    'supabase-schema.sql': 'c12ddd189b08c5d79b747befe37ca1edae45a521f45fcc668818f3820de9e0dc',
  };
  for (const [file, expected] of Object.entries(originalHashes)) {
    const hash = createHash('sha256');
    for await (const chunk of createReadStream(resolve(original, file))) hash.update(chunk);
    if (hash.digest('hex') !== expected) throw new Error('RESTORE_ORIGINAL_HASH_MISMATCH');
  }
  inspect();
  // Never replace an existing populated domain database, even if the name matches.
  if (query("select count(*) from information_schema.tables where table_schema='public' and table_name='profiles';") !== '0') throw new Error('RESTORE_DATABASE_NOT_EMPTY');
  writeFileSync(resolve(target, 'RESTORE_STARTED'), report.started_at + '\n', { mode: 0o600 });
  stage = 'managed-pre-data';
  query('DROP SCHEMA auth CASCADE; DROP SCHEMA storage CASCADE;');
  sqlFile(resolve(target, 'managed-pre-data.sql')); report.steps.push({ stage, ok: true });
  // Application FKs require auth/storage PKs first. Only the profile bootstrap
  // trigger depends on public functions that are loaded in the next step.
  const managedPost = readFileSync(resolve(target, 'managed-post-data.sql'), 'utf8');
  const deferredTrigger = 'CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.tg_create_profile_for_new_user();';
  if (managedPost.split(deferredTrigger).length !== 2) throw new Error('RESTORE_MANAGED_TRIGGER_CONTRACT_DRIFT');
  const managedConstraints = managedPost.replace(deferredTrigger, '-- Profile bootstrap deferred until application functions exist.');
  if (/\b(?:public|private)\./.test(managedConstraints)) throw new Error('RESTORE_UNREVIEWED_MANAGED_DEPENDENCY');
  stage = 'managed-constraints'; query(managedConstraints); report.steps.push({ stage, ok: true });
  stage = 'queue-bootstrap';
  query("CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog; CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions; CREATE EXTENSION IF NOT EXISTS pgmq; SELECT pgmq.create('analysis_jobs');"); report.steps.push({ stage, ok: true });
  stage = 'application-schema'; sqlFile(resolve(original, 'supabase-schema.sql')); report.steps.push({ stage, ok: true });
  stage = 'profile-bootstrap-trigger'; query(deferredTrigger); report.steps.push({ stage, ok: true });
  stage = 'role-settings'; sqlFile(resolve(original, 'supabase-roles.sql')); report.steps.push({ stage, ok: true });
  stage = 'data-copy'; sqlFile(resolve(original, 'supabase-data.sql')); report.steps.push({ stage, ok: true });
  stage = 'row-count-reconciliation';
  const counts = {}; let table = null;
  for await (const line of createInterface({ input: createReadStream(resolve(original, 'supabase-data.sql')), crlfDelay: Infinity })) {
    const match = line.match(/^COPY "([^"]+)"\."([^"]+)" /);
    if (match) { table = `${match[1]}.${match[2]}`; counts[table] = 0; }
    else if (line === '\\.') table = null;
    else if (table) counts[table]++;
  }
  const quote = s => '"' + s.replaceAll('"', '""') + '"';
  const sql = Object.keys(counts).map((name,i) => `SELECT ${i} AS ordinal, count(*) FROM ${name.split('.').map(quote).join('.')}`).join(' UNION ALL ') + ' ORDER BY ordinal;';
  const actual = query(sql).split('\n').map(l => Number(l.split('|')[1]));
  if (actual.length !== Object.keys(counts).length || actual.some((n,i) => n !== Object.values(counts)[i])) throw new Error('RESTORE_ROW_COUNT_MISMATCH');
  report.steps.push({ stage, ok: true, tables: actual.length });
  stage = 'foreign-keys-and-summary';
  report.database_validation = JSON.parse(sqlFile(resolve(ROOT, 'scripts/isg/sql/restore_validate.sql')));
  report.steps.push({ stage, ok: true }); report.ok = true;
} catch (error) {
  report.ok = false; report.failed_stage = stage;
  report.error_code = /^RESTORE_/.test(error.message) ? error.message : 'RESTORE_FAILED';
}
report.finished_at = new Date().toISOString();
report.duration_seconds = (Date.parse(report.finished_at)-Date.parse(report.started_at))/1000;
if (target) { writeFileSync(resolve(target, 'RESTORE_REPORT.json'), JSON.stringify(report, null, 2) + '\n', { mode: 0o600 }); chmodSync(resolve(target, 'RESTORE_REPORT.json'), 0o600); }
console.log(JSON.stringify(report, null, 2));
process.exitCode = report.ok ? 0 : 1;
