import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {beginFileCoreProbe,fileCoreFiles} from './file_core_probe.mjs';

const migration=readFileSync(resolve(ROOT,fileCoreFiles[0]),'utf8');
const runner=readFileSync(resolve(ROOT,'scripts/isg/run_auth_restore.mjs'),'utf8');

test('the probe refuses any other mode before touching SQL',async()=>{
  let touched=false;
  await assert.rejects(beginFileCoreProbe({synthetic:false,sql(){touched=true;}}),/SYNTHETIC_REQUIRED/);
  await assert.rejects(beginFileCoreProbe({synthetic:true,sql(){touched=true;}}),/SCOPE_REQUIRED/);
  assert.equal(touched,false);
});

test('the file core ships disabled, private and without a client grant',()=>{
  assert.match(migration,/INSERT INTO private_isg\.rollout\(feature\) VALUES\('file_core'\)/);
  assert.doesNotMatch(migration,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(migration,/GRANT (EXECUTE|SELECT|INSERT|UPDATE|DELETE|ALL)[\s\S]{0,400}?TO (anon|authenticated|service_role)/);
  const created=[...migration.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
  const secured=new Set([...migration.matchAll(/ALTER TABLE private_isg\.([a-z_]+) ENABLE ROW LEVEL SECURITY/g)].map(m=>m[1]));
  assert.equal(created.length,5);
  for(const table of created) assert.ok(secured.has(table),table);
});

test('the acceptance matrix covers the thirteen source formats and marks its limits unapproved',()=>{
  const extensions=new Set([...migration.matchAll(/'(pdf|jpe?g|png|heic|heif|webp|avif|docx?|xlsx?|csv)'/g)].map(m=>m[1]));
  for(const format of ['pdf','jpg','jpeg','png','heic','heif','webp','avif','doc','docx','xls','xlsx','csv'])
    assert.ok(extensions.has(format),format);
  assert.match(migration,/limit_source text NOT NULL CHECK\(limit_source IN \('v5_candidate','approved'\)\)/);
  assert.match(migration,/'v5_candidate'\),/);
  assert.doesNotMatch(migration,/limit_source\) VALUES[\s\S]*'approved'/);
});

test('a scanner failure is never clean and promotion reverifies the scanned bytes',()=>{
  assert.match(migration,/IF p_verdict='failed' THEN RETURN private_isg\.reject_upload_intent\(p_intent,'SCAN_UNAVAILABLE',p_now\)/);
  assert.match(migration,/IF p_final_sha256<>scan\.scanned_sha256 OR p_final_bytes<>entry\.received_bytes THEN/);
  assert.match(migration,/immutable_path text NOT NULL UNIQUE/);
  assert.match(migration,/scan_status text NOT NULL DEFAULT 'clean' CHECK\(scan_status='clean'\)/);
});

test('the storage ledger stays shadow inside the upload path',()=>{
  assert.match(migration,/IF SQLERRM<>'CAPACITY_EXCEEDED' THEN RAISE; END IF;\n      denied:=true;/);
  assert.match(migration,/'storage_authority','legacy'/);
});

test('the runner wires the probe and hashes the migration',()=>{
  assert.match(runner,/beginFileCoreProbe\(\{synthetic:true/);
  assert.match(runner,/concat\(mode\.synthetic \? fileCoreFiles : \[\]\)/);
  assert.match(runner,/fileProbe\.afterLogout\(\)/);
});
