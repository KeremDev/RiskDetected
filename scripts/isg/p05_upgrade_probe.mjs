import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
export const p05UpgradeFiles = ['scripts/isg/p05_upgrade_probe.mjs',
  'supabase/migrations/20260913074153_isg_personnel_owner_rpc.sql',
  'supabase/migrations/20260913081536_isg_workplace_context_assignments.sql',
  'supabase/migrations/20260913084736_isg_workspace_availability.sql',
  'supabase/migrations/20260913092642_isg_personnel_reactivation.sql',
  'supabase/migrations/20260913110000_isg_event_dispatch.sql',
  'supabase/migrations/20260913113000_isg_quota_reservations.sql',
  'supabase/migrations/20260913130000_isg_file_core.sql',
  'supabase/migrations/20260913150000_isg_rule_core.sql'];

/** Called only on the runner's freshly cloned, network=none, identity-guarded target. */
export function probeP05Upgrade({sql,pass,isolatedCopy}) {
  if (isolatedCopy !== true) throw Error('P05_UPGRADE_ISOLATED_COPY_REQUIRED');
  // One transaction/session per snapshot: only hashes, no rows/names reach the report.
  const fingerprint = () => sql(`BEGIN;
    ${snapshotSQL()}
    SELECT md5(string_agg(name||digest,'' ORDER BY name)) FROM p05_snapshot;COMMIT;`).split('\n').at(-1);
  const before = fingerprint();
  const helperIDs = sql("SELECT string_agg(p.oid::text,',' ORDER BY p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','private') AND p.prokind='f';");
  if (!/^[0-9]+(,[0-9]+)*$/.test(helperIDs)) throw Error('P05_UPGRADE_HELPER_INVENTORY_INVALID');
  const helperSnapshot = () => sql(`SELECT md5(string_agg(pg_get_functiondef(oid),'' ORDER BY oid)) FROM pg_proc WHERE oid IN (${helperIDs});`);
  const helpers = helperSnapshot();
  pass('p05_full_copy_original_rows_fingerprinted', /^[a-f0-9]{32}$/.test(before));
  for (const path of p05UpgradeFiles.slice(1)) sql(readFileSync(resolve(ROOT,path),'utf8'));
  pass('p05_full_copy_legacy_rows_unchanged', fingerprint() === before);
  pass('p05_full_copy_legacy_helpers_unchanged', helperSnapshot() === helpers);
  pass('p05_full_copy_rollout_closed', sql("SELECT NOT read_enabled AND NOT write_enabled FROM private_isg.rollout WHERE feature='personnel';") === 't');
  pass('p05_full_copy_dispatch_and_quota_rollout_closed', sql("SELECT count(*)=4 AND bool_and(NOT read_enabled AND NOT write_enabled) FROM private_isg.rollout WHERE feature IN ('event_dispatch','quota_ledger','file_core','rule_engine');") === 't');
  // Nothing consumes or reserves yet: the new ledgers replay empty on real legacy data.
  pass('p05_full_copy_ledgers_start_empty', sql("SELECT (SELECT count(*) FROM private_isg.consumer_registry)+(SELECT count(*) FROM private_isg.event_deliveries)+(SELECT count(*) FROM private_isg.quota_reservations)+(SELECT count(*) FROM private_isg.legacy_entitlement_floors)+(SELECT count(*) FROM private_isg.upload_intents)+(SELECT count(*) FROM private_isg.file_assets)+(SELECT count(*) FROM private_isg.legal_sources)+(SELECT count(*) FROM private_isg.rule_versions);") === '0');
  pass('p05_full_copy_one_default_per_company', sql("SELECT NOT EXISTS(SELECT c.id FROM public.companies c LEFT JOIN private_isg.workplaces w ON w.company_id=c.id AND w.legacy_company_id=c.id GROUP BY c.id HAVING count(w.id)<>1);") === 't');
  const state = () => sql("SELECT md5(string_agg(to_jsonb(w)::text,'' ORDER BY id)) FROM private_isg.workplaces w;SELECT count(*) FROM private_isg.workplace_initializations;");
  const first = state();
  sql('SELECT private_isg.ensure_default(id) IS NOT NULL FROM public.companies;');
  sql('SELECT private_isg.ensure_default(id) IS NOT NULL FROM public.companies;');
  pass('p05_full_copy_backfill_repeat_no_change', state() === first);
  pass('p05_full_copy_legacy_rows_unchanged_after_retry', fingerprint() === before);
  pass('p05_full_copy_new_schema_rls', sql("SELECT count(*)=37 AND bool_and(rowsecurity) FROM pg_tables WHERE schemaname='private_isg';") === 't');
  pass('p05_full_copy_client_table_grants_closed', sql("SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('PUBLIC','anon','authenticated','service_role');") === '0');
  return {full_legacy_schema_upgrade:true,legacy_row_fingerprint:before,original_helper_fingerprint:helpers,default_backfill_repeated:2,production_changed:false,storage_bytes_tested:false};
}

function snapshotSQL() {
  return `CREATE TEMP TABLE p05_snapshot(name text,digest text) ON COMMIT DROP;
    DO $$ DECLARE r record;d text; BEGIN
    FOR r IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname IN ('public','private','auth','storage') AND c.relkind='r' ORDER BY 1,2 LOOP
      EXECUTE format('SELECT md5(coalesce(string_agg(d, '''' ORDER BY d),'''')) FROM (SELECT md5(to_jsonb(t)::text) d FROM %I.%I t) s',r.nspname,r.relname) INTO d;
      INSERT INTO p05_snapshot VALUES(r.nspname||'.'||r.relname,d);
    END LOOP;END $$;`;
}
