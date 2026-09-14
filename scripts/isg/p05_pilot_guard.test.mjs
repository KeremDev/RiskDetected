import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {ROOT} from './lib.mjs';
import {p05PilotFiles,beginP05PilotProbe} from './p05_pilot_probe.mjs';
import {p05UpgradeFiles} from './p05_upgrade_probe.mjs';
const read=p=>readFileSync(`${ROOT}/${p}`,'utf8');
const migration=read(p05PilotFiles[0]);

test('pilot probe refuses live or incomplete scope before SQL',async()=>{
  let touched=false;
  await assert.rejects(beginP05PilotProbe({synthetic:false,sql(){touched=true;}}),/SYNTHETIC_REQUIRED/);
  await assert.rejects(beginP05PilotProbe({synthetic:true,sql(){touched=true;}}),/SCOPE_REQUIRED/);
  assert.equal(touched,false);
});
test('pilot roster has strict UUID pairs, bounded TTL, RLS and no client grants',()=>{
  assert.match(migration,/PRIMARY KEY\(actor_id,company_id\)/);
  assert.match(migration,/expires_at<=created_at\+interval '30 days'/);
  assert.match(migration,/ALTER TABLE private_isg.p05_pilot_grants ENABLE ROW LEVEL SECURITY/);
  assert.doesNotMatch(migration,/INSERT INTO private_isg.p05_pilot_grants/);
  assert.doesNotMatch(migration,/GRANT (SELECT|INSERT|UPDATE|DELETE|ALL)/);
});
test('authorization uses server roster and current ownership, never a client flag',()=>{
  assert.match(migration,/c.id=g.company_id AND c.user_id=p_actor/);
  assert.match(migration,/g.revoked_at IS NULL AND g.expires_at>clock_timestamp\(\)/);
  assert.match(migration,/FOR SHARE OF r,g,c/);
  assert.doesNotMatch(migration,/auth.jwt\(\)|user_metadata|current_setting\(/);
  assert.match(migration,/actor uuid:=private_isg.active_actor\(\)/);
});
test('pilot writes stay denied even when generic write flag is enabled',()=>{
  assert.match(migration,/IF p_write THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'/);
  assert.match(migration,/'can_write',false/);
  assert.match(migration,/SET read_enabled=false,write_enabled=false WHERE feature='personnel'/);
});
test('all six P05 private entrypoints use shared checked authority',()=>{
  const first=read('supabase/migrations/20260913074153_isg_personnel_owner_rpc.sql');
  const directory=read('supabase/migrations/20260913081536_isg_workplace_context_assignments.sql');
  for(const [source,name] of [[first,'read_personnel'],[first,'mutate_personnel'],[directory,'directory_read'],[directory,'directory_mutate'],[directory,'context_at']]) {
    const body=source.split(`CREATE FUNCTION private_isg.${name}(`)[1]?.split('END $$;')[0];
    assert.ok(body?.includes('private_isg.require_company('),name);
  }
  assert.match(migration,/can_read:=private_isg.p05_pilot_can_read\(actor,p_company\)/);
});
test('pilot is fingerprinted, tested after native regression, and included in upgrade',()=>{
  const runner=read('scripts/isg/run_auth_restore.mjs');
  assert.match(runner,/concat\(mode.synthetic \? p05PilotFiles : \[\]\)/);
  assert.ok(runner.indexOf("stage='p05-readonly-pilot'")>runner.indexOf('report.native_e2e=await nativeE2EBridge'));
  assert.ok(p05UpgradeFiles.includes(p05PilotFiles[0]));
});
