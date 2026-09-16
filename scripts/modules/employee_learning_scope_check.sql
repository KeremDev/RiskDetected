BEGIN;
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',true);
SELECT set_config('test.pilot','true',true);
UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true;
UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='training';
UPDATE private_isg.module_registry SET read_enabled=true,write_enabled=true;
DO $$ DECLARE p uuid; c uuid; r jsonb; BEGIN
 SELECT id,company_id INTO p,c FROM private_isg.employees WHERE company_id='10000000-0000-0000-0000-000000000001' AND NOT is_archived LIMIT 1;
 r:=public.isg_pilot_employee_learning_v1(c,p);
 IF r->>'employee_id'<>p::text OR r->>'certificate_issued'<>'false' THEN RAISE EXCEPTION 'learning scope'; END IF;
 IF NOT private_isg.notice_kind_available('training') THEN RAISE EXCEPTION 'pilot notice follows P07 gate'; END IF;
 BEGIN PERFORM public.isg_pilot_employee_learning_v1(c,gen_random_uuid());RAISE EXCEPTION 'wrong employee';EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'ACCESS_DENIED' THEN RAISE; END IF;END;
 RAISE NOTICE 'ok pilot learning works with P07 disabled / employee isolation / no certificate issued';
END $$;
ROLLBACK;
