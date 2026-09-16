BEGIN;
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',true);
SELECT set_config('test.pilot','true',true);
SELECT set_config('test.pilot_write','true',true);
UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true;
UPDATE private_isg.module_registry SET read_enabled=true,write_enabled=true;
DO $$ DECLARE v jsonb; r jsonb; m uuid:=gen_random_uuid(); o uuid:=gen_random_uuid(); BEGIN
 v:='{"kind":"board","values":{"workplace_id":"40000000-0000-0000-0000-000000000001","applicability":"mandatory","agenda":["Saha gözlemleri"],"initial_decisions":["Korkuluk tamamlanacak","Eğitim verilecek"],"planned_on":"2026-01-01","held_on":"2026-01-01","state":"held","attendance":[]}}';
 r:=public.isg_pilot_process_mutate_v1('10000000-0000-0000-0000-000000000001','save',o,m,v);
 PERFORM public.isg_pilot_process_mutate_v1('10000000-0000-0000-0000-000000000001','save',o,m,v);
 IF (SELECT count(*) FROM private_isg.board_decisions WHERE meeting_id=(r->>'id')::uuid)<>2 OR r->'child_summary'->>'open'<>'2' THEN RAISE EXCEPTION 'decisions duplicated or missing'; END IF;
 IF (SELECT string_agg(decision_no::text,',' ORDER BY decision_no) FROM private_isg.board_decisions WHERE meeting_id=(r->>'id')::uuid)<>'1,2' THEN RAISE EXCEPTION 'decision numbering'; END IF;
 RAISE NOTICE 'ok board inline decisions atomic / numbered / replay safe / company tracking';
END $$;
ROLLBACK;
