import {compileP05PilotBundle,p05PilotBundleSources} from './p05_pilot_bundle.mjs';
import {compileP05PilotRelease} from './p05_pilot_release.mjs';
import {readFileSync} from 'node:fs';
import {ROOT} from './lib.mjs';
import {p05ProfileMigration,p05ProfileFiles} from './p05_profile_probe.mjs';
export const p05PilotUpgradeFiles=['scripts/isg/p05_pilot_upgrade_probe.mjs','scripts/isg/p05_pilot_bundle.mjs','scripts/isg/p05_pilot_release.mjs',...p05PilotBundleSources,...p05ProfileFiles];
export function probeP05PilotUpgrade({isolatedCopy,sql,pass}) {
  if(isolatedCopy!==true)throw Error('AUTH_RESTORE_PILOT_UPGRADE_ISOLATED_REQUIRED');
  const fingerprint=()=>sql(`BEGIN;CREATE TEMP TABLE pilot_snapshot(k text,v text) ON COMMIT DROP;
    DO $$ DECLARE r record;d text;BEGIN
      FOR r IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname IN ('public','private','auth','storage') AND c.relkind='r' ORDER BY 1,2 LOOP
        EXECUTE format('SELECT md5(coalesce(string_agg(d, '''' ORDER BY d),'''')) FROM (SELECT md5(to_jsonb(t)::text) d FROM %I.%I t) s',r.nspname,r.relname) INTO d;
        INSERT INTO pilot_snapshot VALUES(r.nspname||'.'||r.relname,d);
      END LOOP;END $$;
    SELECT md5(string_agg(k||v,',' ORDER BY k)) FROM pilot_snapshot;COMMIT;`).split('\n').at(-1);
  const before=fingerprint();
  const helpers=()=>sql("SELECT md5(pg_get_functiondef('private.user_plan_tier(uuid)'::regprocedure)||pg_get_functiondef('private.company_limit_for_user(uuid)'::regprocedure)||pg_get_functiondef('private.enforce_company_write_rules()'::regprocedure));");
  const beforeHelpers=helpers();
  // Exact release payload under a transaction, only in this owned disposable clone.
  // The pinned baseline dump lacks the platform ledger; model its freshly verified
  // production head for the transport assertions, then roll back the entire probe.
  const release=compileP05PilotRelease();
  if(sql("SELECT to_regclass('supabase_migrations.schema_migrations') IS NULL;")!=='t')throw Error('PILOT_RELEASE_CLONE_LEDGER_UNEXPECTED');
  sql("BEGIN; CREATE SCHEMA supabase_migrations; CREATE TABLE supabase_migrations.schema_migrations(version text PRIMARY KEY); INSERT INTO supabase_migrations.schema_migrations VALUES('20260908134026');\n"+release.sql+"\nROLLBACK;");
  pass('pilot_release_exact_payload_rollback',sql("SELECT to_regnamespace('private_isg') IS NULL AND to_regnamespace('supabase_migrations') IS NULL;")==='t');
  pass('pilot_release_legacy_rows_rollback',fingerprint()===before && helpers()===beforeHelpers);
  const {sql:bundle,manifest}=compileP05PilotBundle();
  const started=performance.now();sql(bundle);const elapsed=performance.now()-started;
  pass('pilot_only_bundle_legacy_rows_preserved',fingerprint()===before);
  pass('pilot_only_bundle_legacy_quota_helpers_preserved',helpers()===beforeHelpers);
  pass('pilot_only_bundle_no_global_backfill',sql('SELECT count(*) FROM private_isg.workplaces;')==='0');
  pass('pilot_only_bundle_no_global_insert_hook',sql("SELECT count(*) FROM pg_trigger WHERE tgrelid='public.companies'::regclass AND tgname='companies_isg_default' AND NOT tgisinternal;")==='0');
  pass('pilot_only_bundle_legacy_insert_guard_preserved',sql("SELECT count(*) FROM pg_trigger WHERE tgrelid='public.companies'::regclass AND tgname='companies_enforce_write_rules' AND NOT tgisinternal;")==='1');
  pass('pilot_only_bundle_closed_empty_roster',sql("SELECT (SELECT count(*)=0 FROM private_isg.p05_pilot_accounts) AND (SELECT count(*)=0 FROM private_isg.p05_pilot_grants) AND (SELECT count(*)=0 FROM private_isg.p05_pilot_company_origins) AND (SELECT NOT read_enabled AND NOT write_enabled FROM private_isg.rollout WHERE feature='personnel');")==='t');
  pass('pilot_only_bundle_exact_private_table_scope',sql("SELECT count(*)="+manifest.tables.length+" AND bool_and(rowsecurity) FROM pg_tables WHERE schemaname='private_isg';")==='t');
  pass('pilot_only_bundle_client_dml_denied',sql("SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('PUBLIC','anon','authenticated','service_role');")==='0');
  pass('pilot_only_bundle_no_other_phase_installed',sql("SELECT to_regclass('private_isg.notification_jobs') IS NULL AND to_regclass('private_isg.billing_lifecycle_evidence') IS NULL;")==='t');
  sql('BEGIN;\n'+readFileSync(`${ROOT}/${p05ProfileMigration}`,'utf8')+'\nCOMMIT;');
  pass('pilot_profile_additive_upgrade_preserves_legacy',fingerprint()===before && helpers()===beforeHelpers);
  pass('pilot_profile_upgrade_no_seed_or_rollout',sql("SELECT (SELECT count(*)=0 FROM private_isg.p05_company_profiles) AND (SELECT NOT read_enabled AND NOT write_enabled FROM private_isg.rollout WHERE feature='personnel');")==='t');
  return{...manifest,release_sha256:release.manifest.release_sha256,release_payload_rollback_tested:true,isolated_legacy_copy:true,execution_ms:Math.round(elapsed),measured_production_lock_time:false,legacy_rows_unchanged:true,legacy_helpers_unchanged:true};
}
