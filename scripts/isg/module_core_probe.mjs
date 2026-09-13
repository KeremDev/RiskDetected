import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

export const moduleCoreFiles=[
  'supabase/migrations/20260913230000_isg_module_core.sql',
  'scripts/isg/module_core_probe.mjs',
];
const read=p=>readFileSync(resolve(ROOT,p),'utf8');
const quote=v=>"'"+String(v).replaceAll("'","''")+"'";
const json=v=>quote(JSON.stringify(v))+'::jsonb';
const now=seconds=>new Date(Date.UTC(2026,8,13,23,0,0)+seconds*1000).toISOString();

export async function beginModuleCoreProbe({synthetic,sql,companyID,ownerID,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_MODULE_SYNTHETIC_REQUIRED');
  if(!companyID||!ownerID)throw Error('AUTH_RESTORE_MODULE_SCOPE_REQUIRED');
  const mark=(name,ok)=>pass('module_core_'+name,ok);
  sql(read(moduleCoreFiles[0]));
  mark('migration_applied_with_closed_rollout',sql("SELECT NOT read_enabled AND NOT write_enabled FROM private_isg.rollout WHERE feature='modules';")==='t'&&
    sql("SELECT count(*)=5 AND bool_and(NOT read_enabled AND NOT write_enabled) FROM private_isg.module_registry;")==='t');
  const workplace=sql("SELECT id FROM private_isg.workplaces WHERE company_id="+quote(companyID)+" ORDER BY id LIMIT 1;");
  const asset=sql("SELECT asset_id FROM private_isg.file_assets ORDER BY created_at LIMIT 1;");
  const employees=sql("SELECT string_agg(id::text,',' ORDER BY id) FROM (SELECT id FROM private_isg.employees WHERE company_id="+quote(companyID)+" AND NOT is_archived ORDER BY id LIMIT 3) s;").split(',');

  sql(["CREATE SCHEMA isg_module_test;",
    "CREATE FUNCTION isg_module_test.observe(kind text,a jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $probe$",
    "DECLARE r jsonb; code text; BEGIN",
    "IF kind='plan' THEN r:=private_isg.publish_emergency_plan((a->>'company')::uuid,(a->>'workplace')::uuid,(a->>'plan')::uuid,a->>'scope',(a->>'prepared_on')::date,(a->>'valid_until')::date,a->'team',(a->>'asset')::uuid,a->>'review_note',(a->>'now')::timestamptz);",
    "ELSIF kind='drill_plan' THEN r:=private_isg.plan_drill((a->>'company')::uuid,(a->>'workplace')::uuid,(a->>'plan')::uuid,(a->>'plan_version')::integer,(a->>'planned_on')::date,(a->>'now')::timestamptz);",
    "ELSIF kind='drill_result' THEN r:=private_isg.record_drill_result((a->>'drill')::uuid,(a->>'performed_on')::date,nullif(a->'participants','null'::jsonb),a->>'observation',a->>'improvement',(a->>'now')::timestamptz);",
    "ELSIF kind='equipment_rule' THEN r:=private_isg.set_equipment_inspection_rule((a->>'company')::uuid,a->>'type',(a->>'period_months')::integer,a->>'source',a->>'exception',(a->>'now')::timestamptz);",
    "ELSIF kind='equipment' THEN r:=private_isg.register_equipment((a->>'company')::uuid,(a->>'workplace')::uuid,a->>'type',a->>'serial',(a->>'acquired_on')::date,(a->>'now')::timestamptz);",
    "ELSIF kind='inspection' THEN r:=private_isg.record_equipment_inspection((a->>'equipment')::uuid,(a->>'performed_on')::date,a->>'result',(a->>'asset')::uuid,a->>'external_ref',a->>'note',(a->>'now')::timestamptz);",
    "ELSIF kind='appointment' THEN r:=private_isg.record_appointment((a->>'company')::uuid,(a->>'employee')::uuid,a->>'kind',(a->>'workplace')::uuid,(a->>'starts_on')::date,(a->>'ends_before')::date,(a->>'asset')::uuid,(a->>'now')::timestamptz);",
    "ELSIF kind='appointment_end' THEN r:=private_isg.end_appointment((a->>'appointment')::uuid,(a->>'ends_before')::date,(a->>'now')::timestamptz);",
    "ELSIF kind='ppe' THEN r:=private_isg.record_ppe_handover((a->>'company')::uuid,(a->>'employee')::uuid,a->>'item',(a->>'quantity')::numeric,a->>'unit',(a->>'handed_on')::date,(a->>'asset')::uuid,(a->>'signed')::boolean,a->>'external_ref',(a->>'now')::timestamptz);",
    "ELSIF kind='ppe_return' THEN r:=private_isg.record_ppe_return((a->>'handover')::uuid,(a->>'quantity')::numeric,(a->>'returned_on')::date,a->>'condition',a->>'note',(a->>'now')::timestamptz);",
    "ELSE RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;",
    "RETURN jsonb_build_object('result',r);",
    "EXCEPTION WHEN SQLSTATE '23514' THEN RETURN jsonb_build_object('error','CHECK_VIOLATION');",
    "WHEN SQLSTATE '23505' THEN RETURN jsonb_build_object('error','UNIQUE_VIOLATION');",
    "WHEN SQLSTATE '23P01' THEN RETURN jsonb_build_object('error','EXCLUSION_VIOLATION');",
    "WHEN SQLSTATE 'P0001' THEN GET STACKED DIAGNOSTICS code=MESSAGE_TEXT;",
    "IF code NOT IN ('FEATURE_UNAVAILABLE','MODULE_UNAVAILABLE','VALIDATION_ERROR','ACCESS_DENIED','PARTICIPANT_OUT_OF_SCOPE','APPOINTMENT_OVERLAP','SIGNED_COPY_REQUIRED','RETURN_BEFORE_HANDOVER','RETURN_EXCEEDS_HANDOVER') THEN RAISE; END IF;",
    "RETURN jsonb_build_object('error',code); END $probe$;"].join('\n'));
  const call=(kind,args)=>JSON.parse(sql("SELECT isg_module_test.observe("+quote(kind)+","+json(args)+");").split('\n').at(-1));
  const ok=(kind,args)=>{const r=call(kind,args);if(r.error)throw Error('AUTH_RESTORE_MODULE_UNEXPECTED_'+r.error);return r.result;};

  const planArgs=(over={})=>({company:companyID,workplace,plan:null,scope:'Ana üretim binası',prepared_on:'2026-03-01',
    valid_until:'2027-03-01',team:[{name:'Ekip Lideri',role:'söndürme'}],asset:null,review_note:null,now:now(0),...over});
  mark('gate_blocks_every_module_while_rollout_off',call('plan',planArgs()).error==='FEATURE_UNAVAILABLE');
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='modules';");
  mark('a_module_stays_closed_until_its_own_switch_is_open',call('plan',planArgs()).error==='MODULE_UNAVAILABLE');
  const privileges=sql("SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role','PUBLIC'); SELECT count(*) FROM pg_tables WHERE schemaname='private_isg' AND NOT rowsecurity; SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND p.proname IN ('module_gate','module_scope','publish_emergency_plan','plan_drill','record_drill_result','set_equipment_inspection_rule','register_equipment','record_equipment_inspection','record_appointment','end_appointment','record_ppe_handover','record_ppe_return') AND (has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE') OR has_function_privilege('service_role',p.oid,'EXECUTE'));").split('\n');
  mark('module_tables_have_rls_and_no_client_grant',privileges[0]==='0'&&privileges[1]==='0'&&privileges[2]==='0');
  sql("UPDATE private_isg.module_registry SET read_enabled=true,write_enabled=true;");

  const first=ok('plan',planArgs());
  mark('an_unverified_legal_basis_stays_in_review',first.version===1&&first.needs_review===true&&first.state==='active');
  const reviewed=ok('plan',planArgs({plan:first.plan_id,scope:'Ana üretim binası ve depo',prepared_on:'2026-08-01',
    valid_until:'2027-08-01',team:[{name:'Yeni Ekip Lideri',role:'söndürme'}],asset,review_note:'Mevzuat maddesi kontrol edildi ve kaydedildi.',now:now(1)}));
  mark('a_renewal_is_a_new_version_not_an_edit',reviewed.version===2&&reviewed.previous_version===1&&reviewed.needs_review===false&&
    sql("SELECT scope||':'||prepared_on||':'||state FROM private_isg.emergency_plan_versions WHERE plan_id="+quote(first.plan_id)+" AND version=1;")==='Ana üretim binası:2026-03-01:superseded'&&
    sql("SELECT count(*) FROM private_isg.emergency_plan_versions WHERE plan_id="+quote(first.plan_id)+" AND state='active';")==='1');
  mark('an_unknown_plan_can_not_be_versioned',call('plan',planArgs({plan:randomUUID(),now:now(2)})).error==='ACCESS_DENIED');
  mark('a_validity_before_preparation_is_refused',call('plan',planArgs({valid_until:'2026-02-01',now:now(3)})).error==='VALIDATION_ERROR');

  const drill=ok('drill_plan',{company:companyID,workplace,plan:first.plan_id,plan_version:2,planned_on:'2026-09-20',now:now(10)});
  mark('planning_a_drill_is_not_performing_one',drill.performed===false&&drill.state==='planned'&&
    sql("SELECT performed_on IS NULL AND participants IS NULL FROM private_isg.drill_records WHERE drill_id="+quote(drill.drill_id)+";")==='t');
  mark('a_drill_needs_a_real_plan_version',call('drill_plan',{company:companyID,workplace,plan:first.plan_id,plan_version:9,planned_on:'2026-09-20',now:now(11)}).error==='ACCESS_DENIED');
  mark('a_participant_from_outside_the_company_is_refused',call('drill_result',{drill:drill.drill_id,performed_on:'2026-09-21',
    participants:[employees[0],randomUUID()],observation:null,improvement:null,now:now(12)}).error==='PARTICIPANT_OUT_OF_SCOPE');
  const performed=ok('drill_result',{drill:drill.drill_id,performed_on:'2026-09-21',participants:[employees[0],employees[1]],
    observation:'Tahliye 4 dakikada tamamlandı.',improvement:'Kuzey kapısı işaretlenecek.',now:now(13)});
  mark('a_performed_drill_records_its_participants',performed.participants===2&&performed.state==='performed'&&
    ok('drill_result',{drill:drill.drill_id,performed_on:'2026-09-22',participants:[employees[0]],observation:null,improvement:null,now:now(14)}).replayed===true&&
    sql("SELECT performed_on FROM private_isg.drill_records WHERE drill_id="+quote(drill.drill_id)+";")==='2026-09-21');

  const crane=ok('equipment',{company:companyID,workplace,type:'crane',serial:'CR-001',acquired_on:'2024-01-10',now:now(20)});
  const ladder=ok('equipment',{company:companyID,workplace,type:'ladder',serial:'LD-001',acquired_on:'2025-05-05',now:now(21)});
  mark('equipment_is_registered_once_per_serial',ok('equipment',{company:companyID,workplace,type:'crane',serial:'CR-001',acquired_on:'2024-01-10',now:now(22)}).replayed===true&&
    sql("SELECT count(*) FROM private_isg.equipment_items WHERE company_id="+quote(companyID)+";")==='2');
  const noRule=ok('inspection',{equipment:ladder.equipment_id,performed_on:'2026-06-01',result:'pass',asset:null,external_ref:null,note:null,now:now(23)});
  mark('without_a_type_rule_no_due_date_is_invented',noRule.next_due_on===null&&noRule.period_months===null&&noRule.period_needs_review===true);
  ok('equipment_rule',{company:companyID,type:'crane',period_months:3,source:'manufacturer',exception:'Üretici el kitabı 3 ayda bir kontrol istiyor.',now:now(24)});
  const fixture=ok('equipment_rule',{company:companyID,type:'ladder',period_months:12,source:'unapproved_fixture',exception:null,now:now(25)});
  mark('every_equipment_type_carries_its_own_period',fixture.needs_review===true&&
    sql("SELECT period_months||':'||period_source FROM private_isg.equipment_inspection_rules WHERE company_id="+quote(companyID)+" AND equipment_type='crane';")==='3:manufacturer'&&
    sql("SELECT count(DISTINCT period_months) FROM private_isg.equipment_inspection_rules WHERE company_id="+quote(companyID)+";")==='2');
  const craneInspection=ok('inspection',{equipment:crane.equipment_id,performed_on:'2026-06-01',result:'pass',asset,external_ref:'TUV-77',note:null,now:now(26)});
  mark('the_due_date_follows_the_type_period_in_calendar_months',craneInspection.next_due_on==='2026-09-01'&&craneInspection.period_months===3&&
    craneInspection.exception_note==='Üretici el kitabı 3 ayda bir kontrol istiyor.');
  const failed=ok('inspection',{equipment:crane.equipment_id,performed_on:'2026-09-02',result:'fail',asset:null,external_ref:null,note:'Halat yıpranmış.',now:now(27)});
  mark('a_failed_inspection_schedules_no_next_period',failed.next_due_on===null&&
    ok('inspection',{equipment:crane.equipment_id,performed_on:'2026-09-02',result:'fail',asset:null,external_ref:null,note:null,now:now(28)}).replayed===true&&
    sql("SELECT count(*) FROM private_isg.equipment_inspections WHERE equipment_id="+quote(crane.equipment_id)+";")==='2');
  mark('an_unclean_evidence_document_is_refused',call('inspection',{equipment:crane.equipment_id,performed_on:'2026-10-01',result:'pass',asset:randomUUID(),external_ref:null,note:null,now:now(29)}).error==='ACCESS_DENIED');

  const appointment=ok('appointment',{company:companyID,employee:employees[0],kind:'representative',workplace,
    starts_on:'2026-01-01',ends_before:null,asset,now:now(40)});
  mark('an_appointment_records_its_scope_and_period',!!appointment.appointment_id&&appointment.kind==='representative');
  mark('the_same_person_can_not_hold_two_overlapping_appointments',call('appointment',{company:companyID,employee:employees[0],
    kind:'representative',workplace,starts_on:'2026-06-01',ends_before:null,asset:null,now:now(41)}).error==='APPOINTMENT_OVERLAP');
  mark('a_different_kind_or_person_is_not_a_conflict',!!ok('appointment',{company:companyID,employee:employees[0],kind:'first_aid',
    workplace,starts_on:'2026-06-01',ends_before:null,asset:null,now:now(42)}).appointment_id&&
    !!ok('appointment',{company:companyID,employee:employees[1],kind:'representative',workplace,starts_on:'2026-06-01',ends_before:null,asset:null,now:now(43)}).appointment_id);
  const ended=ok('appointment_end',{appointment:appointment.appointment_id,ends_before:'2026-05-01',now:now(44)});
  mark('ending_an_appointment_frees_the_period',ended.ends_before==='2026-05-01'&&
    ok('appointment_end',{appointment:appointment.appointment_id,ends_before:'2026-05-01',now:now(45)}).replayed===true&&
    !!ok('appointment',{company:companyID,employee:employees[0],kind:'representative',workplace,starts_on:'2026-05-01',ends_before:null,asset:null,now:now(46)}).appointment_id);
  mark('an_end_before_the_start_is_refused',call('appointment_end',{appointment:appointment.appointment_id,ends_before:'2025-01-01',now:now(47)}).error==='VALIDATION_ERROR');
  mark('an_archived_or_foreign_employee_gets_no_appointment',call('appointment',{company:companyID,employee:randomUUID(),
    kind:'team_member',workplace,starts_on:'2026-01-01',ends_before:null,asset:null,now:now(48)}).error==='ACCESS_DENIED');

  const handoverArgs=(over={})=>({company:companyID,employee:employees[0],item:'Baret',quantity:2,unit:'piece',
    handed_on:'2026-04-01',asset:null,signed:false,external_ref:'PPE-1',now:now(50),...over});
  mark('a_non_positive_quantity_is_refused',call('ppe',handoverArgs({quantity:0,external_ref:'PPE-0'})).error==='VALIDATION_ERROR'&&
    call('ppe',handoverArgs({quantity:-1,external_ref:'PPE-neg'})).error==='VALIDATION_ERROR');
  mark('a_signature_is_never_assumed',call('ppe',handoverArgs({signed:true,asset:null,external_ref:'PPE-sign'})).error==='SIGNED_COPY_REQUIRED');
  const handover=ok('ppe',handoverArgs());
  mark('a_handover_is_recorded_once_per_reference',handover.signed_copy===false&&
    ok('ppe',handoverArgs({now:now(51)})).replayed===true&&
    sql("SELECT count(*) FROM private_isg.ppe_handovers WHERE company_id="+quote(companyID)+";")==='1');
  const signed=ok('ppe',handoverArgs({signed:true,asset,external_ref:'PPE-2',item:'Emniyet kemeri',quantity:1,now:now(52)}));
  mark('a_signed_copy_needs_its_document',signed.signed_copy===true&&
    sql("SELECT evidence_asset_id IS NOT NULL FROM private_isg.ppe_handovers WHERE handover_id="+quote(signed.handover_id)+";")==='t');
  mark('nothing_comes_back_before_it_was_handed_out',call('ppe_return',{handover:handover.handover_id,quantity:1,
    returned_on:'2026-03-01',condition:'reusable',note:null,now:now(53)}).error==='RETURN_BEFORE_HANDOVER');
  const returned=ok('ppe_return',{handover:handover.handover_id,quantity:1,returned_on:'2026-05-01',condition:'worn',note:null,now:now(54)});
  mark('a_partial_return_leaves_the_rest_outstanding',Number(returned.outstanding)===1&&Number(returned.returned_total)===1);
  mark('more_can_not_come_back_than_went_out',call('ppe_return',{handover:handover.handover_id,quantity:2,
    returned_on:'2026-05-02',condition:'lost',note:null,now:now(55)}).error==='RETURN_EXCEEDS_HANDOVER');

  sql("UPDATE private_isg.module_registry SET write_enabled=false WHERE module='ppe';");
  mark('one_module_can_be_paused_without_touching_another',call('ppe',handoverArgs({external_ref:'PPE-3',now:now(60)})).error==='MODULE_UNAVAILABLE'&&
    !!ok('equipment',{company:companyID,workplace,type:'ladder',serial:'LD-002',acquired_on:null,now:now(61)}).equipment_id);
  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='modules';");
  mark('kill_switch_stops_every_module_at_once',call('equipment',{company:companyID,workplace,type:'ladder',serial:'LD-003',acquired_on:null,now:now(62)}).error==='FEATURE_UNAVAILABLE'&&
    call('plan',planArgs({now:now(63)})).error==='FEATURE_UNAVAILABLE');
  return {afterLogout(){
    return {migration_file:moduleCoreFiles[0],exact_migration_executed:true,rollout_left_disabled:true,
      client_grant_added:false,modules_implemented:['emergency_plan','drill','equipment','ppe','appointment'],
      modules_remaining:['isgkatip_contract','annual_work_plan','annual_training_plan','board_meeting',
        'approved_notebook','work_permit','contractor_package','site_visit','document_centre','portfolio','product_guidance'],
      document_export_implemented:false,production_deployed:false};
  }};
}
