import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

const sql=readFileSync(resolve(ROOT,'supabase/pilot-release/candidates/20260918010000_osgb_company_profile_product_parity.sql'),'utf8');
const api=readFileSync(resolve(ROOT,'App/Services/ISG/IsgWorkspaceAPI.swift'),'utf8');
const editor=readFileSync(resolve(ROOT,'App/Views/Components/NovaPilotMainGate.swift'),'utf8');

test('OSGB company product profile stays tenant scoped and backward compatible',()=>{
  assert.match(sql,/CREATE TABLE private_isg\.workspace_company_profiles/);
  assert.match(sql,/FOREIGN KEY\(workspace_id,company_id\)/);
  assert.match(sql,/ENABLE ROW LEVEL SECURITY/);
  assert.match(sql,/workspace_require_member\(p_workspace,ARRAY\['owner','admin'\],true\)/);
  assert.match(sql,/workspace_require_company\(p_workspace,p_company,true\)/);
  assert.match(sql,/workspace_receipt_replay\(actor,p_mutation,'company\.profile',fingerprint\)/);
  assert.match(sql,/workspace_record_effect\(actor,p_mutation,'company\.profile'/);
  assert.match(sql,/workspace_record_effect\(actor,p_mutation,'company\.profile',fingerprint,p_workspace,\s*\n\s*'company',p_company/,
    'profile changes must use the existing company audit/outbox aggregate type');
  assert.doesNotMatch(sql,/'company_profile',p_company/,
    'an undeclared audit aggregate would make every profile save roll back');
  assert.match(sql,/LEFT JOIN private_isg\.workspace_company_profiles/,
    'old companies must remain listable without a profile row');
  assert.match(sql,/REVOKE ALL ON private_isg\.workspace_company_profiles FROM PUBLIC,anon,authenticated,service_role/);
});

test('iOS company form and API persist parity fields through the scoped RPC',()=>{
  for(const token of ['sector','declaredEmployeeCount','responsibleName','responsiblePhone','responsibleEmail','profileVersion'])
    assert.ok(api.includes(token),token);
  assert.match(api,/isg_workspace_company_profile_mutate_v1/);
  assert.match(editor,/Firmayı kaydet/);
  assert.match(editor,/Sektör \*/);
  assert.match(editor,/Çalışan sayısı/);
  assert.match(editor,/Sorumlu personel ekle/);
  const companyEditor=editor.slice(editor.indexOf('private struct IsgWorkspaceCompanyEditor'),
    editor.indexOf('struct NovaPilotRoot'));
  assert.doesNotMatch(companyEditor,/localizable\.nova\.personnel\.save/,
    'company editor must never show the personnel save label');
});
