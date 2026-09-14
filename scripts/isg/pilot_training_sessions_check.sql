-- Local disposable database only. No fixture data is committed.
BEGIN;
SET LOCAL test.actor='20000000-0000-0000-0000-000000000001';
INSERT INTO public.companies(id,user_id,name,hazard_class) VALUES
 ('10000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001','Low fixture','low');
INSERT INTO private_isg.employees(id,company_id,owner_id,full_name) VALUES
 ('30000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001','Second employee');
DO $$
DECLARE basic uuid; renewal uuid; custom uuid; sid uuid; payload jsonb; response jsonb; replay jsonb;
 mutation uuid:=gen_random_uuid(); total integer;
BEGIN
 SELECT id INTO basic FROM private_isg.pilot_training_catalog WHERE code='basic';
 SELECT id INTO renewal FROM private_isg.pilot_training_catalog WHERE code='renewal';
 payload:=jsonb_build_object('action','save','catalog_id',basic,'trainer','Fixture expert','held_on','2026-09-14',
  'method','mixed','confirmed',true,'companies',jsonb_build_array(
   jsonb_build_object('id','10000000-0000-0000-0000-000000000001','participants',jsonb_build_array('30000000-0000-0000-0000-000000000001')),
   jsonb_build_object('id','10000000-0000-0000-0000-000000000003','participants',jsonb_build_array('30000000-0000-0000-0000-000000000003'))));
 response:=public.isg_pilot_training_record_v2(mutation,payload);
 sid:=(response->'row'->>'id')::uuid;
 IF jsonb_array_length(response->'row'->'companies')<>2 THEN RAISE EXCEPTION 'multi company failed'; END IF;
 IF response->'row'->'companies'->0->>'duration_minutes'<>'960' OR response->'row'->'companies'->0->>'valid_until'<>'2027-09-14'
 OR response->'row'->'companies'->1->>'duration_minutes'<>'480' OR response->'row'->'companies'->1->>'valid_until'<>'2029-09-14'
 OR response->'row'->'companies'->0->>'state'<>'completed' THEN RAISE EXCEPTION 'rules/completion failed'; END IF;
 replay:=public.isg_pilot_training_record_v2(mutation,payload);
 IF replay<>response OR (SELECT count(*) FROM private_isg.pilot_training_sessions WHERE id=sid)<>1 THEN RAISE EXCEPTION 'replay failed'; END IF;
 BEGIN PERFORM public.isg_pilot_training_record_v2(mutation,payload||'{"trainer":"changed"}'); RAISE EXCEPTION 'wrong replay accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'IDEMPOTENCY_CONFLICT' THEN RAISE; END IF; END;
 IF jsonb_array_length(public.isg_pilot_training_sessions_v2()->'rows')<>1 OR
 jsonb_array_length(public.isg_pilot_training_sessions_v2('10000000-0000-0000-0000-000000000003')->'rows')<>1 THEN RAISE EXCEPTION 'list failed'; END IF;
 BEGIN PERFORM public.isg_pilot_training_record_v2(gen_random_uuid(),payload||'{"method":"online"}'); RAISE EXCEPTION 'online accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'WORKPLACE_FACE_TO_FACE_REQUIRED' THEN RAISE; END IF; END;
 BEGIN PERFORM public.isg_pilot_training_record_v2(gen_random_uuid(),payload||'{"held_on":"2099-01-01"}'); RAISE EXCEPTION 'future accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'VALIDATION_ERROR' THEN RAISE; END IF; END;
 BEGIN PERFORM public.isg_pilot_training_record_v2(gen_random_uuid(),payload||'{"confirmed":false}'); RAISE EXCEPTION 'unconfirmed accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'VALIDATION_ERROR' THEN RAISE; END IF; END;
 BEGIN PERFORM public.isg_pilot_training_record_v2(gen_random_uuid(),jsonb_set(payload,'{companies,1,participants}', '["30000000-0000-0000-0000-000000000002"]')); RAISE EXCEPTION 'foreign participant accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PARTICIPANT_UNAVAILABLE' THEN RAISE; END IF; END;
 IF (SELECT count(*) FROM private_isg.pilot_training_sessions)<>1 THEN RAISE EXCEPTION 'partial write persisted'; END IF;
 payload:=payload||jsonb_build_object('id',sid,'expected_version',1,'catalog_id',renewal);
 response:=public.isg_pilot_training_record_v2(gen_random_uuid(),payload);
 IF response->'row'->>'version'<>'2' OR response->'row'->'companies'->0->>'duration_minutes'<>'480' THEN RAISE EXCEPTION 'edit/renewal failed'; END IF;
 IF (SELECT count(*) FROM private_isg.pilot_training_session_revisions WHERE session_id=sid)<>1 THEN RAISE EXCEPTION 'history failed'; END IF;
 BEGIN PERFORM public.isg_pilot_training_record_v2(gen_random_uuid(),payload); RAISE EXCEPTION 'stale accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'VERSION_CONFLICT' THEN RAISE; END IF; END;
 response:=public.isg_pilot_training_record_v2(gen_random_uuid(),jsonb_build_object('action','catalog','company_id','10000000-0000-0000-0000-000000000001','title','Fixture custom','minutes',90,'months',6));
 custom:=(response->'catalog'->>'id')::uuid;
 IF response->'catalog'->>'code'<>'custom' OR response->'catalog'->>'content_approved'<>'false' THEN RAISE EXCEPTION 'custom scope failed'; END IF;
 response:=public.isg_pilot_training_record_v2(gen_random_uuid(),payload||jsonb_build_object('expected_version',2,'catalog_id',custom));
 IF response->'row'->'companies'->0->>'valid_until'<>'2027-03-14' OR response->'row'->'companies'->0->>'duration_minutes'<>'90' THEN RAISE EXCEPTION 'custom rule failed'; END IF;
 PERFORM set_config('test.actor','20000000-0000-0000-0000-000000000002',true);
 IF jsonb_array_length(public.isg_pilot_training_sessions_v2()->'rows')<>0 THEN RAISE EXCEPTION 'cross owner read'; END IF;
 BEGIN PERFORM public.isg_pilot_training_record_v2(gen_random_uuid(),payload||'{"expected_version":3}'); RAISE EXCEPTION 'cross owner edit';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'ACCESS_DENIED' THEN RAISE; END IF; END;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.isg_pilot_training_sessions_v2()->'catalog') v WHERE v->>'id'=custom::text) THEN RAISE EXCEPTION 'custom leakage'; END IF;
 PERFORM set_config('test.actor','20000000-0000-0000-0000-000000000001',true);
 mutation:=gen_random_uuid(); payload:=jsonb_build_object('action','delete','id',sid,'expected_version',3);
 response:=public.isg_pilot_training_record_v2(mutation,payload);
 IF response->'row'->>'deleted_at' IS NULL OR jsonb_array_length(public.isg_pilot_training_sessions_v2()->'rows')<>0 THEN RAISE EXCEPTION 'delete failed'; END IF;
 IF (SELECT count(*) FROM private_isg.pilot_training_session_revisions WHERE session_id=sid)<>3 THEN RAISE EXCEPTION 'delete history missing'; END IF;
 IF public.isg_pilot_training_record_v2(mutation,payload)<>response THEN RAISE EXCEPTION 'delete replay failed'; END IF;
 PERFORM set_config('test.expired','true',true);
 BEGIN PERFORM public.isg_pilot_training_record_v2(mutation,payload); RAISE EXCEPTION 'expired replay allowed';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'FEATURE_UNAVAILABLE' THEN RAISE; END IF; END;
 IF has_table_privilege('authenticated','private_isg.pilot_training_sessions','insert') OR
 has_function_privilege('anon','public.isg_pilot_training_record_v2(uuid,jsonb)','execute') THEN RAISE EXCEPTION 'privilege breach'; END IF;
 RAISE NOTICE 'PASS: grouped save, automatic rules, immediate completion, replay/conflict, filters, online restrictions, future/attestation, foreign participant, atomicity, edit/version/history, custom ownership, delete/replay, expiry, grants';
END $$;
ROLLBACK;
