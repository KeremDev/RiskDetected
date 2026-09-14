import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';

export const trainingCoreFiles=[
  'supabase/migrations/20260913170000_isg_training_core.sql',
  'scripts/isg/training_core_probe.mjs',
];
const read=p=>readFileSync(resolve(ROOT,p),'utf8');
const quote=v=>"'"+String(v).replaceAll("'","''")+"'";
const json=v=>quote(JSON.stringify(v))+'::jsonb';
// Recording occurs after the fixed training day, never weeks before it.
const now=seconds=>new Date(Date.UTC(2026,9,1,18,0,0)+seconds*1000).toISOString();
// Fixed training day. All attendance assertions are in whole minutes.
const clock=minutes=>new Date(Date.UTC(2026,9,1,9,0,0)+minutes*60000).toISOString();

export async function beginTrainingCoreProbe({synthetic,sql,concurrentSql,companyID,ownerID,pass}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_TRAINING_SYNTHETIC_REQUIRED');
  if(!companyID||!ownerID)throw Error('AUTH_RESTORE_TRAINING_SCOPE_REQUIRED');
  const mark=(name,ok)=>pass('training_core_'+name,ok);
  sql(read(trainingCoreFiles[0]));
  mark('migration_applied_with_closed_rollout',sql("SELECT NOT read_enabled AND NOT write_enabled FROM private_isg.rollout WHERE feature='training';")==='t');
  const workplace=sql("SELECT id FROM private_isg.workplaces WHERE company_id="+quote(companyID)+" ORDER BY id LIMIT 1;");

  sql(["CREATE SCHEMA isg_training_test;",
    "CREATE FUNCTION isg_training_test.observe(kind text,a jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $probe$",
    "DECLARE r jsonb; code text; BEGIN",
    "IF kind='publish' THEN r:=private_isg.publish_catalog_version(a->>'code',(a->>'version')::integer,(a->>'approver')::uuid,a->>'note',(a->>'content_approved')::boolean,(a->>'now')::timestamptz);",
    "ELSIF kind='curriculum' THEN r:=private_isg.activate_curriculum((a->>'company')::uuid,(a->>'workplace')::uuid,a->>'code',a->>'hazard',a->'g4_topics',(a->>'g4_lessons')::integer,(a->>'now')::timestamptz);",
    "ELSIF kind='plan' THEN r:=private_isg.open_training_plan((a->>'curriculum')::uuid,a->>'kind',(a->>'requirement')::uuid,(a->>'on')::date,(a->>'now')::timestamptz);",
    "ELSIF kind='session' THEN r:=private_isg.schedule_training_session((a->>'plan')::uuid,a->>'method',(a->>'starts')::timestamptz,(a->>'ends')::timestamptz,(a->>'lesson_minutes')::integer,(a->>'break_minutes')::integer,(a->>'now')::timestamptz);",
    "ELSIF kind='enrol' THEN r:=private_isg.enrol_employee((a->>'session')::uuid,(a->>'employee')::uuid,(a->>'now')::timestamptz);",
    "ELSIF kind='attend' THEN r:=private_isg.record_attendance((a->>'enrolment')::uuid,(a->>'starts')::timestamptz,(a->>'ends')::timestamptz,(a->>'now')::timestamptz);",
    "ELSIF kind='attempt' THEN r:=private_isg.record_assessment_attempt((a->>'enrolment')::uuid,(a->>'score')::integer,(a->>'now')::timestamptz);",
    "ELSIF kind='complete' THEN r:=private_isg.complete_training((a->>'enrolment')::uuid,(a->>'on')::date,(a->>'now')::timestamptz);",
    "ELSIF kind='settle' THEN r:=private_isg.settle_training_requirement((a->>'plan')::uuid,(a->>'now')::timestamptz);",
    "ELSIF kind='credential' THEN r:=private_isg.record_external_credential((a->>'company')::uuid,(a->>'employee')::uuid,a->>'issuer',a->>'title',(a->>'issued_on')::date,(a->>'valid_until')::date,(a->>'asset')::uuid,a->>'evidence',(a->>'now')::timestamptz);",
    "ELSIF kind='decide' THEN r:=private_isg.decide_applicability((a->>'company')::uuid,(a->>'workplace')::uuid,a->>'code',(a->>'on')::date,a->'facts',(a->>'now')::timestamptz);",
    "ELSIF kind='requirement' THEN r:=private_isg.open_requirement((a->>'decision')::uuid,(a->>'period_start')::date,a->>'timezone',(a->>'now')::timestamptz);",
    "ELSE RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;",
    "RETURN jsonb_build_object('result',r);",
    "EXCEPTION WHEN SQLSTATE '23514' THEN RETURN jsonb_build_object('error','CHECK_VIOLATION');",
    "WHEN SQLSTATE '23505' THEN RETURN jsonb_build_object('error','UNIQUE_VIOLATION');",
    "WHEN SQLSTATE 'P0001' THEN GET STACKED DIAGNOSTICS code=MESSAGE_TEXT;",
    "IF code NOT IN ('FEATURE_UNAVAILABLE','VALIDATION_ERROR','ACCESS_DENIED','RULE_NEEDS_REVIEW','ATTENDANCE_OVERLAP','ATTENDANCE_INSUFFICIENT','ASSESSMENT_NOT_PASSED','ATTEMPT_LIMIT_REACHED') THEN RAISE; END IF;",
    "RETURN jsonb_build_object('error',code); END $probe$;"].join('\n'));
  const call=(kind,args)=>JSON.parse(sql("SELECT isg_training_test.observe("+quote(kind)+","+json(args)+");").split('\n').at(-1));
  const ok=(kind,args)=>{const r=call(kind,args);if(r.error)throw Error('AUTH_RESTORE_TRAINING_UNEXPECTED_'+r.error);return r.result;};

  mark('gate_blocks_publishing_while_rollout_off',call('publish',{code:'basic_isg',version:1,approver:ownerID,note:'x',content_approved:false,now:now(0)}).error==='FEATURE_UNAVAILABLE');
  const privileges=sql("SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role','PUBLIC'); SELECT count(*) FROM pg_tables WHERE schemaname='private_isg' AND NOT rowsecurity; SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND p.proname IN ('training_gate','attendance_minutes','publish_catalog_version','activate_curriculum','open_training_plan','schedule_training_session','enrol_employee','record_attendance','record_assessment_attempt','complete_training','settle_training_requirement','record_external_credential') AND (has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE') OR has_function_privilege('service_role',p.oid,'EXECUTE'));").split('\n');
  mark('training_tables_have_rls_and_no_client_grant',privileges[0]==='0'&&privileges[1]==='0'&&privileges[2]==='0');
  sql("UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature IN ('training','rule_engine');");

  // Catalogue fixtures. These numbers come from the V5 source and are NOT a
  // legal confirmation, so every version is published content_approved=false.
  const verified=sql("SELECT source_id FROM private_isg.legal_sources WHERE NOT needs_review ORDER BY created_at LIMIT 1;");
  const inReview=sql("SELECT source_id FROM private_isg.legal_sources WHERE needs_review ORDER BY created_at LIMIT 1;");
  const classes=[['low',8,8,2,3],['medium',12,8,2,2],['high',16,8,2,1]];
  const seedVersion=(code,version,source)=>{
    sql("INSERT INTO private_isg.training_catalog_versions(catalog_code,version,source_id) VALUES("+quote(code)+","+version+","+(source?quote(source):'NULL')+");");
    for(const [hazard,first,refresh,onboarding,years] of classes)
      sql("INSERT INTO private_isg.training_class_rules(catalog_code,version,hazard_class,first_lessons,refresh_lessons,onboarding_lessons,refresh_period_years,lesson_minutes,break_minutes,pass_score,max_attempts) VALUES("+
        quote(code)+","+version+","+quote(hazard)+","+first+","+refresh+","+onboarding+","+years+",45,15,60,3);");
    for(const [group,label,min] of [['G1','Genel konular',4],['G2','Sağlık konuları',4],['G3','Teknik konular',4],['G4','İşyerine özgü konular',4]])
      sql("INSERT INTO private_isg.training_topic_groups(catalog_code,version,group_code,official_label,min_lessons) VALUES("+
        quote(code)+","+version+","+quote(group)+","+quote(label)+","+min+");");
  };
  sql("INSERT INTO private_isg.training_catalogs(catalog_code,namespace,title) VALUES('basic_isg','official','Temel İSG Eğitimi'),('vendor_course','special','Temel İSG');");
  seedVersion('basic_isg',1,null);
  mark('an_official_catalogue_needs_a_legal_source',call('publish',{code:'basic_isg',version:1,approver:ownerID,note:'Onay',content_approved:false,now:now(10)}).error==='RULE_NEEDS_REVIEW');
  sql("UPDATE private_isg.training_catalog_versions SET source_id="+quote(inReview)+" WHERE catalog_code='basic_isg' AND version=1;");
  mark('a_source_in_review_can_not_publish_a_catalogue',call('publish',{code:'basic_isg',version:1,approver:ownerID,note:'Onay',content_approved:false,now:now(11)}).error==='RULE_NEEDS_REVIEW');
  sql("UPDATE private_isg.training_catalog_versions SET source_id="+quote(verified)+" WHERE catalog_code='basic_isg' AND version=1;");
  sql("INSERT INTO private_isg.training_catalog_versions(catalog_code,version,source_id) VALUES('basic_isg',9,"+quote(verified)+");");
  mark('a_version_without_class_rules_can_not_publish',call('publish',{code:'basic_isg',version:9,approver:ownerID,note:'Onay',content_approved:false,now:now(12)}).error==='VALIDATION_ERROR');
  sql("DELETE FROM private_isg.training_catalog_versions WHERE catalog_code='basic_isg' AND version=9;");
  const published=ok('publish',{code:'basic_isg',version:1,approver:ownerID,note:'V5 fixture değerleri; resmî içerik onayı verilmedi.',content_approved:false,now:now(13)});
  mark('a_published_catalogue_says_its_content_is_unapproved',published.status==='published'&&published.content_approved===false);
  mark('publishing_a_catalogue_replays',ok('publish',{code:'basic_isg',version:1,approver:ownerID,note:'Tekrar',content_approved:false,now:now(14)}).replayed===true);
  seedVersion('vendor_course',1,null);
  mark('a_special_course_can_not_claim_approved_official_content',call('publish',{code:'vendor_course',version:1,approver:ownerID,note:'Özel eğitim',content_approved:true,now:now(15)}).error==='VALIDATION_ERROR');
  const special=ok('publish',{code:'vendor_course',version:1,approver:ownerID,note:'Özel eğitim yayını.',content_approved:false,now:now(16)});
  mark('the_same_title_does_not_make_a_special_course_official',special.status==='published'&&
    sql("SELECT namespace FROM private_isg.training_catalogs WHERE title='Temel İSG';")==='special'&&
    sql("SELECT count(*) FROM private_isg.training_catalogs WHERE namespace='official';")==='1');

  const g4={g4_topics:['Kimyasal maruziyet','Yüksekte çalışma'],g4_lessons:4};
  mark('a_curriculum_respects_the_g4_minimum',call('curriculum',{company:companyID,workplace,code:'basic_isg',hazard:'high',g4_topics:g4.g4_topics,g4_lessons:3,now:now(20)}).error==='VALIDATION_ERROR');
  mark('a_curriculum_needs_a_published_catalogue',call('curriculum',{company:companyID,workplace,code:'unknown_catalog',hazard:'high',...g4,now:now(20)}).error==='RULE_NEEDS_REVIEW');
  mark('a_foreign_workplace_gets_no_curriculum',call('curriculum',{company:companyID,workplace:randomUUID(),code:'basic_isg',hazard:'high',...g4,now:now(20)}).error==='ACCESS_DENIED');
  const first=ok('curriculum',{company:companyID,workplace,code:'basic_isg',hazard:'high',...g4,now:now(21)});
  const second=ok('curriculum',{company:companyID,workplace,code:'basic_isg',hazard:'high',g4_topics:[...g4.g4_topics,'Yeni görev riski'],g4_lessons:5,now:now(22)});
  mark('a_changed_g4_opens_a_new_curriculum_version',first.version===1&&second.version===2&&second.superseded_curriculum===first.curriculum_id&&
    sql("SELECT count(*) FROM private_isg.company_curriculum_versions WHERE state='active' AND company_id="+quote(companyID)+";")==='1');
  mark('a_superseded_curriculum_can_not_be_planned',call('plan',{curriculum:first.curriculum_id,kind:'refresh',requirement:null,on:'2026-10-01',now:now(23)}).error==='ACCESS_DENIED');

  const decision=ok('decide',{company:companyID,workplace,code:'training.basic_isg',on:'2026-10-01',facts:{jurisdiction:'TR',hazard_class:'high',industry_code:'41.20',employee_count:120},now:now(24)});
  const requirement=ok('requirement',{decision:decision.decision_id,period_start:'2026-10-01',timezone:'Europe/Istanbul',now:now(25)});
  mark('a_training_obligation_from_the_rule_engine_is_open',decision.state==='required'&&requirement.status==='open');
  const plan=ok('plan',{curriculum:second.curriculum_id,kind:'refresh',requirement:requirement.requirement_id,on:'2026-10-01',now:now(26)});
  mark('a_plan_is_not_a_completion',plan.state==='planned'&&plan.completes_nothing===true&&
    sql("SELECT count(*) FROM private_isg.training_completions;")==='0'&&
    sql("SELECT status FROM private_isg.requirement_instances WHERE requirement_id="+quote(requirement.requirement_id)+";")==='open');
  mark('a_plan_can_not_borrow_a_foreign_or_closed_obligation',call('plan',{curriculum:second.curriculum_id,kind:'refresh',requirement:randomUUID(),on:'2026-10-01',now:now(27)}).error==='ACCESS_DENIED');
  const session=ok('session',{plan:plan.plan_id,method:'classroom',starts:clock(0),ends:clock(480),lesson_minutes:45,break_minutes:15,now:now(28)});
  mark('an_unknown_method_is_refused_and_a_session_starts_the_plan',
    call('session',{plan:plan.plan_id,method:'telepathy',starts:clock(0),ends:clock(480),lesson_minutes:45,break_minutes:15,now:now(29)}).error==='VALIDATION_ERROR'&&
    sql("SELECT state FROM private_isg.training_plans WHERE plan_id="+quote(plan.plan_id)+";")==='running');

  const employees=['Eğitim Katılımcı A','Eğitim Katılımcı B','Eğitim Katılımcı C'].map(name=>{
    const id=randomUUID();
    sql("INSERT INTO private_isg.employees(id,company_id,owner_id,employee_code,full_name) VALUES("+quote(id)+","+quote(companyID)+","+quote(ownerID)+",'TRN-'||"+quote(id)+","+quote(name)+");");
    return id;});
  const enrolment=ok('enrol',{session:session.session_id,employee:employees[0],now:now(30)});
  mark('an_employee_enrols_once_per_session',ok('enrol',{session:session.session_id,employee:employees[0],now:now(31)}).replayed===true&&
    sql("SELECT count(*) FROM private_isg.training_enrolments WHERE session_id="+quote(session.session_id)+";")==='1');
  mark('a_foreign_employee_can_not_be_enrolled',call('enrol',{session:session.session_id,employee:randomUUID(),now:now(32)}).error==='ACCESS_DENIED');

  mark('attendance_must_fall_inside_the_session',call('attend',{enrolment:enrolment.enrolment_id,starts:clock(-30),ends:clock(30),now:now(33)}).error==='VALIDATION_ERROR');
  mark('future_attendance_cannot_be_recorded_as_completed_work',call('attend',{enrolment:enrolment.enrolment_id,starts:clock(0),ends:clock(60),now:clock(30)}).error==='VALIDATION_ERROR');
  const overlapping=[[0,60],[30,90]].map(([from,to])=>ok('attend',{enrolment:enrolment.enrolment_id,starts:clock(from),ends:clock(to),now:now(34)}));
  mark('overlapping_attendance_is_credited_as_a_union',overlapping.at(-1).credited_minutes===90);
  mark('adjacent_attendance_merges_into_one_block',ok('attend',{enrolment:enrolment.enrolment_id,starts:clock(90),ends:clock(150),now:now(35)}).credited_minutes===150);
  mark('the_same_interval_twice_credits_nothing_new',ok('attend',{enrolment:enrolment.enrolment_id,starts:clock(90),ends:clock(150),now:now(36)}).replayed===true&&
    sql("SELECT private_isg.attendance_minutes("+quote(enrolment.enrolment_id)+");")==='150');
  const parallelPlan=ok('plan',{curriculum:second.curriculum_id,kind:'special',requirement:null,on:'2026-10-01',now:now(37)});
  const parallelSession=ok('session',{plan:parallelPlan.plan_id,method:'online_sync',starts:clock(0),ends:clock(480),lesson_minutes:45,break_minutes:15,now:now(38)});
  const parallelEnrolment=ok('enrol',{session:parallelSession.session_id,employee:employees[0],now:now(39)});
  mark('one_minute_is_never_credited_to_two_courses',call('attend',{enrolment:parallelEnrolment.enrolment_id,starts:clock(120),ends:clock(180),now:now(40)}).error==='ATTENDANCE_OVERLAP');
  const otherEnrolment=ok('enrol',{session:parallelSession.session_id,employee:employees[1],now:now(41)});
  mark('another_person_may_attend_the_same_minute',ok('attend',{enrolment:otherEnrolment.enrolment_id,starts:clock(120),ends:clock(180),now:now(42)}).credited_minutes===60);
  const raceEmployee=randomUUID();
  sql("INSERT INTO private_isg.employees(id,company_id,owner_id,employee_code,full_name) VALUES("+quote(raceEmployee)+","+quote(companyID)+","+quote(ownerID)+",'RACE-'||"+quote(raceEmployee)+",'Synthetic attendance race');");
  const raceSession=ok('session',{plan:parallelPlan.plan_id,method:'online_sync',starts:clock(0),ends:clock(480),lesson_minutes:45,break_minutes:15,now:now(42)});
  const raceEnrolments=[parallelSession.session_id,raceSession.session_id].map(session=>ok('enrol',{session,employee:raceEmployee,now:now(42)}).enrolment_id);
  const race=await Promise.all(raceEnrolments.map(enrolment=>concurrentSql("BEGIN;SELECT isg_training_test.observe('attend',"+
    json({enrolment,starts:clock(200),ends:clock(260),now:now(43)})+");SELECT pg_sleep(0.2);COMMIT;")));
  const results=race.filter(r=>r.ok).map(r=>JSON.parse(r.output.split('\n').filter(l=>l.startsWith('{')).at(-1)));
  mark('concurrent_courses_cannot_double_credit_one_person',results.length===2&&results.filter(r=>r.result).length===1&&results.filter(r=>r.error==='ATTENDANCE_OVERLAP').length===1);

  const failing=ok('attempt',{enrolment:enrolment.enrolment_id,score:59,now:now(50)});
  mark('the_pass_threshold_is_exact',failing.passed===false&&failing.attempt_no===1&&
    ok('attempt',{enrolment:enrolment.enrolment_id,score:60,now:now(51)}).passed===true);
  mark('attempts_are_capped',ok('attempt',{enrolment:enrolment.enrolment_id,score:61,now:now(52)}).attempts_left===0&&
    call('attempt',{enrolment:enrolment.enrolment_id,score:100,now:now(53)}).error==='ATTEMPT_LIMIT_REACHED');

  mark('an_incomplete_attendance_can_not_complete',call('complete',{enrolment:enrolment.enrolment_id,on:'2026-10-01',now:now(54)}).error==='ATTENDANCE_INSUFFICIENT');
  ok('attend',{enrolment:enrolment.enrolment_id,starts:clock(150),ends:clock(359),now:now(55)});
  mark('one_minute_short_is_still_short',call('complete',{enrolment:enrolment.enrolment_id,on:'2026-10-01',now:now(56)}).error==='ATTENDANCE_INSUFFICIENT'&&
    sql("SELECT private_isg.attendance_minutes("+quote(enrolment.enrolment_id)+");")==='359');
  ok('attend',{enrolment:enrolment.enrolment_id,starts:clock(359),ends:clock(360),now:now(57)});
  mark('completion_date_cannot_precede_attendance_or_be_in_the_future',
    call('complete',{enrolment:enrolment.enrolment_id,on:'2026-09-30',now:now(58)}).error==='VALIDATION_ERROR'&&
    call('complete',{enrolment:enrolment.enrolment_id,on:'2026-10-02',now:now(58)}).error==='VALIDATION_ERROR');
  const completion=ok('complete',{enrolment:enrolment.enrolment_id,on:'2026-10-01',now:now(58)});
  mark('exactly_the_required_lesson_minutes_completes',completion.credited_minutes===360&&completion.required_minutes===360&&completion.score===60);
  mark('validity_uses_the_catalogue_repeat_period_in_calendar_years',completion.valid_until==='2027-10-01'&&completion.content_approved===false);
  mark('completing_replays_without_a_second_record',ok('complete',{enrolment:enrolment.enrolment_id,on:'2026-10-02',now:now(59)}).replayed===true&&
    sql("SELECT count(*) FROM private_isg.training_completions;")==='1');
  const snapshot=sql("SELECT md5(snapshot::text)||':'||catalog_version||':'||curriculum_version FROM private_isg.training_completions WHERE completion_id="+quote(completion.completion_id)+";");
  seedVersion('basic_isg',2,verified);
  ok('publish',{code:'basic_isg',version:2,approver:ownerID,note:'İkinci katalog sürümü.',content_approved:false,now:now(60)});
  ok('curriculum',{company:companyID,workplace,code:'basic_isg',hazard:'high',g4_topics:['Tamamen yeni içerik'],g4_lessons:6,now:now(61)});
  mark('a_finalised_completion_is_never_rewritten',snapshot===sql("SELECT md5(snapshot::text)||':'||catalog_version||':'||curriculum_version FROM private_isg.training_completions WHERE completion_id="+quote(completion.completion_id)+";"));

  const second_person=ok('enrol',{session:session.session_id,employee:employees[2],now:now(62)});
  mark('an_obligation_is_not_satisfied_while_a_participant_is_open',ok('settle',{plan:plan.plan_id,now:now(63)}).requirement_satisfied===false&&
    sql("SELECT status FROM private_isg.requirement_instances WHERE requirement_id="+quote(requirement.requirement_id)+";")==='open');
  ok('attend',{enrolment:second_person.enrolment_id,starts:clock(0),ends:clock(360),now:now(64)});
  ok('attempt',{enrolment:second_person.enrolment_id,score:80,now:now(65)});
  ok('complete',{enrolment:second_person.enrolment_id,on:'2026-10-01',now:now(66)});
  const settled=ok('settle',{plan:plan.plan_id,now:now(67)});
  mark('a_fully_completed_plan_satisfies_the_rule_engine_obligation',settled.requirement_satisfied===true&&
    sql("SELECT status FROM private_isg.requirement_instances WHERE requirement_id="+quote(requirement.requirement_id)+";")==='satisfied'&&
    sql("SELECT state FROM private_isg.requirement_schedules WHERE requirement_id="+quote(requirement.requirement_id)+" AND state='completed';")==='completed'&&
    sql("SELECT state FROM private_isg.training_plans WHERE plan_id="+quote(plan.plan_id)+";")==='closed');
  mark('closed_plan_cannot_gain_an_unfinished_participant',
    call('enrol',{session:session.session_id,employee:employees[1],now:now(68)}).error==='ACCESS_DENIED'&&
    ok('enrol',{session:session.session_id,employee:employees[0],now:now(68)}).replayed===true);

  const credential=(over={})=>({company:companyID,employee:employees[0],issuer:'Dış Eğitim Kurumu',title:'İlk Yardım Sertifikası',
    issued_on:'2026-05-01',valid_until:'2029-05-01',asset:null,evidence:null,now:now(70),...over});
  const bare=ok('credential',credential());
  mark('an_external_certificate_is_not_a_training_completion',bare.is_training_completion===false&&bare.needs_review===true&&
    sql("SELECT count(*) FROM private_isg.training_completions;")==='2');
  mark('an_external_certificate_replays',ok('credential',credential()).replayed===true&&sql("SELECT count(*) FROM private_isg.external_credentials;")==='1');
  mark('an_expiry_before_the_issue_date_is_refused',call('credential',credential({title:'Hatalı tarih',valid_until:'2026-04-01'})).error==='VALIDATION_ERROR');
  mark('an_unknown_document_can_not_be_the_evidence',call('credential',credential({title:'Bilinmeyen belge',asset:randomUUID(),evidence:'Ek dosya'})).error==='ACCESS_DENIED');
  const asset=sql("SELECT asset_id FROM private_isg.file_assets ORDER BY created_at LIMIT 1;");
  const evidenced=ok('credential',credential({title:'Belgeli sertifika',asset,evidence:'Taranmış sertifika dosyası eklendi.'}));
  mark('a_clean_document_takes_the_certificate_out_of_review',evidenced.needs_review===false&&evidenced.is_training_completion===false);

  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='training';");
  mark('kill_switch_stops_the_training_domain',call('plan',{curriculum:second.curriculum_id,kind:'refresh',requirement:null,on:'2026-10-01',now:now(80)}).error==='FEATURE_UNAVAILABLE'&&
    call('complete',{enrolment:second_person.enrolment_id,on:'2026-10-01',now:now(80)}).error==='FEATURE_UNAVAILABLE');
  sql("UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='rule_engine';");
  return {afterLogout(){
    return {migration_file:trainingCoreFiles[0],exact_migration_executed:true,rollout_left_disabled:true,
      client_grant_added:false,official_content_approved:false,legal_catalogue_loaded:false,
      document_export_implemented:false,score_contribution_connected:false,production_deployed:false};
  }};
}
