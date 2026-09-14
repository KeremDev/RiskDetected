BEGIN;
CREATE FUNCTION pg_temp.must_refuse(sql text,want text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE sql; EXCEPTION WHEN OTHERS THEN
 IF SQLERRM=want THEN RAISE NOTICE 'ok pilot guard %',want; RETURN; END IF; RAISE; END;
 RAISE EXCEPTION 'Expected % for %',want,sql;
END $$;
UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='modules';
UPDATE private_isg.module_registry SET read_enabled=true,write_enabled=true;
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',true);
SELECT set_config('test.pilot','false',true);
SELECT pg_temp.must_refuse('SELECT public.isg_emergency_plans_read_v1(NULL,''list'',NULL,NULL,NULL,NULL,10,0)','FEATURE_UNAVAILABLE');
SELECT pg_temp.must_refuse('SELECT public.isg_drills_read_v1(NULL,''list'',NULL,NULL,NULL,NULL,10,0)','FEATURE_UNAVAILABLE');
SELECT pg_temp.must_refuse('SELECT public.isg_ppe_read_v1(NULL,''list'',NULL,NULL,NULL,NULL,10,0)','FEATURE_UNAVAILABLE');
SELECT pg_temp.must_refuse('SELECT public.isg_appointments_read_v1(NULL,''list'',NULL,NULL,NULL,NULL,NULL,10,0)','FEATURE_UNAVAILABLE');
SELECT set_config('test.pilot','true',true);
SELECT set_config('test.pilot_write','false',true);
SELECT pg_temp.must_refuse('SELECT public.isg_emergency_plans_mutate_v1(''10000000-0000-0000-0000-000000000001'',''publish_plan'',gen_random_uuid(),gen_random_uuid(),''{}'')','FEATURE_UNAVAILABLE');
SELECT pg_temp.must_refuse('SELECT public.isg_drills_mutate_v1(''10000000-0000-0000-0000-000000000001'',''plan_drill'',gen_random_uuid(),gen_random_uuid(),''{}'')','FEATURE_UNAVAILABLE');
SELECT pg_temp.must_refuse('SELECT public.isg_ppe_mutate_v1(''10000000-0000-0000-0000-000000000001'',''record_handover'',gen_random_uuid(),gen_random_uuid(),''{}'')','FEATURE_UNAVAILABLE');
SELECT pg_temp.must_refuse('SELECT public.isg_appointments_mutate_v1(''10000000-0000-0000-0000-000000000001'',''record_appointment'',gen_random_uuid(),gen_random_uuid(),''{}'')','FEATURE_UNAVAILABLE');
ROLLBACK;
