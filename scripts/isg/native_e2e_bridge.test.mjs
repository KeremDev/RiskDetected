import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync,existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {nativeE2EBridge} from './native_e2e_bridge.mjs';
import {parseRestoreMode} from './restore_mode.mjs';
import {verifyNativeDirectory} from './native_e2e_oracle.mjs';

test('native database oracle rejects a missing directory invariant',()=>{
  const company='11111111-1111-4111-8111-111111111111';
  const expected={catalogs:true,engagement:true,contexts:true,context_values:true,assignments:true,snapshots:true,employer:true};
  assert.equal(verifyNativeDirectory(()=>JSON.stringify(expected),company,'ios').ok,true);
  for(const key of Object.keys(expected))assert.equal(verifyNativeDirectory(()=>JSON.stringify({...expected,[key]:false}),company,'android').ok,false);
  assert.throws(()=>verifyNativeDirectory(()=>{throw Error('SQL must not run')},"' OR true",'ios'),/ORACLE_SCOPE/);
  assert.throws(()=>verifyNativeDirectory(()=>{throw Error('SQL must not run')},company,'other'),/ORACLE_SCOPE/);
});

test('native acceptance requires the exact synthetic-only invocation',async()=>{
  assert.deepEqual(parseRestoreMode(['--synthetic-session','--native-e2e']),{storage:false,sessionGuard:true,synthetic:true,nativeE2E:true});
  for(const args of [['--native-e2e'],['--isolated-copy','--native-e2e'],['--synthetic-session','--native-e2e','--with-storage'],['--native-e2e','--synthetic-session']])assert.throws(()=>parseRestoreMode(args));
  await assert.rejects(nativeE2EBridge({synthetic:false}),/SYNTHETIC_REQUIRED/);
});
test('loopback native broker rejects browser/admin/table access and never forwards its fixture key as a JWT',async()=>{
  const target=mkdtempSync(join(tmpdir(),'isg-native-bridge-test-'));
  let forwarded=0;
  const completion=nativeE2EBridge({synthetic:true,target,fixture:{synthetic:true},auth(){throw Error('No auth expected')},rest(path,args){forwarded++;assert.equal(path,'/rpc/isg_workspace_availability_v1');assert.equal(args.authorization,'session-test-token');return {status:200,body:{ok:true}}},control(){throw Error('No control expected')},verify(){return {ok:true}}});
  const path=join(target,'native-connection.json');
  for(let i=0;i<100&&!existsSync(path);i++)await new Promise(r=>setTimeout(r,5));
  const {url,keys}=JSON.parse(readFileSync(path));
  const call=(path,options={})=>fetch(url+path,{...options,headers:{apikey:keys.ios,...options.headers}});
  assert.equal((await call('/qa/bootstrap',{headers:{apikey:'wrong'}})).status,403);
  assert.equal((await call('/qa/bootstrap',{headers:{origin:'https://example.invalid'}})).status,403);
  for(const path of ['/auth/v1/admin/users','/auth/v1/logout','/rest/v1/employees','/rest/v1/rpc/private_rpc','/qa/sql','//example.invalid'])assert.equal((await call(path,{method:'POST'})).status,404);
  assert.equal(forwarded,0);
  assert.equal((await call('/rest/v1/rpc/isg_workspace_availability_v1',{method:'POST',headers:{authorization:'Bearer session-test-token'},body:'{}'})).status,200);
  assert.equal(forwarded,1);
  for(const key of Object.values(keys))assert.equal((await call('/qa/finish',{method:'POST',headers:{apikey:key},body:'{}'})).status,200);
  const result=await completion;assert.equal(result.loopback_only,true);assert.equal(result.requests.ios,1);
});
