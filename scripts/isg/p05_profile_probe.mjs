import {readFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import {ROOT} from './lib.mjs';
export const p05ProfileMigration='supabase/pilot-release/candidates/20260913203710_isg_p05_company_profile_overview.sql';
export const p05ProfileFiles=[p05ProfileMigration,'scripts/isg/p05_profile_probe.mjs'];
export async function probeP05Profile({synthetic,sql,rpc,ownerID,oldCompanyID,waitReady,pass}) {
  if(synthetic!==true)throw Error('PROFILE_SYNTHETIC_REQUIRED');
  sql('BEGIN;\n'+readFileSync(`${ROOT}/${p05ProfileMigration}`,'utf8')+'\nCOMMIT;');
  await waitReady(()=>rpc('isg_pilot_overview_v1',{p_company:null}).status!==404);
  const mark=(id,value)=>pass('p05_profile_'+id,value);
  const args={p_mutation:randomUUID(),p_name:'Profil Provası',p_hazard_class:'medium',p_sector:'  Metal  ',
    p_email:'qa@example.test',p_employee_count:25,p_responsible_name:'Sorumlu Prova'};
  const create=(changes={})=>rpc('isg_pilot_company_create_v2',{...args,...changes});
  const first=create();
  mark('v2_create',first.status===200 && first.body.schema_version===2 && first.body.company.user_id===ownerID);
  const company=first.body.company.id;
  const overview=()=>rpc('isg_pilot_overview_v1',{p_company:company});
  const row=overview().body.companies[0];
  mark('atomic_profile_and_employee',row.sector==='Metal' && row.email===args.p_email && row.declared_employee_count===25 &&
    row.personnel_count===1 && row.workplace_count===1 && row.responsible_employee_id && row.owner_id===ownerID);
  mark('unimplemented_metrics_are_null',row.finding_count===null && row.document_count===null && row.completion_score===null);
  mark('same_intent_replays_without_duplicates',create().body.replayed===true && create().body.company.id===company && overview().body.companies[0].personnel_count===1);
  for(const change of [{p_sector:'Other'},{p_email:'other@example.test'},{p_employee_count:26},{p_responsible_name:'Other'}]) {
    mark('changed_'+Object.keys(change)[0]+'_conflicts',create(change).body.message==='IDEMPOTENCY_CONFLICT');
  }
  for(const [index,change] of [{p_sector:''},{p_sector:null},{p_email:'invalid'},{p_employee_count:-1},{p_responsible_name:''}].entries()) {
    mark('invalid_'+index+'_'+Object.keys(change)[0]+'_rejected',create({...change,p_mutation:randomUUID()}).body.message==='VALIDATION_ERROR');
  }
  mark('legacy_company_not_exposed',rpc('isg_pilot_overview_v1',{p_company:oldCompanyID}).body.message==='FEATURE_UNAVAILABLE');
  const all=rpc('isg_pilot_overview_v1',{p_company:null});
  mark('overview_owner_scope',all.status===200 && all.body.owner_id===ownerID && all.body.companies.every(c=>c.owner_id===ownerID && c.id!==oldCompanyID));
  mark('private_rls_no_client_grants',sql("SELECT relrowsecurity AND NOT has_table_privilege('authenticated',oid,'SELECT,INSERT,UPDATE,DELETE') FROM pg_class WHERE oid='private_isg.p05_company_profiles'::regclass;")==='t');
  mark('anon_and_service_role_no_rpc_access',sql("SELECT NOT has_function_privilege('anon','public.isg_pilot_overview_v1(uuid)','EXECUTE') AND NOT has_function_privilege('service_role','public.isg_pilot_company_create_v2(uuid,text,text,text,text,integer,text)','EXECUTE');")==='t');
  sql("UPDATE private_isg.p05_pilot_accounts SET write_enabled=false WHERE actor_id='"+ownerID+"';");
  mark('write_pause_blocks_replay',create().body.message==='FEATURE_UNAVAILABLE' && overview().status===200);
  sql("UPDATE private_isg.p05_pilot_accounts SET write_enabled=true,read_enabled=true,revoked_at=clock_timestamp() WHERE actor_id='"+ownerID+"';");
  mark('revoke_hides_overview',overview().body.message==='FEATURE_UNAVAILABLE');
  sql("UPDATE private_isg.p05_pilot_accounts SET revoked_at=NULL WHERE actor_id='"+ownerID+"';");
}
