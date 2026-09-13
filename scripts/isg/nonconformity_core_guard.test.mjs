import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {beginNonconformityCoreProbe,nonconformityCoreFiles} from './nonconformity_core_probe.mjs';

const migration=readFileSync(resolve(ROOT,nonconformityCoreFiles[0]),'utf8');
const runner=readFileSync(resolve(ROOT,'scripts/isg/run_auth_restore.mjs'),'utf8');

test('the probe refuses any other mode before touching SQL',async()=>{
  let touched=false;
  await assert.rejects(beginNonconformityCoreProbe({synthetic:false,sql(){touched=true;}}),/SYNTHETIC_REQUIRED/);
  await assert.rejects(beginNonconformityCoreProbe({synthetic:true,sql(){touched=true;}}),/SCOPE_REQUIRED/);
  assert.equal(touched,false);
});

test('the domain ships disabled, private and writes no legacy finding',()=>{
  assert.match(migration,/INSERT INTO private_isg\.rollout\(feature\) VALUES\('nonconformity'\)/);
  assert.doesNotMatch(migration,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(migration,/GRANT (EXECUTE|SELECT|INSERT|UPDATE|DELETE|ALL)[\s\S]{0,400}?TO (anon|authenticated|service_role)/);
  assert.doesNotMatch(migration,/(INSERT INTO|UPDATE) public\.findings/);
  assert.doesNotMatch(migration,/(SELECT|UPDATE|INSERT)[^\n]*\bpublic\.findings\b/);
  const created=[...migration.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
  const secured=new Set([...migration.matchAll(/ALTER TABLE private_isg\.([a-z_]+) ENABLE ROW LEVEL SECURITY/g)].map(m=>m[1]));
  assert.equal(created.length,11);
  for(const table of created) assert.ok(secured.has(table),table);
});

test('the transition matrix is server data with exactly sixteen edges',()=>{
  const edges=[...migration.matchAll(/\('(draft|open|assigned|in_progress|pending_verification|closed|reopened|cancelled)','(draft|open|assigned|in_progress|pending_verification|closed|reopened|cancelled)',(?:true|false),/g)];
  assert.equal(edges.length,16);
  assert.match(migration,/MESSAGE='TRANSITION_NOT_ALLOWED'/);
  assert.match(migration,/IF entry\.version<>p_expected_version THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'/);
});

test('closing needs an accepted verification of the current cycle',()=>{
  assert.match(migration,/WHERE nonconformity_id=p_nonconformity AND cycle=entry\.version AND outcome='accepted'/);
  assert.match(migration,/MESSAGE='VERIFICATION_REQUIRED'/);
  assert.match(migration,/verified_by uuid NOT NULL REFERENCES public\.profiles\(id\)/);
});

test('an assignee is a report person, never an application user',()=>{
  assert.match(migration,/assignee_contact text CHECK\(assignee_contact IS NULL OR \(btrim\(assignee_contact\)<>''/);
  assert.doesNotMatch(migration,/assignee_contact uuid|assignee_id uuid REFERENCES/);
  assert.match(migration,/'assignee_is_application_user',false/);
});

test('one record per source and a run pins its template version',()=>{
  assert.match(migration,/CREATE UNIQUE INDEX nonconformity_source_idx/);
  assert.match(migration,/template_version integer NOT NULL/);
  assert.match(migration,/MESSAGE='RUN_SUBMITTED'/);
  assert.match(migration,/MESSAGE='RUN_INCOMPLETE'/);
});

test('the runner wires the probe and hashes the migration',()=>{
  assert.match(runner,/beginNonconformityCoreProbe\(\{synthetic:true/);
  assert.match(runner,/concat\(mode\.synthetic \? nonconformityCoreFiles : \[\]\)/);
  assert.match(runner,/nonconformityProbe\.afterLogout\(\)/);
});
