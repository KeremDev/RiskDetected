import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { verifyLocalSessionToken } from './auth_session_probe.mjs';
import { parseRestoreMode } from './restore_mode.mjs';

const secret = 'local-test-secret-'.repeat(4);
const claims = () => ({ iss:'http://127.0.0.1:9999/auth/v1',aud:'authenticated',role:'authenticated',
  sub:'00000000-0000-4000-8000-000000000001',session_id:'00000000-0000-4000-8000-000000000002',iat:1000,exp:2000 });
function token(payload = claims(), header = {alg:'HS256',typ:'JWT'}, key = secret) {
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const data = `${encode(header)}.${encode(payload)}`;
  return `${data}.${createHmac('sha256',key).update(data).digest('base64url')}`;
}
test('local proof verifies exact GoTrue test issuer, audience, signature and live expiry', () => {
  assert.deepEqual(verifyLocalSessionToken(token(),secret,1500),claims());
});
for (const [id,payload] of [
  ['wrong issuer',{iss:'https://production.example/auth/v1'}],['wrong audience',{aud:'service_role'}],
  ['audience array',{aud:['authenticated']}],['wrong role',{role:'service_role'}],
  ['missing session',{session_id:undefined}],['malformed session',{session_id:'invalid'}],
  ['missing subject',{sub:undefined}],['invalid subject',{sub:'invalid'}],
  ['expired',{exp:1499}],['expiry boundary',{exp:1500}],['string expiry',{exp:'2000'}],
  ['future issued-at',{iat:1501}],['missing issued-at',{iat:undefined}],
  ['future not-before',{nbf:1501}],['string not-before',{nbf:'1499'}],
]) test(`local JWT proof rejects ${id}`, () => {
  assert.throws(() => verifyLocalSessionToken(token({...claims(),...payload}),secret,1500),/AUTH_RESTORE_LOCAL_TOKEN_INVALID/);
});
test('local proof rejects wrong signing key, algorithm confusion, truncation and malformed inputs', () => {
  for (const value of [token(claims(),{alg:'none',typ:'JWT'}),token(claims(),{alg:'HS512',typ:'JWT'}),
    token(claims(),{alg:'HS256',typ:'not-JWT'}),token(claims(),{alg:'HS256',typ:'JWT',crit:['unknown']}),
    token(claims(),{alg:'HS256',typ:'JWT',b64:false}),token(claims(),undefined,'wrong-key'),token().slice(0,-8),'a.b.c','',null,'x'.repeat(16385)]) {
    assert.throws(() => verifyLocalSessionToken(value,secret,1500),/AUTH_RESTORE_LOCAL_TOKEN_INVALID/);
  }
  for (const now of [NaN,Infinity,-1,1500.5,'1500']) assert.throws(()=>verifyLocalSessionToken(token(),secret,now),/AUTH_RESTORE_LOCAL_TOKEN_INVALID/);
});
test('restore flags accept only explicit independent opt-ins', () => {
  assert.deepEqual(parseRestoreMode(['--isolated-copy']),{storage:false,sessionGuard:false});
  assert.deepEqual(parseRestoreMode(['--isolated-copy','--with-storage']),{storage:true,sessionGuard:false});
  assert.deepEqual(parseRestoreMode(['--isolated-copy','--with-session-guard']),{storage:false,sessionGuard:true});
  for(const flags of [['--with-storage','--with-session-guard'],['--with-session-guard','--with-storage']]) {
    assert.deepEqual(parseRestoreMode(['--isolated-copy',...flags]),{storage:true,sessionGuard:true});
  }
  for(const args of [null,[],['--with-storage'],['--isolated-copy','--production'],
    ['--isolated-copy','--with-storage','--with-storage'],['--isolated-copy','--with-session-guard','--with-session-guard'],
    ['--isolated-copy','--with-storage','--with-session-guard','extra']]) {
    assert.throws(()=>parseRestoreMode(args),/AUTH_RESTORE_EXPLICIT_MODE_REQUIRED/);
  }
});
