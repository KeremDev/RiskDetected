import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

const sql=readFileSync(resolve(ROOT,
  'supabase/pilot-release/candidates/20260918013000_osgb_operational_surface_parity.sql'),'utf8');
const screen=readFileSync(resolve(ROOT,'App/DesignSystem/ISG/IsgWorkspaceDomainScreen.swift'),'utf8');
const editor=readFileSync(resolve(ROOT,'App/DesignSystem/ISG/IsgWorkspaceDomainCreateEditor.swift'),'utf8');

test('operational parity metrics stay tenant scoped and additive',()=>{
  for(const gate of ["workspace_domain_gate('emergency_ppe',false)",
    "workspace_domain_gate('risk_nonconformity',false)",
    "workspace_domain_gate('operations',false)"])
    assert.ok(sql.includes(gate),gate);
  assert.equal((sql.match(/workspace_require_company\(p_workspace,p_company,false\)/g)||[]).length,3);
  for(const metric of ["'untracked'","'due_soon'","'upcoming'","'ended'",
    "'open_decisions'","'held'","'cancelled'"])
    assert.ok(sql.includes(metric),metric);
  assert.doesNotMatch(sql,/DROP\s+(TABLE|FUNCTION)|TRUNCATE|DELETE\s+FROM/i);
});

test('OSGB screens expose personal-pilot operational behavior without the retired training planner',()=>{
  assert.doesNotMatch(screen,/showingTrainingManagement|Müfredat, yıllık plan ve belgeler/);
  for(const marker of ['plans.expired','appointments.active','risk.expired','board.open_decisions'])
    assert.ok(screen.includes(marker),marker);
  for(const marker of ['Acil durum ekibi','Bitiş tarihi belirle','Alınan kararlar','board.outcome'])
    assert.ok(editor.includes(marker),marker);
  assert.match(editor,/"applicability": \.string\("mandatory"\)/);
  assert.match(editor,/if domain == \.training \{ saveTraining\(\); return \}/);
  assert.match(editor,/workflowMutationID\("training\.complete"/);
  assert.match(editor,/"attended": \.bool\(true\)/);
  assert.doesNotMatch(editor,/Eğitim planlamak için/);
});
