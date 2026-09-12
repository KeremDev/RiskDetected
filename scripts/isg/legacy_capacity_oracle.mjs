import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { ROOT } from './lib.mjs';

// Load only the reviewed historical function definitions, not entire migrations.
// They are executed in the new synthetic container, then rolled back.
export function legacyCapacityOracle(root = ROOT) {
  const definitions = [
    ['private.user_plan_tier', 'supabase/migrations/20260513223911_fix_subscription_quota_review_findings.sql'],
    ['private.company_limit_for_user', 'supabase/migrations/20260520154818_add_companies.sql'],
  ].map(([name, path]) => {
    const source = readFileSync(resolve(root, path), 'utf8');
    const escaped = name.replaceAll('.', '\\.');
    const matches = [...source.matchAll(new RegExp(`create or replace function ${escaped}\\(p_user_id uuid\\)[\\s\\S]*?\\$\\$;`, 'gi'))];
    if (matches.length !== 1) throw new Error('DB_LEGACY_ORACLE_SOURCE_DRIFT');
    const sql = matches[0][0];
    return { name, path, sql, sha256: createHash('sha256').update(sql).digest('hex') };
  });
  const cases = [], profiles = [], subscriptions = [];
  const uid = number => `10000000-0000-4000-8000-${number.toString().padStart(12, '0')}`;
  const tiers = ['free', 'plus', 'pro'];
  const statuses = ['active', 'trialing', 'grace_period', 'inactive', 'cancelled', 'canceled', 'expired', 'paused', 'billing_issue'];
  const expiry = { none: 'NULL', past: "now()-interval '1 second'", boundary: 'now()', future: "now()+interval '1 hour'" };
  function add(profileTier, subscriptionTier, status, expiryCase) {
    const id = uid(cases.length + 1);
    profiles.push(`('${id}','${profileTier}')`);
    const paid = subscriptionTier && subscriptionTier !== 'free' && ['active', 'trialing', 'grace_period'].includes(status) && ['none', 'future'].includes(expiryCase);
    const effective = paid ? subscriptionTier : 'free';
    const limit = { free: 0, plus: 5, pro: 25 }[effective];
    const caseID = `${profileTier}_${subscriptionTier ?? 'missing'}_${status ?? 'none'}_${expiryCase ?? 'none'}`;
    cases.push(`('${caseID}','${id}'::uuid,'${effective}',${limit})`);
    if (subscriptionTier) subscriptions.push(`('${id}','${subscriptionTier}','${status}',${expiry[expiryCase]},now())`);
  }
  for (const profileTier of tiers) {
    add(profileTier, null, null, null);
    for (const subscriptionTier of tiers) for (const status of statuses) for (const end of Object.keys(expiry)) add(profileTier, subscriptionTier, status, end);
  }
  const sql = `BEGIN;
CREATE SCHEMA IF NOT EXISTS private;
CREATE TABLE public.profiles(id uuid PRIMARY KEY, tier text NOT NULL);
CREATE TABLE public.user_subscriptions(user_id uuid PRIMARY KEY, tier text NOT NULL, status text NOT NULL, current_period_ends_at timestamptz, updated_at timestamptz NOT NULL);
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_subscriptions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.profiles, public.user_subscriptions FROM PUBLIC, anon, authenticated, service_role;
${definitions.map(d => d.sql).join('\n')}
REVOKE ALL ON FUNCTION private.user_plan_tier(uuid), private.company_limit_for_user(uuid) FROM PUBLIC, anon, authenticated;
INSERT INTO public.profiles VALUES ${profiles.join(',')};
INSERT INTO public.user_subscriptions VALUES ${subscriptions.join(',')},('${uid(9999)}','pro','active',NULL,now());
WITH expected(case_id,user_id,tier,capacity) AS (VALUES ${cases.join(',')},
 ('missing_profile_active_pro','${uid(9999)}'::uuid,'pro',NULL),('null_user',NULL::uuid,'free',NULL)),
 actual AS (SELECT *, private.user_plan_tier(user_id) AS actual_tier, private.company_limit_for_user(user_id) AS actual_capacity FROM expected)
SELECT jsonb_build_object('case_count',count(*),'passed',count(*) FILTER (WHERE tier IS NOT DISTINCT FROM actual_tier AND capacity IS NOT DISTINCT FROM actual_capacity),
 'failures',coalesce(jsonb_agg(case_id) FILTER (WHERE tier IS DISTINCT FROM actual_tier OR capacity IS DISTINCT FROM actual_capacity),'[]'::jsonb)) FROM actual;
ROLLBACK;`;
  return { sql, expected_cases: cases.length + 2, definitions: definitions.map(({ sql, ...metadata }) => metadata) };
}
