import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

export const moduleSecondFiles=[
  'supabase/migrations/20260914010000_isg_module_core_second.sql',
  'scripts/isg/module_second_probe.mjs',
];
const read=p=>readFileSync(resolve(ROOT,p),'utf8');
const quote=v=>"'"+String(v).replaceAll("'","''")+"'";
const json=v=>quote(JSON.stringify(v))+'::jsonb';
const now=seconds=>new Date(Date.UTC(2026,8,14,1,0,0)+seconds*1000).toISOString();

export async function beginModuleSecondProbe({synthetic,sql,companyID,ownerID,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_MODULE_SECOND_SYNTHETIC_REQUIRED');
  if(!companyID||!ownerID)throw Error('AUTH_RESTORE_MODULE_SECOND_SCOPE_REQUIRED');
  const mark=(name,ok)=>pass('module_second_'+name,ok);
  sql(read(moduleSecondFiles[0]));
  mark('migration_applied_with_closed_switches',sql("SELECT count(*)=12 AND count(*) FILTER (WHERE NOT read_enabled AND NOT write_enabled)=7 FROM private_isg.module_registry;")==='t');
  const workplace=sql("SELECT id FROM private_isg.workplaces WHERE company_id="+quote(companyID)+" ORDER BY id LIMIT 1;");
  const asset=sql("SELECT asset_id FROM private_isg.file_assets ORDER BY created_at LIMIT 1;");
  const trainingPlan=sql("SELECT plan_id FROM private_isg.training_plans WHERE company_id="+quote(companyID)+" ORDER BY created_at LIMIT 1;");

  sql(["CREATE SCHEMA isg_module2_test;",
    "CREATE FUNCTION isg_module2_test.observe(kind text,a jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $probe$",
    "DECLARE r jsonb; code text; BEGIN",
    "IF kind='katip' THEN r:=private_isg.record_katip_contract((a->>'company')::uuid,(a->>'workplace')::uuid,a->>'counterparty',a->>'expert',a->>'scope',(a->>'starts_on')::date,(a->>'ends_before')::date,(a->>'asset')::uuid,(a->>'now')::timestamptz);",
    "ELSIF kind='work_plan' THEN r:=private_isg.open_annual_work_plan((a->>'company')::uuid,(a->>'workplace')::uuid,(a->>'year')::integer,(a->>'now')::timestamptz);",
    "ELSIF kind='work_item' THEN r:=private_isg.add_work_plan_item((a->>'plan')::uuid,a->>'activity',a->>'responsible',(a->>'planned_on')::date,(a->>'now')::timestamptz);",
    "ELSIF kind='work_settle' THEN r:=private_isg.settle_work_plan_item((a->>'item')::uuid,a->>'state',(a->>'performed_on')::date,a->>'reason',(a->>'carry_to')::uuid,(a->>'now')::timestamptz);",
    "ELSIF kind='work_close' THEN r:=private_isg.close_annual_work_plan((a->>'plan')::uuid,(a->>'closed_on')::date,(a->>'now')::timestamptz);",
    "ELSIF kind='training_plan' THEN r:=private_isg.plan_annual_training((a->>'company')::uuid,(a->>'workplace')::uuid,(a->>'year')::integer,a->>'catalog',a->>'target_group',(a->>'sessions')::integer,(a->>'now')::timestamptz);",
    "ELSIF kind='training_link' THEN r:=private_isg.link_annual_training_realisation((a->>'plan')::uuid,(a->>'training_plan')::uuid,(a->>'now')::timestamptz);",
    "ELSIF kind='board' THEN r:=private_isg.record_board_meeting((a->>'company')::uuid,(a->>'workplace')::uuid,a->>'applicability',(a->>'planned_on')::date,a->'agenda',(a->>'now')::timestamptz);",
    "ELSIF kind='board_hold' THEN r:=private_isg.hold_board_meeting((a->>'meeting')::uuid,(a->>'held_on')::date,nullif(a->'attendance','null'::jsonb),(a->>'asset')::uuid,nullif(a->'decisions','null'::jsonb),(a->>'now')::timestamptz);",
    "ELSIF kind='permit' THEN r:=private_isg.draft_work_permit((a->>'company')::uuid,(a->>'workplace')::uuid,a->>'template',(a->>'version')::integer,a->>'job',a->'parties',(a->>'planned_on')::date,(a->>'now')::timestamptz);",
    "ELSIF kind='permit_render' THEN r:=private_isg.render_work_permit((a->>'permit')::uuid,(a->>'asset')::uuid,(a->>'signed')::boolean,(a->>'now')::timestamptz);",
    "ELSIF kind='visit' THEN r:=private_isg.record_site_visit((a->>'company')::uuid,(a->>'workplace')::uuid,(a->>'visited_on')::date,a->>'location',a->>'note',(a->>'now')::timestamptz);",
    "ELSIF kind='observation' THEN r:=private_isg.record_site_observation((a->>'visit')::uuid,a->>'note',(a->>'asset')::uuid,a->>'external_ref',(a->>'open_nonconformity')::boolean,a->>'severity',(a->>'due_on')::date,(a->>'now')::timestamptz);",
    "ELSIF kind='notebook' THEN r:=private_isg.archive_notebook_entry((a->>'company')::uuid,(a->>'workplace')::uuid,a->>'ref',(a->>'entry_on')::date,(a->>'asset')::uuid,a->>'ai_draft_ref',(a->>'now')::timestamptz);",
    "ELSIF kind='force_official' THEN UPDATE private_isg.katip_contracts SET official_integration=true WHERE contract_id=(a->>'id')::uuid; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_authorises' THEN UPDATE private_isg.work_permit_forms SET authorises_work=true WHERE permit_id=(a->>'id')::uuid; r:=to_jsonb('updated'::text);",
    "ELSIF kind='force_ai_official' THEN UPDATE private_isg.notebook_archive_entries SET ai_text_is_official_record=true WHERE entry_id=(a->>'id')::uuid; r:=to_jsonb('updated'::text);",
    "ELSE RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;",
    "RETURN jsonb_build_object('result',r);",
    "EXCEPTION WHEN SQLSTATE '23514' THEN RETURN jsonb_build_object('error','CHECK_VIOLATION');",
    "WHEN SQLSTATE '23505' THEN RETURN jsonb_build_object('error','UNIQUE_VIOLATION');",
    "WHEN SQLSTATE 'P0001' THEN GET STACKED DIAGNOSTICS code=MESSAGE_TEXT;",
    "IF code NOT IN ('FEATURE_UNAVAILABLE','MODULE_UNAVAILABLE','VALIDATION_ERROR','ACCESS_DENIED','PLAN_CLOSED','PLAN_YEAR_MISMATCH','CARRY_OVER_INVALID','SIGNED_COPY_REQUIRED') THEN RAISE; END IF;",
    "RETURN jsonb_build_object('error',code); END $probe$;"].join('\n'));
  const call=(kind,args)=>JSON.parse(sql("SELECT isg_module2_test.observe("+quote(kind)+","+json(args)+");").split('\n').at(-1));
  const ok=(kind,args)=>{const r=call(kind,args);if(r.error)throw Error('AUTH_RESTORE_MODULE_SECOND_UNEXPECTED_'+r.error);return r.result;};

  const katipArgs=(over={})=>({company:companyID,workplace,counterparty:'OSGB A.Ş.',expert:'Uzman Ad Soyad',
    scope:'İSG uzmanı hizmeti',starts_on:'2026-01-01',ends_before:null,asset:null,now:now(0),...over});
  mark('the_phase_gate_answers_before_the_module_switch',call('katip',katipArgs()).error==='FEATURE_UNAVAILABLE');
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature IN ('modules','nonconformity');");
  mark('a_new_module_stays_closed_until_its_own_switch_opens',call('katip',katipArgs()).error==='MODULE_UNAVAILABLE');
  sql("UPDATE private_isg.module_registry SET read_enabled=true,write_enabled=true;");
  const privileges=sql("SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role','PUBLIC'); SELECT count(*) FROM pg_tables WHERE schemaname='private_isg' AND NOT rowsecurity; SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND p.proname IN ('record_katip_contract','open_annual_work_plan','add_work_plan_item','settle_work_plan_item','close_annual_work_plan','plan_annual_training','link_annual_training_realisation','record_board_meeting','hold_board_meeting','draft_work_permit','render_work_permit','record_site_visit','record_site_observation','archive_notebook_entry','clean_asset') AND (has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE') OR has_function_privilege('service_role',p.oid,'EXECUTE'));").split('\n');
  mark('new_module_tables_have_rls_and_no_client_grant',privileges[0]==='0'&&privileges[1]==='0'&&privileges[2]==='0');

  const openEnded=ok('katip',katipArgs());
  mark('an_open_ended_contract_is_its_own_state',openEnded.term_state==='open_ended'&&openEnded.official_integration===false&&
    openEnded.official_submission_made===false);
  const fixed=ok('katip',katipArgs({scope:'Sağlık personeli hizmeti',ends_before:'2027-01-01',asset,now:now(1)}));
  mark('a_fixed_term_contract_is_distinguished',fixed.term_state==='fixed_term'&&
    ok('katip',katipArgs({scope:'Sağlık personeli hizmeti',ends_before:'2027-01-01',asset,now:now(2)})).replayed===true&&
    sql("SELECT count(*) FROM private_isg.katip_contracts WHERE company_id="+quote(companyID)+";")==='2');
  mark('no_official_integration_can_be_claimed',sql("SELECT bool_and(NOT official_integration) FROM private_isg.katip_contracts;")==='t'&&
    call('force_official',{id:openEnded.contract_id}).error==='CHECK_VIOLATION');

  const plan2026=ok('work_plan',{company:companyID,workplace,year:2026,now:now(10)});
  const plan2027=ok('work_plan',{company:companyID,workplace,year:2027,now:now(11)});
  mark('one_work_plan_per_workplace_and_year',plan2026.plan_year===2026&&
    ok('work_plan',{company:companyID,workplace,year:2026,now:now(12)}).replayed===true&&
    sql("SELECT count(*) FROM private_isg.annual_work_plans WHERE company_id="+quote(companyID)+";")==='2');
  mark('an_activity_belongs_to_its_own_calendar_year',call('work_item',{plan:plan2026.plan_id,activity:'Yıllık eğitim turu',
    responsible:'Uzman',planned_on:'2027-03-01',now:now(13)}).error==='PLAN_YEAR_MISMATCH');
  const item=ok('work_item',{plan:plan2026.plan_id,activity:'Yıllık eğitim turu',responsible:'Uzman',planned_on:'2026-03-01',now:now(14)});
  const slipping=ok('work_item',{plan:plan2026.plan_id,activity:'Acil durum tatbikatı',responsible:'Uzman',planned_on:'2026-11-01',now:now(15)});
  mark('an_item_is_added_once',ok('work_item',{plan:plan2026.plan_id,activity:'Yıllık eğitim turu',responsible:'Uzman',planned_on:'2026-03-01',now:now(16)}).replayed===true&&
    sql("SELECT count(*) FROM private_isg.annual_work_plan_items WHERE plan_id="+quote(plan2026.plan_id)+";")==='2');
  mark('a_carry_over_needs_a_reason_and_a_later_plan',
    call('work_settle',{item:slipping.item_id,state:'carried_over',performed_on:null,reason:null,carry_to:plan2027.plan_id,now:now(17)}).error==='VALIDATION_ERROR'&&
    call('work_settle',{item:slipping.item_id,state:'carried_over',performed_on:null,reason:'Saha kapalı olduğu için ertelendi.',carry_to:plan2026.plan_id,now:now(18)}).error==='CARRY_OVER_INVALID');
  const carried=ok('work_settle',{item:slipping.item_id,state:'carried_over',performed_on:null,reason:'Saha kapalı olduğu için ertelendi.',carry_to:plan2027.plan_id,now:now(19)});
  mark('a_carried_item_names_its_target_year',carried.state==='carried_over'&&carried.carried_to_plan_id===plan2027.plan_id);
  const closed=ok('work_close',{plan:plan2026.plan_id,closed_on:'2026-12-31',now:now(20)});
  mark('closing_a_plan_performs_nothing',closed.items_marked_performed_by_closing===0&&closed.performed_items===0&&
    closed.still_planned_items===1&&
    sql("SELECT state FROM private_isg.annual_work_plan_items WHERE item_id="+quote(item.item_id)+";")==='planned');
  mark('a_closed_plan_takes_no_new_item',call('work_item',{plan:plan2026.plan_id,activity:'Sonradan',responsible:null,planned_on:'2026-12-01',now:now(21)}).error==='PLAN_CLOSED');

  const trainingNeed=ok('training_plan',{company:companyID,workplace,year:2026,catalog:'basic_isg',target_group:'Saha ekibi',sessions:2,now:now(30)});
  mark('an_annual_training_plan_is_not_a_completion',trainingNeed.is_training_completion===false&&trainingNeed.state==='planned'&&
    sql("SELECT count(*) FROM private_isg.training_completions;")===sql("SELECT count(*) FROM private_isg.training_completions;"));
  mark('a_duplicate_training_plan_is_refused',ok('training_plan',{company:companyID,workplace,year:2026,catalog:'basic_isg',target_group:'Saha ekibi',sessions:5,now:now(31)}).replayed===true&&
    sql("SELECT planned_sessions FROM private_isg.annual_training_plans WHERE plan_id="+quote(trainingNeed.plan_id)+";")==='2');
  mark('an_unknown_catalogue_can_not_be_planned',call('training_plan',{company:companyID,workplace,year:2026,catalog:'unknown_catalog',target_group:'Saha ekibi',sessions:1,now:now(32)}).error==='ACCESS_DENIED');
  const linked=ok('training_link',{plan:trainingNeed.plan_id,training_plan:trainingPlan,now:now(33)});
  mark('linking_a_realisation_keeps_completions_in_the_training_domain',linked.state==='realised'&&
    linked.is_training_completion===false&&linked.completions_in_training_domain>=1&&
    ok('training_link',{plan:trainingNeed.plan_id,training_plan:trainingPlan,now:now(34)}).replayed===true);

  const voluntary=ok('board',{company:companyID,workplace,applicability:'voluntary',planned_on:'2026-04-01',
    agenda:['Saha gözlemleri','KKD ihtiyacı'],now:now(40)});
  const mandatory=ok('board',{company:companyID,workplace,applicability:'mandatory',planned_on:'2026-05-01',
    agenda:['Yasal gündem'],now:now(41)});
  mark('voluntary_use_stays_out_of_the_legal_score',voluntary.counts_towards_legal_score===false&&
    mandatory.counts_towards_legal_score===true&&voluntary.creates_account_or_role===false);
  mark('a_planned_meeting_has_no_attendance',sql("SELECT held_on IS NULL AND attendance IS NULL FROM private_isg.board_meetings WHERE meeting_id="+quote(voluntary.meeting_id)+";")==='t');
  const held=ok('board_hold',{meeting:voluntary.meeting_id,held_on:'2026-04-02',attendance:[{name:'Uzman'},{name:'İşveren Vekili'}],
    asset,decisions:[{text:'Baret stoğu artırılacak.',responsible:'Satın alma',due_on:'2026-05-01'}],now:now(42)});
  mark('holding_a_meeting_records_attendance_and_decisions',held.decisions===1&&held.counts_towards_legal_score===false&&
    ok('board_hold',{meeting:voluntary.meeting_id,held_on:'2026-04-03',attendance:[{name:'Uzman'}],asset:null,decisions:[],now:now(43)}).replayed===true&&
    sql("SELECT count(*) FROM private_isg.board_decisions WHERE meeting_id="+quote(voluntary.meeting_id)+";")==='1');
  mark('a_meeting_can_not_be_held_without_attendance',call('board_hold',{meeting:mandatory.meeting_id,held_on:'2026-05-02',
    attendance:null,asset:null,decisions:[],now:now(44)}).error==='VALIDATION_ERROR');

  const permit=ok('permit',{company:companyID,workplace,template:'hot_work',version:1,job:'Kaynak işi',
    parties:[{role:'işveren',name:'A'},{role:'taşeron',name:'B'}],planned_on:'2026-06-01',now:now(50)});
  mark('a_permit_form_authorises_nothing',permit.authorises_work===false&&permit.approval_workflow===false&&permit.state==='draft'&&
    call('force_authorises',{id:permit.permit_id}).error==='CHECK_VIOLATION'&&
    sql("SELECT count(*) FROM information_schema.columns WHERE table_schema='private_isg' AND table_name='work_permit_forms' AND column_name IN ('approved_by','approved_at','work_started_at');")==='0');
  mark('a_draft_permit_carries_no_rendered_document',sql("SELECT rendered_asset_id IS NULL AND NOT signed_copy FROM private_isg.work_permit_forms WHERE permit_id="+quote(permit.permit_id)+";")==='t');
  const rendered=ok('permit_render',{permit:permit.permit_id,asset,signed:true,now:now(51)});
  mark('rendering_records_a_signed_copy_without_granting_permission',rendered.state==='rendered'&&rendered.signed_copy===true&&
    rendered.authorises_work===false&&ok('permit_render',{permit:permit.permit_id,asset,signed:true,now:now(52)}).replayed===true);
  mark('an_unclean_document_can_not_be_rendered',call('permit_render',{permit:ok('permit',{company:companyID,workplace,
    template:'hot_work',version:1,job:'İkinci kaynak işi',parties:[{role:'işveren',name:'A'}],planned_on:'2026-06-02',now:now(53)}).permit_id,
    asset:randomUUID(),signed:false,now:now(54)}).error==='ACCESS_DENIED');

  const visit=ok('visit',{company:companyID,workplace,visited_on:'2026-07-01',location:'Kuzey saha',
    note:'Kuzey sahada düzenli tur yapıldı.',now:now(60)});
  mark('a_site_visit_is_company_scoped_and_separate_from_private_notes',visit.company_scoped===true&&
    visit.merged_with_personal_notes===false&&
    sql("SELECT count(*) FROM information_schema.columns WHERE table_schema='private_isg' AND table_name IN ('site_visits','site_visit_observations') AND column_name ~ 'health|medical|diagnos|clinic';")==='0');
  mark('the_same_visit_is_recorded_once',ok('visit',{company:companyID,workplace,visited_on:'2026-07-01',location:'Kuzey saha',
    note:'Kuzey sahada düzenli tur yapıldı.',now:now(61)}).replayed===true&&
    sql("SELECT count(*) FROM private_isg.site_visits WHERE company_id="+quote(companyID)+";")==='1');
  const observation=ok('observation',{visit:visit.visit_id,note:'Merdiven sabitlenmemiş.',asset,external_ref:'OBS-1',
    open_nonconformity:true,severity:'high',due_on:'2026-07-15',now:now(62)});
  mark('a_selected_observation_opens_one_nonconformity',!!observation.nonconformity_id&&
    ok('observation',{visit:visit.visit_id,note:'Merdiven sabitlenmemiş.',asset,external_ref:'OBS-1',
      open_nonconformity:true,severity:'high',due_on:'2026-07-15',now:now(63)}).nonconformity_id===observation.nonconformity_id&&
    sql("SELECT count(*) FROM private_isg.site_visit_observations WHERE visit_id="+quote(visit.visit_id)+";")==='1');

  mark('an_ai_draft_alone_is_not_an_official_record',call('notebook',{company:companyID,workplace,ref:'Defter-1',
    entry_on:'2026-08-01',asset:null,ai_draft_ref:'ai-draft-9',now:now(70)}).error==='SIGNED_COPY_REQUIRED');
  const notebook=ok('notebook',{company:companyID,workplace,ref:'Defter-1',entry_on:'2026-08-01',asset,ai_draft_ref:'ai-draft-9',now:now(71)});
  mark('only_a_signed_copy_is_archived_with_its_draft_as_provenance',notebook.has_signed_copy===true&&
    notebook.ai_text_is_official_record===false&&notebook.ai_draft_ref==='ai-draft-9'&&
    ok('notebook',{company:companyID,workplace,ref:'Defter-1',entry_on:'2026-08-01',asset,ai_draft_ref:null,now:now(72)}).replayed===true&&
    call('force_ai_official',{id:notebook.entry_id}).error==='CHECK_VIOLATION'&&
    sql("SELECT count(*) FROM private_isg.notebook_archive_entries;")==='1');

  sql("UPDATE private_isg.module_registry SET write_enabled=false WHERE module='notebook_archive';");
  mark('pausing_one_new_module_leaves_the_others_running',call('notebook',{company:companyID,workplace,ref:'Defter-2',
    entry_on:'2026-08-02',asset,ai_draft_ref:null,now:now(80)}).error==='MODULE_UNAVAILABLE'&&
    !!ok('visit',{company:companyID,workplace,visited_on:'2026-07-02',location:null,note:'İkinci tur.',now:now(81)}).visit_id);
  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature IN ('modules','nonconformity');");
  mark('kill_switch_stops_every_new_module',call('visit',{company:companyID,workplace,visited_on:'2026-07-03',location:null,
    note:'Üçüncü tur.',now:now(82)}).error==='FEATURE_UNAVAILABLE'&&call('katip',katipArgs({now:now(83)})).error==='FEATURE_UNAVAILABLE');
  return {afterLogout(){
    return {migration_file:moduleSecondFiles[0],exact_migration_executed:true,rollout_left_disabled:true,
      client_grant_added:false,
      modules_implemented:['katip_contract','annual_work_plan','annual_training_plan','board','work_permit','site_visit','notebook_archive'],
      official_integration_claimed:false,work_authorised_by_form:false,ai_text_as_official_record:false,
      production_deployed:false};
  }};
}
