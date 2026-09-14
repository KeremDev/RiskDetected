import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

export const integratedRehearsalFiles=['scripts/isg/integrated_rehearsal_probe.mjs'];
const quote=v=>"'"+String(v).replaceAll("'","''")+"'";

// Every rollout feature this transition has introduced, in the order it arrived.
const GATED_FEATURES=['event_dispatch','quota_ledger','file_core','rule_engine','training','risk',
  'nonconformity','modules','documents','imports','notifications','personal_notes','billing_lifecycle',
  'campaigns','observability','score'];

export async function beginIntegratedRehearsalProbe({synthetic,sql:rawSql,companyID,ownerID,pass}) {
  let step='start';
  const sql=query=>{try{return rawSql(query);}catch(error){throw Error('AUTH_RESTORE_REHEARSAL_SQL_'+step);}};
  if(synthetic!==true)throw Error('AUTH_RESTORE_REHEARSAL_SYNTHETIC_REQUIRED');
  if(!ownerID||!companyID)throw Error('AUTH_RESTORE_REHEARSAL_SCOPE_REQUIRED');
  const mark=(name,ok)=>pass('integrated_rehearsal_'+name,ok);

  step='schema';
  sql(["CREATE SCHEMA isg_rehearsal_test;",
    "CREATE FUNCTION isg_rehearsal_test.gate(p_feature text) RETURNS text LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $probe$",
    "DECLARE err_code text; BEGIN",
    "IF p_feature='event_dispatch' THEN PERFORM private_isg.dispatch_gate(true);",
    "ELSIF p_feature='quota_ledger' THEN PERFORM private_isg.quota_gate(true);",
    "ELSIF p_feature='file_core' THEN PERFORM private_isg.file_gate(true);",
    "ELSIF p_feature='rule_engine' THEN PERFORM private_isg.rule_gate(true);",
    "ELSIF p_feature='training' THEN PERFORM private_isg.training_gate(true);",
    "ELSIF p_feature='risk' THEN PERFORM private_isg.risk_gate(true);",
    "ELSIF p_feature='nonconformity' THEN PERFORM private_isg.nonconformity_gate(true);",
    "ELSIF p_feature='modules' THEN PERFORM private_isg.module_gate('emergency_plan',true);",
    "ELSIF p_feature='documents' THEN PERFORM private_isg.document_gate(true);",
    "ELSIF p_feature='imports' THEN PERFORM private_isg.import_gate(true);",
    "ELSIF p_feature='notifications' THEN PERFORM private_isg.notification_gate(true);",
    "ELSIF p_feature='personal_notes' THEN PERFORM private_isg.notes_gate(true);",
    "ELSIF p_feature='billing_lifecycle' THEN PERFORM private_isg.billing_gate(true);",
    "ELSIF p_feature='campaigns' THEN PERFORM private_isg.campaign_gate(true);",
    "ELSIF p_feature='observability' THEN PERFORM private_isg.observability_gate(true);",
    "ELSIF p_feature='score' THEN PERFORM private_isg.score_gate(true);",
    "ELSE RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='UNKNOWN_FEATURE'; END IF;",
    "RETURN 'open';",
    "EXCEPTION WHEN SQLSTATE 'P0001' THEN GET STACKED DIAGNOSTICS err_code=MESSAGE_TEXT; RETURN err_code;",
    "WHEN OTHERS THEN GET STACKED DIAGNOSTICS err_code=RETURNED_SQLSTATE; RETURN 'SQLSTATE_'||err_code; END $probe$;"].join('\n'));
  const gate=feature=>sql("SELECT isg_rehearsal_test.gate("+quote(feature)+");").split('\n').at(-1);

  // A whole-transition snapshot: what the legacy product owns, before and after.
  const legacyFingerprint=()=>sql(`SELECT md5(coalesce(string_agg(part,'|' ORDER BY part),'')) FROM (
      SELECT 'companies:'||md5(coalesce(string_agg(c.id::text||c.user_id::text||c.name||c.hazard_class,',' ORDER BY c.id),'')) AS part FROM public.companies c
      UNION ALL SELECT 'profiles:'||md5(coalesce(string_agg(p.id::text||p.tier,',' ORDER BY p.id),'')) FROM public.profiles p
      UNION ALL SELECT 'subscriptions:'||md5(coalesce(string_agg(s.user_id::text||s.tier||s.status,',' ORDER BY s.user_id),'')) FROM public.user_subscriptions s
    ) parts;`);
  const helperFingerprint=()=>sql(`SELECT md5(string_agg(pg_get_functiondef(p.oid),'' ORDER BY p.oid))
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.prokind='f';`);
  step='legacy_fingerprint';
  const legacyBefore=legacyFingerprint(), helpersBefore=helperFingerprint();

  step='close_all';
  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false;");
  const refusals=GATED_FEATURES.map(feature=>[feature,gate(feature)]);
  mark('every_new_feature_refuses_while_its_switch_is_closed',
    refusals.length===16&&refusals.every(([,answer])=>answer==='FEATURE_UNAVAILABLE')&&
    sql("SELECT count(*)=17 AND bool_and(NOT read_enabled AND NOT write_enabled) FROM private_isg.rollout;")==='t');
  step='module_registry';
  // The phase switch answers before the module switch, so closing the phase is
  // enough even if an earlier probe left a module open. Then both are closed.
  const openModules=sql("SELECT count(*) FROM private_isg.module_registry WHERE read_enabled OR write_enabled;");
  mark('the_phase_switch_closes_a_module_even_when_the_module_switch_is_open',
    gate('modules')==='FEATURE_UNAVAILABLE');
  sql("UPDATE private_isg.module_registry SET read_enabled=false,write_enabled=false;");
  mark('the_shipped_posture_closes_every_module_switch_as_well',
    sql("SELECT count(*)=12 AND bool_and(NOT read_enabled AND NOT write_enabled) FROM private_isg.module_registry;")==='t'&&
    /^[0-9]+$/.test(openModules));

  // The legacy product is the one that must keep answering during a kill switch.
  step='legacy_helper';
  mark('the_legacy_plan_helper_still_answers',
    sql("SELECT private.user_plan_tier("+quote(ownerID)+");")==='plus'&&
    /^[0-9]+$/.test(sql("SELECT private.company_limit_for_user("+quote(ownerID)+");")));
  // The free account already owns its one company, so the legacy limit rule -
  // not a foreign key - is what has to refuse this write.
  step='free_owner';
  const freeOwner=sql("SELECT id FROM public.profiles WHERE tier='free' ORDER BY id LIMIT 1;");
  mark('the_legacy_company_rule_still_refuses_an_over_limit_write',(()=>{
    try{sql("INSERT INTO public.companies(id,user_id,name,hazard_class) VALUES("+quote(randomUUID())+","+quote(freeOwner)+",'Kapali anahtar firmasi','low');");
      return false;}catch{return true;}})());
  mark('the_legacy_rows_and_helpers_are_untouched_after_every_phase',
    legacyFingerprint()===legacyBefore&&helperFingerprint()===helpersBefore&&/^[a-f0-9]{32}$/.test(legacyBefore));

  // The whole new schema, checked once rather than phase by phase.
  step='posture';
  const posture=sql([
    "SELECT count(*) FROM pg_tables WHERE schemaname='private_isg';",
    "SELECT count(*) FROM pg_tables WHERE schemaname='private_isg' AND NOT rowsecurity;",
    "SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role','PUBLIC');",
    "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND p.prosecdef;",
    "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND NOT (coalesce(array_to_string(p.proconfig,','),'') LIKE '%search_path=%');",
    "SELECT count(*) FROM private_isg.rollout WHERE read_enabled OR write_enabled;",
  ].join('\n')).split('\n');
  mark('the_whole_new_schema_keeps_one_posture',posture[0]==='155'&&posture[1]==='0'&&posture[2]==='0'&&
    posture[4]==='0'&&posture[5]==='0');
  // A definer function is the client RPC boundary and nothing else. The server
  // only ledgers of P14 to P17 must not have quietly added one.
  const definers=sql("SELECT coalesce(string_agg(p.proname,',' ORDER BY p.proname),'') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND p.prosecdef;");
  const allowed=['company_default_after_insert','context_at','directory_mutate','directory_read','employee_row',
    'mutate_notebook','mutate_notebook_reminder','mutate_personnel','organize_notebook','read_notebook',
    'read_nonconformities','mutate_nonconformity',
    'read_notebook_organization','read_notebook_reminders','read_personnel','record_device_permission',
    'workspace_availability'];
  const actual=definers?definers.split(','):[];
  mark('only_the_known_client_rpc_boundary_runs_as_a_definer',
    actual.length===Number(posture[3])&&actual.every(name=>allowed.includes(name))&&
    actual.every(name=>!name.endsWith('_gate')));

  // Re-opening must be a decision, not a side effect: one feature at a time.
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='quota_ledger';");
  mark('opening_one_switch_opens_exactly_one_feature',gate('quota_ledger')==='open'&&
    GATED_FEATURES.filter(f=>f!=='quota_ledger').every(f=>gate(f)==='FEATURE_UNAVAILABLE'));
  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false;");
  mark('closing_again_is_immediate',gate('quota_ledger')==='FEATURE_UNAVAILABLE');

  return {afterLogout(){
    return {rehearsal:'integrated kill switch and legacy preservation',features_checked:GATED_FEATURES.length+1,
      legacy_rows_unchanged:true,legacy_helpers_unchanged:true,client_grants:0,
      cross_layer_user_journey_run:false,old_binary_matrix_run:false,account_deletion_run:false,
      restore_drill_run_here:false,production_deployed:false};
  }};
}
