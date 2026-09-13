import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {beginDocumentImportProbe,documentImportFiles} from './document_import_probe.mjs';

const migration=readFileSync(resolve(ROOT,documentImportFiles[0]),'utf8');
const runner=readFileSync(resolve(ROOT,'scripts/isg/run_auth_restore.mjs'),'utf8');

test('the probe refuses any other mode before touching SQL',async()=>{
  let touched=false;
  await assert.rejects(beginDocumentImportProbe({synthetic:false,sql(){touched=true;}}),/SYNTHETIC_REQUIRED/);
  await assert.rejects(beginDocumentImportProbe({synthetic:true,sql(){touched=true;}}),/SCOPE_REQUIRED/);
  assert.equal(touched,false);
});

test('documents and imports ship disabled, private and without a client grant',()=>{
  assert.match(migration,/INSERT INTO private_isg\.rollout\(feature\) VALUES\('documents'\),\('imports'\)/);
  assert.doesNotMatch(migration,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(migration,/GRANT (EXECUTE|SELECT|INSERT|UPDATE|DELETE|ALL)[\s\S]{0,400}?TO (anon|authenticated|service_role)/);
  const created=[...migration.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
  const secured=new Set([...migration.matchAll(/ALTER TABLE private_isg\.([a-z_]+) ENABLE ROW LEVEL SECURITY/g)].map(m=>m[1]));
  assert.equal(created.length,9);
  for(const table of created) assert.ok(secured.has(table),table);
});

test('numbering is locked per company, scope and year and a snapshot is hashed',()=>{
  assert.match(migration,/PRIMARY KEY\(company_id,scope,year\)/);
  assert.match(migration,/UPDATE private_isg\.document_number_sequences SET next_value=next_value\+1/);
  assert.match(migration,/CREATE UNIQUE INDEX document_no_idx/);
  assert.match(migration,/snapshot_sha256 bytea NOT NULL CHECK\(octet_length\(snapshot_sha256\)=32\)/);
  assert.match(migration,/UNIQUE\(document_id,mutation_id\)/);
});

test('a scanned original never becomes a structured spreadsheet',()=>{
  assert.match(migration,/content:=CASE WHEN p_format='xlsx' AND revision\.source_kind='scanned' THEN 'metadata_index'/);
  assert.match(migration,/UNIQUE\(document_id,version,format\)/);
});

test('a cell is data and an ambiguous number is reviewed',()=>{
  assert.match(migration,/FORMULA_PREFIX_REMOVED/);
  assert.match(migration,/AMBIGUOUS_DECIMAL/);
  assert.match(migration,/EXCEL_1900_LEAP_BUG/);
  assert.match(migration,/IF serial=60 THEN/);
});

test('identity is never guessed and health columns are refused',()=>{
  assert.match(migration,/IDENTITY_NOT_DERIVABLE/);
  assert.match(migration,/MESSAGE='HEALTH_COLUMN_REFUSED'/);
  assert.match(migration,/kan_grubu/);
});

test('commit needs a fresh preview and compensation never undoes a later edit',()=>{
  assert.match(migration,/MESSAGE='PREVIEW_REQUIRED'/);
  assert.match(migration,/MESSAGE='PREVIEW_STALE'/);
  assert.match(migration,/MESSAGE='PARTIAL_COMMIT_NOT_ALLOWED'/);
  assert.match(migration,/IF current_version<>row_entry\.target_version THEN kept:=kept\+1; CONTINUE; END IF;/);
});

test('the runner wires the probe and hashes the migration',()=>{
  assert.match(runner,/beginDocumentImportProbe\(\{synthetic:true/);
  assert.match(runner,/concat\(mode\.synthetic \? documentImportFiles : \[\]\)/);
  assert.match(runner,/documentProbe\.afterLogout\(\)/);
});
