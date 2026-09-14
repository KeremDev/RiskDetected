BEGIN;
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',true);
SELECT set_config('test.pilot','true',true);
SELECT set_config('test.pilot_write','true',true);
UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true;
UPDATE private_isg.module_registry SET read_enabled=true,write_enabled=true;
CREATE FUNCTION pg_temp.ok(condition boolean,label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF condition IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL %',label; END IF; RAISE NOTICE 'ok management %',label; END $$;
CREATE FUNCTION pg_temp.refuses(sql text,want text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN BEGIN EXECUTE sql; EXCEPTION WHEN OTHERS THEN IF SQLERRM=want THEN RAISE NOTICE 'ok management refuses %',want; RETURN; END IF; RAISE; END; RAISE EXCEPTION 'Expected %',want; END $$;
CREATE FUNCTION pg_temp.edit(m text,k uuid,a text,v jsonb,doc uuid DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.isg_pilot_module_mutate_v1('10000000-0000-0000-0000-000000000001',a,gen_random_uuid(),gen_random_uuid(),jsonb_build_object('module',m,'id',k,'expected',public.isg_pilot_module_editor_v1(m,'10000000-0000-0000-0000-000000000001',k)->>'expected','values',v,'document_id',doc))
$$;
CREATE TEMP TABLE test_ids(kind text,id uuid);
INSERT INTO test_ids SELECT 'ppe',(public.isg_ppe_mutate_v1('10000000-0000-0000-0000-000000000001','record_handover',gen_random_uuid(),gen_random_uuid(),'{"employee_id":"30000000-0000-0000-0000-000000000001","item":"Baret","quantity":2,"unit":"piece","handed_on":"2026-01-01"}')->>'handover_id')::uuid;
SELECT pg_temp.edit('ppe',(SELECT id FROM test_ids WHERE kind='ppe'),'update','{"employee_id":"30000000-0000-0000-0000-000000000001","item":"Yeni baret","quantity":"3.5","unit":"piece","handed_on":"2026-01-01","signed_copy_location":"Dolap"}');
SELECT pg_temp.ok((SELECT item='Yeni baret' AND quantity=3.5 FROM private_isg.ppe_handovers),'PPE fields updated');
INSERT INTO private_isg.document_obligations(obligation_id,company_id,owner_id,kind_code,title) VALUES
 ('70000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','ppe_handover','Zimmet belgesi'),
 ('70000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','ppe_handover','Diğer belge');
SELECT pg_temp.edit('ppe',(SELECT id FROM test_ids WHERE kind='ppe'),'link_document','{}','70000000-0000-0000-0000-000000000001');
SELECT pg_temp.ok((SELECT obligation_id='70000000-0000-0000-0000-000000000001' FROM private_isg.module_record_links),'document linked');
SELECT pg_temp.refuses(format('SELECT pg_temp.edit(''ppe'',%L,''link_document'',''{}'',''70000000-0000-0000-0000-000000000002'')',(SELECT id FROM test_ids WHERE kind='ppe')),'ACCESS_DENIED');
SELECT pg_temp.edit('ppe',(SELECT id FROM test_ids WHERE kind='ppe'),'link_document','{}',NULL);
SELECT pg_temp.ok((SELECT obligation_id IS NULL FROM private_isg.module_record_links),'document unlinked without deletion');
SELECT pg_temp.refuses(format('SELECT public.isg_pilot_module_mutate_v1(''10000000-0000-0000-0000-000000000001'',''delete'',gen_random_uuid(),gen_random_uuid(),jsonb_build_object(''module'',''ppe'',''id'',%L,''expected'',''stale''))',(SELECT id FROM test_ids WHERE kind='ppe')),'VERSION_CONFLICT');
SELECT pg_temp.edit('ppe',(SELECT id FROM test_ids WHERE kind='ppe'),'delete','{}');
SELECT pg_temp.ok((public.isg_ppe_read_v1(NULL,'list',NULL,NULL,NULL,NULL,10,0)->>'total')='0','deleted PPE hidden from list');
SELECT pg_temp.ok((SELECT count(*)=1 FROM private_isg.ppe_handovers WHERE is_deleted),'deleted PPE retained');
INSERT INTO test_ids SELECT 'appointment',(public.isg_appointments_mutate_v1('10000000-0000-0000-0000-000000000001','record_appointment',gen_random_uuid(),gen_random_uuid(),'{"employee_id":"30000000-0000-0000-0000-000000000001","workplace_id":"40000000-0000-0000-0000-000000000001","kind":"representative","starts_on":"2026-01-01","basis":"elected"}')->>'appointment_id')::uuid;
SELECT pg_temp.edit('appointment',(SELECT id FROM test_ids WHERE kind='appointment'),'update','{"employee_id":"30000000-0000-0000-0000-000000000002","scope_workplace_id":"40000000-0000-0000-0000-000000000001","kind":"support_staff","starts_on":"2026-01-02","ends_before":null,"basis":"appointed","basis_note":"Yeni atama","letter_location":"Dosya"}');
SELECT pg_temp.ok((SELECT employee_id='30000000-0000-0000-0000-000000000002' AND kind='support_staff' FROM private_isg.appointments),'appointment person and role edited');
SELECT pg_temp.edit('appointment',(SELECT id FROM test_ids WHERE kind='appointment'),'delete','{}');
SELECT pg_temp.ok((public.isg_appointments_read_v1(NULL,'list',NULL,NULL,NULL,NULL,NULL,10,0)->>'total')='0','deleted appointment hidden');
INSERT INTO test_ids SELECT 'emergency_plan',(public.isg_emergency_plans_mutate_v1('10000000-0000-0000-0000-000000000001','publish_plan',gen_random_uuid(),gen_random_uuid(),'{"workplace_id":"40000000-0000-0000-0000-000000000001","scope":"Plan","prepared_on":"2026-01-01","team":[{"full_name":"Kişi","role":"coordinator"}]}')->>'plan_id')::uuid;
SELECT pg_temp.edit('emergency_plan',(SELECT id FROM test_ids WHERE kind='emergency_plan'),'update','{"workplace_id":"40000000-0000-0000-0000-000000000001","scope":"Düzeltilmiş plan","prepared_on":"2026-01-01","valid_until":null,"review_note":"Dayanak","team_snapshot":[{"full_name":"Yeni kişi","role":"fire"}]}');
SELECT pg_temp.ok((SELECT count(*)=2 FROM private_isg.emergency_plan_versions),'plan edit retains previous revision');
INSERT INTO test_ids SELECT 'drill',(public.isg_drills_mutate_v1('10000000-0000-0000-0000-000000000001','plan_drill',gen_random_uuid(),gen_random_uuid(),jsonb_build_object('plan_id',(SELECT id FROM test_ids WHERE kind='emergency_plan'),'planned_on','2026-01-02'))->>'drill_id')::uuid;
SELECT pg_temp.edit('drill',(SELECT id FROM test_ids WHERE kind='drill'),'update',jsonb_build_object('plan_id',(SELECT id FROM test_ids WHERE kind='emergency_plan'),'planned_on','2026-02-01','observation','Yeni gözlem','improvement','Aksiyon'));
SELECT pg_temp.ok((SELECT planned_on='2026-02-01' FROM private_isg.drill_records),'drill date edited');
SELECT pg_temp.refuses(format('SELECT pg_temp.edit(''emergency_plan'',%L,''delete'',''{}'')',(SELECT id FROM test_ids WHERE kind='emergency_plan')),'DEPENDENT_RECORDS');
SELECT pg_temp.edit('drill',(SELECT id FROM test_ids WHERE kind='drill'),'delete','{}');
SELECT pg_temp.ok((public.isg_drills_read_v1(NULL,'list',NULL,NULL,NULL,NULL,10,0)->>'total')='0','deleted drill hidden');
SELECT pg_temp.edit('emergency_plan',(SELECT id FROM test_ids WHERE kind='emergency_plan'),'delete','{}');
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM private_isg.emergency_plan_versions WHERE NOT is_deleted),'plan all revisions deleted from active view');
SELECT pg_temp.ok((SELECT count(*)>=10 FROM private_isg.module_record_history),'history retained');
-- A deleted row cannot be changed via older RPC paths either.
SELECT pg_temp.refuses(format('SELECT public.isg_appointments_mutate_v1(''10000000-0000-0000-0000-000000000001'',''end_appointment'',gen_random_uuid(),gen_random_uuid(),jsonb_build_object(''appointment_id'',%L,''ends_before'',''2026-12-01''))',(SELECT id FROM test_ids WHERE kind='appointment')),'RECORD_DELETED');
-- Deleting an appointment releases only the active overlap range.
SELECT public.isg_appointments_mutate_v1('10000000-0000-0000-0000-000000000001','record_appointment',gen_random_uuid(),gen_random_uuid(),'{"employee_id":"30000000-0000-0000-0000-000000000002","workplace_id":"40000000-0000-0000-0000-000000000001","kind":"support_staff","starts_on":"2026-01-02","basis":"appointed"}');
SELECT pg_temp.ok((SELECT count(*)=1 FROM private_isg.appointments WHERE NOT is_deleted),'deleted appointment releases overlap');
SELECT set_config('test.pilot','false',true);
SELECT pg_temp.refuses('SELECT public.isg_pilot_module_editor_v1(''ppe'',''10000000-0000-0000-0000-000000000001'',gen_random_uuid())','FEATURE_UNAVAILABLE');
SELECT set_config('test.pilot','true',true);
SELECT pg_temp.refuses('SELECT public.isg_pilot_module_editor_v1(''ppe'',''10000000-0000-0000-0000-000000000002'',gen_random_uuid())','ACCESS_DENIED');
ROLLBACK;
