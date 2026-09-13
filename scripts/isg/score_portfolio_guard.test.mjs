import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {beginScorePortfolioProbe,scorePortfolioFiles} from './score_portfolio_probe.mjs';

const migration=readFileSync(resolve(ROOT,scorePortfolioFiles[0]),'utf8');
const probe=readFileSync(resolve(ROOT,scorePortfolioFiles[1]),'utf8');
const runner=readFileSync(resolve(ROOT,'scripts/isg/run_auth_restore.mjs'),'utf8');

test('the probe refuses any other mode before touching SQL',async()=>{
  let touched=false;
  await assert.rejects(beginScorePortfolioProbe({synthetic:false,sql(){touched=true;}}),/SYNTHETIC_REQUIRED/);
  await assert.rejects(beginScorePortfolioProbe({synthetic:true,sql(){touched=true;}}),/SCOPE_REQUIRED/);
  assert.equal(touched,false);
});

test('the score ledger ships disabled, private and without a client grant',()=>{
  assert.match(migration,/INSERT INTO private_isg\.rollout\(feature\) VALUES\('score'\)/);
  assert.doesNotMatch(migration,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(migration,/GRANT (EXECUTE|SELECT|INSERT|UPDATE|DELETE|ALL)[\s\S]{0,400}?TO (anon|authenticated|service_role)/);
  const created=[...migration.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
  const secured=new Set([...migration.matchAll(/ALTER TABLE private_isg\.([a-z_]+) ENABLE ROW LEVEL SECURITY/g)].map(m=>m[1]));
  assert.equal(created.length,10);
  for(const table of created) assert.ok(secured.has(table),table);
});

test('a score never certifies and its weights are never approved here',()=>{
  assert.match(migration,/is_official_compliance_certificate boolean NOT NULL DEFAULT false CHECK\(NOT is_official_compliance_certificate\)/);
  assert.match(migration,/is_official_certificate boolean NOT NULL DEFAULT false CHECK\(NOT is_official_certificate\)/);
  assert.match(migration,/weights_approved boolean NOT NULL DEFAULT false CHECK\(NOT weights_approved\)/);
  assert.match(migration,/cap_approved boolean NOT NULL DEFAULT false CHECK\(NOT cap_approved\)/);
  assert.match(migration,/CHECK\(status<>'published' OR \(approved_by IS NOT NULL AND approval_note IS NOT NULL AND published_at IS NOT NULL\)\)/);
});

test('no data means no number, and a cap really caps',()=>{
  assert.match(migration,/CHECK\(has_any_data OR main_score IS NULL\)/);
  assert.match(migration,/CHECK\(total_weight>0 OR main_score IS NULL\)/);
  assert.match(migration,/CHECK\(contribution_cap<=weight\)/);
  assert.match(migration,/CHECK\(capped_points<=contribution_cap\)/);
  assert.match(migration,/IF points>proc\.contribution_cap THEN points:=proc\.contribution_cap/);
});

test('unknown is its own state and never collapses into not required',()=>{
  assert.match(migration,/resolved:=coalesce\(subject\.applicability,'needs_review'\)/);
  assert.match(migration,/CHECK\(needs_review_count=0 OR provisional\)/);
  assert.match(migration,/CHECK\(applicability<>'not_required' OR \(justification_note IS NOT NULL AND verified_by IS NOT NULL AND verified_on IS NOT NULL\)\)/);
  // An unknown process keeps its weight in the denominator.
  const preview=migration.slice(migration.indexOf('CREATE FUNCTION private_isg.score_preview'));
  const unknownBranch=preview.slice(preview.indexOf("ELSIF resolved='needs_review'"),preview.indexOf("ELSIF resolved='not_required'"));
  assert.match(unknownBranch,/running_weight:=running_weight\+proc\.weight/);
});

test('a voluntary record is neutral on both sides of the fraction',()=>{
  assert.match(migration,/CHECK\(exclusion_reason IS DISTINCT FROM 'voluntary' OR capped_points=0\)/);
  const preview=migration.slice(migration.indexOf('CREATE FUNCTION private_isg.score_preview'));
  const volunteerBranch=preview.slice(preview.indexOf("volunteer_count:=volunteer_count+1"),preview.indexOf('END IF;'));
  assert.doesNotMatch(volunteerBranch,/running_weight:=/);
});

test('a critical warning can never be hidden by a high total',()=>{
  assert.match(migration,/hidden_by_total_score boolean NOT NULL DEFAULT false CHECK\(NOT hidden_by_total_score\)/);
  assert.match(migration,/'critical_findings_hidden',false/);
});

test('the oracle is a hand computed number, not a second call into the code',()=>{
  assert.match(migration,/hand_computed boolean NOT NULL DEFAULT true CHECK\(hand_computed\)/);
  assert.match(migration,/computed_by_production_function boolean NOT NULL DEFAULT false CHECK\(NOT computed_by_production_function\)/);
  // The expected values are literals in the probe, never read back from the code.
  assert.match(probe,/expected_main_score[\s\S]{0,400}?56\.67,true,75\.000,42\.500/);
  assert.doesNotMatch(probe,/expected_main_score[^\n]*score_preview/);
});

test('history is added to, never rewritten, and a simulation writes nothing',()=>{
  assert.match(migration,/history_rewritten boolean NOT NULL DEFAULT false CHECK\(NOT history_rewritten\)/);
  assert.match(migration,/'snapshots_written',0/);
  assert.match(migration,/UNIQUE\(company_id,policy_version_id,computed_for\)/);
  const simulation=migration.slice(migration.indexOf('CREATE FUNCTION private_isg.simulate_policy_change'));
  const body=simulation.slice(0,simulation.indexOf('$$;'));
  assert.doesNotMatch(body,/INSERT INTO private_isg\.score_snapshots|UPDATE private_isg\.score_snapshots/);
});

test('every company counts once and a headcount is never a weight',()=>{
  assert.match(migration,/weighting text NOT NULL DEFAULT 'equal_per_company' CHECK\(weighting='equal_per_company'\)/);
  assert.match(migration,/headcount_used_as_weight boolean NOT NULL DEFAULT false CHECK\(NOT headcount_used_as_weight\)/);
  assert.match(migration,/portfolio_weight numeric\(6,5\) NOT NULL DEFAULT 1 CHECK\(portfolio_weight=1\)/);
  assert.match(migration,/CHECK\(companies_scored>0 OR average_main_score IS NULL\)/);
  const portfolio=migration.slice(migration.indexOf('CREATE FUNCTION private_isg.build_portfolio_projection'));
  assert.doesNotMatch(portfolio.slice(0,portfolio.indexOf('$$;')),/employee_count\s*\*|\*\s*employee_count/);
});

test('the runner wires the probe and hashes the migration',()=>{
  assert.match(runner,/beginScorePortfolioProbe\(\{synthetic:true/);
  assert.match(runner,/concat\(mode\.synthetic \? scorePortfolioFiles : \[\]\)/);
  assert.match(runner,/scoreProbe\.afterLogout\(\)/);
});
