import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {verifyLocalSessionToken} from './auth_session_probe.mjs';
import {preparePersonnelRPC} from '../../supabase/functions/_shared/personnel/rpc-request.ts';
export const personnelMigrationFiles=[
  'supabase/migrations/20260913074153_isg_personnel_owner_rpc.sql',
  'supabase/migrations/20260520154818_add_companies.sql',
  'supabase/migrations/20260513101505_free_plus_pro_subscription_system.sql',
  'supabase/migrations/20260513223911_fix_subscription_quota_review_findings.sql',
  'scripts/isg/personnel_migration_probe.mjs',
  'scripts/isg/personnel_http_probe.mjs',
  'scripts/isg/personnel_advisor_probe.mjs',
  'supabase/functions/_shared/personnel/rpc-request.ts',
];
const read=p=>readFileSync(resolve(ROOT,p),'utf8');
const quote=v=>"'"+v.replaceAll("'","''")+"'";
function exactly(source,pattern){const matches=[...source.matchAll(pattern)];if(matches.length!==1)throw Error('AUTH_RESTORE_PERSONNEL_SOURCE_DRIFT');return matches[0][0];}
export async function beginPersonnelMigrationProbe({synthetic,sql,concurrentSql,token,secret,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_PERSONNEL_MIGRATION_SYNTHETIC_REQUIRED');
  const claims=verifyLocalSessionToken(token,secret);
  // Minimal profile dependency; legacy company/subscription DDL and helpers are exact.
  const companies=read(personnelMigrationFiles[1]), subscriptions=read(personnelMigrationFiles[2]),tier=read(personnelMigrationFiles[3]);
  const actor=claims.sub,foreign=randomUUID(),company=randomUUID(),other=randomUUID();
  const definitions=[
    exactly(companies,/create table if not exists public\.companies \([\s\S]*?\n\);/gi),
    exactly(subscriptions,/create table if not exists public\.user_subscriptions \([\s\S]*?\n\);/gi),
    exactly(tier,/create or replace function private\.user_plan_tier\(p_user_id uuid\)[\s\S]*?\$\$;/gi),
    exactly(companies,/create or replace function private\.company_limit_for_user\(p_user_id uuid\)[\s\S]*?\$\$;/gi),
    exactly(companies,/create or replace function private\.enforce_company_write_rules\(\)[\s\S]*?end \$\$;/gi),
  ];
  sql(["CREATE SCHEMA IF NOT EXISTS private;",
    "CREATE TABLE public.profiles(id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,tier text NOT NULL DEFAULT 'free');",
    ...definitions,
    "ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY; ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY; ALTER TABLE public.user_subscriptions ENABLE ROW LEVEL SECURITY;",
    "REVOKE ALL ON TABLE public.profiles,public.companies,public.user_subscriptions FROM PUBLIC,anon,authenticated,service_role;",
    "REVOKE ALL ON FUNCTION private.user_plan_tier(uuid),private.company_limit_for_user(uuid),private.enforce_company_write_rules() FROM PUBLIC,anon,authenticated,service_role;",
    "INSERT INTO auth.users(id) VALUES("+quote(foreign)+");",
    "INSERT INTO public.profiles(id,tier) VALUES("+quote(actor)+",'pro'),("+quote(foreign)+",'free');",
    "INSERT INTO public.companies(id,user_id,name,hazard_class) VALUES("+quote(company)+","+quote(actor)+",'Firma A','high'),("+quote(other)+","+quote(foreign)+",'Firma B','medium');",
    "INSERT INTO public.user_subscriptions(user_id,tier,status,current_period_ends_at) VALUES("+quote(actor)+",'plus','active',now()+interval '1 hour');",
    "CREATE TRIGGER companies_enforce_write_rules BEFORE INSERT OR UPDATE ON public.companies FOR EACH ROW EXECUTE FUNCTION private.enforce_company_write_rules();"].join('\n'));
  const legacyBefore=sql('SELECT jsonb_agg(to_jsonb(c) ORDER BY id) FROM public.companies c;');
  sql(read(personnelMigrationFiles[0]));
  const mark=(name,ok)=>pass('personnel_migration_'+name,ok);
  mark('legacy_rows_unchanged',legacyBefore===sql('SELECT jsonb_agg(to_jsonb(c) ORDER BY id) FROM public.companies c;'));
  mark('backfill_one_default_each_and_unknown_context',sql("SELECT count(*)=2 AND bool_and(needs_review AND timezone IS NULL AND jurisdiction IS NULL) FROM private_isg.workplaces;")==='t');
  // Test-only error observer; every failed call rolls back its complete subtransaction.
  sql(["CREATE SCHEMA isg_rpc_test; GRANT USAGE ON SCHEMA isg_rpc_test TO authenticated;",
    "CREATE FUNCTION isg_rpc_test.observe(kind text,a jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$",
    "DECLARE r jsonb; code text; BEGIN",
    "IF kind='read' THEN r:=public.isg_personnel_read_v1((a->>'p_company')::uuid,a->>'p_kind',a->>'p_query',(a->>'p_archived')::boolean,(a->>'p_after')::uuid,(a->>'p_id')::uuid);",
    "ELSE r:=public.isg_personnel_mutate_v1((a->>'p_company')::uuid,a->>'p_action',(a->>'p_operation')::uuid,(a->>'p_mutation')::uuid,(a->>'p_employee')::uuid,(a->>'p_expected')::bigint,a->>'p_name',(a->>'p_change_department')::boolean,(a->>'p_department')::uuid,a->>'p_department_name');",
    "END IF; RETURN jsonb_build_object('result',r);",
    "EXCEPTION WHEN SQLSTATE '28000' THEN RETURN jsonb_build_object('error','AUTH_REQUIRED');",
    "WHEN SQLSTATE 'P0001' THEN GET STACKED DIAGNOSTICS code=MESSAGE_TEXT;",
    "IF code NOT IN ('FEATURE_UNAVAILABLE','PAID_PLAN_REQUIRED','ACCESS_DENIED','VALIDATION_ERROR','VERSION_CONFLICT','IDEMPOTENCY_CONFLICT','DEPARTMENT_SCOPE_INVALID','DEPARTMENT_SELECTION_REQUIRED','TEST_FAULT') THEN RAISE; END IF;",
    "RETURN jsonb_build_object('error',code); END $$;",
    "REVOKE ALL ON FUNCTION isg_rpc_test.observe(text,jsonb) FROM PUBLIC; GRANT EXECUTE ON FUNCTION isg_rpc_test.observe(text,jsonb) TO authenticated;"].join('\n'));
  const context=(version=0)=>({schema_version:1,operation_id:randomUUID(),client_mutation_id:randomUUID(),platform:'ios',client_build:1,expected_version:version,scope:{kind:'company',company_id:company}});
  const create={action:'create',context:context(),full_name:'Ada Kaya',department:{kind:'new',name:'Bakım'}};
  const list={action:'employees',company_id:company,query:'',include_archived:false,cursor:null};
  const call=request=>{
    const prepared=preparePersonnelRPC(request);assert.ok(prepared);
    return "SELECT isg_rpc_test.observe("+quote(prepared.functionName==='isg_personnel_read_v1'?'read':'write')+","+quote(JSON.stringify(prepared.args))+"::jsonb);";
  };
  const tx=(body,jwt=claims,legacySub='')=>"BEGIN; SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claims',"+quote(JSON.stringify(jwt))+",true) IS NOT NULL; SELECT set_config('request.jwt.claim.sub',"+quote(legacySub)+",true) IS NOT NULL; "+body+" COMMIT;";
  const invoke=(request,jwt=claims,sub='')=>JSON.parse(sql(tx(call(request),jwt,sub)).split('\n').at(-1));
  const snap=()=>sql("SELECT jsonb_build_array((SELECT jsonb_agg(to_jsonb(e) ORDER BY id) FROM private_isg.employees e),(SELECT count(*) FROM private_isg.departments),(SELECT count(*) FROM private_isg.personnel_receipts),(SELECT count(*) FROM private_isg.personnel_audit),(SELECT count(*) FROM private_isg.personnel_outbox));");
  const deny=(name,request,code,jwt=claims,sub='')=>{const before=snap();mark(name,invoke(request,jwt,sub).error===code&&snap()===before);};
  deny('rollout_default_off_read',list,'FEATURE_UNAVAILABLE');deny('rollout_default_off_write',create,'FEATURE_UNAVAILABLE');
  mark('private_tables_rls_and_zero_client_privileges',sql("SELECT count(*) FROM pg_tables WHERE schemaname='private_isg' AND NOT rowsecurity; SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role','PUBLIC'); SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND has_function_privilege('anon',p.oid,'EXECUTE');")==='0\n0\n0');
  mark('public_wrappers_invoker_only',sql("SELECT bool_and(NOT prosecdef) FROM pg_proc WHERE oid IN('public.isg_personnel_read_v1(uuid,text,text,boolean,uuid,uuid)'::regprocedure,'public.isg_personnel_mutate_v1(uuid,text,uuid,uuid,uuid,bigint,text,boolean,uuid,text)'::regprocedure);")==='t');
  mark('checked_entry_points_only_and_fixed_search_path',sql("SELECT count(*)=2 AND bool_and(proname IN ('read_personnel','mutate_personnel')) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND has_function_privilege('authenticated',p.oid,'EXECUTE'); SELECT bool_and(proconfig @> ARRAY['search_path=\"\"']) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg'; SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND has_function_privilege('service_role',p.oid,'EXECUTE');")==='t\nt\n0');
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true;");
  deny('foreign_company', {...list,company_id:other},'ACCESS_DENIED');
  deny('mismatched_legacy_sub',list,'AUTH_REQUIRED',claims,foreign);
  const receipt=invoke(create).result;mark('paid_session_name_only_inline_department',!!receipt?.employee_id&&receipt.version===0);
  mark('dates_remain_unknown',sql("SELECT hired_on IS NULL AND employment_ends_before IS NULL FROM private_isg.employees WHERE id="+quote(receipt.employee_id)+";")==='t');
  const baseline=snap();mark('create_retry_no_duplicate',JSON.stringify(invoke(create).result)===JSON.stringify(receipt)&&snap()===baseline);
  deny('same_key_different_body', {...create,full_name:'Başka'},'IDEMPOTENCY_CONFLICT');
  // Fail each write tail independently, including newly typed department creation.
  sql("CREATE FUNCTION isg_rpc_test.fail_write() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='TEST_FAULT'; END $$;");
  for(const table of ['personnel_audit','personnel_outbox','personnel_receipts']) {
    sql(`CREATE TRIGGER test_tail_failure BEFORE INSERT ON private_isg.${table} FOR EACH ROW EXECUTE FUNCTION isg_rpc_test.fail_write();`);
    const request={...create,context:context(),department:{kind:'new',name:'Geri alınacak '+table}};
    deny(table+'_fault_rolls_back_employee_department_and_events',request,'TEST_FAULT');
    sql(`DROP TRIGGER test_tail_failure ON private_isg.${table};`);
  }
  const reused=invoke({...create,context:context(),department:{kind:'new',name:'  BAKIM  '}}).result;
  mark('turkish_department_reused',!!reused&&sql('SELECT count(*) FROM private_isg.departments;')==='1');
  const missingDepartment={...create,context:context(),department:{kind:'existing',id:randomUUID()}};
  deny('unknown_department_no_side_effect',missingDepartment,'DEPARTMENT_SCOPE_INVALID');
  // Lock the real subscription row through COMMIT; cancellation must wait or deny.
  const appName='isg_personnel_lock_'+randomUUID().replaceAll('-','');
  const lockBody=tx("SET LOCAL application_name="+quote(appName)+"; "+call({...create,context:context(),department:null})+" SELECT pg_sleep(2);");
  const holding=concurrentSql(lockBody);
  let lockReady=false;
  for(let attempt=0;attempt<30;attempt++) {
    if(sql("SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE application_name="+quote(appName)+" AND wait_event='PgSleep');")==='t'){lockReady=true;break;}
    await new Promise(resolve=>setTimeout(resolve,30));
  }
  mark('subscription_lock_probe_ready',lockReady);
  try {
    const revoke=sql("BEGIN; SET LOCAL lock_timeout='150ms'; CREATE FUNCTION pg_temp.revoke_personnel_probe() RETURNS text LANGUAGE plpgsql AS $$ BEGIN UPDATE public.user_subscriptions SET status='expired' WHERE user_id="+quote(actor)+"; RETURN 'UNEXPECTED'; EXCEPTION WHEN lock_not_available THEN RETURN 'BLOCKED'; END $$; SELECT pg_temp.revoke_personnel_probe(); ROLLBACK;");
    mark('subscription_revoke_waits_for_authorized_transaction',revoke==='BLOCKED');
  } finally {
    const held=await holding;
    mark('subscription_lock_authorized_write_completes',held.ok&&!!JSON.parse(held.output.split('\n').at(-1)).result);
  }
  const edit={action:'edit',context:context(),employee_id:receipt.employee_id,full_name:'Ada Yeni',department:{kind:'keep'}};
  const races=await Promise.all(Array.from({length:20},()=>concurrentSql(tx(call({...edit,context:context()})))));
  const results=races.filter(r=>r.ok).map(r=>JSON.parse(r.output.split('\n').at(-1)));
  mark('twenty_edit_races_one_commit',results.length===20&&results.filter(r=>r.result?.version===1).length===1&&results.filter(r=>r.error==='VERSION_CONFLICT').length===19);
  for(const [status,expires,allowed] of [['active','future',true],['trialing','future',true],['grace_period','future',true],['expired','future',false],['paused','future',false],['billing_issue','future',false],['inactive','future',false],['cancelled','future',false],['active','past',false],['active','null',true]]) {
    sql("UPDATE public.user_subscriptions SET status="+quote(status)+",current_period_ends_at="+(expires==='null'?'NULL':"now()"+(expires==='past'?'-':'+')+"interval '1 hour'")+" WHERE user_id="+quote(actor)+";");
    const r=invoke({...create,context:context(),department:null});
    mark('paid_'+status+'_'+expires,allowed?!!r.result:r.error==='PAID_PLAN_REQUIRED');
  }
  sql("UPDATE public.user_subscriptions SET tier='free',status='active' WHERE user_id="+quote(actor)+";");
  deny('profile_pro_cannot_grant_access',create,'PAID_PLAN_REQUIRED');
  deny('user_metadata_cannot_grant_access',create,'PAID_PLAN_REQUIRED',{...claims,user_metadata:{tier:'pro'}});
  mark('free_owner_can_read_retained_records',invoke(list).result.rows.length>0);
  sql("UPDATE public.user_subscriptions SET tier='plus',status='active',current_period_ends_at=now()+interval '1 hour' WHERE user_id="+quote(actor)+";");
  const archive={action:'archive',context:context(1),employee_id:receipt.employee_id};
  mark('archive_and_retry_same_receipt',invoke(archive).result?.version===2&&invoke(archive).result?.version===2);
  mark('archive_retains_employee',invoke({action:'detail',company_id:company,employee_id:receipt.employee_id}).result?.is_archived===true);
  deny('archived_create_receipt_not_replayed',create,'ACCESS_DENIED');
  deny('archived_employee_cannot_edit', {...edit,context:context(2)},'ACCESS_DENIED');
  mark('active_list_excludes_archived',!invoke(list).result.rows.some(r=>r.id===receipt.employee_id));
  mark('archive_filter_includes_retained',invoke({...list,include_archived:true}).result.rows.some(r=>r.id===receipt.employee_id));
  // Real RPC pagination corpus; direct seeding is test-only and intentionally lacks events.
  sql("INSERT INTO private_isg.employees(company_id,owner_id,employee_code,full_name) SELECT "+quote(company)+","+quote(actor)+",'PAGE-'||g,'Sayfa %_'||g FROM generate_series(1,105) g;");
  const pageRequest={...list,query:'Sayfa %_'};
  const first=invoke(pageRequest).result,second=invoke({...pageRequest,cursor:first.next}).result,third=invoke({...pageRequest,cursor:second.next}).result;
  mark('keyset_pages_50_50_5_no_duplicates',first.rows.length===50&&second.rows.length===50&&third.rows.length===5&&third.next===null&&new Set([...first.rows,...second.rows,...third.rows].map(r=>r.id)).size===105);
  mark('search_wildcards_are_literal',invoke({...list,query:'%_'}).result.rows.every(r=>r.name.includes('%_'))&&invoke({...list,query:'%missing'}).result.rows.length===0);
  sql("DELETE FROM private_isg.employees WHERE company_id="+quote(company)+" AND employee_code LIKE 'PAGE-%';");
  sql("UPDATE private_isg.rollout SET write_enabled=false;");
  deny('kill_switch_denies_cached_receipt',archive,'FEATURE_UNAVAILABLE');
  mark('kill_switch_keeps_read',!!invoke(list).result);
  const legacyNew=randomUUID();
  sql("INSERT INTO public.companies(id,user_id,name,hazard_class) VALUES("+quote(legacyNew)+","+quote(actor)+",'Eski istemci yeni firma','low');");
  mark('legacy_new_company_catchup_while_rollout_disabled',sql("SELECT count(*) FROM private_isg.workplaces WHERE legacy_company_id="+quote(legacyNew)+";")==='1');
  const ids=sql("SELECT string_agg(id::text,',' ORDER BY id) FROM private_isg.workplaces;");
  sql('SELECT private_isg.ensure_default(id) FROM public.companies ORDER BY id;');
  mark('backfill_retry_stable_ids',ids===sql("SELECT string_agg(id::text,',' ORDER BY id) FROM private_isg.workplaces;"));
  // Delete only the disposable, synthetic company; validate all new FK cascades.
  sql("UPDATE private_isg.rollout SET write_enabled=true;");
  const disposable=invoke({...create,context:{...context(),scope:{kind:'company',company_id:legacyNew}},department:{kind:'new',name:'Geçici'}}).result;
  mark('disposable_company_personnel_created',!!disposable);
  sql("DELETE FROM public.companies WHERE id="+quote(legacyNew)+";");
  mark('company_deletion_cascades_entire_new_graph',sql("SELECT (SELECT count(*) FROM private_isg.workplaces WHERE company_id="+quote(legacyNew)+")+(SELECT count(*) FROM private_isg.departments WHERE company_id="+quote(legacyNew)+")+(SELECT count(*) FROM private_isg.employees WHERE company_id="+quote(legacyNew)+")+(SELECT count(*) FROM private_isg.personnel_receipts WHERE company_id="+quote(legacyNew)+")+(SELECT count(*) FROM private_isg.personnel_audit WHERE company_id="+quote(legacyNew)+")+(SELECT count(*) FROM private_isg.personnel_outbox o LEFT JOIN private_isg.personnel_audit a USING(event_id) WHERE a.event_id IS NULL);")==='0');
  mark('other_company_survives_cascade',invoke(list).result.rows.length>0);
  return {companyID:company,afterLogout(){
    deny('logout_read',list,'AUTH_REQUIRED');deny('logout_write',create,'AUTH_REQUIRED');
    return {migration_file:personnelMigrationFiles[0],exact_migration_executed:true,real_local_auth:true,existing_subscription_helper:true,full_schema_restore:false,http_e2e_tested_by_this_probe:false,production_deployed:false};
  }};
}
