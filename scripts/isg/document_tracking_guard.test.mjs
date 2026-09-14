import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {beginDocumentTrackingProbe,documentTrackingFiles} from './document_tracking_probe.mjs';

const migration=readFileSync(resolve(ROOT,documentTrackingFiles[0]),'utf8');
const portfolio=readFileSync(resolve(ROOT,documentTrackingFiles[1]),'utf8');
const probe=readFileSync(resolve(ROOT,documentTrackingFiles[2]),'utf8');
const runner=readFileSync(resolve(ROOT,'scripts/isg/run_auth_restore.mjs'),'utf8');

test('the probe refuses any other mode before touching SQL',async()=>{
  let touched=false;
  await assert.rejects(beginDocumentTrackingProbe({synthetic:false,sql(){touched=true;}}),/SYNTHETIC_REQUIRED/);
  await assert.rejects(beginDocumentTrackingProbe({synthetic:true,sql(){touched=true;}}),/SCOPE_REQUIRED/);
  assert.equal(touched,false);
});

test('the slice ships without opening the switch and without a table grant',()=>{
  assert.doesNotMatch(migration,/UPDATE private_isg\.rollout SET/);
  assert.match(migration,/INSERT INTO private_isg\.rollout\(feature\) VALUES\('document_tracking'\);/);
  assert.match(migration,/REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;/);
  const created=[...migration.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
  const secured=new Set([...migration.matchAll(/ALTER TABLE private_isg\.([a-z_]+) ENABLE ROW LEVEL SECURITY/g)].map(m=>m[1]));
  assert.deepEqual(created,['document_obligation_kinds','document_obligations',
    'document_obligation_records','document_tracking_receipts']);
  for(const table of created) assert.ok(secured.has(table),table);
  // Only the two checked entries and their wrappers are callable.
  const granted=migration.slice(migration.indexOf('GRANT EXECUTE ON FUNCTION'));
  assert.match(granted,/private_isg\.read_document_tracking/);
  assert.match(granted,/private_isg\.mutate_document_tracking/);
  assert.doesNotMatch(granted,/document_obligation_row|require_document_tracking_company|document_obligation_status|document_tracking_gate/);
});

test('a health record has no kind to arrive under',()=>{
  // The allowed set is a CHECK in the schema, not a seed a later insert can grow.
  const check=migration.slice(migration.indexOf('CREATE TABLE private_isg.document_obligation_kinds'),
    migration.indexOf('INSERT INTO private_isg.document_obligation_kinds'));
  assert.match(check,/kind_code text PRIMARY KEY CHECK\(kind_code IN \(/);
  assert.doesNotMatch(check,/health|medical|saglik|sağlık|muayene/i);
  // The kinds the tracker offers are exactly the ones the CHECK allows.
  const allowed=[...check.matchAll(/'([a-z_]+)'/g)].map(m=>m[1]);
  const seeded=[...migration.slice(migration.indexOf('INSERT INTO private_isg.document_obligation_kinds'),
    migration.indexOf('-- One tracked obligation')).matchAll(/\('([a-z_]+)',\d+,/g)].map(m=>m[1]);
  assert.deepEqual([...seeded].sort(),[...allowed].sort());
  assert.equal(seeded.length,16);
});

test('a status is computed at read time and never stored',()=>{
  const tables=migration.slice(migration.indexOf('CREATE TABLE private_isg.document_obligations'),
    migration.indexOf('CREATE TABLE private_isg.document_tracking_receipts'));
  for(const column of ['status','state','is_valid','is_expired','is_compliant'])
    assert.doesNotMatch(tables,new RegExp(`\\n  ${column} `),column);
  assert.match(migration,/CREATE FUNCTION private_isg\.document_obligation_status\(p_valid_until date,p_has_record boolean,\s*\n\s*p_notice_days integer,p_today date\) RETURNS text/);
  assert.match(migration,/'status_authority','computed_at_read'/);
  // No action may carry a status the client chose.
  const allowlist=migration.slice(migration.indexOf('allowed:=CASE p_action'),migration.indexOf('IF allowed IS NULL'));
  assert.doesNotMatch(allowlist,/'status'|'state'|'is_archived'/);
});

test('the tracker keeps a reference, never a stored file',()=>{
  const tables=migration.slice(migration.indexOf('CREATE TABLE private_isg.document_obligations'),
    migration.indexOf('CREATE TABLE private_isg.document_tracking_receipts'));
  for(const column of ['asset_id','storage_path','file_sha256','derivative_id'])
    assert.ok(!tables.includes(column),column);
  // Both answers say so out loud rather than leaving it to be assumed.
  assert.match(migration,/'file_stored',false/);
  assert.match(migration,/'file_storage_available',false/);
  const allowlist=migration.slice(migration.indexOf('allowed:=CASE p_action'),migration.indexOf('IF allowed IS NULL'));
  assert.doesNotMatch(allowlist,/'asset_id'|'storage_path'/);
});

test('the product never asserts a legal duty of its own',()=>{
  assert.match(migration,/basis text NOT NULL DEFAULT 'expert' CHECK\(basis IN \('expert','legal'\)\)/);
  assert.match(migration,/CHECK\(basis<>'legal' OR \(legal_ref IS NOT NULL AND btrim\(legal_ref\)<>''\)\)/);
});

test('the list is a tally and carries no compliance verdict',()=>{
  assert.match(migration,/'compliance_verdict',NULL/);
  // Nothing anywhere computes a ratio or a score out of the counts.
  assert.doesNotMatch(migration,/compliance_(score|ratio|percent)|uygunluk/i);
});

test('every write is idempotent and every read is owner checked',()=>{
  assert.match(migration,/PRIMARY KEY\(actor_id,mutation_id\)/);
  assert.match(migration,/IF prior\.request_hash IS DISTINCT FROM fingerprint THEN\s*\n\s*RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'/);
  assert.match(migration,/UNIQUE\(obligation_id,mutation_id\)/);
  // Both checked entries run the same session, plan and ownership check first.
  for(const entry of ['read_document_tracking','mutate_document_tracking'])
    assert.match(migration,new RegExp(`CREATE FUNCTION private_isg\\.${entry}[\\s\\S]{0,900}?private_isg\\.require_document_tracking_company`),entry);
  assert.match(migration,/IF expected IS NULL OR obligation\.version<>expected THEN\s*\n\s*RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'/);
});

test('the probe hand-computes its dates instead of asking the server twice',()=>{
  assert.match(probe,/const NOTICE_DAYS=30,DUE_SOON_IN=10,EXPIRED_BY=1,STILL_VALID_IN=200;/);
  assert.match(probe,/const DRILL_VALIDITY_DAYS=365;/);
  // The expected end date is built in the probe, not read back from the row.
  assert.match(probe,/latest_valid_until===day\(anchor,DRILL_VALIDITY_DAYS\)/);
  assert.doesNotMatch(probe,/document_obligation_status\(/);
});

test('the runner wires the probe and fingerprints its sources',()=>{
  assert.match(runner,/import \{ beginDocumentTrackingProbe, documentTrackingFiles \} from '\.\/document_tracking_probe\.mjs';/);
  assert.match(runner,/\.concat\(mode\.synthetic \? documentTrackingFiles : \[\]\)/);
  assert.match(runner,/stage = 'document-tracking';/);
  // The newest migration is applied last, after the older slices have re-added
  // the rollout CHECK with their own feature lists.
  assert.ok(runner.indexOf("stage = 'document-tracking';")>runner.indexOf("stage = 'billing-lifecycle';"));
  assert.ok(runner.indexOf("stage = 'document-tracking';")<runner.indexOf("stage = 'integrated-rehearsal';"));
  assert.match(runner,/report\.document_tracking = documentTrackingProbe\.afterLogout\(\);/);
});

test('the switch answers the rehearsal the same way every other feature does',()=>{
  assert.match(migration,/CREATE FUNCTION private_isg\.document_tracking_gate\(p_write boolean\) RETURNS void/);
  assert.match(migration,/PERFORM private_isg\.document_tracking_gate\(p_write\);/);
  const rehearsal=readFileSync(resolve(ROOT,'scripts/isg/integrated_rehearsal_probe.mjs'),'utf8');
  assert.match(rehearsal,/'document_tracking'\];/);
  assert.match(rehearsal,/private_isg\.document_tracking_gate\(true\)/);
  assert.match(rehearsal,/refusals\.length===17/);
  assert.match(rehearsal,/count\(\*\)=18 AND bool_and\(NOT read_enabled AND NOT write_enabled\)/);
  // The two checked entries are definers, and the rehearsal knows them by name.
  assert.match(rehearsal,/'read_document_tracking','mutate_document_tracking',/);
  const definers=[...migration.matchAll(/CREATE FUNCTION private_isg\.([a-z_]+)\([^)]*\)[\s\S]{0,200}?SECURITY DEFINER/g)].map(m=>m[1]);
  assert.deepEqual(definers.sort(),['mutate_document_tracking','read_document_tracking']);
});

test('the portfolio is one aggregate, not one read per company',()=>{
  // The plan forbids sweeping thirty companies on every open, so the tally,
  // the per-company summary and the page all come from one CTE.
  assert.doesNotMatch(portfolio,/CREATE TEMP TABLE|FOR .* IN SELECT .* LOOP/);
  assert.match(portfolio,/WITH scope AS \(/);
  assert.match(portfolio,/\), page AS \(/);
  assert.match(portfolio,/\), filtered AS \(/);
  assert.match(portfolio,/INTO tally_all,tally_companies,tally_kinds,matching_rows,tally_rows;/);
  // The headline counts every tracked row, before any filter is applied.
  assert.match(portfolio,/FROM \(SELECT state,count\(\*\) AS total FROM page GROUP BY state\) tally/);
  // The page is bounded by the server, whatever the client asks for.
  assert.match(portfolio,/page_limit:=least\(greatest\(coalesce\(p_limit,10\),1\),100\);/);
  // It ships closed and adds no table grant of its own.
  assert.doesNotMatch(portfolio,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(portfolio,/GRANT (SELECT|INSERT|UPDATE|DELETE|ALL) ON/);
  assert.match(portfolio,/PERFORM private_isg\.document_tracking_gate\(false\);/);
  assert.match(portfolio,/'compliance_verdict',NULL,'file_storage_available',false/);
});

test('the new tables are on the advisor deny list and in the schema counts',()=>{
  const advisor=readFileSync(resolve(ROOT,'scripts/isg/personnel_advisor_probe.mjs'),'utf8');
  for(const table of ['document_obligation_kinds','document_obligations',
    'document_obligation_records','document_tracking_receipts'])
    assert.ok(advisor.includes(`'${table}'`),table);
  assert.match(readFileSync(resolve(ROOT,'scripts/isg/p05_upgrade_probe.mjs'),'utf8'),/count\(\*\)=163/);
  assert.match(readFileSync(resolve(ROOT,'scripts/isg/integrated_rehearsal_probe.mjs'),'utf8'),/posture\[0\]==='160'/);
});
