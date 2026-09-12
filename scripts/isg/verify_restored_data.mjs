#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { existsSync, lstatSync, realpathSync } from 'node:fs';
import { resolve, sep } from 'node:path';
import { ROOT } from './lib.mjs';

const container = 'isg_restore_20260912_db';
function query(sql) {
  const info = spawnSync('docker', ['inspect', container], { encoding: 'utf8' });
  if (info.status !== 0) throw new Error('RESTORE_CONTAINER_MISSING');
  const i = JSON.parse(info.stdout)[0];
  if (i.HostConfig.NetworkMode !== 'none' || i.Mounts.length || Object.keys(i.NetworkSettings.Ports ?? {}).length || i.Config.Labels?.['com.riskdetected.isg-restore'] !== '20260912') throw new Error('RESTORE_ISOLATION_FAILED');
  const r = spawnSync('docker', ['exec', '-i', container, 'psql', '-X', '-U', 'supabase_admin', '-d', 'postgres', '-Atq', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=sqlstate'], { input: sql, encoding: 'utf8', timeout: 60_000, maxBuffer: 4 * 1024 * 1024 });
  if (r.status !== 0) throw new Error('RESTORE_READ_QUERY_FAILED');
  return JSON.parse(r.stdout.trim());
}
try {
  const objects = query("SELECT json_agg(json_build_object('bucket',bucket_id,'name',name,'bytes',(metadata->>'size')::bigint)) FROM storage.objects;");
  const storage = realpathSync(resolve(ROOT, 'backups/riskdetected-change-point-20260912-182850/storage'));
  // The original CLI recursive copies nested the bucket name; legal documents
  // were captured directly. Use the verified checkpoint layout, not guesswork.
  const layout = { reports: ['reports','reports'], photos: ['photos','photos'], logos: ['logos','logos'], avatars: ['avatars','avatars'], 'legal-documents': ['legal-documents'] };
  let bytes = 0; const failures = [];
  for (const [index, object] of objects.entries()) {
    if (!Object.hasOwn(layout, object.bucket)) { failures.push({ code: 'UNKNOWN_CHECKPOINT_BUCKET', index }); continue; }
    const file = resolve(storage, ...layout[object.bucket], object.name);
    if (!file.startsWith(storage + sep) || !existsSync(file) || !realpathSync(file).startsWith(storage + sep) || lstatSync(file).isSymbolicLink()) { failures.push({ code: 'OBJECT_FILE_MISSING_OR_UNSAFE', index }); continue; }
    const size = lstatSync(file).size;
    if (size !== object.bytes) failures.push({ code: 'OBJECT_SIZE_MISMATCH', index });
    bytes += size;
  }
  const rls = query(`BEGIN READ ONLY;
DO $$ DECLARE uid uuid; n bigint; BEGIN
  SELECT user_id INTO uid FROM public.companies GROUP BY user_id ORDER BY count(*) DESC LIMIT 1;
  IF uid IS NULL THEN RAISE EXCEPTION 'OWNER_FIXTURE_UNAVAILABLE'; END IF;
  SELECT count(*) INTO n FROM public.companies WHERE user_id=uid;
  PERFORM set_config('request.jwt.claims', json_build_object('sub',uid,'role','authenticated')::text, true);
  PERFORM set_config('isg.test.expected_company_count',n::text,true);
END $$;
SET LOCAL ROLE authenticated;
SELECT json_build_object(
 'own_companies',(SELECT count(*) FROM public.companies WHERE user_id=auth.uid()),
 'expected_own_companies',current_setting('isg.test.expected_company_count')::bigint,
 'foreign_companies',(SELECT count(*) FROM public.companies WHERE user_id<>auth.uid()),
 'own_profiles',(SELECT count(*) FROM public.profiles WHERE id=auth.uid()),
 'foreign_profiles',(SELECT count(*) FROM public.profiles WHERE id<>auth.uid()),
 'foreign_analyses',(SELECT count(*) FROM public.analyses WHERE user_id<>auth.uid()),
 'foreign_reports',(SELECT count(*) FROM public.reports WHERE user_id<>auth.uid())
);
ROLLBACK;`);
  if (rls.own_companies !== rls.expected_own_companies || rls.own_companies < 1 || rls.own_profiles !== 1 || [rls.foreign_companies,rls.foreign_profiles,rls.foreign_analyses,rls.foreign_reports].some(n=>n!==0)) failures.push({ code: 'RESTORED_OWNER_READ_POLICY_FAILED' });
  console.log(JSON.stringify({ ok: failures.length === 0, captured_at: new Date().toISOString(), storage_objects_checked: objects.length, storage_bytes_matched: bytes, owner_rls: rls, failure_count: failures.length, failures: failures.slice(0,10), full_application_restore_proven: false, remaining: ['Auth API login', 'Storage API signed download', 'iOS/Android connected E2E', 'external configuration restore', 'off-device encrypted copy'] }, null, 2));
  process.exitCode = failures.length ? 1 : 0;
} catch (error) { console.error(/^RESTORE_/.test(error.message) ? error.message : 'RESTORED_DATA_VERIFICATION_FAILED'); process.exitCode = 1; }
