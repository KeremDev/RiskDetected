import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

const read=path=>readFileSync(resolve(ROOT,path),'utf8');
const seedText=read('docs/isg/checklists/ISG_ADASI_CHECKLIST_SEED.json');
const seed=JSON.parse(seedText);
const migration=read('supabase/migrations/20260921072445_checklist_catalog_v1.sql');
const code=migration.split('\n').filter(line=>!line.trimStart().startsWith('--')).join('\n');
const completion=read('supabase/migrations/20260921114500_checklist_catalog_completion.sql');
const snapshots=read('supabase/migrations/20260921130000_checklist_snapshots_and_personal_runs.sql');

test('the attached verified catalogue is copied losslessly',()=>{
  assert.equal(seed.sectors.length,24);
  assert.equal(seed.templates.length,200);
  assert.equal(seed.templates.flatMap(x=>x.items).length,2000);
  assert.ok(seed.templates.every(x=>x.items.length===10));
  assert.equal(createHash('sha256').update(seedText).digest('hex'),
    'c32e8ab71ae86663972eb89f02de158bc2b899892963312b0695ebb7ec79d62d');
});

test('catalogue data is immutable, normalized and inaccessible as direct client tables',()=>{
  for(const table of ['checklist_catalogs','checklist_catalog_sectors','checklist_catalog_sources',
    'checklist_topic_packs','checklist_atomic_items','checklist_catalog_templates','checklist_catalog_items']){
    assert.match(code,new RegExp(`CREATE TABLE private_isg\\.${table}`));
  }
  assert.match(code,/CHECKLIST_CATALOG_IMMUTABILITY_CONFLICT/);
  assert.match(code,/CHECKLIST_CATALOG_COUNT_MISMATCH/);
  assert.match(code,/ENABLE ROW LEVEL SECURITY/);
  assert.match(code,/REVOKE ALL ON private_isg\.checklist_catalogs/);
});

test('search covers item text and Turkish characters are normalized',()=>{
  assert.match(code,/checklist_search_fold/);
  assert.match(code,/translate\(lower\(coalesce\(p_value,''\)\),'çğıöşüâîû','cgiosuaiu'\)/);
  assert.match(code,/EXISTS\(SELECT 1 FROM private_isg\.checklist_catalog_items/);
  assert.match(code,/i\.search_document LIKE/);
});

test('runs pin a version and findings preserve checklist lineage idempotently',()=>{
  assert.match(code,/source_run_id uuid REFERENCES private_isg\.checklist_runs/);
  assert.match(code,/nonconformity_checklist_lineage_idx/);
  assert.match(code,/source_ref.*p_run::text\|\|':'\|\|p_item|p_run::text\|\|':'\|\|p_item/);
  assert.match(code,/UPDATE private_isg\.nonconformities SET source_run_id=p_run,source_item_code=p_item/);
  assert.match(code,/'auto_nonconformity',false/);
});

test('three-state answer contract, reason rules and evidence ownership are server enforced',()=>{
  assert.match(code,/WHEN 'compliant' THEN 'conform'/);
  assert.match(code,/WHEN 'non_compliant' THEN 'nonconform'/);
  assert.match(code,/normalized IN \('nonconform','not_applicable'\)/);
  assert.match(code,/MESSAGE='EXPLANATION_REQUIRED'/);
  assert.match(code,/a\.company_id=run\.company_id AND a\.scan_status='clean'/);
  assert.match(code,/evidence_asset_id.*private_isg\.file_assets/);
});

test('catalogue copies and company assignments are explicit receipted mutations',()=>{
  assert.match(code,/WHEN 'copy_template'/);
  assert.match(code,/WHEN 'assign_template'/);
  assert.match(code,/checklist_template_assignments/);
  assert.match(code,/INSERT INTO private_isg\.checklist_receipts/);
  assert.match(code,/IDEMPOTENCY_CONFLICT/);
});

test('item search is a separate deduplicated result with its list contexts',()=>{
  assert.match(completion,/'matched_items'/);
  assert.match(completion,/GROUP BY i\.atomic_item_code/);
  assert.match(completion,/'contexts',jsonb_agg/);
  assert.match(completion,/i\.search_document LIKE/);
});

test('custom lists compose catalogue items, reject accidental duplicates and reorder atomically',()=>{
  assert.match(completion,/WHEN 'copy_items'/);
  assert.match(completion,/WHEN 'reorder_items'/);
  assert.match(completion,/MESSAGE='DUPLICATE_CHECKLIST_ITEM'/);
  assert.match(completion,/scope_key/);
  assert.match(completion,/UNIQUE\(template_code,version,position\) DEFERRABLE INITIALLY DEFERRED/);
});

test('run writes use optimistic revision and corrections create a linked run',()=>{
  assert.match(completion,/ADD COLUMN IF NOT EXISTS edit_revision bigint NOT NULL DEFAULT 0/);
  assert.match(completion,/MESSAGE='CHECKLIST_CONFLICT'/);
  assert.match(completion,/WHEN 'revise_run'/);
  assert.match(completion,/revises_run_id/);
  assert.match(completion,/'applicable_coverage_percent'/);
});

test('workspace company assignments do not pretend an OSGB firm has a personal owner',()=>{
  assert.match(completion,/checklist_template_assignments[\s\S]*?owner_id DROP NOT NULL/);
  assert.match(completion,/p_kind='assignments'/);
  assert.match(completion,/WHEN 'deactivate_assignment'/);
});

test('each run owns immutable question snapshots and company-free runs stay personal',()=>{
  assert.match(snapshots,/CREATE TABLE private_isg\.checklist_run_questions/);
  assert.match(snapshots,/CREATE TRIGGER checklist_run_snapshot_after_insert/);
  assert.match(snapshots,/FROM private_isg\.checklist_run_questions q LEFT JOIN/);
  assert.match(snapshots,/company_id IS NULL AND workplace_id IS NULL AND owner_id IS NOT NULL/);
  assert.match(snapshots,/MESSAGE='COMPANY_REQUIRED_FOR_NONCONFORMITY'/);
});

test('template editing and every run correction use expected revisions',()=>{
  assert.match(snapshots,/ADD COLUMN IF NOT EXISTS edit_revision bigint NOT NULL DEFAULT 0/);
  assert.match(snapshots,/template_action boolean/);
  assert.match(snapshots,/p_payload->>'expected_revision'/);
  assert.match(snapshots,/SET edit_revision=edit_revision\+1/);
});
