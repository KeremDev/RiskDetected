BEGIN;
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',true);
SELECT set_config('test.pilot','true',true);
SELECT set_config('test.pilot_write','true',true);
UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true;
UPDATE private_isg.module_registry SET read_enabled=true,write_enabled=true;
CREATE FUNCTION pg_temp.process_save(k text,v jsonb,r jsonb DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$ SELECT public.isg_pilot_process_mutate_v1('10000000-0000-0000-0000-000000000001','save',gen_random_uuid(),gen_random_uuid(),jsonb_build_object('kind',k,'values',v,'id',r->>'id','expected',r->>'expected')) $$;
CREATE TEMP TABLE records(kind text,r jsonb);
INSERT INTO records VALUES ('katip_contract',pg_temp.process_save('katip_contract','{"workplace_id":"40000000-0000-0000-0000-000000000001","counterparty":"Sözleşme","expert_contact":"Uzman","scope":"İSG","starts_on":"2026-01-01","declared_monthly_minutes":12}'));
INSERT INTO records VALUES ('annual_work_plan',pg_temp.process_save('annual_work_plan','{"workplace_id":"40000000-0000-0000-0000-000000000001","plan_year":2026}'));
INSERT INTO records SELECT 'annual_work_item',pg_temp.process_save('annual_work_item',jsonb_build_object('plan_id',r->>'id','activity','Faaliyet','planned_on','2026-01-01','state','planned')) FROM records WHERE kind='annual_work_plan';
INSERT INTO records VALUES ('board',pg_temp.process_save('board','{"workplace_id":"40000000-0000-0000-0000-000000000001","applicability":"voluntary","agenda":["Gündem"],"planned_on":"2026-01-01","state":"planned"}'));
INSERT INTO records SELECT 'board_decision',pg_temp.process_save('board_decision',jsonb_build_object('meeting_id',r->>'id','decision_no',1,'decision_text','Karar','state','open')) FROM records WHERE kind='board';
INSERT INTO records VALUES ('site_visit',pg_temp.process_save('site_visit','{"workplace_id":"40000000-0000-0000-0000-000000000001","visited_on":"2026-01-01","expert_note":"Saha ziyareti"}'));
INSERT INTO records SELECT 'site_observation',pg_temp.process_save('site_observation',jsonb_build_object('visit_id',r->>'id','note','Gözlem')) FROM records WHERE kind='site_visit';
INSERT INTO records VALUES ('work_permit',pg_temp.process_save('work_permit','{"workplace_id":"40000000-0000-0000-0000-000000000001","template_code":"hot_work","job_description":"İş","planned_on":"2026-01-01","parties":[]}'));
INSERT INTO records VALUES ('contractor',pg_temp.process_save('contractor','{"code":"C1","name":"Dış firma","relationship":"contractor"}'));
INSERT INTO records SELECT 'contractor_engagement',pg_temp.process_save('contractor_engagement',jsonb_build_object('organization_id',r->>'id','workplace_id','40000000-0000-0000-0000-000000000001','starts_on','2026-01-01','description','İş')) FROM records WHERE kind='contractor';


INSERT INTO private_isg.pilot_training_records(company_id,owner_id,title,trainer,starts_at,duration_minutes,state) VALUES
('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Tamamlanan eğitim','Uzman','2026-01-01',120,'completed'),
('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Plan eğitim','Uzman','2026-01-01',120,'planned');
INSERT INTO private_isg.equipment_items(company_id,owner_id,workplace_id,equipment_type,serial_tag) VALUES ('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','test_type','LINK-TEST');
INSERT INTO private_isg.equipment_inspections(equipment_id,performed_on,result) SELECT equipment_id,'2026-01-01','fail' FROM private_isg.equipment_items WHERE serial_tag='LINK-TEST';
SELECT public.isg_nonconformity_mutate_v1('10000000-0000-0000-0000-000000000001','open_detailed',gen_random_uuid(),gen_random_uuid(),'{"workplace_id":"40000000-0000-0000-0000-000000000001","title":"LINK-NC","severity":"high","description":"Saha gözlemi"}');
DO $$ DECLARE kind text; page jsonb; linked jsonb; a jsonb; vals jsonb; co uuid:='10000000-0000-0000-0000-000000000001'; spec jsonb; BEGIN
 SELECT r INTO a FROM records WHERE records.kind='annual_work_item';
 spec:=private_isg.process_spec('annual_work_item');
 SELECT jsonb_object_agg(key,value) INTO vals FROM jsonb_each(a->'values') WHERE spec->'fields' ? key;
 FOREACH kind IN ARRAY ARRAY['training_record','equipment_inspection','nonconformity'] LOOP
  page:=public.isg_pilot_process_references_v1(kind,co,NULL,NULL,0);
  IF jsonb_array_length(page->'rows')<>1 THEN RAISE EXCEPTION 'Reference count %: %',kind,page; END IF;
  linked:=page->'rows'->0;
  IF public.isg_pilot_process_references_v1(kind,co,(linked->>'id')::uuid,NULL,0)->'rows'->0 IS DISTINCT FROM linked THEN RAISE EXCEPTION 'Reference read mismatch'; END IF;
  a:=public.isg_pilot_process_mutate_v1(co,'save',gen_random_uuid(),gen_random_uuid(),jsonb_build_object('kind','annual_work_item','id',a->>'id','expected',a->>'expected','values',vals,'related_kind',kind,'related_id',linked->>'id'));
  IF a->>'related_id' IS DISTINCT FROM linked->>'id' OR a->'values'->>'state'<>'planned' THEN RAISE EXCEPTION 'Link/state mismatch'; END IF;
  IF jsonb_array_length(public.isg_pilot_process_references_v1(kind,co,NULL,'not-matching-record',0)->'rows')<>0 THEN RAISE EXCEPTION 'Search mismatch'; END IF;
  PERFORM set_config('test.actor','20000000-0000-0000-0000-000000000002',true);
  BEGIN PERFORM public.isg_pilot_process_references_v1(kind,co,(linked->>'id')::uuid,NULL,0); RAISE EXCEPTION 'Owner leak';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'ACCESS_DENIED' THEN RAISE; END IF; END;
  PERFORM set_config('test.actor','20000000-0000-0000-0000-000000000001',true);
  RAISE NOTICE 'ok cross-module reference % list/read/link/search/owner',kind;
 END LOOP;
END $$;
ROLLBACK;
