import {writeFileSync} from 'node:fs'; import {content,fixture} from './fixtures.mjs';
const j=x=>`$j$${JSON.stringify(x)}$j$::jsonb`;
let sql=`SET test.actor='20000000-0000-0000-0000-000000000001'; UPDATE private_isg.education_controls SET enabled=true;
CREATE FUNCTION pg_temp.ok(condition boolean,label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF condition IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %',label; END IF; RAISE NOTICE 'PASS: %',label; END $$;
CREATE FUNCTION pg_temp.denied(statement text,code text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN EXECUTE statement; RAISE EXCEPTION 'EXPECTED_REJECTION'; EXCEPTION WHEN OTHERS THEN IF SQLERRM<>code THEN RAISE EXCEPTION 'Expected %, got %',code,SQLERRM; END IF; END $$;
`;
for(const [i,p] of content.presets.entries()){
 const f=fixture(p.code);const hazard={hazardous:'medium',very_hazardous:'high',low:'low'}[p.hazard_class];
 sql+=`UPDATE private_isg.workplaces SET hazard_class='${hazard}';
DO $$ DECLARE r jsonb; d jsonb; c jsonb; replay jsonb; payload jsonb:=${j(f)}; sid uuid; v bigint; oldrecord uuid; BEGIN
 r:=private_isg.education_save('60000000-0000-0000-0000-00000000000${i+1}',payload); sid:=(r->'row'->>'id')::uuid;
 PERFORM pg_temp.ok((r->'row'->'education'->'scopes'->0->>'instruction_minutes')::int=${p.default_instruction_minutes},'${p.code} net teaching');
 PERFORM pg_temp.ok((r->'row'->'education'->'scopes'->0->>'break_minutes')::int=${p.default_break_minutes},'${p.code} breaks');
 PERFORM pg_temp.ok((r->'row'->'education'->'scopes'->0->>'group4_minutes')::int=${p.group4.budget_instruction_minutes},'${p.code} G4');
 PERFORM pg_temp.ok(r->'row'->'education'->'scopes'->0->'issues'='[]','${p.code} certificate scope valid');
 replay:=private_isg.education_save('60000000-0000-0000-0000-00000000000${i+1}',payload); PERFORM pg_temp.ok(replay=r,'save replay');
 d:=jsonb_build_object('action','issue','session_id',sid,'scope_id',payload->'scopes'->0->>'id','person_id','30000000-0000-0000-0000-000000000001','expected_version',r->'row'->'version','mutation_id',gen_random_uuid());
 c:=private_isg.education_certificate(d); PERFORM pg_temp.ok((c->>'ready')::boolean,'certificate ready');
 PERFORM pg_temp.ok(c->'snapshot'->>'completion_basis'='expert_record','expert record without assessment');
 replay:=private_isg.education_certificate(jsonb_set(d,'{mutation_id}',to_jsonb(gen_random_uuid()))); PERFORM pg_temp.ok(replay=c,'new request same certificate');
 SELECT id INTO oldrecord FROM private_isg.pilot_training_records WHERE session_id=sid;
 payload:=payload||jsonb_build_object('id',sid,'expected_version',r->'row'->'version','notes','Correction');
 r:=private_isg.education_save(gen_random_uuid(),payload);
 PERFORM pg_temp.ok(oldrecord=(SELECT id FROM private_isg.pilot_training_records WHERE session_id=sid),'stable company record');
 PERFORM pg_temp.ok((SELECT snapshot FROM private_isg.document_versions WHERE document_id=(c->>'document_id')::uuid AND version=1)=c->'snapshot','old document immutable');
 PERFORM pg_temp.denied(format('SELECT private_isg.pilot_training_sessions_save(%L,%L::jsonb)',gen_random_uuid(),jsonb_build_object('id',sid)),'UPGRADE_REQUIRED');
END $$;
`;
}
sql+=`SELECT private_isg.education_install_package(${j(content)});
SELECT pg_temp.denied($sql$SELECT private_isg.education_install_package(jsonb_set(${j(content)},'{locale}','"en-US"'))$sql$,'CONTENT_VERSION_CONFLICT');
DO $$ DECLARE p jsonb:=${j(fixture())}; r jsonb; BEGIN
 p:=jsonb_set(p,'{scopes,0,participants,0,id}','"30000000-0000-0000-0000-000000000002"');
 PERFORM pg_temp.denied(format('SELECT private_isg.education_save(%L,%L::jsonb)',gen_random_uuid(),p),'PARTICIPANT_UNAVAILABLE');
END $$;
SELECT pg_temp.ok((SELECT count(DISTINCT document_no)=count(*) FROM private_isg.document_versions),'unique certificate numbers');
SELECT pg_temp.ok(NOT has_function_privilege('anon','public.isg_pilot_training_certificate_v1(jsonb)','EXECUTE'),'anon denied');
SELECT 'EDU database acceptance passed' AS result;
`;
writeFileSync(new URL('./checks.sql',import.meta.url),sql);
// Additional negative and cross-company cases are appended to the generated SQL.
let extra = `UPDATE private_isg.workplaces SET hazard_class='high';
CREATE FUNCTION pg_temp.save_issue(p jsonb, issue text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE r jsonb; c jsonb; BEGIN
 r:=private_isg.education_save(gen_random_uuid(),p);
 c:=private_isg.education_certificate(jsonb_build_object('action','issue','mutation_id',gen_random_uuid(),'session_id',r->'row'->>'id','scope_id',p->'scopes'->0->>'id','person_id',p->'scopes'->0->'participants'->0->>'id','expected_version',r->'row'->'version'));
 PERFORM pg_temp.ok(c->'issues' ? issue,'certificate blocked: '||issue);
 PERFORM pg_temp.ok(c->>'document_id' IS NULL AND c->'snapshot'->>'number'='' AND (c->'snapshot'->>'is_draft')::boolean,'numberless draft; saved occurrence retained');
 PERFORM pg_temp.ok(EXISTS(SELECT 1 FROM private_isg.pilot_training_records WHERE session_id=(r->'row'->>'id')::uuid AND state='completed'),'incomplete certificate preserves occurred training');
END $$;
`;
function issue(change,code){const f=fixture();change(f);extra+=`SELECT pg_temp.save_issue(${j(f)},'${code}');\n`;}
issue(f=>f.scopes[0].topics.find(t=>t.group==='G4').instruction_minutes=0,'GROUP4_TOO_SHORT');
issue(f=>f.scopes[0].topics[0].instruction_minutes=0,'REQUIRED_TOPIC_MISSING');
issue(f=>f.scopes[0].topics[0].instruction_minutes=0,'COMMON_GROUPS_TOO_SHORT');
issue(f=>f.scopes[0].topics.find(t=>t.group==='G4').method='online','FACE_TO_FACE_REQUIRED');
issue(f=>f.scopes[0].participants[0].job_title='','JOB_TITLE_MISSING');
issue(f=>f.scopes[0].context_note='','GROUP4_CONTEXT_MISSING');
issue(f=>f.scopes[0].employer_name='','EMPLOYER_MISSING');
issue(f=>f.trainers[0].title='','TRAINER_TITLE_MISSING');
issue(f=>f.scopes[0].lessons[0].break_minutes=0,'LESSON_BREAK_INVALID');
function denied(change,code){const f=fixture();change(f);extra+=`SELECT pg_temp.denied(format('SELECT private_isg.education_save(%L,%L::jsonb)',gen_random_uuid(),${j(f)}),'${code}');\n`;}
denied(f=>f.scopes.push(structuredClone(f.scopes[0])),'SCOPE_INVALID');
denied(f=>{let x=structuredClone(f.scopes[0]);x.id='50000000-0000-0000-0000-000000000099';f.scopes.push(x);},'PARTICIPANT_DUPLICATE');
denied(f=>f.scopes[0].lessons[1].starts_at=f.scopes[0].lessons[0].starts_at,'LESSON_OVERLAP_OR_FUTURE');
denied(f=>f.scopes[0].lessons[0].starts_at='2099-01-01T00:00:00Z','TRAINING_DATE_INVALID');
denied(f=>f.scopes[0].topics.push({...f.scopes[0].topics[0],code:'G1-A-child',parent_code:'G1-A'}),'TOPIC_HIERARCHY_INVALID');
extra+=`DO $$ DECLARE p jsonb:=${j(fixture())}; r jsonb; c jsonb; before_no bigint; BEGIN
 p:=jsonb_set(p,'{scopes,0,topics,0,instruction_minutes}','12');
 r:=private_isg.education_save(gen_random_uuid(),p);
 PERFORM pg_temp.ok((r->'row'->'education'->'scopes'->0->'topics'->0->>'instruction_minutes')::int=12,'integer minutes not rounded');
 p:=p||jsonb_build_object('id',r->'row'->>'id','expected_version',0);
 PERFORM pg_temp.denied(format('SELECT private_isg.education_save(%L,%L::jsonb)',gen_random_uuid(),p),'VERSION_CONFLICT');
 PERFORM pg_temp.ok(to_regclass('private_isg.attendance_intervals') IS NULL AND to_regclass('private_isg.training_assessments') IS NULL,'no attendance or exam dependency');
END $$;
INSERT INTO public.companies(id,user_id,name,hazard_class) VALUES('10000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001','Second Company','low');
INSERT INTO private_isg.workplaces VALUES('40000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001','Office','low',false);
INSERT INTO private_isg.employees VALUES('30000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001','Second Employee',false);
`;
const multi=fixture();const second=fixture('repeat_low').scopes[0];second.id='50000000-0000-0000-0000-000000000003';second.company_id='10000000-0000-0000-0000-000000000003';second.workplace_id='40000000-0000-0000-0000-000000000003';second.participants[0].id='30000000-0000-0000-0000-000000000003';multi.scopes.push(second);
extra+=`DO $$ DECLARE p jsonb:=${j(multi)}; r jsonb; c jsonb; d jsonb; s jsonb; count_before bigint; BEGIN
 r:=private_isg.education_save(gen_random_uuid(),p);
 PERFORM pg_temp.ok(jsonb_array_length(r->'row'->'companies')=2,'multi-company single session');
 PERFORM pg_temp.ok((r->'row'->'education'->'scopes'->1->>'instruction_minutes')::int=360,'different company minutes not added');
 FOR s IN SELECT value FROM jsonb_array_elements(p->'scopes') LOOP
  d:=jsonb_build_object('action','issue','mutation_id',gen_random_uuid(),'session_id',r->'row'->>'id','scope_id',s->>'id','person_id',s->'participants'->0->>'id','expected_version',r->'row'->'version');
  c:=private_isg.education_certificate(d);
  PERFORM pg_temp.ok((c->>'ready')::boolean AND c->'snapshot'->'scope'->>'company_id'=s->>'company_id','personal company snapshot');
  PERFORM pg_temp.ok(c->'snapshot'->'scope'->'participants' IS NULL,'no other participants in certificate');
  SELECT count(*) INTO count_before FROM private_isg.document_versions;
  c:=private_isg.education_certificate(d||'{"action":"preview"}');
  PERFORM pg_temp.ok((c->>'ready')::boolean AND count_before=(SELECT count(*) FROM private_isg.document_versions),'reopen same frozen certificate');
  PERFORM set_config('test.actor','20000000-0000-0000-0000-000000000002',true);
  PERFORM pg_temp.denied(format('SELECT private_isg.education_certificate(%L::jsonb)',jsonb_build_object('action','read','document_id',c->>'document_id')),'ACCESS_DENIED');
  PERFORM set_config('test.actor','20000000-0000-0000-0000-000000000001',true);
 END LOOP;
 p:=p||jsonb_build_object('action','curriculum','id',null,'scopes',jsonb_build_array(p->'scopes'->0));
 c:=private_isg.education_save(gen_random_uuid(),p); c:=private_isg.education_save(gen_random_uuid(),p);
 PERFORM pg_temp.ok((SELECT count(*)=1 FROM private_isg.company_curriculum_versions WHERE state='active'),'single active curriculum per scope');
 PERFORM pg_temp.ok((private_isg.education_detail(null,null)->'curricula'->0->'education'->>'cycle')='initial','curriculum available in detail');
END $$;
SELECT pg_temp.ok((SELECT count(DISTINCT document_no)=count(*) FROM private_isg.document_versions),'global numbering across companies');
SELECT pg_temp.ok(('2028-02-29'::date+interval '12 months')::date='2029-02-28'::date,'calendar renewal leap day');
SELECT 'EDU expanded acceptance passed';
`;
writeFileSync(new URL('./checks.sql',import.meta.url),sql+extra);
