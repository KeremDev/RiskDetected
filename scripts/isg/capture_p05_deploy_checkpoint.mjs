import {spawnSync} from 'node:child_process';
import {chmodSync, mkdtempSync, readFileSync, writeFileSync} from 'node:fs';
import {resolve, relative} from 'node:path';
import {ROOT} from './lib.mjs';
import {hashFile} from './backup_crypto.mjs';

// Read-only, fixed-project checkpoint. Restricted archive may contain personal data
// and database function secrets; never print its contents or commit it to Git.
try {
  if (process.argv.length !== 2) throw Error('CHECKPOINT_ARGUMENTS_DENIED');
  const ref = readFileSync(resolve(ROOT, 'supabase/.temp/project-ref'), 'utf8').trim();
  if (ref !== 'ppcrzemgiztzcgddbins') throw Error('CHECKPOINT_PROJECT_MISMATCH');
  const url = new URL(readFileSync(resolve(ROOT, 'supabase/.temp/pooler-url'), 'utf8').trim());
  if (!['postgres:', 'postgresql:'].includes(url.protocol) || decodeURIComponent(url.username) !== `postgres.${ref}` ||
      !url.hostname.endsWith('.pooler.supabase.com') || url.pathname !== '/postgres') throw Error('CHECKPOINT_CONNECTION_DENIED');
  const key = spawnSync('security', ['find-generic-password', '-a', process.env.USER ?? '', '-s', 'riskdetected_supabase_db_password', '-w'], {encoding: 'utf8'});
  if (key.status !== 0 || !key.stdout.trim()) throw Error('CHECKPOINT_CREDENTIAL_MISSING');
  const target = mkdtempSync(resolve(ROOT, 'backups/isg-p05-predeploy-')); chmodSync(target, 0o700);
  const env = {PATH: process.env.PATH, PGHOST: url.hostname, PGPORT: url.port || '5432', PGUSER: decodeURIComponent(url.username),
    PGDATABASE: 'postgres', PGPASSWORD: key.stdout.trim(), PGSSLMODE: 'require', PGCONNECT_TIMEOUT: '15',
    PGAPPNAME: 'isg-p05-readonly-checkpoint', PGOPTIONS: '-c default_transaction_read_only=on -c statement_timeout=60000 -c lock_timeout=1000'};
  const started_at = new Date().toISOString();
  const file = resolve(target, 'predeploy.dump');
  // umask protects the archive from its first byte, not only after completion.
  process.umask(0o077);
  const dump = spawnSync('pg_dump', ['--format=custom', '--schema=public', '--schema=private', '--schema=auth', '--schema=storage',
    '--schema=supabase_migrations', '--lock-wait-timeout=1000', '--file', file], {env, encoding: 'utf8', timeout: 120000});
  if (dump.status !== 0) throw Error('CHECKPOINT_DUMP_FAILED');
  // Fully read/decompress the archive without running a single restore statement.
  const verify = spawnSync('pg_restore', ['--file=/dev/null', file], {encoding: 'utf8', timeout: 60000});
  if (verify.status !== 0) throw Error('CHECKPOINT_ARCHIVE_INVALID');
  const manifest = {schema_version: 1, project_ref: ref, started_at, finished_at: new Date().toISOString(),
    archive: 'predeploy.dump', sha256: await hashFile(file), read_only: true, archive_read_verified: true,
    full_restore_tested: false, storage_binary_backup: false,
    note: 'Single consistent database archive of affected application/Auth/Storage metadata and migration ledger. This is not a complete managed-project or Storage binary backup. No production restore is authorized.'};
  writeFileSync(resolve(target, 'MANIFEST.json'), JSON.stringify(manifest, null, 2)+'\n', {mode: 0o600});
  console.log(JSON.stringify({ok: true, path: relative(ROOT, target), ...manifest}));
} catch (error) {
  console.error(/^CHECKPOINT_/.test(error.message) ? error.message : 'CHECKPOINT_FAILED');
  process.exitCode = 1;
}
