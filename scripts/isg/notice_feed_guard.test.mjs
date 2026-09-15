import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

const read=path=>readFileSync(resolve(ROOT,path),'utf8');
const slice=read('supabase/migrations/20260915240000_isg_pilot_notice_feed.sql');
const checks=read('scripts/isg/notice_feed_check.sql');
const fixture=read('scripts/isg/notice_feed_fixture.sql');
const models=read('App/DesignSystem/ISG/NovaNotices.swift');
const service=read('App/Services/Company/NovaNoticeService.swift');
const adapter=read('App/Services/Company/NovaNoticeLiveAdapter.swift');
const shell=read('App/DesignSystem/ISG/NovaExpertShell.swift');
/** Comments explain the rule; they are not evidence that the rule is there. */
const code=source=>source.split('\n').filter(line=>!line.trimStart().startsWith('--')).join('\n');

test('the feed opens no switch and reads both of them',()=>{
  assert.doesNotMatch(slice,/UPDATE private_isg\.rollout SET/);
  assert.doesNotMatch(slice,/INSERT INTO private_isg\.rollout/);
  assert.doesNotMatch(slice,/UPDATE private_isg\.module_registry SET/);
  assert.match(code(slice),/FROM private_isg\.rollout WHERE feature='modules'/);
  assert.match(code(slice),/FROM private_isg\.module_registry m WHERE m\.module=/);
  assert.match(checks,/a closed module drops its own notices/);
  assert.match(checks,/the module switch drops every module kind/);
});

test('no notice text, severity or date is stored',()=>{
  // The only table this slice creates holds marks, and marks hold no prose.
  const tables=code(slice).match(/CREATE TABLE IF NOT EXISTS private_isg\.[a-z_]+/g)??[];
  assert.deepEqual(tables,['CREATE TABLE IF NOT EXISTS private_isg.notice_marks']);
  const marks=code(slice).slice(code(slice).indexOf('CREATE TABLE IF NOT EXISTS private_isg.notice_marks'));
  const body=marks.slice(0,marks.indexOf(');'));
  for(const column of ['title','body','message','severity','due_on','kind'])
    assert.doesNotMatch(body,new RegExp(`\\b${column}\\b`),`notice_marks must not store ${column}`);
  assert.match(body,/read_at timestamptz/);
  assert.match(body,/dismissed_at timestamptz/);
});

test('the feed never claims a push was sent, delivered or read',()=>{
  // It reads no delivery table at all.
  for(const table of ['delivery_attempts','notification_jobs','notification_episodes','notification_consents'])
    assert.doesNotMatch(code(slice),new RegExp(table),`the feed must not read ${table}`);
  assert.match(code(slice),/'push_delivery_claimed',false/);
  // Both answers carry it, not just the read.
  assert.equal((code(slice).match(/'push_delivery_claimed',false/g)??[]).length,2);
  assert.match(checks,/the feed claims no push delivery/);
  assert.match(checks,/and marking one read claims none either/);
  assert.match(models,/pushDeliveryClaimed/);
});

test('deleting a notice deletes no record',()=>{
  // The only DELETE targets the marks table.
  const deletes=code(slice).match(/DELETE FROM private_isg\.[a-z_]+/g)??[];
  assert.deepEqual([...new Set(deletes)],['DELETE FROM private_isg.notice_marks']);
  assert.doesNotMatch(code(slice),/UPDATE private_isg\.(katip_contracts|appointments|drill_records|board_meetings|document_obligations|equipment_items|risk_assessments)/);
  assert.match(code(slice),/'dismiss_is_permanent',false/);
  assert.match(checks,/the record itself is untouched/);
  assert.match(checks,/a moved date is a new situation/);
  assert.match(checks,/marking changes no record/);
});

test('an integer column in a text position is cast, not left to break UNION',()=>{
  // board_decisions.decision_no is integer on the live schema; a bare column
  // here breaks the UNION ALL with every other kind's text title.
  assert.match(code(slice),/t\.decision_no::text/);
});

test('the window is asked of the module that owns it',()=>{
  // A second copy of a number the module already owns could silently disagree.
  for(const fn of ['risk_notice_days','emergency_notice_days','drill_notice_days','equipment_notice_days'])
    assert.match(code(slice),new RegExp(`private_isg\\.${fn}\\(\\)`),`the window must ask ${fn}`);
  assert.match(checks,/a risk record 50 days out is inside the 60 day window/);
  assert.match(checks,/a drill 20 days out is outside the 14 day window/);
  // Evrak keeps the window written on its own obligation row.
  assert.doesNotMatch(code(slice),/WHEN 'document' THEN/);
  assert.match(code(slice),/o\.notice_days/);
});

test('the key carries the situation, so a moved date is a new notice',()=>{
  assert.match(code(slice),/r\.kind\|\|':'\|\|r\.record_id::text\|\|':'\|\|coalesce\(r\.due_on::text,'none'\)/);
  assert.match(checks,/the mark on the situation that is gone is pruned/);
});

test('no date is invented',()=>{
  // Every source demands its own date before it can raise anything.
  for(const clause of ['t\\.ends_before IS NOT NULL','t\\.valid_until IS NOT NULL',
    't\\.planned_on IS NOT NULL','t\\.due_on IS NOT NULL','i\\.next_due_on IS NOT NULL',
    'd\\.valid_until IS NOT NULL'])
    assert.match(code(slice),new RegExp(clause));
  assert.match(checks,/an open ended contract is not a notice/);
  assert.match(checks,/only the plan that carries a date is a notice/);
});

test('another account is unreachable and the pilot gate is on both calls',()=>{
  assert.match(code(slice),/c\.user_id=p_actor/);
  assert.match(code(slice),/private_isg\.p05_pilot_can_read\(p_actor,c\.id\)/);
  assert.equal((code(slice).match(/p05_pilot_account_enabled\(actor,(false|true)\)/g)??[]).length,2);
  assert.match(checks,/another company is never in the feed/);
  assert.match(checks,/an ungranted company is refused by name/);
  assert.match(checks,/an account outside the pilot can not read the feed/);
});

test('only the two wrappers reach a client',()=>{
  assert.match(code(slice),/GRANT EXECUTE ON FUNCTION[\s\S]*?public\.isg_pilot_notice_feed_v1\(uuid,text,integer\),public\.isg_pilot_notice_mark_v1\(text,text\[\]\)\s*\n?\s*TO authenticated;/);
  assert.doesNotMatch(code(slice),/GRANT[^;]*ON TABLE/);
  assert.match(checks,/the row builders are not callable by a client/);
  assert.match(checks,/exactly the two public wrappers are callable/);
});

test('the bulk actions take no list',()=>{
  assert.match(code(slice),/RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'/);
  assert.match(checks,/the bulk action takes no list/);
  // The client keeps the same rule rather than sending an empty array.
  assert.match(service,/if let keys \{ payload\["p_keys"\] = \.array/);
  assert.match(service,/action: "read_all", keys: nil/);
  assert.match(service,/action: "dismiss_all", keys: nil/);
});

test('the client says what the server says, and no more',()=>{
  // An unknown kind or destination is dropped rather than renamed.
  assert.match(service,/guard let kind = NovaNoticeKind\(rawValue: row\.kind\),[\s\S]*?else \{ return nil \}/);
  assert.match(service,/compactMap\(entry\)/);
  // Every refusal the server can raise has a word here.
  for(const code_ of ['ACCESS_DENIED','FEATURE_UNAVAILABLE','NOTICE_NOT_FOUND','VALIDATION_ERROR','PAYLOAD_NOT_ALLOWED'])
    assert.match(adapter,new RegExp(`"${code_}"`));
  assert.match(models,/noPushNote/);
  assert.match(models,/dismissNote/);
});

test('the bell shows unread without inventing it',()=>{
  assert.match(shell,/var unreadCount = 0/);
  assert.match(shell,/onReadNotice: \(\(String\) -> Void\)\?/);
  assert.match(shell,/onDismissNotice: \(\(String\) -> Void\)\?/);
  assert.match(shell,/onRestoreNotice: \(\(String\) -> Void\)\?/);
  // Opening a notice is reading it.
  assert.match(shell,/onReadNotice\?\(notice\.id\)\n\s*send\(\.navigate\(notice\.destination\)\)/);
});

test('the fixture is the live shape and is disposable only',()=>{
  assert.match(fixture,/Run only in a fresh, disposable local database/);
  // The live tables carry is_deleted; the dev chain's earlier shape did not.
  assert.match(fixture,/is_deleted boolean NOT NULL DEFAULT false/);
  // The fixture stands in for what exists before the slice; the slice itself
  // creates the marks table, so a fixture copy would hide a broken migration.
  assert.doesNotMatch(fixture,/notice_marks/);
  assert.doesNotMatch(fixture,/isg_pilot_notice/);
});
