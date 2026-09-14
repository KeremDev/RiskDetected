import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

const read=path=>readFileSync(resolve(ROOT,path),'utf8');
const slice=read('supabase/migrations/20260915090000_isg_risk_versions.sql');
const base=read('supabase/migrations/20260913190000_isg_risk_versioning.sql');
const checks=read('scripts/isg/risk_versions_check.sql');
const fixture=read('scripts/isg/pilot_document_tracking_fixture.sql');
/** Comments explain the rule; they are not evidence that the rule is there. */
const code=source=>source.split('\n').filter(line=>!line.trimStart().startsWith('--')).join('\n');

test('the slice adds no switch of its own and opens none',()=>{
  assert.doesNotMatch(slice,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(slice,/INSERT INTO private_isg\.rollout/);
  assert.doesNotMatch(slice,/rollout_feature_check/);
  // It rides on the switch the first P08 slice created.
  assert.match(code(slice),/PERFORM private_isg\.risk_gate\(p_write\);/);
  assert.match(checks,/the risk switch is still closed/);
});

test('the only new table is private, row secured and ungranted',()=>{
  const created=[...slice.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
  assert.deepEqual(created,['risk_version_receipts']);
  assert.match(slice,/ALTER TABLE private_isg\.risk_version_receipts ENABLE ROW LEVEL SECURITY/);
  assert.match(slice,/REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;/);
});

test('exactly two wrappers reach the client and nothing else is granted',()=>{
  const wrappers=[...slice.matchAll(/CREATE FUNCTION public\.(isg_[a-z_0-9]+)/g)].map(m=>m[1]);
  assert.deepEqual(wrappers,['isg_risk_versions_read_v1','isg_risk_versions_mutate_v1']);
  for(const name of wrappers) assert.match(slice,new RegExp(`CREATE FUNCTION public\\.${name}[\\s\\S]{0,200}SECURITY INVOKER`));
  const granted=[...slice.matchAll(/GRANT EXECUTE ON FUNCTION([\s\S]*?)TO authenticated;/g)];
  assert.equal(granted.length,1);
  assert.equal((granted[0][1].match(/private_isg\./g)||[]).length,2);
});

test('the boundary checks ownership the domain functions never did',()=>{
  // The first slice's functions take a company and trust it.
  assert.doesNotMatch(code(base),/require_risk_company/);
  assert.match(code(slice),/CREATE FUNCTION private_isg\.require_risk_company/);
  assert.match(code(slice),/actor:=private_isg\.require_risk_company\(p_company,false\);/);
  assert.match(code(slice),/actor:=private_isg\.require_risk_company\(p_company,true\);/);
  // And every write re-checks the row against this actor before delegating.
  assert.match(code(slice),/WHERE assessment_id=target AND company_id=p_company AND owner_id=actor FOR UPDATE;/);
  assert.match(code(slice),/WHERE company_id=p_company\n\s+AND id=\(p_payload->>'workplace_id'\)::uuid AND owner_id=actor AND NOT is_archived;/);
});

test('a validity date is never invented and a missing one is never valid',()=>{
  const status=code(slice).match(/CREATE FUNCTION private_isg\.risk_assessment_status[\s\S]*?END \$\$;/)[0];
  // The order is the rule: no final document, then no period, then the dates.
  assert.match(status,/IF NOT p_has_final OR coalesce\(p_current_version,0\)=0 THEN RETURN 'never_assessed'/);
  assert.match(status,/IF p_valid_until IS NULL THEN RETURN 'period_unknown'/);
  assert.ok(status.indexOf("period_unknown")<status.indexOf("RETURN 'valid'"));
  assert.match(checks,/a missing period is a gap, not a clean bill/);
});

test('every state belongs to exactly one counter',()=>{
  const group=code(slice).match(/CREATE FUNCTION private_isg\.risk_assessment_group[\s\S]*?\$\$;/)[0];
  const status=code(slice).match(/CREATE FUNCTION private_isg\.risk_assessment_status[\s\S]*?END \$\$;/)[0];
  const states=[...status.matchAll(/RETURN '([a-z_]+)'/g)].map(m=>m[1]);
  assert.deepEqual([...new Set(states)].sort(),
    ['due_soon','expired','never_assessed','period_unknown','valid']);
  for(const state of states){
    assert.ok(group.includes(`'${state}'`)||group.includes('ELSE'),state);
  }
});

test('the client can neither name a verifier nor move the legal date',()=>{
  const allow=code(slice).match(/allowed:=CASE p_action[\s\S]*?ELSE NULL END;/)[0];
  assert.doesNotMatch(allow,/verified_by/);
  assert.match(checks,/a named verifier is refused/);
  assert.match(checks,/a correction cannot move the legal date/);
  // finalize_version is handed the signed-in actor, never a payload value.
  assert.match(code(slice),/\(p_payload->>'expected_current'\)::integer,actor,/);
});

test('a period the expert chose is never presented as a rule',()=>{
  const catalog=code(slice).match(/IF p_kind='catalog' THEN[\s\S]*?END IF;/)[0];
  assert.match(catalog,/'period_defaults_offered',false/);
  assert.match(catalog,/'expert_period_source','unapproved_fixture'/);
  assert.match(catalog,/'expert_period_needs_review',true/);
  // Only published rules with a yearly period are ever offered.
  assert.match(catalog,/WHERE r\.status='published' AND r\.period_kind='years'/);
  assert.match(checks,/an expert period is not presented as a rule/);
  assert.match(checks,/an unpublished rule is refused rather than assumed/);
});

test('no read claims compliance, a health record or an analysis as an assessment',()=>{
  assert.match(code(slice),/'compliance_verdict',NULL/);
  assert.match(code(slice),/'health_records_tracked',false/);
  assert.match(code(slice),/'analysis_is_not_an_assessment',true/);
  assert.match(code(slice),/'legacy_analysis_written',false/);
  assert.doesNotMatch(code(slice),/health_record_id|medical/i);
});

test('the state is computed at read and says so',()=>{
  assert.match(code(slice),/'state_authority','computed_at_read'/);
  // Nothing in the slice stores a state word on a row.
  assert.doesNotMatch(code(slice),/ADD COLUMN[\s\S]{0,80}state/);
});

test('every mutation is receipted and the same id cannot mean two things',()=>{
  assert.match(code(slice),/PRIMARY KEY\(actor_id,mutation_id\)/);
  assert.match(code(slice),/request_hash IS DISTINCT FROM fingerprint THEN[\s\S]{0,120}IDEMPOTENCY_CONFLICT/);
  assert.match(checks,/the same id with a different body is refused/);
});

test('the checks are written for a disposable database only',()=>{
  assert.match(fixture,/Run only in a fresh, disposable local database, never on a project database\./);
  assert.doesNotMatch(checks,/DROP SCHEMA|DROP DATABASE/);
  assert.match(checks,/ALL RISK VERSION CHECKS PASSED/);
});
