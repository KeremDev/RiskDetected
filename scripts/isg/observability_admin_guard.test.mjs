import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {beginObservabilityAdminProbe,observabilityAdminFiles} from './observability_admin_probe.mjs';

const migration=readFileSync(resolve(ROOT,observabilityAdminFiles[0]),'utf8');
const runner=readFileSync(resolve(ROOT,'scripts/isg/run_auth_restore.mjs'),'utf8');

test('the probe refuses any other mode before touching SQL',async()=>{
  let touched=false;
  await assert.rejects(beginObservabilityAdminProbe({synthetic:false,sql(){touched=true;}}),/SYNTHETIC_REQUIRED/);
  await assert.rejects(beginObservabilityAdminProbe({synthetic:true,sql(){touched=true;}}),/SCOPE_REQUIRED/);
  assert.equal(touched,false);
});

test('the observability ledger ships disabled, private and without a client grant',()=>{
  assert.match(migration,/INSERT INTO private_isg\.rollout\(feature\) VALUES\('observability'\)/);
  assert.doesNotMatch(migration,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(migration,/GRANT (EXECUTE|SELECT|INSERT|UPDATE|DELETE|ALL)[\s\S]{0,400}?TO (anon|authenticated|service_role)/);
  const created=[...migration.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
  const secured=new Set([...migration.matchAll(/ALTER TABLE private_isg\.([a-z_]+) ENABLE ROW LEVEL SECURITY/g)].map(m=>m[1]));
  assert.equal(created.length,13);
  for(const table of created) assert.ok(secured.has(table),table);
});

test('the envelope has no column for a secret or a person’s content',()=>{
  // Column definitions only: the file's prose names what must never be logged.
  assert.doesNotMatch(migration,/^\s*\w*(email|password|otp|access_token|refresh_token|secret|signature|signed_url|photo|note_body|document_text)\w*\s+(uuid|text|jsonb|bytea)/mi);
  assert.match(migration,/carries_user_content boolean NOT NULL DEFAULT false CHECK\(NOT carries_user_content\)/);
  assert.match(migration,/telemetry_redaction_violation/);
  assert.match(migration,/MESSAGE='METADATA_NOT_ALLOWED'/);
  assert.match(migration,/MESSAGE='REDACTION_VIOLATION'/);
});

test('the chain starts before any analysis row and only a render is a success',()=>{
  assert.match(migration,/analysis_row_created boolean NOT NULL DEFAULT false/);
  assert.match(migration,/CHECK\(outcome<>'rendered' OR last_stage='ui_render'\)/);
  assert.match(migration,/CHECK\(outcome<>'failed_before_submit' OR NOT analysis_row_created\)/);
  assert.match(migration,/'successful_user_outcome',p_outcome='rendered'/);
  const stages=[...migration.matchAll(/^\s*\('[a-z_]+',[0-9]+,(true|false),'[^']+'\),?;?$/gm)].length;
  assert.equal(stages,10);
});

test('telemetry can never block or change a domain operation',()=>{
  assert.match(migration,/blocks_domain boolean NOT NULL DEFAULT false CHECK\(NOT blocks_domain\)/);
  assert.match(migration,/'domain_operation_affected',false/);
  // Nothing in this slice reads or writes a domain table.
  assert.doesNotMatch(migration,/INSERT INTO private_isg\.(employees|analyses|risk_|training_|documents)/);
  assert.doesNotMatch(migration,/public\.analyses|public\.findings|public\.reports/);
});

test('without a tracking authorization there is nothing to attribute or store',()=>{
  assert.match(migration,/CHECK\(tracking_authorized OR attribution_source='unknown'\)/);
  assert.match(migration,/identifier_stored boolean NOT NULL DEFAULT false CHECK\(NOT identifier_stored\)/);
  assert.match(migration,/third_party_sdk_called boolean NOT NULL DEFAULT false CHECK\(NOT third_party_sdk_called\)/);
  assert.match(migration,/resolved:=CASE WHEN p_authorized THEN p_source ELSE 'unknown' END/);
});

test('an admin needs a live session, a second factor and a real scope',()=>{
  assert.match(migration,/requires_aal2 boolean NOT NULL DEFAULT true CHECK\(requires_aal2\)/);
  assert.match(migration,/MESSAGE='MFA_REQUIRED'/);
  assert.match(migration,/MESSAGE='SCOPE_DENIED'/);
  assert.match(migration,/IF NOT \(p_scope=ANY\(entry\.granted_scopes\)\)/);
  assert.match(migration,/'scopes_verified_by','server'/);
});

test('a publish is fail-closed on its simulation and its audit',()=>{
  assert.match(migration,/CHECK\(state<>'published' OR \(simulated_at IS NOT NULL AND published_at IS NOT NULL AND audit_id IS NOT NULL\)\)/);
  assert.match(migration,/MESSAGE='SIMULATION_REQUIRED'/);
  assert.match(migration,/'audit_written_before_publish',true/);
  assert.match(migration,/carries_raw_payload boolean NOT NULL DEFAULT false CHECK\(NOT carries_raw_payload\)/);
  // The audit INSERT stands before the action UPDATE in the same transaction.
  const body=migration.slice(migration.indexOf('CREATE FUNCTION private_isg.publish_admin_action'));
  assert.ok(body.indexOf('INSERT INTO private_isg.admin_audit_entries')<body.indexOf("SET state='published'"));
});

test('an export is a masked allowlisted projection',()=>{
  assert.match(migration,/raw_pii_included boolean NOT NULL DEFAULT false CHECK\(NOT raw_pii_included\)/);
  assert.match(migration,/MESSAGE='EXPORT_DENIED'/);
  assert.match(migration,/safe_columns:=ARRAY\[/);
  assert.match(migration,/maskable:=ARRAY\[/);
});

test('pausing admin writes leaves the audit and the settlement chain alone',()=>{
  assert.match(migration,/MESSAGE='ADMIN_WRITES_PAUSED'/);
  assert.match(migration,/audit_continues boolean NOT NULL DEFAULT true CHECK\(audit_continues\)/);
  assert.match(migration,/settlement_continues boolean NOT NULL DEFAULT true CHECK\(settlement_continues\)/);
  assert.doesNotMatch(migration,/UPDATE private_isg\.benefit_settlements|UPDATE private_isg\.benefit_instances/);
});

test('the runner wires the probe and hashes the migration',()=>{
  assert.match(runner,/beginObservabilityAdminProbe\(\{synthetic:true/);
  assert.match(runner,/concat\(mode\.synthetic \? observabilityAdminFiles : \[\]\)/);
  assert.match(runner,/observabilityProbe\.afterLogout\(\)/);
});
