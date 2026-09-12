import { createHash, createHmac, timingSafeEqual, randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { ROOT } from './lib.mjs';

// Local pinned GoTrue emits HS256 in this drill. Do not reuse this function as
// production JWT verification: live keys/issuer/JWKS/rotation differ.
export function verifyLocalSessionToken(token, secret, now = Math.floor(Date.now()/1000)) {
  const fail = (reason = 'FORMAT') => { throw new Error(`AUTH_RESTORE_LOCAL_TOKEN_INVALID_${reason}`); };
  if (typeof token !== 'string' || token.length > 16384 || typeof secret !== 'string' || secret.length < 32 ||
      !Number.isSafeInteger(now) || now < 0) fail();
  const parts = token.split('.');
  if (parts.length !== 3 || parts.some(p => !/^[A-Za-z0-9_-]+$/.test(p))) fail();
  const expected = createHmac('sha256',secret).update(parts.slice(0,2).join('.')).digest();
  const actual = Buffer.from(parts[2],'base64url');
  if (actual.length !== expected.length || !timingSafeEqual(actual,expected)) fail('SIGNATURE');
  let header, claims;
  try { header=JSON.parse(Buffer.from(parts[0],'base64url')); claims=JSON.parse(Buffer.from(parts[1],'base64url')); } catch { fail(); }
  const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
  if (header?.alg !== 'HS256' || header.typ !== 'JWT' || header.crit !== undefined || header.b64 !== undefined || !claims) fail('HEADER');
  if (claims.iss !== 'http://127.0.0.1:9999/auth/v1') fail('ISSUER');
  if (claims.aud !== 'authenticated' || claims.role !== 'authenticated') fail('AUDIENCE_ROLE');
  if (
      !uuid.test(claims.sub ?? '') || !uuid.test(claims.session_id ?? '') ||
      !Number.isSafeInteger(claims.exp) || claims.exp <= now ||
      !Number.isSafeInteger(claims.iat) || claims.iat > now ||
      (claims.nbf !== undefined && (!Number.isSafeInteger(claims.nbf) || claims.nbf > now))) fail('CLAIMS');
  return claims;
}

export async function beginSessionProbe({ sql, concurrentSql, token, secret, pass }) {
  const claims = verifyLocalSessionToken(token,secret);
  const fixture = readFileSync(resolve(ROOT,'scripts/isg/sql/auth_session_fixture.sql'),'utf8');
  sql(fixture);
  const quote = s => "'" + s.replaceAll("'","''") + "'";
  const check = (input, role = 'authenticated') => {
    if (!['authenticated','supabase_admin'].includes(role)) throw new Error('AUTH_RESTORE_SESSION_ROLE_INVALID');
    return sql(`BEGIN; SET LOCAL lock_timeout='2s'; SET LOCAL statement_timeout='5s'; SET LOCAL ROLE ${role}; SELECT set_config('request.jwt.claims',${quote(JSON.stringify(input))},true) IS NOT NULL; SELECT isg_session_fixture.observe_guard(); ROLLBACK;`).split('\n').at(-1);
  };
  const report = { source_sha256: createHash('sha256').update(fixture).digest('hex'), production_deployed: false,
    gateway_tested: false, company_capability_tested: false, global_inactivity_policy_tested: false, concurrency_ordering_tested: false };
  pass('session_guard_allows_real_signed_login', check(claims) === 'ALLOW');
  pass('session_guard_private_acl', sql("select has_function_privilege('anon','isg_session_fixture.require_active_session()','EXECUTE'); select has_function_privilege('service_role','isg_session_fixture.require_active_session()','EXECUTE'); select has_function_privilege('authenticated','isg_session_fixture.require_active_session()','EXECUTE');") === 'f\nf\nt');
  const invalid = [
    ['missing_claims',null],['empty_claims',{}],['array_claims',[]],
    ['missing_session', {...claims,session_id:undefined}],['bad_session', {...claims,session_id:'not-a-uuid'}],
    ['unknown_session',{...claims,session_id:randomUUID()}],['other_actor',{...claims,sub:randomUUID()}],
    ['bad_actor',{...claims,sub:17}],['anonymous_role',{...claims,role:'anon'}],['service_role',{...claims,role:'service_role'}],
    ['expired_token',{...claims,exp:Math.floor(Date.now()/1000)-1}],['missing_expiry',{...claims,exp:undefined}],
    ['string_expiry',{...claims,exp:String(claims.exp)}],['fractional_expiry',{...claims,exp:claims.exp+0.5}],
    ['metadata_cannot_supply_session',{...claims,session_id:undefined,user_metadata:{session_id:claims.session_id}}],
    ['metadata_cannot_supply_actor',{...claims,sub:undefined,user_metadata:{sub:claims.sub,role:'authenticated'}}],
  ];
  for (const [id,input] of invalid) pass(`session_guard_rejects_${id}`,check(input) === 'DENY');
  pass('session_guard_ignores_user_metadata_authority',check({...claims,user_metadata:{role:'service_role',sub:randomUUID(),session_id:randomUUID(),is_admin:true}}) === 'ALLOW');
  const actor = claims.sub, session = claims.session_id;
  sql(`UPDATE auth.sessions SET not_after=clock_timestamp()-interval '1 second' WHERE id='${session}' AND user_id='${actor}';`);
  pass('session_guard_rejects_expired_database_session',check(claims) === 'DENY');
  sql(`UPDATE auth.sessions SET not_after=clock_timestamp()+interval '1 hour' WHERE id='${session}' AND user_id='${actor}';`);
  pass('session_guard_accepts_future_not_after',check(claims) === 'ALLOW');
  sql(`UPDATE auth.sessions SET not_after=NULL WHERE id='${session}' AND user_id='${actor}';`);
  for (const [id, column, deniedValue, originalValue] of [
    ['banned_user','banned_until',"clock_timestamp()+interval '1 hour'",'NULL'],
    ['deleted_user','deleted_at','clock_timestamp()','NULL'],
    ['anonymous_user','is_anonymous','true','false'],
  ]) {
    sql(`UPDATE auth.users SET ${column}=${deniedValue} WHERE id='${actor}';`);
    pass(`session_guard_rejects_${id}`,check(claims) === 'DENY');
    sql(`UPDATE auth.users SET ${column}=${originalValue} WHERE id='${actor}';`);
  }
  pass('session_guard_restores_synthetic_user_eligibility',check(claims) === 'ALLOW');
  const appName = 'isg_session_lock_' + randomUUID().replaceAll('-','');
  const lockedTransaction = concurrentSql(`BEGIN; SET LOCAL application_name='${appName}'; SET LOCAL ROLE authenticated;
    SELECT set_config('request.jwt.claims',${quote(JSON.stringify(claims))},true) IS NOT NULL;
    SELECT isg_session_fixture.require_active_session() IS NOT NULL; SELECT pg_sleep(2); COMMIT;`);
  try {
    let sleeping = false;
    for (let i=0;i<30;i++) {
      if (sql(`select count(*) from pg_stat_activity where application_name='${appName}' and datname='postgres' and wait_event='PgSleep';`) === '1') { sleeping=true;break; }
      await new Promise(r=>setTimeout(r,30));
    }
    pass('session_guard_transaction_lock_ready',sleeping);
    for (const [id,statement] of [
      ['logout_delete',`DELETE FROM auth.sessions WHERE id='${session}' AND user_id='${actor}'`],
      ['ban_update',`UPDATE auth.users SET banned_until=clock_timestamp()+interval '1 hour' WHERE id='${actor}'`],
    ]) {
      const result = sql(`BEGIN; SET LOCAL lock_timeout='150ms'; SET LOCAL statement_timeout='1s';
        CREATE FUNCTION pg_temp.try_revocation() RETURNS text LANGUAGE plpgsql AS $probe$
        BEGIN ${statement}; RETURN 'UNEXPECTED_WRITE'; EXCEPTION WHEN lock_not_available THEN RETURN 'BLOCKED'; END;
        $probe$; SELECT pg_temp.try_revocation(); ROLLBACK;`);
      pass(`session_guard_active_transaction_blocks_${id}`,result === 'BLOCKED');
    }
  } finally {
    const completed = await lockedTransaction;
    pass('session_guard_authorized_transaction_completes',completed.ok && completed.output === 't\nt');
  }
  report.concurrency_ordering_tested = true;
  pass('session_guard_lock_probe_preserves_session',check(claims) === 'ALLOW');
  return {
    afterLogout() {
      // Reverify signature + expiry after real GoTrue logout. Cryptographic
      // validity alone must not authorize a sensitive new write.
      const stillSigned = verifyLocalSessionToken(token,secret);
      pass('session_guard_logout_token_still_cryptographically_valid',stillSigned.session_id === session);
      pass('session_guard_logout_removes_actual_auth_session',sql(`select count(*) from auth.sessions where id='${session}';`) === '0');
      pass('session_guard_rejects_still_signed_logged_out_token',check(stillSigned) === 'DENY');
      return report;
    },
  };
}
