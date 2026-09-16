BEGIN;
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',true);
SELECT set_config('test.pilot','true',true);
SELECT set_config('test.pilot_write','true',true);
UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true;
UPDATE private_isg.module_registry SET read_enabled=true,write_enabled=true;
INSERT INTO private_isg.file_assets VALUES
 ('50000000-0000-0000-0000-000000000011','20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','image/png','clean'),
 ('50000000-0000-0000-0000-000000000012','20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','application/pdf','clean'),
 ('50000000-0000-0000-0000-000000000013','20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','image/jpeg','clean');
INSERT INTO private_isg.file_library_entries(asset_id,owner_id,company_id) SELECT asset_id,owner_id,company_id FROM private_isg.file_assets;
CREATE FUNCTION pg_temp.visit_save(k text,v jsonb,r jsonb DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS $$ SELECT public.isg_pilot_process_mutate_v1('10000000-0000-0000-0000-000000000001','save',gen_random_uuid(),gen_random_uuid(),jsonb_build_object('kind',k,'values',v,'id',r->>'id','expected',r->>'expected')) $$;
DO $$ DECLARE v jsonb:='{"workplace_id":"40000000-0000-0000-0000-000000000001","visited_on":"2026-01-01","expert_note":"Saha incelemesi","responsible_contact":"Ada","duration_minutes":75,"visit_asset_id":"50000000-0000-0000-0000-000000000011"}';
 r jsonb; r2 jsonb; board jsonb; summary jsonb; data jsonb; bad jsonb; op uuid:=gen_random_uuid(); mutation uuid:=gen_random_uuid(); payload jsonb;
BEGIN
 r:=pg_temp.visit_save('site_visit',v);
 IF r->'values'->>'duration_minutes'<>'75' THEN RAISE EXCEPTION 'duration not persisted'; END IF;
 PERFORM public.isg_pilot_process_attachment_v1('site_visit',(r->>'id')::uuid,'visit_asset_id');
 r2:=pg_temp.visit_save('site_visit',(v-'duration_minutes'-'visit_asset_id')||'{"expert_note":"Güncellenen ziyaret"}',r);
 IF r2->'values'->>'duration_minutes'<>'75' OR r2->'values'->>'visit_asset_id'<>v->>'visit_asset_id' THEN RAISE EXCEPTION 'legacy edit erased new fields'; END IF;
 BEGIN PERFORM pg_temp.visit_save('site_visit',v,r);RAISE EXCEPTION 'stale write accepted';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'VERSION_CONFLICT' THEN RAISE; END IF; END;
 r:=r2;
 FOR bad IN SELECT x FROM jsonb_array_elements('[{"duration_minutes":0},{"duration_minutes":-1},{"duration_minutes":1441},{"duration_minutes":1.5},{"duration_minutes":"bad"}]') x LOOP
  BEGIN PERFORM pg_temp.visit_save('site_visit',v||bad);RAISE EXCEPTION 'bad duration accepted';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'VALIDATION_ERROR' THEN RAISE; END IF; END;
 END LOOP;
 FOR bad IN SELECT x FROM jsonb_array_elements('[{"visit_asset_id":"50000000-0000-0000-0000-000000000012"},{"visit_asset_id":"50000000-0000-0000-0000-000000000013"}]') x LOOP
  BEGIN PERFORM pg_temp.visit_save('site_visit',v||bad);RAISE EXCEPTION 'bad photo accepted';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'ACCESS_DENIED' THEN RAISE; END IF; END;
 END LOOP;
 payload:=jsonb_build_object('kind','site_visit','values',v||'{"duration_minutes":null,"visit_asset_id":null}');
 r2:=public.isg_pilot_process_mutate_v1('10000000-0000-0000-0000-000000000001','save',op,mutation,payload);
 IF r2 IS DISTINCT FROM public.isg_pilot_process_mutate_v1('10000000-0000-0000-0000-000000000001','save',op,mutation,payload) THEN RAISE EXCEPTION 'replay not stable'; END IF;
 summary:=public.isg_pilot_visit_summary_v1('10000000-0000-0000-0000-000000000001',NULL,NULL);
 IF summary->>'visits'<>'2' OR summary->>'timed_visits'<>'1' OR summary->>'recorded_minutes'<>'75' THEN RAISE EXCEPTION 'summary counts unknown as zero or duplicate %',summary; END IF;
 IF public.isg_pilot_visit_summary_v1(NULL,'2026-02-01',NULL)->>'visits'<>'0' THEN RAISE EXCEPTION 'date filter'; END IF;
 board:=pg_temp.visit_save('board','{"workplace_id":"40000000-0000-0000-0000-000000000001","applicability":"mandatory","agenda":["A","B"],"planned_on":"2026-01-01","held_on":"2026-01-01","state":"held","attendance":[],"minutes_asset_id":"50000000-0000-0000-0000-000000000012"}');
 PERFORM public.isg_pilot_process_attachment_v1('board',(board->>'id')::uuid,'minutes_asset_id');
 UPDATE private_isg.file_library_entries SET is_archived=true WHERE asset_id='50000000-0000-0000-0000-000000000011';
 BEGIN PERFORM pg_temp.visit_save('site_visit',v);RAISE EXCEPTION 'archived photo accepted';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'ACCESS_DENIED' THEN RAISE; END IF; END;
 PERFORM public.isg_pilot_process_mutate_v1('10000000-0000-0000-0000-000000000001','delete',gen_random_uuid(),gen_random_uuid(),jsonb_build_object('kind','site_visit','id',r->>'id','expected',r->>'expected'));
 summary:=public.isg_pilot_visit_summary_v1(NULL,NULL,NULL);
 IF summary->>'visits'<>'1' OR summary->>'timed_visits'<>'0' OR summary->>'recorded_minutes' IS NOT NULL THEN RAISE EXCEPTION 'deleted still counted/unknown zero'; END IF;
 PERFORM set_config('test.actor','20000000-0000-0000-0000-000000000002',true);
 IF public.isg_pilot_visit_summary_v1(NULL,NULL,NULL)->>'visits'<>'0' THEN RAISE EXCEPTION 'other owner stats leak'; END IF;
 BEGIN PERFORM public.isg_pilot_process_attachment_v1('board',(board->>'id')::uuid,'minutes_asset_id');RAISE EXCEPTION 'other owner attachment leak';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'ACCESS_DENIED' THEN RAISE; END IF; END;
 PERFORM set_config('test.pilot','false',true);
 BEGIN PERFORM public.isg_pilot_visit_summary_v1(NULL,NULL,NULL);RAISE EXCEPTION 'nonpilot stats access';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'FEATURE_UNAVAILABLE' THEN RAISE; END IF; END;
 RAISE NOTICE 'ok visit duration, optional photo, board PDF, replay, legacy edit, optimistic locking, summary, deletion, ownership and pilot gates';
END $$;
ROLLBACK;
