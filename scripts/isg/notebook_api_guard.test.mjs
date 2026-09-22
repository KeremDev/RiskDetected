import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { beginNotebookAPIProbe, notebookAPIFiles } from './notebook_api_probe.mjs';
import { p05UpgradeFiles } from './p05_upgrade_probe.mjs';
test('notebook API probe refuses unsafe mode before SQL or HTTP',async()=>{
  await assert.rejects(beginNotebookAPIProbe({synthetic:false,sql:()=>assert.fail('SQL'),request:()=>assert.fail('HTTP')}),/SYNTHETIC_REQUIRED/);
});
test('notebook authenticated boundary has no company or paid-plan dependency',()=>{
  const sql=readFileSync(notebookAPIFiles[0],'utf8');
  assert.doesNotMatch(sql,/require_company|user_plan_tier|user_subscriptions|company_id|entity_id/);
  for(const required of ['active_actor()','notes_gate(true)','notes_gate(false)','IDEMPOTENCY_CONFLICT','NOTE_TOMBSTONED','VERSION_CONFLICT','LIMIT 21','full_scan_restart','ENABLE ROW LEVEL SECURITY'])assert.ok(sql.includes(required));
  assert.ok(p05UpgradeFiles.includes(notebookAPIFiles[0]));
});
test('organization API preserves owner, version, immutable retry and bounded payload guards',()=>{
  const sql=readFileSync(notebookAPIFiles[2],'utf8');
  for(const expected of ['active_actor()','notes_gate(true)','notes_gate(false)','IDEMPOTENCY_CONFLICT','VERSION_CONFLICT','NOTE_TOMBSTONED','jsonb_array_length(p_items)>500','jsonb_array_length(p_tags)>30','FOR UPDATE','FOR SHARE','entry.owner_id<>actor']) assert.ok(sql.includes(expected),expected);
  assert.doesNotMatch(sql,/company_id|employee_id|entity_id|user_plan_tier|user_subscriptions/);
  assert.ok(p05UpgradeFiles.includes(notebookAPIFiles[2]));
  const migrations=p05UpgradeFiles.filter(p=>p.endsWith('.sql'));
  assert.deepEqual(migrations,[...migrations].sort());
});
test('native notebook entry uses fail-closed server rollout and never a paid capability gate',()=>{
  const swift=readFileSync('App/Views/Components/NotebookDestination.swift','utf8');
  const kotlin=readFileSync('android/feature/profile/src/main/kotlin/com/riskdetectedan/feature/profile/NotebookScreen.kt','utf8');
  assert.match(swift,/isg_notebook_rollout_v1/);
  assert.match(swift,/identity == novaCurrentSessionIdentity\(\)/);
  assert.doesNotMatch(swift,/static let enabled = false/);
  for(const source of [swift,kotlin]) {
    assert.match(source,/enabled = false/);
    assert.doesNotMatch(source,/isPaid|currentTier|company_id|Analytics|Logger|println\(/);
    assert.match(source,/Kaydetmeden çık/);
    assert.match(source,/İki sürümü incele/);
  }
});
test('native notebook presents one shared notes library and paper editor flow',()=>{
  const swift=readFileSync('App/Views/Components/NotebookDestination.swift','utf8');
  for(const expected of [
    'private enum LibrarySection',
    'case notes, reminders, drafts',
    'LazyVStack',
    'notebook.search',
    'square.and.pencil',
    'notebook.title',
    'notebook.body',
    'scrollDismissesKeyboard(.interactively)',
    'Bu hatırlatıcı seçili nota bağlanacak'
  ]) assert.ok(swift.includes(expected),expected);
  assert.equal((swift.match(/struct NotebookDestination: View/g)??[]).length,1);
});
