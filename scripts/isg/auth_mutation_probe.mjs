import { randomUUID, createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { ROOT } from './lib.mjs';
import { verifyLocalSessionToken } from './auth_session_probe.mjs';

// This is a trusted SQL test adapter, not an HTTP gateway or client RPC.
export async function beginAuthMutationProbe({ synthetic, sql, concurrentSql, token, secret, pass }) {
  if (synthetic !== true) throw new Error('AUTH_RESTORE_MUTATION_SYNTHETIC_REQUIRED');
  const claims=verifyLocalSessionToken(token,secret);
  const files=['scripts/isg/sql/transaction_fixture.sql','scripts/isg/sql/auth_mutation_fixture.sql'];
  const source_sha256={};
  for(const path of files) {
    const source=readFileSync(resolve(ROOT,path),'utf8');
    source_sha256[path]=createHash('sha256').update(source).digest('hex');sql(source);
  }
  const actor=claims.sub, foreign=randomUUID(), company=randomUUID(), otherCompany=randomUUID(), entity=randomUUID(), otherEntity=randomUUID(), mutation=randomUUID();
  sql(`INSERT INTO isg_fixture.actors(id) VALUES ('${actor}'),('${foreign}');
    INSERT INTO isg_fixture.companies VALUES ('${company}','${actor}'),('${otherCompany}','${foreign}');
    INSERT INTO isg_fixture.counters(company_id,id) VALUES ('${company}','${entity}'),('${otherCompany}','${otherEntity}');
    INSERT INTO isg_fixture.write_capabilities VALUES ('${actor}',true);`);
  const quote=s=>"'"+s.replaceAll("'","''")+"'";
  const callSQL=({m=mutation,c=company,e=entity,v=0,d=1}={})=>`isg_fixture.observe_mutation('${m}','${c}','${e}',${v},${d})`;
  const context=(input=claims)=>`SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claims',${quote(JSON.stringify(input))},true) IS NOT NULL;`;
  const invoke=(args={},input=claims,fault='')=>{
    if(!['','audit','outbox'].includes(fault))throw new Error('AUTH_RESTORE_MUTATION_BAD_FAULT');
    return JSON.parse(sql(`BEGIN; SET LOCAL lock_timeout='2s'; SET LOCAL statement_timeout='5s'; ${context(input)}
      SELECT set_config('request.jwt.claim.sub','${foreign}',true) IS NOT NULL;
      SELECT set_config('isg_fixture.fail_at','${fault}',true) IS NOT NULL;
      SELECT ${callSQL(args)}; COMMIT;`).split('\n').at(-1));
  };
  const snapshot=()=>sql(`SELECT jsonb_build_object('counters',(select jsonb_agg(to_jsonb(t) order by company_id,id) from isg_fixture.counters t),
    'receipts',(select jsonb_agg(to_jsonb(t) order by actor_id,mutation_id) from isg_fixture.mutation_receipts t),
    'audit',(select jsonb_agg(to_jsonb(t) order by id) from isg_fixture.audit t),
    'outbox',(select jsonb_agg(to_jsonb(t) order by event_id) from isg_fixture.outbox t));`);
  const denied=(name,args,input,code,fault='')=>{
    const before=snapshot(),result=invoke(args,input,fault);
    pass(`auth_mutation_${name}`,JSON.stringify(result)===JSON.stringify({error:code}) && snapshot()===before);
  };
  pass('auth_mutation_private_acl',sql(`SELECT has_function_privilege('authenticated','isg_fixture.mutate_verified(uuid,uuid,uuid,bigint,integer)','EXECUTE');
    SELECT has_function_privilege('anon','isg_fixture.mutate_verified(uuid,uuid,uuid,bigint,integer)','EXECUTE');
    SELECT has_function_privilege('service_role','isg_fixture.mutate_verified(uuid,uuid,uuid,bigint,integer)','EXECUTE');
    SELECT has_function_privilege('authenticated','isg_fixture.mutate(uuid,uuid,uuid,bigint,integer)','EXECUTE');
    SELECT has_table_privilege('authenticated','isg_fixture.write_capabilities','UPDATE');
    SELECT has_table_privilege('authenticated','isg_fixture.counters','UPDATE');
    SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='isg_fixture' AND c.relkind='r' AND NOT c.relrowsecurity;`) === 't\nf\nf\nf\nf\nf\n0');
  pass('auth_mutation_real_session_commits',JSON.stringify(invoke())===JSON.stringify({result:{value:1,version:1}}));
  pass('auth_mutation_actor_is_verified_sub_not_legacy_guc',sql(`SELECT actor_id='${actor}' FROM isg_fixture.audit;`) === 't');
  pass('auth_mutation_atomic_four_records',sql(`SELECT value||':'||version FROM isg_fixture.counters WHERE company_id='${company}';
    SELECT count(*) FROM isg_fixture.audit; SELECT count(*) FROM isg_fixture.outbox; SELECT count(*) FROM isg_fixture.mutation_receipts;`) === '1:1\n1\n1\n1');
  const beforeReplay=snapshot();
  pass('auth_mutation_same_retry_returns_saved_result',JSON.stringify(invoke())===JSON.stringify({result:{value:1,version:1}}) && snapshot()===beforeReplay);
  denied('changed_payload_conflict', {d:2},claims,'IDEMPOTENCY_CONFLICT');
  denied('stale_version_no_side_effect',{m:randomUUID()},claims,'VERSION_CONFLICT');
  denied('foreign_company_no_side_effect',{m:randomUUID(),c:otherCompany,e:otherEntity},claims,'ACCESS_DENIED');
  denied('missing_company_indistinguishable',{m:randomUUID(),c:randomUUID()},claims,'ACCESS_DENIED');
  denied('cross_company_entity_no_side_effect',{m:randomUUID(),e:otherEntity},claims,'ACCESS_DENIED');
  denied('missing_entity_indistinguishable',{m:randomUUID(),e:randomUUID()},claims,'ACCESS_DENIED');
  denied('missing_session_no_side_effect',{m:randomUUID(),v:1},{...claims,session_id:undefined},'AUTH_REQUIRED');
  denied('expired_claim_no_side_effect',{m:randomUUID(),v:1},{...claims,exp:Math.floor(Date.now()/1000)-1},'AUTH_REQUIRED');
  sql(`UPDATE isg_fixture.write_capabilities SET can_mutate=false WHERE actor_id='${actor}';`);
  denied('revoked_permission_rejects_new',{m:randomUUID(),v:1},claims,'ACCESS_DENIED');
  denied('revoked_permission_rejects_saved_receipt',{},claims,'ACCESS_DENIED');
  denied('user_metadata_cannot_grant_permission',{m:randomUUID(),v:1},{...claims,user_metadata:{can_mutate:true,tier:'pro',is_admin:true}},'ACCESS_DENIED');
  sql(`DELETE FROM isg_fixture.write_capabilities WHERE actor_id='${actor}';`);
  denied('missing_permission_fail_closed',{m:randomUUID(),v:1},claims,'ACCESS_DENIED');
  sql(`INSERT INTO isg_fixture.write_capabilities VALUES ('${actor}',true);`);
  for(const fault of ['audit','outbox']) denied(`${fault}_failure_rolls_back_all`,{m:randomUUID(),v:1},claims,'INJECTED_FAILURE',fault);

  // Two independent connections: a permission revoke may not overtake a short
  // already-authorized write. Roll back this ordering probe to preserve state.
  const appName='isg_mutation_lock_'+randomUUID().replaceAll('-','');
  const locked=concurrentSql(`BEGIN; SET LOCAL application_name='${appName}'; ${context()}
    SELECT ${callSQL({m:randomUUID(),v:1})}->'result' IS NOT NULL; SELECT pg_sleep(2); ROLLBACK;`);
  try {
    let ready=false;
    for(let i=0;i<30;i++) {
      if(sql(`select count(*) from pg_stat_activity where application_name='${appName}' and wait_event='PgSleep';`)==='1') {ready=true;break;}
      await new Promise(r=>setTimeout(r,30));
    }
    pass('auth_mutation_capability_lock_ready',ready);
    pass('auth_mutation_permission_revoke_waits_for_transaction',sql(`BEGIN; SET LOCAL lock_timeout='150ms'; SET LOCAL statement_timeout='1s';
      CREATE FUNCTION pg_temp.revoke_probe() RETURNS text LANGUAGE plpgsql AS $probe$
      BEGIN UPDATE isg_fixture.write_capabilities SET can_mutate=false WHERE actor_id='${actor}'; RETURN 'UNEXPECTED';
      EXCEPTION WHEN lock_not_available THEN RETURN 'BLOCKED'; END; $probe$;
      SELECT pg_temp.revoke_probe(); ROLLBACK;`)==='BLOCKED');
  } finally {
    const done=await locked;pass('auth_mutation_authorized_lock_probe_completes',done.ok && done.output==='t\nt');
  }
  pass('auth_mutation_lock_probe_rollback_preserves_state',snapshot()===beforeReplay);
  // A fresh mutation after the failures proves the connection/transaction path
  // did not become permanently poisoned by fault injection or denied calls.
  pass('auth_mutation_recovers_after_denials',JSON.stringify(invoke({m:randomUUID(),v:1,d:2}))===JSON.stringify({result:{value:3,version:2}}));
  const parallelMutation=randomUUID();
  const retryResults=await Promise.all(Array.from({length:20},()=>concurrentSql(`BEGIN; ${context()}
    SELECT ${callSQL({m:parallelMutation,v:2})}; COMMIT;`)));
  pass('auth_mutation_twenty_retries_same_result',retryResults.every(r=>r.ok && JSON.stringify(JSON.parse(r.output.split('\n').at(-1)))===JSON.stringify({result:{value:4,version:3}})));
  pass('auth_mutation_twenty_retries_one_commit',sql(`SELECT value||':'||version FROM isg_fixture.counters WHERE company_id='${company}';
    SELECT count(*) FROM isg_fixture.audit; SELECT count(*) FROM isg_fixture.outbox; SELECT count(*) FROM isg_fixture.mutation_receipts;`) === '4:3\n3\n3\n3');
  const versionResults=await Promise.all(Array.from({length:20},()=>concurrentSql(`BEGIN; ${context()}
    SELECT ${callSQL({m:randomUUID(),v:3})}; COMMIT;`)));
  const versions=versionResults.filter(r=>r.ok).map(r=>JSON.parse(r.output.split('\n').at(-1)));
  pass('auth_mutation_twenty_versions_one_winner',versions.length===20 && versions.filter(r=>r.result?.version===4 && r.result.value===5).length===1 && versions.filter(r=>r.error==='VERSION_CONFLICT').length===19);
  pass('auth_mutation_version_race_one_atomic_commit',sql(`SELECT value||':'||version FROM isg_fixture.counters WHERE company_id='${company}';
    SELECT count(*) FROM isg_fixture.audit; SELECT count(*) FROM isg_fixture.outbox; SELECT count(*) FROM isg_fixture.mutation_receipts;`) === '5:4\n4\n4\n4');
  return {
    afterLogout() {
      const signed=verifyLocalSessionToken(token,secret);
      denied('logged_out_signed_token_cannot_write',{m:randomUUID(),v:4},signed,'AUTH_REQUIRED');
      denied('logged_out_signed_token_cannot_replay',{},signed,'AUTH_REQUIRED');
      return {source_sha256,production_deployed:false,gateway_tested:false,billing_capability_tested:false,
        synthetic_permission_gate_tested:true,real_session_mutation_composition_tested:true};
    },
  };
}
