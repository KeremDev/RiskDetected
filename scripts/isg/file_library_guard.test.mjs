import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {beginFileLibraryProbe,fileLibraryFiles} from './file_library_probe.mjs';

const migration=readFileSync(resolve(ROOT,fileLibraryFiles[0]),'utf8');
const probe=readFileSync(resolve(ROOT,fileLibraryFiles[1]),'utf8');
const runner=readFileSync(resolve(ROOT,'scripts/isg/run_auth_restore.mjs'),'utf8');
const worker=readFileSync(resolve(ROOT,'supabase/functions/isg-file-inspect/index.ts'),'utf8');
const inspector=readFileSync(resolve(ROOT,'supabase/functions/_shared/isg/file-format-inspector.ts'),'utf8');
const core=readFileSync(resolve(ROOT,'supabase/migrations/20260913130000_isg_file_core.sql'),'utf8');
/** Comments explain the rule; they are not evidence that the rule is there. */
const code=source=>source.split('\n').filter(line=>!line.trimStart().startsWith('--')).join('\n');

test('the probe refuses any other mode before touching SQL',async()=>{
  let touched=false;
  await assert.rejects(beginFileLibraryProbe({synthetic:false,sql(){touched=true;}}),/SYNTHETIC_REQUIRED/);
  await assert.rejects(beginFileLibraryProbe({synthetic:true,sql(){touched=true;}}),/SCOPE_REQUIRED/);
  assert.equal(touched,false);
});

test('the slice ships without opening the switch and without a table grant',()=>{
  assert.doesNotMatch(migration,/UPDATE private_isg\.rollout SET/);
  assert.match(migration,/INSERT INTO private_isg\.rollout\(feature\) VALUES\('file_library'\);/);
  assert.match(migration,/REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;/);
  const created=[...migration.matchAll(/CREATE TABLE private_isg\.([a-z_]+)/g)].map(m=>m[1]);
  const secured=new Set([...migration.matchAll(/ALTER TABLE private_isg\.([a-z_]+) ENABLE ROW LEVEL SECURITY/g)].map(m=>m[1]));
  assert.deepEqual(created,['file_scanners','file_library_categories','file_library_entries','file_library_receipts']);
  for(const table of created) assert.ok(secured.has(table),table);
});

test('only the two client entries and their wrappers reach a signed-in account',()=>{
  const granted=migration.slice(migration.indexOf('GRANT EXECUTE ON FUNCTION'));
  const toAuthenticated=granted.slice(0,granted.indexOf('TO authenticated;'));
  assert.match(toAuthenticated,/private_isg\.read_file_library/);
  assert.match(toAuthenticated,/private_isg\.mutate_file_library/);
  assert.doesNotMatch(toAuthenticated,/inspect_file_upload|file_library_gate|require_file_library_company|file_library_entry_row|file_library_purpose/);
});

test('the inspection entry is reachable by the worker identity and nobody else',()=>{
  const workerGrant=migration.slice(migration.indexOf('TO service_role;')-400,migration.indexOf('TO service_role;'));
  assert.match(workerGrant,/inspect_file_upload/);
  assert.doesNotMatch(workerGrant,/read_file_library|mutate_file_library/);
  // It takes no actor argument at all, so holding the grant is not an identity.
  assert.match(code(migration),/CREATE FUNCTION private_isg\.inspect_file_upload\(p_intent uuid,p_stage text,p_payload jsonb\)/);
  assert.doesNotMatch(code(migration),/inspect_file_upload\([^)]*p_actor/);
});

test('no client action can declare a verdict or name an asset',()=>{
  const allowlist=migration.slice(migration.indexOf("allowed:=CASE p_action"),migration.indexOf("ELSE NULL END;"));
  assert.match(allowlist,/'open_upload'/);
  assert.match(allowlist,/'rename_entry'/);
  assert.match(allowlist,/'archive_entry'/);
  assert.match(allowlist,/'cancel_upload'/);
  // The words a verdict would arrive under are not in any payload allowlist.
  // 'sha256' is there and belongs there: it is what the client announces it is
  // about to upload, and the state machine re-computes it before believing it.
  for(const forbidden of ['verdict','scanner','asset_id','state','download_path','scan_version']){
    assert.doesNotMatch(allowlist,new RegExp(`'${forbidden}'`),forbidden);
  }
  assert.match(allowlist,/'sha256'/);
});

test('the purpose is decided by the server, never sent by the client',()=>{
  assert.match(code(migration),/purpose:=private_isg\.file_library_purpose\(extension\);/);
  const allowlist=migration.slice(migration.indexOf("allowed:=CASE p_action"),migration.indexOf("ELSE NULL END;"));
  assert.doesNotMatch(allowlist,/'purpose'/);
});

test('a path is emitted only when an asset exists',()=>{
  const row=migration.slice(migration.indexOf('CREATE FUNCTION private_isg.file_library_entry_row'),
    migration.indexOf('CREATE FUNCTION private_isg.read_file_library'));
  assert.match(code(row),/'download_bucket',asset\.bucket,'download_path',asset\.immutable_path,/);
  // The upload path is offered only while the upload has not started.
  assert.match(code(row),/'upload_path',CASE WHEN intent\.state='pending' THEN intent\.quarantine_path END/);
  // The state is worked out at read time; no column stores it.
  assert.match(code(row),/'state_authority','computed_at_read'/);
  assert.equal(/CREATE TABLE private_isg\.file_library_entries[\s\S]*?\);/.exec(migration)[0]
    .split('\n').filter(line=>/^\s+(state|status)\s/.test(line)).length,0);
});

test('an unregistered scanner can never be reported as a malware scan',()=>{
  const row=migration.slice(migration.indexOf('CREATE FUNCTION private_isg.file_library_entry_row'),
    migration.indexOf('CREATE FUNCTION private_isg.read_file_library'));
  assert.match(code(row),/'malware_scanned',coalesce\(registry\.detects_malware,false\)/);
  // Only a registry row whose assurance is a malware scan may set that flag.
  assert.match(code(migration),/CHECK\(detects_malware=\(assurance='malware_scan'\)\)/);
  const seeded=migration.slice(migration.indexOf("INSERT INTO private_isg.file_scanners"),
    migration.indexOf("-- ---",migration.indexOf("INSERT INTO private_isg.file_scanners")));
  assert.match(seeded,/'isg_format_inspector','format_inspection',false/);
  assert.doesNotMatch(seeded,/'malware_scan'/);
});

test('the client is write-only into quarantine and read-only out of the archive',()=>{
  const policies=code(migration);
  assert.match(policies,/CREATE POLICY isg_quarantine_insert_own ON storage\.objects\s*\n\s*FOR INSERT TO authenticated/);
  assert.match(policies,/CREATE POLICY isg_documents_select_own ON storage\.objects\s*\n\s*FOR SELECT TO authenticated/);
  // Exactly two policies, and neither of them lets a client rewrite an object.
  assert.equal([...policies.matchAll(/CREATE POLICY/g)].length,2);
  assert.doesNotMatch(policies,/FOR (UPDATE|DELETE|ALL) TO authenticated/);
  // Both prefixes are pinned to the caller's own id, so knowing a path is not access.
  assert.equal([...policies.matchAll(/storage\.foldername\(name\)\)\[2\]=auth\.uid\(\)::text/g)].length,2);
});

test('the legacy storage paths and buckets are left alone',()=>{
  assert.doesNotMatch(code(migration),/\b(photos|reports|logos)\b/);
  assert.doesNotMatch(migration,/DROP POLICY|ALTER TABLE storage\.objects/);
  assert.match(probe,/the_legacy_storage_rows_and_policies_are_byte_identical_afterwards/);
  assert.match(probe,/the_eleven_legacy_storage_policies_are_still_there/);
  // The fingerprint carries its own row counts, so nothing can match over nothing.
  assert.match(probe,/\^11:3:\[a-f0-9\]\{32\}\$/);
});

test('the promoted object is content addressed and never overwritten',()=>{
  // The path formula lives in the P04 slice; this one must not have moved it.
  assert.match(code(core),/path:='assets\/'\|\|entry\.owner_id::text\|\|'\/'\|\|encode\(p_final_sha256,'hex'\)/);
  assert.doesNotMatch(migration,/CREATE OR REPLACE FUNCTION private_isg\.promote_clean_upload/);
  // A second filing of the same bytes links to the asset already there.
  assert.match(code(migration),/duplicate_of_existing_asset',true/);
  assert.match(worker,/upsert: false/);
});

test('the worker proves ownership with the caller token and uses the key only for bytes',()=>{
  // The entry is read with the caller's own JWT before anything else happens.
  assert.match(worker,/global: \{ headers: \{ Authorization: authorization \} \}/);
  assert.match(worker,/isg_file_library_read_v1/);
  const serviceUse=worker.slice(worker.indexOf('const worker = createClient'));
  assert.match(serviceUse,/isg_file_inspection_v1/);
  // The service client never carries a user id into the database.
  assert.doesNotMatch(serviceUse,/p_actor|p_owner|user\.id/);
});

test('the inspector says what it is and refuses what it cannot read',()=>{
  assert.match(inspector,/WHAT THIS IS NOT: antivirus/);
  assert.match(inspector,/malware_scanned: false/);
  // An encrypted or unreadable file is refused rather than cleared.
  assert.match(inspector,/return reject\("ENCRYPTED_FILE"/);
  assert.match(inspector,/return reject\("MALFORMED_FILE", "", \{ \.\.\.base \}\);\n  \}\n  if \(pixels > LIMITS\.imagePixels\)/);
  // Every code it can emit is a shape the database will accept.
  const codes=[...inspector.matchAll(/\| "([A-Z_]+)"/g)].map(m=>m[1]);
  assert.ok(codes.length>=10);
  for(const value of codes) assert.match(value,/^[A-Z][A-Z_]{2,39}$/);
});

test('the probe runs last and reports what it left closed',()=>{
  assert.match(runner,/stage = 'file-library';/);
  // Newest timestamp, so it has to follow every slice that re-adds the CHECK.
  assert.ok(runner.indexOf("stage = 'file-library';")>runner.indexOf("stage = 'document-tracking';"));
  assert.ok(runner.indexOf("stage = 'file-library';")<runner.indexOf("stage = 'integrated-rehearsal';"));
  assert.match(probe,/rollout_left_disabled:true/);
  assert.match(probe,/client_can_declare_a_verdict:false/);
  assert.match(probe,/malware_scanning_available:false/);
  assert.match(probe,/production_deployed:false/);
});

test('the probe asserts the honesty invariants it claims in its report',()=>{
  for(const name of ['a_closed_switch_refuses_both_directions',
    'the_inspection_entry_is_out_of_reach_of_a_signed_in_account',
    'no_client_action_can_declare_a_verdict',
    'bytes_that_are_not_the_bytes_announced_are_refused_not_scanned',
    'promoting_different_bytes_than_the_ones_inspected_is_refused',
    'an_inspection_that_could_not_finish_is_never_read_as_clean',
    'an_unregistered_scanner_is_never_reported_as_a_malware_scan',
    'filing_the_same_document_twice_links_to_one_object_instead_of_overwriting_it',
    'the_kill_switch_stops_the_library_and_the_inspector_together']){
    assert.match(probe,new RegExp(`mark\\('${name}'`),name);
  }
});
