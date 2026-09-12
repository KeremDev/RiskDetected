import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { ROOT } from './lib.mjs';
import { beginAuthMutationProbe } from './auth_mutation_probe.mjs';

test('Auth mutation composition rejects every non-synthetic mode before SQL',async()=>{
  let calls=0;
  for(const synthetic of [false,undefined,null,'true',1]) {
    await assert.rejects(()=>beginAuthMutationProbe({synthetic,sql:()=>calls++}),/AUTH_RESTORE_MUTATION_SYNTHETIC_REQUIRED/);
  }
  assert.equal(calls,0);
});
test('Auth mutation composition rejects an unverified token before DDL',async()=>{
  let calls=0;
  await assert.rejects(()=>beginAuthMutationProbe({synthetic:true,token:'bad.token.signature',secret:'a'.repeat(64),sql:()=>calls++}),/AUTH_RESTORE_LOCAL_TOKEN_INVALID/);
  assert.equal(calls,0);
});
test('Auth mutation composition is wired only in synthetic lane, including after logout',()=>{
  const runner=readFileSync(resolve(ROOT,'scripts/isg/run_auth_restore.mjs'),'utf8');
  assert.match(runner,/if \(mode\.synthetic\) \{\s*stage = 'auth-mutation-composition';\s*mutationProbe = await beginAuthMutationProbe\(\{ synthetic:true,/);
  assert.ok(runner.indexOf("pass('logout_succeeds'")<runner.indexOf('report.auth_mutation = mutationProbe.afterLogout()'));
  for(const file of ['auth_mutation_probe.mjs','sql/auth_mutation_fixture.sql','sql/transaction_fixture.sql']) assert.ok(runner.includes(`'scripts/isg/${file}'`));
});
test('composition keeps explicit private grants and reuses original transaction implementation',()=>{
  const source=readFileSync(resolve(ROOT,'scripts/isg/sql/auth_mutation_fixture.sql'),'utf8');
  assert.match(source,/SECURITY DEFINER SET search_path=pg_catalog/);
  assert.match(source,/actor := isg_session_fixture\.require_active_session\(\)/);
  assert.match(source,/actor_id=actor AND can_mutate FOR SHARE/);
  assert.match(source,/result := isg_fixture\.mutate\(p_mutation,p_company,p_entity,p_expected,p_delta\)/);
  assert.match(source,/ALTER TABLE isg_fixture\.write_capabilities ENABLE ROW LEVEL SECURITY/);
  assert.doesNotMatch(source,/GRANT[^;]+ON FUNCTION isg_fixture\.mutate\(/);
  assert.doesNotMatch(source,/CREATE (?:OR REPLACE )?(?:FUNCTION|TABLE) (?:public|auth|storage)\./);
  assert.doesNotMatch(source,/user_metadata|raw_user_meta_data/);
});
