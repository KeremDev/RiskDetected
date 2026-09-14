import {createHash} from 'node:crypto';
import {compileP05PilotBundle} from './p05_pilot_bundle.mjs';

// Approved production transport for the reviewed six-source P05 bundle only.
// No networking, credentials, activation or ledger writes. The migration service
// supplies the outer transaction and records the single deployment migration.
export function compileP05PilotRelease() {
  const bundle = compileP05PilotBundle();
  if (bundle.manifest.bundle_sha256 !== '2b7063d865ece5c3d791732065c763b821f6f4cbc2ed303b6cb462dd8e1784aa') throw Error('PILOT_RELEASE_UNREVIEWED_SOURCE');
  let body = bundle.sql.replace(/^BEGIN;$/m, '').replace(/^COMMIT;$/m, '');
  body = body.replace(/^SET LOCAL lock_timeout\s*=\s*'5s';$/gm, "SET LOCAL lock_timeout='1s';")
    .replace(/^SET LOCAL statement_timeout='30s';$/gm, "SET LOCAL statement_timeout='15s';");
  const preflight = `-- Approved P05 scoped pilot; activation is a separate DML transaction.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='15s';
DO $preflight$ BEGIN
  IF to_regnamespace('private_isg') IS NOT NULL OR
    (SELECT max(version) FROM supabase_migrations.schema_migrations) IS DISTINCT FROM '20260908134026' THEN
    RAISE EXCEPTION 'PILOT_RELEASE_BASELINE_CHANGED'; END IF;
  IF md5(pg_get_functiondef('private.user_plan_tier(uuid)'::regprocedure)||pg_get_functiondef('private.company_limit_for_user(uuid)'::regprocedure)||pg_get_functiondef('private.enforce_company_write_rules()'::regprocedure)) <> 'e61b8d817d8917fdb99d2f44364b8414' THEN
    RAISE EXCEPTION 'PILOT_RELEASE_LEGACY_HELPER_CHANGED'; END IF;
END $preflight$;
`;
  const postflight = `
SET LOCAL search_path=pg_catalog,public;
DO $postflight$ BEGIN
  IF (SELECT count(*) FROM pg_tables WHERE schemaname='private_isg' AND rowsecurity) <> 18 OR
     (SELECT count(*) FROM pg_tables WHERE schemaname='private_isg') <> 18 OR
     EXISTS(SELECT 1 FROM private_isg.p05_pilot_accounts) OR
     EXISTS(SELECT 1 FROM private_isg.p05_pilot_grants) OR
     EXISTS(SELECT 1 FROM private_isg.p05_pilot_company_origins) OR
     EXISTS(SELECT 1 FROM private_isg.workplaces) OR
     EXISTS(SELECT 1 FROM private_isg.rollout WHERE read_enabled OR write_enabled) OR
     EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.companies'::regclass AND tgname='companies_isg_default') OR
     NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.companies'::regclass AND tgname='companies_enforce_write_rules' AND tgenabled='O') OR
     EXISTS(SELECT 1 FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('PUBLIC','anon','authenticated','service_role')) THEN
     RAISE EXCEPTION 'PILOT_RELEASE_POSTFLIGHT_FAILED'; END IF;
  IF md5(pg_get_functiondef('private.user_plan_tier(uuid)'::regprocedure)||pg_get_functiondef('private.company_limit_for_user(uuid)'::regprocedure)||pg_get_functiondef('private.enforce_company_write_rules()'::regprocedure)) <> 'e61b8d817d8917fdb99d2f44364b8414' THEN
    RAISE EXCEPTION 'PILOT_RELEASE_LEGACY_HELPER_CHANGED'; END IF;
END $postflight$;
NOTIFY pgrst,'reload schema';
`;
  const sql = preflight + body + postflight;
  return {sql, manifest: {...bundle.manifest, deployment_authorized: true,
    release_sha256: createHash('sha256').update(sql).digest('hex'),
    migration_name: 'isg_p05_scoped_pilot_bundle',
    transport_transforms: ['Outer transaction delegated to migration service', 'lock_timeout lowered to 1s and statement_timeout to 15s', 'Baseline and closed-state postflight assertions added'],
    activation_included: false}};
}
