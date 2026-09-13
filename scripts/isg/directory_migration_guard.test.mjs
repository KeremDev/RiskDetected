import test from 'node:test';
import assert from 'node:assert/strict';
import {beginDirectoryMigrationProbe,directoryMigrationFiles} from './directory_migration_probe.mjs';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

test('directory migration refuses other modes before SQL or HTTP',async()=>{
  let touched=false;
  await assert.rejects(beginDirectoryMigrationProbe({synthetic:false,sql(){touched=true},request(){touched=true}}),/SYNTHETIC_REQUIRED/);
  assert.equal(touched,false);
});
test('directory migration rejects unverified Auth claims before DDL',async()=>{
  let touched=false;
  await assert.rejects(beginDirectoryMigrationProbe({synthetic:true,token:'forged',secret:'local-test-only',sql(){touched=true}}));
  assert.equal(touched,false);
});
test('actual expansion is hashed, feature gated and never enables the rollout',()=>{
  const migration=readFileSync(resolve(ROOT,directoryMigrationFiles[0]),'utf8');
  const runner=readFileSync(resolve(ROOT,'scripts/isg/run_auth_restore.mjs'),'utf8');
  assert.match(migration,/actor:=private_isg.require_company\(p_company,true\)/);
  assert.doesNotMatch(migration,/UPDATE private_isg.rollout SET/);
  assert.match(runner,/concat\(directoryMigrationFiles\)/);
  assert.match(runner,/directoryProbe.afterLogout\(\)/);
  assert.match(migration,/CREATE FUNCTION public.isg_context_at_v1/);
  assert.match(migration,/'status','needs_review'/);
});
