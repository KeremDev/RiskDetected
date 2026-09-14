import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

export const equipmentChecksFiles=[
  'supabase/migrations/20260915030000_isg_equipment_checks.sql',
  'supabase/migrations/20260915050000_isg_equipment_periods.sql',
  'supabase/migrations/20260915070000_isg_equipment_inspection_edit.sql',
  'scripts/isg/equipment_checks_probe.mjs',
];
// The general period the product now starts every type at.
const DEFAULT_PERIOD_MONTHS=12;
const read=p=>readFileSync(resolve(ROOT,p),'utf8');
const quote=v=>"'"+String(v).replaceAll("'","''")+"'";

// Hand-computed, never a second call into the production expression. The page
// warns thirty days ahead, so a check that runs out in ten days is 'due_soon',
// one that ran out yesterday is 'overdue' and one good for another year is
// 'valid'. A twelve-month period added to a report date is what the server
// must produce; 365 days is added here by hand rather than read back.
const NOTICE_DAYS=30,DUE_SOON_IN=10,OVERDUE_BY=1;
const CRANE_PERIOD_MONTHS=12,COMPRESSOR_PERIOD_MONTHS=6;
// The page shows ten rows at a time, so the fixture has to carry more than ten.
const PAGE_SIZE=10,FILLER_ROWS=8;
const day=(anchor,offset)=>{
  const value=new Date(Date.UTC(anchor.y,anchor.m-1,anchor.d));
  value.setUTCDate(value.getUTCDate()+offset);
  return value.toISOString().slice(0,10);
};
const addMonths=(anchor,months)=>{
  const value=new Date(Date.UTC(anchor.y,anchor.m-1,anchor.d));
  value.setUTCMonth(value.getUTCMonth()+months);
  return value.toISOString().slice(0,10);
};

export async function beginEquipmentChecksProbe({synthetic,sql,request,companyID,ownerID,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_EQUIPMENT_CHECKS_SYNTHETIC_REQUIRED');
  if(!companyID||!ownerID||typeof request!=='function')throw Error('AUTH_RESTORE_EQUIPMENT_CHECKS_SCOPE_REQUIRED');
  const mark=(name,ok)=>pass('equipment_checks_'+name,ok);
  sql(read(equipmentChecksFiles[0]));
  sql(read(equipmentChecksFiles[1]));
  sql(read(equipmentChecksFiles[2]));

  mark('the_slice_adds_no_switch_of_its_own',
    // It rides on the switches P10 already created rather than inventing a
    // third one, so there is nothing new here that could be left half open.
    sql("SELECT count(*) FROM private_isg.rollout WHERE feature='equipment';")==='0'&&
    sql("SELECT count(*) FROM private_isg.module_registry WHERE module='equipment';")==='1');
  mark('every_new_table_is_private_and_row_secured',
    sql("SELECT count(*) FROM pg_tables WHERE schemaname='private_isg' AND rowsecurity AND tablename IN ('equipment_type_suggestions','equipment_check_receipts');")==='2'&&
    sql("SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role','PUBLIC');")==='0');
  // Every type now starts at a period, and every one of those defaults carries
  // the basis it rests on. A period with no story behind it cannot be seeded.
  mark('every_type_starts_at_a_period_and_every_default_carries_its_basis',
    sql("SELECT count(*) FROM private_isg.equipment_type_suggestions;")==='20'&&
    sql("SELECT count(*) FROM private_isg.equipment_default_periods;")==='20'&&
    sql("SELECT count(*) FROM private_isg.equipment_default_periods WHERE period_months<>"+DEFAULT_PERIOD_MONTHS+";")==='0'&&
    sql("SELECT count(*) FROM private_isg.equipment_default_periods WHERE length(btrim(basis_note))<20;")==='0');
  // A default is the product's, never the expert's own determination: the
  // schema refuses to store one that is not flagged for their confirmation.
  sql(`DO $$ BEGIN
    INSERT INTO private_isg.equipment_inspection_rules(company_id,equipment_type,period_months,
      period_source,needs_review) VALUES(gen_random_uuid(),'crane',12,'regulation_default',false);
  EXCEPTION WHEN check_violation THEN NULL; END $$;`);
  mark('the_schema_refuses_an_unconfirmed_default_that_hides_its_flag',
    sql("SELECT count(*) FROM private_isg.equipment_inspection_rules WHERE period_source='regulation_default' AND NOT needs_review;")==='0');
  // This module is not a human health check, and the schema has no code for one.
  mark('no_suggested_type_is_a_health_record',
    sql("SELECT count(*) FROM private_isg.equipment_type_suggestions WHERE equipment_type ~ '(health|medical|saglik|muayene|person|employee)';")==='0');
  sql(`DO $$ BEGIN
    INSERT INTO private_isg.equipment_type_suggestions(equipment_type,ordinal) VALUES('health_check',900);
  EXCEPTION WHEN check_violation THEN NULL; END $$;`);
  mark('the_schema_itself_refuses_a_health_type',
    sql("SELECT count(*) FROM private_isg.equipment_type_suggestions WHERE equipment_type='health_check';")==='0');
  // Nothing stores the answer, so no row can carry yesterday's.
  mark('no_column_stores_a_state_a_stale_row_could_claim',
    sql("SELECT count(*) FROM information_schema.columns WHERE table_schema='private_isg' AND table_name IN ('equipment_items','equipment_inspections') AND column_name IN ('status','state','is_due','is_overdue','is_compliant');")==='0');
  // The P10 slice already indexes (company_id, equipment_type); adding a second
  // identical one would be dead weight the advisor is right to flag.
  mark('the_slice_adds_no_index_that_duplicates_one_already_there',
    sql("SELECT count(*) FROM (SELECT regexp_replace(indexdef,'INDEX [a-z_]+ ON','INDEX ON') AS shape FROM pg_indexes WHERE schemaname='private_isg' AND tablename IN ('equipment_items','equipment_inspections') GROUP BY 1 HAVING count(*)>1) duplicated;")==='0');
  mark('the_boundary_exposes_exactly_two_functions_to_a_signed_in_account',
    sql("SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname LIKE 'isg_equipment%' AND has_function_privilege('authenticated',p.oid,'EXECUTE');")==='2');

  const post=(path,body,options={})=>request('/rpc/'+path,{method:'POST',body,...options});
  const readCall=(args={},options={})=>post('isg_equipment_checks_read_v1',
    {p_company:companyID,p_kind:'list',p_query:null,p_state:null,p_workplace:null,p_type:null,p_id:null,
     p_limit:PAGE_SIZE,p_offset:0,...args},options);
  const mutate=(action,payload,ids={},options={})=>post('isg_equipment_checks_mutate_v1',
    {p_company:companyID,p_action:action,p_operation:ids.operation??randomUUID(),
     p_mutation:ids.mutation??randomUUID(),p_payload:payload},options);

  const settle=ms=>Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,ms);
  let closed=null;
  for(let attempt=0;attempt<20;attempt++){
    try{ closed=readCall(); break; }catch{ settle(500); }
  }
  if(closed===null)throw Error('AUTH_RESTORE_EQUIPMENT_CHECKS_BOUNDARY_UNREACHABLE');

  // Two switches, and each one alone is not enough.
  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='modules';");
  sql("UPDATE private_isg.module_registry SET read_enabled=true,write_enabled=true WHERE module='equipment';");
  mark('the_phase_switch_alone_closes_the_module',
    readCall().body?.message==='FEATURE_UNAVAILABLE');
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='modules';");
  sql("UPDATE private_isg.module_registry SET read_enabled=false,write_enabled=false WHERE module='equipment';");
  mark('the_module_switch_alone_closes_the_module',
    readCall().body?.message==='MODULE_UNAVAILABLE'&&
    mutate('register_equipment',{workplace_id:randomUUID(),equipment_type:'crane',
      serial_tag:'KAPALI-1'}).body?.message==='MODULE_UNAVAILABLE');
  sql("UPDATE private_isg.module_registry SET read_enabled=true,write_enabled=true WHERE module='equipment';");

  const catalogue=readCall({p_kind:'catalog'});
  mark('the_catalogue_offers_a_default_period_and_says_what_it_is',
    catalogue.status===200&&catalogue.body.suggestions.length===20&&
    catalogue.body.period_defaults_offered===true&&
    catalogue.body.period_default_source==='regulation_default'&&
    catalogue.body.period_default_needs_review===true&&
    catalogue.body.katip_official_verification===false&&
    catalogue.body.health_records_tracked===false&&
    catalogue.body.notice_days===NOTICE_DAYS&&
    catalogue.body.suggestions.every(entry=>entry.default_period_months===DEFAULT_PERIOD_MONTHS&&
      typeof entry.default_basis_note==='string'&&entry.default_basis_note.length>=20));
  const workplace=catalogue.body.workplaces?.[0]?.id;
  if(!workplace)throw Error('AUTH_RESTORE_EQUIPMENT_CHECKS_WORKPLACE_MISSING');

  const stamp=sql('SELECT to_char((clock_timestamp() AT TIME ZONE \'UTC\')::date,\'YYYY-MM-DD\');');
  const anchor={y:Number(stamp.slice(0,4)),m:Number(stamp.slice(5,7)),d:Number(stamp.slice(8,10))};

  // An item with no inspection at all.
  const fresh=mutate('register_equipment',{workplace_id:workplace,equipment_type:'lifting_equipment',
    serial_tag:'VNC-001',acquired_on:day(anchor,-800),location_note:'Montaj hattı · 2. göz'});
  mark('an_item_with_no_inspection_reads_as_never_inspected',fresh.status===200&&
    fresh.body.row.state==='never_inspected'&&fresh.body.row.state_group==='untracked'&&
    fresh.body.row.state_authority==='computed_at_read'&&
    fresh.body.row.next_due_on===null&&
    fresh.body.row.location_note==='Montaj hattı · 2. göz'&&
    fresh.body.row.health_record===false);
  // Registering the item materialised the type's default as a real, visible,
  // editable company rule that is flagged for the expert's confirmation.
  mark('registering_an_item_starts_its_type_at_the_default_period',
    fresh.body.row.period_months===DEFAULT_PERIOD_MONTHS&&
    fresh.body.row.period_source==='regulation_default'&&
    fresh.body.row.period_needs_review===true&&
    typeof fresh.body.row.period_exception_note==='string');

  // The first report now produces a date on its own.
  const unruled=mutate('record_inspection',{equipment_id:fresh.body.equipment_id,
    performed_on:day(anchor,-30),result:'pass',inspector:'Dış kuruluş · A. Yılmaz',
    external_ref:'RPT-2026-0011'});
  mark('a_report_produces_the_next_date_by_itself_and_says_it_came_from_the_period',
    unruled.status===200&&
    unruled.body.row.next_due_on===addMonths({y:Number(day(anchor,-30).slice(0,4)),
      m:Number(day(anchor,-30).slice(5,7)),d:Number(day(anchor,-30).slice(8,10))},DEFAULT_PERIOD_MONTHS)&&
    unruled.body.row.due_source==='period'&&
    unruled.body.row.last_inspector==='Dış kuruluş · A. Yılmaz');
  // And a type the product has no default for still gets no date at all.
  sql("DELETE FROM private_isg.equipment_default_periods WHERE equipment_type='welding_set';");
  const undefaulted=mutate('register_equipment',{workplace_id:workplace,equipment_type:'welding_set',
    serial_tag:'KYN-001'});
  const noDefault=mutate('record_inspection',{equipment_id:undefaulted.body.equipment_id,
    performed_on:day(anchor,-5),result:'pass'});
  mark('a_type_with_no_default_still_never_invents_a_due_date',
    undefaulted.body.row.period_months===null&&
    noDefault.body.row.next_due_on===null&&noDefault.body.row.state==='period_unknown'&&
    noDefault.body.row.due_source===null);

  // The period belongs to the type, and the source travels with it.
  const rule=mutate('set_rule',{equipment_type:'crane',period_months:CRANE_PERIOD_MONTHS,
    period_source:'manufacturer'});
  mark('a_period_belongs_to_the_type_and_carries_where_it_came_from',rule.status===200&&
    rule.body.rule.period_months===CRANE_PERIOD_MONTHS&&
    rule.body.rule.period_source==='manufacturer'&&rule.body.rule.needs_review===false);
  const fixture=mutate('set_rule',{equipment_type:'compressor',period_months:COMPRESSOR_PERIOD_MONTHS,
    period_source:'unapproved_fixture',exception_note:'Uzmanın kendi belirlediği süre; kaynak onaylanmadı.'});
  mark('an_unapproved_period_is_flagged_for_review_and_cannot_hide_it',fixture.status===200&&
    fixture.body.rule.needs_review===true&&fixture.body.rule.period_source==='unapproved_fixture'&&
    sql("SELECT count(*) FROM private_isg.equipment_inspection_rules WHERE company_id="+quote(companyID)+" AND period_source='unapproved_fixture' AND NOT needs_review;")==='0');

  // A period that is not one fixed year for everything.
  const crane=mutate('register_equipment',{workplace_id:workplace,equipment_type:'crane',serial_tag:'KRN-001'});
  const craneCheck=mutate('record_inspection',{equipment_id:crane.body.equipment_id,
    performed_on:day(anchor,0),result:'pass',inspector:'TSE yetkili kuruluş'});
  const compressor=mutate('register_equipment',{workplace_id:workplace,equipment_type:'compressor',serial_tag:'KMP-001'});
  const compressorCheck=mutate('record_inspection',{equipment_id:compressor.body.equipment_id,
    performed_on:day(anchor,0),result:'pass'});
  mark('two_types_inspected_the_same_day_are_not_due_the_same_day',
    craneCheck.body.row.next_due_on===addMonths(anchor,CRANE_PERIOD_MONTHS)&&
    compressorCheck.body.row.next_due_on===addMonths(anchor,COMPRESSOR_PERIOD_MONTHS)&&
    craneCheck.body.row.next_due_on!==compressorCheck.body.row.next_due_on&&
    craneCheck.body.row.state==='valid'&&compressorCheck.body.row.state==='valid');

  // A failed check produces no due date at all.
  const broken=mutate('register_equipment',{workplace_id:workplace,equipment_type:'crane',serial_tag:'KRN-002'});
  const failed=mutate('record_inspection',{equipment_id:broken.body.equipment_id,
    performed_on:day(anchor,-3),result:'fail',note:'Fren testi olumsuz.'});
  mark('a_failed_check_produces_no_due_date_and_says_so',failed.status===200&&
    failed.body.row.state==='failed'&&failed.body.row.state_group==='failed'&&
    failed.body.row.next_due_on===null&&failed.body.row.last_result==='fail');

  // Due soon and overdue, worked out from the dates at read time.
  const soon=mutate('register_equipment',{workplace_id:workplace,equipment_type:'crane',serial_tag:'KRN-003'});
  const soonCheck=mutate('record_inspection',{equipment_id:soon.body.equipment_id,
    performed_on:addMonths({...anchor},-CRANE_PERIOD_MONTHS)===day(anchor,0)
      ? day(anchor,-360) : addMonths(anchor,-CRANE_PERIOD_MONTHS),result:'pass'});
  const late=mutate('register_equipment',{workplace_id:workplace,equipment_type:'crane',serial_tag:'KRN-004'});
  mutate('record_inspection',{equipment_id:late.body.equipment_id,
    performed_on:day(anchor,-400),result:'pass'});
  mark('a_check_that_ran_out_reads_as_overdue',
    readCall({p_kind:'detail',p_id:late.body.equipment_id}).body.row.state==='overdue');
  mark('a_check_inside_the_notice_window_reads_as_due_soon',(()=>{
    // The fixture is built by hand: a report exactly one period plus a little
    // in the past lands inside the thirty-day window.
    const target=mutate('register_equipment',{workplace_id:workplace,equipment_type:'crane',serial_tag:'KRN-005'});
    const performed=day({y:Number(addMonths(anchor,-CRANE_PERIOD_MONTHS).slice(0,4)),
      m:Number(addMonths(anchor,-CRANE_PERIOD_MONTHS).slice(5,7)),
      d:Number(addMonths(anchor,-CRANE_PERIOD_MONTHS).slice(8,10))},DUE_SOON_IN);
    const answer=mutate('record_inspection',{equipment_id:target.body.equipment_id,
      performed_on:performed,result:'pass'});
    return answer.body.row.state==='due_soon'&&answer.body.row.state_group==='due_soon';
  })());
  void soonCheck; void OVERDUE_BY;

  // The row always reports the latest report, so each of these gets its own
  // item rather than filing an older report under one that already has a newer.
  const own=name=>mutate('register_equipment',{workplace_id:workplace,equipment_type:'crane',
    serial_tag:name}).body.equipment_id;
  // The expert can change the next date, and the record says whose it is.
  const overridden=mutate('record_inspection',{equipment_id:own('KRN-101'),
    performed_on:day(anchor,-2),result:'pass',next_due_on:day(anchor,200)});
  mark('a_next_date_the_expert_wrote_is_recorded_as_theirs_not_as_the_periods',
    overridden.status===200&&overridden.body.row.next_due_on===day(anchor,200)&&
    overridden.body.row.due_source==='expert');
  // Writing exactly what the period produces is still the period's answer.
  const twin=mutate('register_equipment',{workplace_id:workplace,equipment_type:'compressor',
    serial_tag:'KMP-101'});
  const matching=mutate('record_inspection',{equipment_id:twin.body.equipment_id,
    performed_on:day(anchor,-4),result:'pass',
    next_due_on:addMonths({y:Number(day(anchor,-4).slice(0,4)),m:Number(day(anchor,-4).slice(5,7)),
      d:Number(day(anchor,-4).slice(8,10))},COMPRESSOR_PERIOD_MONTHS)});
  mark('a_date_that_matches_the_period_is_still_the_periods_answer',
    matching.status===200&&matching.body.row.due_source==='period');
  mark('a_next_date_that_is_not_after_the_report_is_refused',
    mutate('record_inspection',{equipment_id:own('KRN-102'),performed_on:day(anchor,-6),
      result:'pass',next_due_on:day(anchor,-6)}).body?.message==='DUE_BEFORE_REPORT');
  mark('a_failed_check_cannot_be_given_a_next_date_by_hand',
    mutate('record_inspection',{equipment_id:own('KRN-103'),performed_on:day(anchor,-7),
      result:'fail',next_due_on:day(anchor,300)}).body?.message==='DUE_ON_A_FAILED_CHECK');

  // The İSG-KATİP mark is the expert's own declaration and nothing else.
  const katip=mutate('record_inspection',{equipment_id:own('KRN-104'),
    performed_on:day(anchor,-8),result:'pass',katip_declared:true,
    katip_note:'Atama 2026-09-01 tarihinde yapıldı.'});
  mark('the_katip_mark_is_the_experts_own_declaration_and_never_a_verification',
    katip.status===200&&katip.body.row.katip_assignment_declared===true&&
    katip.body.row.katip_declared_note==='Atama 2026-09-01 tarihinde yapıldı.'&&
    katip.body.row.katip_official_verification===false);
  mark('the_katip_mark_is_optional_and_defaults_to_not_declared',
    mutate('record_inspection',{equipment_id:own('KRN-105'),performed_on:day(anchor,-9),
      result:'pass'}).body.row.katip_assignment_declared===false);
  // No row anywhere can claim this product checked the official system.
  sql(`DO $$ BEGIN
    UPDATE private_isg.equipment_inspections SET katip_official_verification=true;
  EXCEPTION WHEN check_violation THEN NULL; END $$;`);
  mark('no_row_can_ever_claim_the_official_system_was_checked',
    sql("SELECT count(*) FROM private_isg.equipment_inspections WHERE katip_official_verification;")==='0');
  // A note without the mark is not storable: an unticked box explains nothing.
  mark('a_katip_note_without_the_mark_is_refused',
    sql("SELECT count(*) FROM private_isg.equipment_inspections WHERE NOT katip_assignment_declared AND katip_declared_note IS NOT NULL;")==='0');

  // A report that is already on file can be corrected.
  const filed=mutate('record_inspection',{equipment_id:own('KRN-110'),
    performed_on:day(anchor,-11),result:'pass',inspector:'Yanlış isim',
    external_ref:'YNLS-1',katip_declared:false});
  const report=filed.body.row.inspections[0];
  const corrected=mutate('update_inspection',{equipment_id:filed.body.equipment_id,
    inspection_id:report.id,inspector:'Doğru kuruluş',external_ref:'RPT-2026-0200',
    next_due_on:day(anchor,150),katip_declared:true,katip_note:'Atama sonradan işaretlendi.'});
  mark('a_report_already_on_file_can_be_corrected',corrected.status===200&&
    corrected.body.row.last_inspector==='Doğru kuruluş'&&
    corrected.body.row.last_external_ref==='RPT-2026-0200'&&
    corrected.body.row.next_due_on===day(anchor,150)&&
    corrected.body.row.due_source==='expert'&&
    corrected.body.row.katip_assignment_declared===true&&
    corrected.body.row.katip_declared_note==='Atama sonradan işaretlendi.');
  // Putting it back on the period's own answer reads as the period's again.
  const restored=mutate('update_inspection',{equipment_id:filed.body.equipment_id,
    inspection_id:report.id,
    next_due_on:addMonths({y:Number(day(anchor,-11).slice(0,4)),m:Number(day(anchor,-11).slice(5,7)),
      d:Number(day(anchor,-11).slice(8,10))},CRANE_PERIOD_MONTHS)});
  mark('a_corrected_date_that_matches_the_period_reads_as_the_periods_again',
    restored.status===200&&restored.body.row.due_source==='period');
  // The date and the result are what the report is, and cannot be edited.
  mark('a_correction_can_never_rewrite_the_check_date_or_its_result',
    mutate('update_inspection',{equipment_id:filed.body.equipment_id,inspection_id:report.id,
      performed_on:day(anchor,-1)}).body?.message==='PAYLOAD_NOT_ALLOWED'&&
    mutate('update_inspection',{equipment_id:filed.body.equipment_id,inspection_id:report.id,
      result:'fail'}).body?.message==='PAYLOAD_NOT_ALLOWED'&&
    sql("SELECT performed_on||':'||result FROM private_isg.equipment_inspections WHERE inspection_id="+quote(report.id)+";")===day(anchor,-11)+':pass');
  mark('a_correction_is_refused_on_another_owners_report',
    mutate('update_inspection',{equipment_id:filed.body.equipment_id,
      inspection_id:randomUUID(),inspector:'Yabancı'}).body?.message==='ACCESS_DENIED');
  mark('a_corrected_date_before_the_report_is_refused',
    mutate('update_inspection',{equipment_id:filed.body.equipment_id,inspection_id:report.id,
      next_due_on:day(anchor,-11)}).body?.message==='DUE_BEFORE_REPORT');
  // Unticking the mark takes its note with it: a note explains a tick.
  const untick=mutate('update_inspection',{equipment_id:filed.body.equipment_id,
    inspection_id:report.id,katip_declared:false});
  mark('unticking_the_katip_mark_removes_the_note_it_explained',
    untick.body.row.katip_assignment_declared===false&&
    untick.body.row.katip_declared_note===null);
  // The mark is information and nothing else: it moves no state and no counter.
  const beforeMark=readCall({p_limit:100}).body;
  mutate('update_inspection',{equipment_id:filed.body.equipment_id,inspection_id:report.id,
    katip_declared:true,katip_note:'Bilgi amaçlı.'});
  const afterMark=readCall({p_limit:100}).body;
  mark('the_katip_mark_moves_no_state_no_counter_and_no_filter',
    JSON.stringify(beforeMark.counts)===JSON.stringify(afterMark.counts)&&
    beforeMark.rows.find(row=>row.id===filed.body.equipment_id).state===
      afterMark.rows.find(row=>row.id===filed.body.equipment_id).state&&
    // There is no state or group word to filter it by, either.
    readCall({p_state:'katip'}).body?.message==='VALIDATION_ERROR');

  // A report cannot be dated in the future.
  mark('a_report_dated_after_today_is_refused',
    mutate('record_inspection',{equipment_id:crane.body.equipment_id,
      performed_on:day(anchor,7),result:'pass'}).body?.message==='PERFORMED_IN_THE_FUTURE');

  // The domain functions had no ownership check; the boundary is where it lives.
  const foreignOwner=sql("SELECT id FROM public.profiles WHERE id<>"+quote(ownerID)+" ORDER BY id LIMIT 1;");
  const foreignCompany=sql("SELECT id FROM public.companies WHERE user_id="+quote(foreignOwner)+" ORDER BY id LIMIT 1;");
  mark('another_owners_company_is_refused_on_every_action',
    post('isg_equipment_checks_mutate_v1',{p_company:foreignCompany||randomUUID(),p_action:'set_rule',
      p_operation:randomUUID(),p_mutation:randomUUID(),
      p_payload:{equipment_type:'crane',period_months:12,period_source:'manufacturer'}}).body?.message==='ACCESS_DENIED'&&
    post('isg_equipment_checks_read_v1',{p_company:foreignCompany||randomUUID(),p_kind:'list',p_query:null,
      p_state:null,p_workplace:null,p_type:null,p_id:null,p_limit:PAGE_SIZE,p_offset:0}).body?.message==='ACCESS_DENIED');
  mark('another_owners_equipment_cannot_be_inspected_through_this_company',
    mutate('record_inspection',{equipment_id:randomUUID(),performed_on:day(anchor,0),
      result:'pass'}).body?.message==='ACCESS_DENIED');
  mark('a_field_the_server_never_agreed_to_read_is_refused',
    mutate('register_equipment',{workplace_id:workplace,equipment_type:'crane',serial_tag:'KRN-009',
      state:'valid'}).body?.message==='PAYLOAD_NOT_ALLOWED'&&
    // next_due_on is the expert's to set now; due_source and the state are not.
    mutate('record_inspection',{equipment_id:crane.body.equipment_id,performed_on:day(anchor,0),
      result:'pass',due_source:'period'}).body?.message==='PAYLOAD_NOT_ALLOWED'&&
    mutate('record_inspection',{equipment_id:crane.body.equipment_id,performed_on:day(anchor,0),
      result:'pass',katip_official_verification:true}).body?.message==='PAYLOAD_NOT_ALLOWED');

  for(let index=0;index<FILLER_ROWS;index++){
    mutate('register_equipment',{workplace_id:workplace,equipment_type:'power_tool',
      serial_tag:'MRD-'+String(index).padStart(3,'0')});
  }

  const page=readCall();
  mark('the_page_is_bounded_and_the_tally_counts_the_same_rows_it_pages',
    page.status===200&&page.body.rows.length===PAGE_SIZE&&page.body.limit===PAGE_SIZE&&
    page.body.has_more===true&&page.body.total>PAGE_SIZE&&
    Object.values(page.body.counts).reduce((sum,value)=>sum+Number(value),0)===page.body.total);
  // The whole inventory, so the ordering can be read end to end rather than
  // judged from whichever ten rows happen to fit on the first page.
  const ordered=readCall({p_limit:100}).body.rows;
  const rank=['overdue','failed','never_inspected','period_unknown','due_soon','valid'];
  mark('the_page_puts_what_ran_out_first',
    page.body.rows[0].state==='overdue'&&
    ordered.map(row=>rank.indexOf(row.state)).every((value,index,all)=>index===0||all[index-1]<=value)&&
    ordered.some(row=>row.state==='valid')&&ordered.some(row=>row.state==='never_inspected'));
  mark('the_answer_is_a_tally_and_never_a_compliance_verdict',
    page.body.compliance_verdict===null&&page.body.health_records_tracked===false&&
    page.body.notice_days===NOTICE_DAYS&&
    page.body.rows.every(row=>row.state_authority==='computed_at_read'&&row.health_record===false));
  // A counter and the filter it carries have to be the same set of rows.
  const grouped={current:['valid'],due_soon:['due_soon'],overdue:['overdue'],failed:['failed'],
    untracked:['never_inspected','period_unknown']};
  mark('tapping_a_counter_filters_exactly_what_that_counter_counted',
    Object.entries(grouped).every(([word,states])=>{
      const answer=readCall({p_state:word,p_limit:100});
      const expected=states.reduce((sum,state)=>sum+Number(page.body.counts[state]??0),0);
      return answer.body.total===expected&&answer.body.rows.every(row=>states.includes(row.state));
    })&&
    Object.values(grouped).flat().length===new Set(Object.values(grouped).flat()).size&&
    Object.values(grouped).flat().length===6);
  mark('a_state_word_the_server_never_agreed_to_is_refused',
    readCall({p_state:'uygun'}).body?.message==='VALIDATION_ERROR');
  const sum=states=>Object.values(states).reduce((running,value)=>running+Number(value),0);
  mark('the_per_type_tally_answers_the_whole_inventory_in_one_call',
    typeof page.body.type_counts==='object'&&
    Object.values(page.body.type_counts).reduce((running,states)=>running+sum(states),0)===sum(page.body.counts));
  const tools=readCall({p_type:'power_tool',p_limit:100});
  mark('a_type_filter_returns_only_that_type',
    tools.status===200&&tools.body.rows.length>0&&
    tools.body.rows.every(row=>row.equipment_type==='power_tool'));
  mark('the_type_filter_counts_what_the_inventory_really_holds',
    // Compared against the table rather than against a constant, so a fixture
    // that filed fewer rows than intended is a fixture failure, not a silent pass.
    String(tools.body.total)===sql("SELECT count(*) FROM private_isg.equipment_items WHERE company_id="+quote(companyID)+" AND equipment_type='power_tool' AND NOT is_archived;")&&
    tools.body.total===FILLER_ROWS);
  mark('a_workplace_filter_returns_only_that_workplace',
    readCall({p_workplace:workplace,p_limit:100}).body.rows.every(row=>row.workplace_id===workplace));
  mark('the_whole_account_reads_in_one_call_without_naming_a_company',
    post('isg_equipment_checks_read_v1',{p_company:null,p_kind:'list',p_query:null,p_state:null,
      p_workplace:null,p_type:null,p_id:null,p_limit:PAGE_SIZE,p_offset:0}).body.companies
      .every(entry=>entry.id===companyID));

  // Setting a rule later must not rewrite a report that was already filed. The
  // welding set is the one type with no default, so its report really was
  // written before any period existed.
  const lateRule=mutate('set_rule',{equipment_type:'welding_set',period_months:24,
    period_source:'manufacturer'});
  const unchanged=readCall({p_kind:'detail',p_id:undefaulted.body.equipment_id});
  mark('a_rule_added_later_never_rewrites_a_report_that_was_already_filed',
    lateRule.status===200&&unchanged.body.row.next_due_on===null&&
    unchanged.body.row.state==='period_unknown'&&
    unchanged.body.row.period_months===24&&
    // And the row says why, instead of leaving the two facts to contradict
    // each other on screen.
    unchanged.body.row.period_defined_after_report===true);

  const detail=readCall({p_kind:'detail',p_id:fresh.body.equipment_id});
  mark('the_detail_carries_the_history_and_the_period_it_was_worked_out_from',
    detail.status===200&&Array.isArray(detail.body.row.inspections)&&
    detail.body.row.inspections.length===1&&
    detail.body.row.inspections[0].inspector==='Dış kuruluş · A. Yılmaz'&&
    // Still sitting on the product's default, still flagged for confirmation.
    detail.body.row.period_source==='regulation_default'&&
    detail.body.row.period_needs_review===true);

  const replayIDs={operation:randomUUID(),mutation:randomUUID()};
  const first=mutate('record_inspection',{equipment_id:compressor.body.equipment_id,
    performed_on:day(anchor,-1),result:'pass',inspector:'Tekrar'},replayIDs);
  const second=mutate('record_inspection',{equipment_id:compressor.body.equipment_id,
    performed_on:day(anchor,-1),result:'pass',inspector:'Tekrar'},replayIDs);
  mark('a_retry_returns_the_first_answer_instead_of_filing_a_second_report',first.status===200&&
    second.body.replayed===true&&
    sql("SELECT count(*) FROM private_isg.equipment_inspections WHERE equipment_id="+quote(compressor.body.equipment_id)+" AND performed_on="+quote(day(anchor,-1))+";")==='1');

  const archived=mutate('archive_equipment',{equipment_id:broken.body.equipment_id});
  mark('archiving_takes_the_item_off_the_list_and_keeps_its_history',archived.status===200&&
    readCall({p_limit:100}).body.rows.every(row=>row.id!==broken.body.equipment_id)&&
    sql("SELECT count(*) FROM private_isg.equipment_inspections WHERE equipment_id="+quote(broken.body.equipment_id)+";")==='1');

  mark('the_legacy_analysis_and_report_tables_were_never_written',
    sql("SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name IN ('analyses','findings','reports') AND column_name IN ('equipment_id','inspection_id');")==='0');

  sql("UPDATE private_isg.module_registry SET read_enabled=false,write_enabled=false WHERE module='equipment';");
  mark('the_kill_switch_stops_the_module_in_both_directions',
    readCall().body?.message==='MODULE_UNAVAILABLE'&&
    mutate('archive_equipment',{equipment_id:crane.body.equipment_id}).body?.message==='MODULE_UNAVAILABLE');

  return {afterLogout(){
    return {migration_file:equipmentChecksFiles[0],exact_migration_executed:true,
      own_rollout_feature_added:false,module_left_disabled:true,
      needs_two_switches:['modules','equipment'],
      period_defaults_offered:true,period_default_source:'regulation_default',
      period_default_needs_review:true,due_date_invented_without_a_rule:false,
      next_date_editable_by_the_expert:true,filed_report_correctable:true,
      correction_can_rewrite_date_or_result:false,
      katip_official_verification:false,katip_mark_affects_state:false,
      state_stored:false,health_records_tracked:false,compliance_verdict_returned:false,
      legacy_tables_written:false,production_deployed:false};
  }};
}
