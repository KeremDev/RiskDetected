import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
export const p05PilotFiles=['supabase/migrations/20260913191226_isg_p05_readonly_pilot.sql','scripts/isg/p05_pilot_probe.mjs'];
const q=value=>"'"+String(value).replaceAll("'","''")+"'";

export async function beginP05PilotProbe({synthetic,sql,companyID,ownerID,request,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_PILOT_SYNTHETIC_REQUIRED');
  if(!companyID||!ownerID)throw Error('AUTH_RESTORE_PILOT_SCOPE_REQUIRED');
  const mark=(name,ok)=>pass('p05_pilot_'+name,ok);
  const rpc=(name,body,extra={})=>request('/rpc/'+name,{method:'POST',body,...extra});
  const availability=(company=companyID)=>rpc('isg_workspace_availability_v1',{p_company:company});
  const read=(company=companyID)=>rpc('isg_personnel_read_v1',{p_company:company,p_kind:'employees',p_query:'',p_archived:false,p_after:null,p_id:null});
  const directory=company=>rpc('isg_directory_read_v1',{p_company:company,p_kind:'workplaces',p_parent:null,p_after:null,p_archived:false});
  const blocked=r=>r.status===400&&r.body.message==='FEATURE_UNAVAILABLE';
  const snapshot=()=>sql("SELECT md5(coalesce(string_agg(part,'|' ORDER BY part),'')) FROM ("+
    "SELECT to_jsonb(c)::text part FROM public.companies c UNION ALL SELECT to_jsonb(e)::text FROM private_isg.employees e "+
    "UNION ALL SELECT to_jsonb(s)::text FROM public.user_subscriptions s UNION ALL SELECT to_jsonb(o)::text FROM private_isg.personnel_outbox o "+
    "UNION ALL SELECT to_jsonb(a)::text FROM private_isg.personnel_audit a UNION ALL SELECT to_jsonb(r)::text FROM private_isg.personnel_receipts r) s;");
  const before=snapshot();
  sql(readFileSync(resolve(ROOT,p05PilotFiles[0]),'utf8'));
  mark('ships_disabled_with_empty_roster',sql("SELECT (SELECT count(*)=0 FROM private_isg.p05_pilot_grants) AND (SELECT NOT read_enabled AND NOT write_enabled FROM private_isg.rollout WHERE feature='personnel');")==='t');
  mark('disabled_hides_global_and_company',availability(null).body.can_read===false&&availability().body.company_name===null&&blocked(read()));
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='personnel';");
  mark('generic_flags_cannot_bypass_roster',availability(null).body.can_read===false&&blocked(read())&&blocked(directory(companyID)));
  mark('client_claims_cannot_add_grant',rpc('isg_workspace_availability_v1',{p_company:companyID,pilot:true,actor_id:ownerID}).status>=400);
  const grant=company=>sql("INSERT INTO private_isg.p05_pilot_grants(actor_id,company_id,approved_reference,expires_at) VALUES("+q(ownerID)+","+q(company)+",'synthetic-review',clock_timestamp()+interval '1 hour');");
  grant(companyID);
  mark('allowlisted_owner_discovers_read_only_pilot',availability(null).body.can_read===true&&availability(null).body.can_write===false&&availability().body.can_read===true&&availability().body.can_write===false);
  mark('allowlisted_owner_reads_existing_personnel_and_directory',read().status===200&&directory(companyID).status===200);
  const workplace=sql("SELECT id FROM private_isg.workplaces WHERE company_id="+q(companyID)+" ORDER BY id LIMIT 1;");
  mark('allowlisted_context_read_reaches_domain',rpc('isg_context_at_v1',{p_company:companyID,p_workplace:workplace,p_on:'2026-09-13'}).status===200);
  const employee=sql("SELECT id FROM private_isg.employees WHERE company_id="+q(companyID)+" ORDER BY id LIMIT 1;");
  for(const action of ['create','edit','archive','restore']) {
    mark('write_'+action+'_denied_even_with_generic_write_flag',blocked(rpc('isg_personnel_mutate_v1',{
      p_company:companyID,p_action:action,p_operation:ownerID,p_mutation:ownerID,p_employee:employee,p_expected:0,
      p_name:null,p_change_department:false,p_department:null,p_department_name:null})));
  }
  mark('directory_write_denied',blocked(rpc('isg_directory_mutate_v1',{p_company:companyID,p_kind:'workplaces',p_operation:ownerID,p_mutation:ownerID,p_id:null,p_expected:0,p_body:{}})));
  const foreign=sql("SELECT id FROM public.companies WHERE user_id<>"+q(ownerID)+" ORDER BY id LIMIT 1;");
  mark('foreign_company_fixture_exists',Boolean(foreign));
  mark('nonallowlisted_company_hidden',availability(foreign).body.company_name===null&&availability(foreign).body.can_read===false&&blocked(read(foreign)));
  grant(foreign);
  mark('grant_cannot_override_company_ownership',blocked(read(foreign))&&blocked(directory(foreign))&&availability(foreign).body.can_read===false);
  sql("UPDATE private_isg.p05_pilot_grants SET revoked_at=clock_timestamp() WHERE company_id="+q(companyID)+";");
  mark('revocation_takes_effect_without_token_refresh',blocked(read())&&availability(null).body.can_read===false);
  sql("UPDATE private_isg.p05_pilot_grants SET revoked_at=NULL,created_at=clock_timestamp()-interval '2 days',expires_at=clock_timestamp()-interval '1 day' WHERE company_id="+q(companyID)+";");
  mark('expired_grant_denied_without_token_refresh',blocked(read())&&availability().body.can_read===false);
  sql("UPDATE private_isg.p05_pilot_grants SET created_at=clock_timestamp(),expires_at=clock_timestamp()+interval '1 hour' WHERE company_id="+q(companyID)+";");
  mark('valid_grant_restores_read_only',read().status===200&&availability().body.can_write===false);
  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='personnel';");
  mark('kill_switch_denies_cached_allowlisted_session',blocked(read())&&availability().body.can_read===false);
  mark('private_roster_and_helper_have_no_client_grants',sql("SELECT NOT has_table_privilege('authenticated','private_isg.p05_pilot_grants','SELECT') AND NOT has_table_privilege('service_role','private_isg.p05_pilot_grants','INSERT') AND NOT has_function_privilege('authenticated','private_isg.p05_pilot_can_read(uuid,uuid)','EXECUTE') AND NOT has_function_privilege('anon','private_isg.p05_pilot_can_read(uuid,uuid)','EXECUTE');")==='t');
  mark('roster_rls_enabled',sql("SELECT rowsecurity FROM pg_tables WHERE schemaname='private_isg' AND tablename='p05_pilot_grants';")==='t');
  mark('anonymous_availability_denied',rpc('isg_workspace_availability_v1',{p_company:companyID},{authorization:null}).status===401);
  mark('no_legacy_personnel_subscription_or_outbox_writes',snapshot()===before);
  sql('DELETE FROM private_isg.p05_pilot_grants;');
  mark('leaves_empty_roster_and_closed_rollout',sql("SELECT (SELECT count(*)=0 FROM private_isg.p05_pilot_grants) AND (SELECT NOT read_enabled AND NOT write_enabled FROM private_isg.rollout WHERE feature='personnel');")==='t');
  return {afterLogout(){mark('revoked_auth_session_still_rejected',availability().status===403&&read().status===403);return {readonly:true,server_allowlist:true,production_deployed:false,live_data_tested:false,native_pilot_tested:false};}};
}
