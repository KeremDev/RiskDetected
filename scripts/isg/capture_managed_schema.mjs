#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve, relative } from 'node:path';
import { ROOT, policy } from './lib.mjs';

// Explicit read-only supplement for the pinned P00 checkpoint. No data rows or DDL execution.
try {
  if (process.argv.length !== 2) throw new Error('BACKUP_ARGUMENTS_NOT_ALLOWED');
  const ref = readFileSync(resolve(ROOT, 'supabase/.temp/project-ref'), 'utf8').trim();
  if (ref !== policy.production_project_refs[0]) throw new Error('LINKED_PROJECT_MISMATCH');
  const connection = new URL(readFileSync(resolve(ROOT, 'supabase/.temp/pooler-url'), 'utf8').trim());
  if (!['postgres:', 'postgresql:'].includes(connection.protocol) || decodeURIComponent(connection.username) !== `postgres.${ref}` || !connection.hostname.endsWith('.pooler.supabase.com') || connection.pathname !== '/postgres') throw new Error('BACKUP_CONNECTION_NOT_APPROVED');
  const key = spawnSync('security', ['find-generic-password', '-a', process.env.USER ?? '', '-s', 'riskdetected_supabase_db_password', '-w'], { encoding: 'utf8' });
  if (key.status !== 0 || !key.stdout.trim()) throw new Error('BACKUP_CREDENTIAL_UNAVAILABLE');
  mkdirSync(resolve(ROOT, 'backups'), { recursive: true });
  const target = mkdtempSync(resolve(ROOT, 'backups/isg-managed-schema-20260912-')); chmodSync(target, 0o700);
  const env = { PATH: process.env.PATH, PGHOST: connection.hostname, PGPORT: connection.port || '5432', PGUSER: decodeURIComponent(connection.username), PGDATABASE: 'postgres', PGPASSWORD: key.stdout.trim(), PGSSLMODE: 'require', PGCONNECT_TIMEOUT: '15', PGAPPNAME: 'isg-p00-readonly-schema-backup', PGOPTIONS: '-c default_transaction_read_only=on -c statement_timeout=60000' };
  const files = [];
  for (const section of ['pre-data', 'post-data']) {
    const file = `managed-${section}.sql`; const path = resolve(target, file);
    const r = spawnSync('pg_dump', ['--schema-only', '--schema=auth', '--schema=storage', `--section=${section}`, '--file', path], { env, encoding: 'utf8', timeout: 120_000 });
    if (r.status !== 0) throw new Error('MANAGED_SCHEMA_CAPTURE_FAILED');
    chmodSync(path, 0o600);
    const data = readFileSync(path); files.push({ file, bytes: data.length, sha256: createHash('sha256').update(data).digest('hex') });
  }
  const manifest = { captured_at: new Date().toISOString(), project_ref: ref, mode: 'read_only_schema_supplement', contains_data_rows: false, note: 'Captured after original data checkpoint; restore must prove compatibility. SQL is restricted, not a public fixture.', files };
  writeFileSync(resolve(target, 'MANIFEST.json'), JSON.stringify(manifest, null, 2) + '\n', { mode: 0o600 });
  console.log(JSON.stringify({ ok: true, backup_root: relative(ROOT, target), ...manifest }, null, 2));
} catch (error) {
  console.error(/^(LINKED_|BACKUP_|MANAGED_)/.test(error.message) ? error.message : 'MANAGED_SCHEMA_BACKUP_FAILED');
  process.exitCode = 1;
}
