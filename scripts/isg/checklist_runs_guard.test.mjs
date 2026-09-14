import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

const read=path=>readFileSync(resolve(ROOT,path),'utf8');
const slice=read('supabase/migrations/20260915110000_isg_checklist_runs.sql');
const core=read('supabase/migrations/20260913210000_isg_nonconformity_core.sql');
const checks=read('scripts/isg/checklist_runs_check.sql');
/** Comments explain the rule; they are not evidence that the rule is there. */
const code=source=>source.split('\n').filter(line=>!line.trimStart().startsWith('--')).join('\n');

test('the slice adds no switch of its own and opens none',()=>{
  assert.doesNotMatch(slice,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(slice,/INSERT INTO private_isg\.rollout/);
  assert.doesNotMatch(slice,/rollout_feature_check/);
  assert.match(code(slice),/PERFORM private_isg\.nonconformity_gate\(p_write\);/);
  assert.match(checks,/the nonconformity switch is still closed/);
});

test('the product ships no question list, and nothing here can create one',()=>{
  // No seed, and the only writer of a template always names an owner.
  assert.doesNotMatch(slice,/INSERT INTO private_isg\.checklist_templates\b(?![\s\S]{0,200}owner_id)/);
  assert.doesNotMatch(core,/INSERT INTO private_isg\.checklist_templates/);
  assert.match(code(slice),/'product_templates_offered',false/);
  assert.match(checks,/no template is seeded at all/);
});

test('a template belongs to an account and its code cannot collide',()=>{
  assert.match(slice,/ADD COLUMN owner_id uuid REFERENCES public\.profiles\(id\)/);
  const derive=code(slice).match(/CREATE FUNCTION private_isg\.checklist_template_code[\s\S]*?\$\$;/)[0];
  // The owner is inside the hash, so two accounts naming a list the same thing
  // get two different codes.
  assert.match(derive,/md5\(p_owner::text\|\|':'\|\|btrim\(lower\(p_title\)\)\)/);
  assert.match(checks,/the same title in two accounts is two codes/);
  assert.match(checks,/each account sees only its own lists/);
});

test('a product template is readable but never editable',()=>{
  const guard=code(slice).match(/CREATE FUNCTION private_isg\.require_checklist_template[\s\S]*?END \$\$;/)[0];
  assert.match(guard,/IF p_write THEN\s*\n\s*IF entry\.owner_id IS DISTINCT FROM p_actor THEN/);
  assert.match(guard,/ELSIF entry\.owner_id IS NOT NULL AND entry\.owner_id<>p_actor THEN/);
});

test('only a draft is editable, and a run pins the version it was filled with',()=>{
  for(const name of ['set_checklist_item','remove_checklist_item']){
    const fn=code(slice).match(new RegExp(`CREATE FUNCTION private_isg\\.${name}[\\s\\S]*?END \\$\\$;`))[0];
    assert.match(fn,/IF entry\.status<>'draft' THEN RAISE EXCEPTION[\s\S]{0,80}TEMPLATE_PUBLISHED/,name);
  }
  assert.match(checks,/a published question cannot be rewritten/);
  assert.match(checks,/publishing a newer list does not change what the run asks/);
});

test('a failing answer never becomes a nonconformity on its own',()=>{
  const allow=code(slice).match(/allowed:=CASE p_action[\s\S]*?ELSE NULL END;/)[0];
  // The ask is its own field, and it defaults to false when absent.
  assert.match(allow,/'open_nonconformity'/);
  assert.match(code(slice),/coalesce\(\(p_payload->>'open_nonconformity'\)::boolean,false\)/);
  // Every surface that answers says so.
  assert.match(code(slice),/'auto_nonconformity',false/);
  assert.match(checks,/a failing answer alone opens nothing/);
  assert.match(checks,/the read states it never converts on its own/);
});

test('the client cannot name who approved a list',()=>{
  const allow=code(slice).match(/allowed:=CASE p_action[\s\S]*?ELSE NULL END;/)[0];
  assert.doesNotMatch(allow,/approver/);
  assert.match(code(slice),/private_isg\.publish_checklist_version\(p_payload->>'template_code',\s*\n?\s*\(p_payload->>'version'\)::integer,actor,/);
  assert.match(checks,/a named approver is refused/);
  assert.match(checks,/the approver is the signed-in expert/);
});

test('the boundary checks ownership the core functions never did',()=>{
  assert.doesNotMatch(code(core),/require_checklist_company/);
  assert.match(code(slice),/CREATE FUNCTION private_isg\.require_checklist_company/);
  assert.match(code(slice),/WHERE run_id=run AND company_id=p_company AND owner_id=actor FOR UPDATE;/);
  assert.match(code(slice),/AND id=\(p_payload->>'workplace_id'\)::uuid AND owner_id=actor AND NOT is_archived;/);
});

test('the only new table is private, row secured and ungranted',()=>{
  const created=[...slice.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
  assert.deepEqual(created,['checklist_receipts']);
  assert.match(slice,/ALTER TABLE private_isg\.checklist_receipts ENABLE ROW LEVEL SECURITY/);
  assert.match(slice,/REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;/);
});

test('exactly two wrappers reach the client and both are invoker',()=>{
  const wrappers=[...slice.matchAll(/CREATE FUNCTION public\.(isg_[a-z_0-9]+)/g)].map(m=>m[1]);
  assert.deepEqual(wrappers,['isg_checklists_read_v1','isg_checklists_mutate_v1']);
  for(const name of wrappers) assert.match(slice,new RegExp(`CREATE FUNCTION public\\.${name}[\\s\\S]{0,260}SECURITY INVOKER`));
  const granted=[...slice.matchAll(/GRANT EXECUTE ON FUNCTION([\s\S]*?)TO authenticated;/g)];
  assert.equal(granted.length,1);
  assert.equal((granted[0][1].match(/private_isg\./g)||[]).length,2);
});

test('no read claims compliance or a health record',()=>{
  assert.match(code(slice),/'compliance_verdict',NULL/);
  assert.match(code(slice),/'health_records_tracked',false/);
  assert.doesNotMatch(code(slice),/health_record_id|medical/i);
});

test('every mutation is receipted and the same id cannot mean two things',()=>{
  assert.match(code(slice),/PRIMARY KEY\(actor_id,mutation_id\)/);
  assert.match(code(slice),/request_hash IS DISTINCT FROM fingerprint THEN[\s\S]{0,120}IDEMPOTENCY_CONFLICT/);
  assert.match(checks,/the same id with a different body is refused/);
});

test('the checks are written for a disposable database only',()=>{
  assert.doesNotMatch(checks,/DROP SCHEMA|DROP DATABASE/);
  assert.match(checks,/ALL CHECKLIST RUN CHECKS PASSED/);
});
