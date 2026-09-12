#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve, relative } from 'node:path';
import { ROOT, policy } from './lib.mjs';

// P00 read-only supplement: service migration ledgers omitted by the original
// application data dump. No customer queries, remote writes or migration apply.
try {
  if (process.argv.length !== 2) throw new Error('BACKUP_ARGUMENTS_NOT_ALLOWED');
  const ref = readFileSync(resolve(ROOT, 'supabase/.temp/project-ref'), 'utf8').trim();
  if (ref !== policy.production_project_refs[0]) throw new Error('LINKED_PROJECT_MISMATCH');
  const connection = new URL(readFileSync(resolve(ROOT, 'supabase/.temp/pooler-url'), 'utf8').trim());
  if (!['postgres:', 'postgresql:'].includes(connection.protocol) || decodeURIComponent(connection.username) !== `postgres.${ref}` ||
      !connection.hostname.endsWith('.pooler.supabase.com') || connection.pathname !== '/postgres') throw new Error('BACKUP_CONNECTION_NOT_APPROVED');
  const key = spawnSync('security', ['find-generic-password', '-a', process.env.USER ?? '', '-s', 'riskdetected_supabase_db_password', '-w'], { encoding: 'utf8' });
  if (key.status !== 0 || !key.stdout.trim()) throw new Error('BACKUP_CREDENTIAL_UNAVAILABLE');
  const env = { PATH: process.env.PATH, PGHOST: connection.hostname, PGPORT: connection.port || '5432',
    PGUSER: decodeURIComponent(connection.username), PGDATABASE: 'postgres', PGPASSWORD: key.stdout.trim(),
    PGSSLMODE: 'require', PGCONNECT_TIMEOUT: '15', PGAPPNAME: 'isg-p00-readonly-service-migrations',
    PGOPTIONS: '-c default_transaction_read_only=on -c statement_timeout=60000' };
  const target = mkdtempSync(resolve(ROOT, 'backups/isg-managed-migrations-20260912-')); chmodSync(target, 0o700);
  const file = 'managed-migration-data.sql', path = resolve(target, file);
  const dump = spawnSync('pg_dump', ['--data-only', '--table=auth.schema_migrations', '--table=storage.migrations', '--file', path],
    { env, encoding: 'utf8', timeout: 90_000 });
  if (dump.status !== 0) throw new Error('MANAGED_MIGRATION_CAPTURE_FAILED');
  chmodSync(path, 0o600);
  const bytes = readFileSync(path), counts = {}; let table;
  for (const line of bytes.toString('utf8').split('\n')) {
    const match = line.match(/^COPY (auth\.schema_migrations|storage\.migrations) /);
    if (match) { table = match[1]; counts[table] = 0; }
    else if (line === '\\.') table = undefined;
    else if (table) counts[table]++;
  }
  if (Object.keys(counts).length !== 2) throw new Error('MANAGED_MIGRATION_COPY_FORMAT_CHANGED');
  const manifest = { schema_version: 1, captured_at: new Date().toISOString(), project_ref: ref,
    mode: 'read_only_service_migration_ledger', customer_data_queried: false, rows: counts,
    files: [{ file, bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') }],
    note: 'Later supplement, not the original checkpoint timestamp. Required for service auto-migration compatibility; isolated restore still required.' };
  writeFileSync(resolve(target, 'MANIFEST.json'), JSON.stringify(manifest, null, 2) + '\n', { mode: 0o600 });
  console.log(JSON.stringify({ ok: true, backup_root: relative(ROOT, target), ...manifest }, null, 2));
} catch (error) {
  console.error(/^(LINKED_|BACKUP_|MANAGED_)/.test(error.message) ? error.message : 'MANAGED_MIGRATION_BACKUP_FAILED');
  process.exitCode = 1;
}
