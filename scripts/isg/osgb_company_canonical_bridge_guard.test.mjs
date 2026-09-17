import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const sql=readFileSync(new URL('../../supabase/pilot-release/candidates/20260917143000_osgb_company_canonical_bridge.sql',import.meta.url),'utf8');

test('canonical company identity keeps legacy owner nullable only for scoped workspace rows',()=>{
  assert.match(sql,/ALTER COLUMN user_id DROP NOT NULL/);
  assert.match(sql,/CHECK\(user_id IS NOT NULL OR workspace_id IS NOT NULL\)/);
  assert.match(sql,/workspace_company_required/);
  assert.match(sql,/workspace_company_legacy_fk/);
});

test('legacy direct writes synchronize into personal workspace without opening OSGB RLS',()=>{
  assert.match(sql,/workspace_company_canonical_sync/);
  assert.match(sql,/kind='personal' AND personal_owner_user_id=NEW\.user_id/);
  assert.doesNotMatch(sql,/CREATE POLICY|GRANT\s+(SELECT|INSERT|UPDATE|DELETE)\s+ON\s+public\.companies/i);
});

test('OSGB company create update and archive are atomic dual writes',()=>{
  for(const token of ['CREATE OR REPLACE FUNCTION private_isg.workspace_company_create',
    'CREATE OR REPLACE FUNCTION private_isg.workspace_company_update',
    'CREATE OR REPLACE FUNCTION private_isg.workspace_company_archive',
    'INSERT INTO public.companies','UPDATE public.companies SET name','UPDATE public.companies SET is_archived=true']){
    assert.ok(sql.includes(token),token);
  }
  assert.match(sql,/VALUES\(company\.id,NULL,p_workspace/);
});

test('personal mapping is resumable and observation-only by default',()=>{
  assert.match(sql,/p_apply boolean DEFAULT false/);
  assert.match(sql,/SOURCE_FINGERPRINT_CONFLICT/);
  assert.match(sql,/workspace_company_backfill_checkpoints/);
  assert.doesNotMatch(sql,/DELETE FROM/);
});
