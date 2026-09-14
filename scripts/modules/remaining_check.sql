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
DO $$ DECLARE test record; got jsonb; edited jsonb; vals jsonb; spec jsonb; op uuid; mutation uuid; payload jsonb; BEGIN
FOR test IN SELECT * FROM records LOOP
 got:=public.isg_pilot_process_read_v1(test.kind,NULL,(test.r->>'id')::uuid,NULL,NULL,0);
 IF got IS DISTINCT FROM test.r THEN RAISE EXCEPTION 'Read mismatch %',test.kind; END IF;
 got:=public.isg_pilot_process_read_v1(test.kind,NULL,NULL,NULL,NULL,0);
 IF jsonb_array_length(got->'rows')<>1 THEN RAISE EXCEPTION 'List mismatch %',test.kind; END IF;
 spec:=private_isg.process_spec(test.kind);
 SELECT jsonb_object_agg(key,value) INTO vals FROM jsonb_each(test.r->'values') WHERE spec->'fields' ? key;
 edited:=pg_temp.process_save(test.kind,vals,test.r);
 op:=gen_random_uuid();mutation:=gen_random_uuid();payload:=jsonb_build_object('kind',test.kind,'id',edited->>'id','expected',edited->>'expected');
 got:=public.isg_pilot_process_mutate_v1('10000000-0000-0000-0000-000000000001','export',op,mutation,payload);
 IF got IS DISTINCT FROM public.isg_pilot_process_mutate_v1('10000000-0000-0000-0000-000000000001','export',op,mutation,payload) THEN RAISE EXCEPTION 'Replay mismatch'; END IF;
 RAISE NOTICE 'ok process create/read/list/edit/export/replay %',test.kind;
END LOOP;
END $$;
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000002',true);
DO $$ DECLARE test record; BEGIN FOR test IN SELECT * FROM records LOOP
 BEGIN PERFORM public.isg_pilot_process_read_v1(test.kind,NULL,(test.r->>'id')::uuid,NULL,NULL,0);RAISE EXCEPTION 'Scope leak';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'ACCESS_DENIED' THEN RAISE; END IF; END;
 RAISE NOTICE 'ok process other owner denied %',test.kind;
END LOOP; END $$;

SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',true);
CREATE FUNCTION pg_temp.process_refuses(q text,want text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN IF SQLERRM=want THEN RAISE NOTICE 'ok process refuses %',want; RETURN; END IF; RAISE; END; RAISE EXCEPTION 'Expected %',want; END $$;
SELECT pg_temp.process_refuses(format('SELECT pg_temp.process_save(''annual_work_item'',jsonb_build_object(''plan_id'',%L,''activity'',''Yanlış yıl'',''planned_on'',''2027-01-01''))',r->>'id'),'PLAN_YEAR_MISMATCH') FROM records WHERE kind='annual_work_plan';
SELECT pg_temp.process_refuses('SELECT pg_temp.process_save(''board'',''{"workplace_id":"40000000-0000-0000-0000-000000000001","applicability":"voluntary","agenda":["Gündem"],"planned_on":"2026-01-01","state":"held","held_on":"2026-01-01","attendance":[{"id":"30000000-0000-0000-0000-000000000009","name":"spoof"}]}'')','ACCESS_DENIED');
SELECT pg_temp.process_refuses('SELECT pg_temp.process_save(''site_visit'',''{"workplace_id":"40000000-0000-0000-0000-000000000001","visited_on":"2099-01-01","expert_note":"Gelecek"}'')','FUTURE_DATE');
SELECT pg_temp.process_refuses(format('SELECT public.isg_pilot_process_mutate_v1(''10000000-0000-0000-0000-000000000001'',''delete'',gen_random_uuid(),gen_random_uuid(),jsonb_build_object(''kind'',''board'',''id'',%L,''expected'',%L))',r->>'id',r->>'expected'),'DEPENDENT_RECORDS') FROM records WHERE kind='board';
DO $$ DECLARE r jsonb;v jsonb;got jsonb;old_export jsonb;n integer;BEGIN
SELECT records.r INTO r FROM records WHERE kind='katip_contract';
v:=jsonb_build_object('workplace_id',r->'values'->>'workplace_id','counterparty','Düzeltilmiş taraf','expert_contact','Uzman','scope','İSG','starts_on','2026-01-01');
got:=pg_temp.process_save('katip_contract',v,r);
BEGIN PERFORM pg_temp.process_save('katip_contract',v,r); RAISE EXCEPTION 'Lost-update accepted'; EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'VERSION_CONFLICT' THEN RAISE; END IF; END;
SELECT snapshot INTO old_export FROM private_isg.document_versions WHERE snapshot->>'id'=r->>'id' AND version=1;
PERFORM public.isg_pilot_process_mutate_v1('10000000-0000-0000-0000-000000000001','export',gen_random_uuid(),gen_random_uuid(),jsonb_build_object('kind','katip_contract','id',got->>'id','expected',got->>'expected'));
SELECT count(*) INTO n FROM private_isg.document_versions WHERE snapshot->>'id'=r->>'id';
IF n<>2 OR old_export->'values'->>'counterparty'<>'Sözleşme' THEN RAISE EXCEPTION 'Version history lost'; END IF;
RAISE NOTICE 'ok process optimistic conflict and immutable document revisions';
END $$;
DO $$ DECLARE test record;current_ jsonb;BEGIN
FOR test IN SELECT * FROM records ORDER BY CASE WHEN kind IN ('annual_work_item','board_decision','site_observation','contractor_engagement') THEN 0 ELSE 1 END LOOP
current_:=public.isg_pilot_process_read_v1(test.kind,NULL,(test.r->>'id')::uuid,NULL,NULL,0);
PERFORM public.isg_pilot_process_mutate_v1('10000000-0000-0000-0000-000000000001','delete',gen_random_uuid(),gen_random_uuid(),jsonb_build_object('kind',test.kind,'id',current_->>'id','expected',current_->>'expected'));
IF jsonb_array_length(public.isg_pilot_process_read_v1(test.kind,NULL,NULL,NULL,NULL,0)->'rows')<>0 THEN RAISE EXCEPTION 'Delete visible'; END IF;
RAISE NOTICE 'ok process soft delete %',test.kind;
END LOOP;
END $$;
DO $$ DECLARE d record;got jsonb;BEGIN
FOR d IN SELECT document_id,version,snapshot FROM private_isg.document_versions LOOP
 got:=public.isg_pilot_process_documents_v1(NULL,d.document_id,d.version,0);
 IF got IS DISTINCT FROM d.snapshot THEN RAISE EXCEPTION 'Archived document changed'; END IF;
END LOOP;
IF jsonb_array_length(public.isg_pilot_process_documents_v1(NULL,NULL,NULL,0))=0 THEN RAISE EXCEPTION 'Archive empty'; END IF;
RAISE NOTICE 'ok process archived snapshots survive source deletion';
END $$;
SELECT set_config('test.pilot','false',true);
SELECT pg_temp.process_refuses('SELECT public.isg_pilot_process_read_v1(''board'',NULL,NULL,NULL,NULL,0)','FEATURE_UNAVAILABLE');
ROLLBACK;
