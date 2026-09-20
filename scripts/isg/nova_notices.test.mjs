import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

const read=path=>readFileSync(resolve(ROOT,path),'utf8');
const models=read('App/DesignSystem/ISG/NovaNotices.swift');
const screen=read('App/DesignSystem/ISG/NovaNoticeCenterScreen.swift');
const shell=read('App/DesignSystem/ISG/NovaExpertShell.swift');
const service=read('App/Services/Company/NovaNoticeService.swift');
const adapter=read('App/Services/Company/NovaNoticeLiveAdapter.swift');
const gate=read('App/Views/Components/NovaPilotNoticeGate.swift');
const main=read('App/Views/Components/NovaPilotMainGate.swift');
const catalogue=JSON.parse(read('App/Localization/Localizable.xcstrings')).strings;

test('the design layer never imports the SDK',()=>{
  for(const source of [models,screen,shell]) assert.doesNotMatch(source,/^import Supabase$/m);
  assert.match(adapter,/^import Supabase$/m);
});

test('the bell is reachable and carries the count',()=>{
  // The destination must be available, or the button stays disabled.
  assert.match(main,/NovaWorkspaceRole\.personnel\.destinations/);
  assert.match(main,/NovaWorkspaceRole\.osgbExpert\.destinations/);
  assert.match(main,/case \.notifications:/);
  assert.match(main,/hasUnread: notices\.unread > 0, unreadCount: notices\.unread/);
  assert.match(shell,/unreadCount > 99 \? "99\+" : String\(unreadCount\)/);
  // The badge is decoration; the label already says it.
  assert.match(shell,/notifications\.with\.new/);
});

test('the panel can read, delete and undo one notice',()=>{
  for(const action of ['read','dismiss','restore'])
    assert.match(shell,new RegExp(`"nova\\.notice\\.${action}\\.`),`the panel has no ${action} control`);
  assert.match(shell,/onReadNotice\?\(notice\.id\)/);
  assert.match(shell,/onDismissNotice\?\(notice\.id\)/);
  assert.match(shell,/onRestoreNotice\?\(notice\.id\)/);
  assert.match(main,/onReadNotice: \{ key in/);
  assert.match(main,/onDismissNotice: \{ key in/);
  assert.match(main,/onRestoreNotice: \{ key in/);
});

test('tapping a notice opens the record it came from',()=>{
  assert.match(shell,/send\(\.navigate\(notice\.destination\)\)/);
  assert.match(shell,/\.disabled\(!canOpen\(notice\.destination\)\)/);
  assert.match(screen,/onOpen\(entry\.destination\)/);
  // The destination is the server's word, decoded, never guessed from the kind.
  assert.match(service,/NovaDestination\(rawValue: row\.destination\)/);
});

test('the centre states what this list is and is not',()=>{
  assert.match(screen,/NovaNoticeWords\.noPushNote/);
  assert.match(screen,/NovaNoticeWords\.dismissNote/);
  assert.match(main,/noticeNote: notices\.rows\.isEmpty \? "" : NovaNoticeWords\.dismissNote/);
});

test('a mark is never applied locally',()=>{
  // Every write asks the server again rather than editing the list in place.
  assert.match(main,/private func markNotices[\s\S]*?noticeRevision = UUID\(\)/);
  assert.doesNotMatch(main,/notices\.rows\.remove/);
  assert.match(screen,/if reload \{ await load\(\) \}/);
  assert.doesNotMatch(screen,/feed\.rows\.removeAll/);
});

test('every kind and scope the client knows has copy in the catalogue',()=>{
  const keys=[...models.matchAll(/"(localizable\.nova\.notice\.[a-z.]+)"/g)].map(m=>m[1]);
  assert.ok(keys.length>=20);
  for(const key of new Set(keys)){
    assert.ok(catalogue[key],`${key} missing from the catalogue`);
    for(const language of ['tr','en'])
      assert.ok(catalogue[key].localizations?.[language]?.stringUnit?.value,`${key} has no ${language}`);
  }
});

test('the gate hands the screen closures and nothing else',()=>{
  assert.match(gate,/NovaNoticeCenterScreen\(client: client, onOpen: onOpen, onBack: onBack\)/);
  for(const call of ['feed:','read:','readAll:','dismiss:','dismissAll:','restore:'])
    assert.match(gate,new RegExp(call.replace(':','\\:')));
});
