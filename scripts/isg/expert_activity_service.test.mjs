import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

const source=readFileSync(resolve(ROOT,'App/Services/ISG/ExpertActivityService.swift'),'utf8');
const code=source.split('\n').filter(line=>!/^\s*\/\//.test(line)).join('\n');

test('activity reads are session-bound, bounded and cancelled before decoding',()=>{
  for(const method of ['page','detail']){
    const start=source.indexOf(`static func ${method}(`);
    const next=source.indexOf('\n    static func ',start+1);
    const block=source.slice(start,next<0?source.length:next);
    assert.match(block,/let identity = novaCurrentSessionIdentity\(\)/,method);
    assert.match(block,/guard identity != nil/,method);
    assert.match(block,/try Task\.checkCancellation\(\)/,method);
    assert.match(block,/identity == novaCurrentSessionIdentity\(\)/,method);
  }
  assert.match(source,/data\.count < 2_000_000/);
  assert.match(source,/page\.items\.count <= 30/);
  assert.match(source,/data\.count < 100_000/);
});

test('workspace activity selects only the scoped RPC and never reads tables directly',()=>{
  assert.match(source,/query\.p_workspace == nil \? "isg_activity_self_v1" : "isg_workspace_member_activity_v1"/);
  assert.match(source,/"isg_activity_event_detail_v1"/);
  assert.doesNotMatch(source,/\.from\(|service_role|anonKey/);
});

test('presence is current-session only and deliberately has no offline replay queue',()=>{
  assert.match(source,/guard NetworkMonitor\.shared\.isOnline, let current = novaCurrentSessionIdentity\(\)/);
  assert.match(source,/guard NetworkMonitor\.shared\.isOnline, novaCurrentSessionIdentity\(\) == identity/);
  assert.match(source,/loop\?\.cancel\(\)/);
  assert.match(source,/pendingStop/);
  assert.match(source,/Offline intervals are discarded/);
  assert.doesNotMatch(code,/UserDefaults|offlineQueue|enqueue|replay/);
});
