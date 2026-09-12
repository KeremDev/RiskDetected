#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { ROOT } from './lib.mjs';
import { legacyCapacityOracle } from './legacy_capacity_oracle.mjs';
import { proposeCompanyCapacity } from './company_capacity_shadow.mjs';

// Fixed restricted restore; read-only SQL and aggregate counts only. No live
// credentials, UUIDs, e-mails, company names, subscription rows or receipt payloads.
const container = 'isg_restore_20260912_db';
try {
  if (process.argv.length !== 2) throw new Error('CAPACITY_ARGUMENTS_NOT_ALLOWED');
  const inspect = spawnSync('docker', ['inspect', container], { encoding: 'utf8' });
  if (inspect.status !== 0) throw new Error('CAPACITY_RESTORE_UNAVAILABLE');
  const info = JSON.parse(inspect.stdout)[0];
  if (info.Name !== `/${container}` || info.Config.Labels?.['com.riskdetected.isg-restore'] !== '20260912' ||
      info.State.Running !== true || info.HostConfig.NetworkMode !== 'none' || info.HostConfig.Privileged || info.Mounts.length ||
      Object.keys(info.NetworkSettings.Ports ?? {}).length) throw new Error('CAPACITY_RESTORE_ISOLATION_FAILED');
  const sql = `BEGIN READ ONLY;
SET LOCAL statement_timeout='15s';
SELECT jsonb_build_object(
 'evaluated_at',now(),
 'functions',(SELECT jsonb_agg(jsonb_build_object('name',n.nspname||'.'||p.proname,'body',p.prosrc,'security_definer',p.prosecdef,'volatility',p.provolatile))
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname IN ('user_plan_tier','company_limit_for_user') AND p.pronargs=1),
 'cohorts',(SELECT jsonb_agg(to_jsonb(c)) FROM (
    SELECT stored_tier,canonical_tier,company_limit,active_companies,count(*) AS accounts FROM (
      SELECT p.tier::text AS stored_tier,private.user_plan_tier(p.id) AS canonical_tier,private.company_limit_for_user(p.id) AS company_limit,
        (SELECT count(*) FROM public.companies c WHERE c.user_id=p.id AND NOT c.is_archived) AS active_companies
      FROM public.profiles p
    ) individual GROUP BY stored_tier,canonical_tier,company_limit,active_companies ORDER BY stored_tier,canonical_tier,active_companies
 ) c)
);
ROLLBACK;`;
  const result = spawnSync('docker', ['exec', '-i', info.Id, 'psql', '-X', '-U', 'supabase_admin', '-d', 'postgres', '-Atq', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=sqlstate'],
    { input: sql, encoding: 'utf8', timeout: 20_000, maxBuffer: 128 * 1024 });
  if (result.status !== 0) throw new Error('CAPACITY_READ_FAILED');
  const data = JSON.parse(result.stdout.trim()), oracle = legacyCapacityOracle();
  const body = text => text.trim().replace(/\s+/g, ' ');
  for (const definition of oracle.definitions) {
    const source = readFileSync(resolve(ROOT, definition.path), 'utf8');
    const escaped = definition.name.replaceAll('.', '\\.');
    const match = source.match(new RegExp(`create or replace function ${escaped}\\(p_user_id uuid\\)[\\s\\S]*?as \\$\\$([\\s\\S]*?)\\$\\$;`, 'i'));
    const actual = data.functions.filter(f => f.name === definition.name);
    if (actual.length !== 1 || !match || body(actual[0].body) !== body(match[1]) || actual[0].security_definer !== true || actual[0].volatility !== 's') throw new Error('CAPACITY_ORACLE_DIFFERS_FROM_CHECKPOINT');
  }
  const hypothetical = data.cohorts.filter(c => ['plus', 'pro'].includes(c.canonical_tier)).map(c => {
    if (c.active_companies > c.company_limit) return { ...c, status: 'REVIEW_OVER_LIMIT_USAGE' };
    const proposal = proposeCompanyCapacity({ billing_state: 'verified_paid', eligibility: 'eligible',
      legacy_contract: { kind: 'finite', value: c.company_limit }, existing_floor: { kind: 'finite', value: 0 },
      candidate_capacity: { kind: 'finite', value: c.canonical_tier === 'plus' ? 3 : 30 },
      active_company_count: c.active_companies, protected_active_company_count: c.active_companies });
    return { ...c, hypothetical_proposal: proposal };
  });
  console.log(JSON.stringify({ ok: true, evaluated_at: data.evaluated_at, source: 'restricted_20260912_restored_checkpoint',
    source_is_current_live_state: false, source_function_bodies_match_migrations: true, source_definitions: oracle.definitions,
    shadow_model_sha256: createHash('sha256').update(readFileSync(resolve(ROOT, 'scripts/isg/company_capacity_shadow.mjs'))).digest('hex'),
    accounts: data.cohorts.reduce((sum,c) => sum + c.accounts, 0),
    stored_paid_but_canonical_free: data.cohorts.filter(c => c.stored_tier !== 'free' && c.canonical_tier === 'free').reduce((sum,c) => sum + c.accounts, 0),
    cohorts: data.cohorts, hypothetical_paid_cohorts: hypothetical,
    assumptions: ['Candidate Plus3/Pro30 not approved or published', 'Hypothesis only: current snapshot paid cohorts eligible at future rollout', 'No existing new floor ledger yet; hypothetical existing floor=0', 'Current within-limit active usage is treated as protected only for this simulation'],
    unresolved: ['Real rollout cutoff and historical eligibility', 'Offboarded/late-update cohort catch-up', 'Approved commercial catalog', 'Override and protected usage provenance', 'Live store/RC reconciliation'],
    writes_performed: false, floor_backfill_performed: false, publishable: false }, null, 2));
} catch (error) { console.error(/^CAPACITY_/.test(error.message) ? error.message : 'CAPACITY_SNAPSHOT_FAILED'); process.exitCode = 1; }
