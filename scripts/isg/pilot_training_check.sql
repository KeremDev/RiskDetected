-- Behavioral checks of the register in an isolated fixture. The fixture gate
-- simulates actor/expiry; production P05 gate is reused unchanged by the migration.
BEGIN;
SET LOCAL test.actor='20000000-0000-0000-0000-000000000001';
DO $$
DECLARE company uuid:='10000000-0000-0000-0000-000000000001';
 mutation uuid:=gen_random_uuid(); payload jsonb; receipt jsonb; replay jsonb; target uuid; other uuid;
BEGIN
 payload:=jsonb_build_object('action','save','title','Test training','trainer','Test trainer',
   'starts_at','2026-01-01T10:00:00Z','duration_minutes',60,'participants',jsonb_build_array(
     jsonb_build_object('id','30000000-0000-0000-0000-000000000001','attended',false)));
 receipt:=public.isg_pilot_training_save_v1(company,mutation,payload);
 target:=(receipt->'row'->>'id')::uuid;
 ASSERT receipt->'row'->>'state'='planned';
 ASSERT receipt->'row'->'participants'->0->>'name'='Test Person';
 replay:=public.isg_pilot_training_save_v1(company,mutation,payload);
 ASSERT replay=receipt, 'retry must return the same receipt';
 ASSERT (SELECT count(*) FROM private_isg.pilot_training_records)=1;
 BEGIN
   PERFORM public.isg_pilot_training_save_v1(company,mutation,payload||'{"title":"Changed"}');
   RAISE EXCEPTION 'missing idempotency rejection';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN ASSERT SQLERRM='IDEMPOTENCY_CONFLICT'; END;
 BEGIN
   PERFORM public.isg_pilot_training_save_v1(company,gen_random_uuid(),jsonb_build_object('action','complete','id',target,'expected_version',1));
   RAISE EXCEPTION 'missing attendance rejection';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN ASSERT SQLERRM='ATTENDANCE_REQUIRED'; END;
 BEGIN
   PERFORM public.isg_pilot_training_save_v1(company,gen_random_uuid(),payload||jsonb_build_object('participants',jsonb_build_array(jsonb_build_object('id','30000000-0000-0000-0000-000000000002','attended',false))));
   RAISE EXCEPTION 'foreign participant accepted';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN ASSERT SQLERRM='PARTICIPANT_UNAVAILABLE'; END;
 ASSERT (SELECT count(*) FROM private_isg.pilot_training_records)=1, 'rejected create must be atomic';
 payload:=payload||jsonb_build_object('id',target,'expected_version',1,'participants',jsonb_build_array(jsonb_build_object('id','30000000-0000-0000-0000-000000000001','attended',true)));
 receipt:=public.isg_pilot_training_save_v1(company,gen_random_uuid(),payload);
 ASSERT (receipt->'row'->>'version')::integer=2;
 BEGIN
   PERFORM public.isg_pilot_training_save_v1(company,gen_random_uuid(),payload);
   RAISE EXCEPTION 'stale version accepted';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN ASSERT SQLERRM='VERSION_CONFLICT'; END;
 receipt:=public.isg_pilot_training_save_v1(company,gen_random_uuid(),jsonb_build_object('action','complete','id',target,'expected_version',2));
 ASSERT receipt->'row'->>'state'='completed';
 ASSERT (public.isg_pilot_training_read_v1(company)->>'completed')::integer=1;
 BEGIN
   PERFORM public.isg_pilot_training_save_v1(company,gen_random_uuid(),payload||'{"expected_version":3}');
   RAISE EXCEPTION 'completed record changed';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN ASSERT SQLERRM='TRAINING_LOCKED'; END;
 BEGIN
   PERFORM public.isg_pilot_training_read_v1('10000000-0000-0000-0000-000000000002');
   RAISE EXCEPTION 'foreign company accepted';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN ASSERT SQLERRM='ACCESS_DENIED'; END;
 PERFORM set_config('test.expired','true',true);
 BEGIN
   PERFORM public.isg_pilot_training_save_v1(company,mutation,payload);
   RAISE EXCEPTION 'expired retry accepted';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN ASSERT SQLERRM='ACCESS_DENIED'; END;
 PERFORM set_config('test.expired','false',true);
 payload:=payload-'id'-'expected_version'||jsonb_build_object('starts_at','2099-01-01T10:00:00Z');
 BEGIN
   PERFORM public.isg_pilot_training_save_v1(company,gen_random_uuid(),payload);
   RAISE EXCEPTION 'future attendance accepted';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN ASSERT SQLERRM='FUTURE_ATTENDANCE'; END;
 payload:=jsonb_set(payload,'{participants}','[]');
 receipt:=public.isg_pilot_training_save_v1(company,gen_random_uuid(),payload);
 other:=(receipt->'row'->>'id')::uuid;
 BEGIN
   PERFORM public.isg_pilot_training_save_v1(company,gen_random_uuid(),jsonb_build_object('action','complete','id',other,'expected_version',1));
   RAISE EXCEPTION 'future completion accepted';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN ASSERT SQLERRM='TRAINING_NOT_ENDED'; END;
 receipt:=public.isg_pilot_training_save_v1(company,gen_random_uuid(),jsonb_build_object('action','cancel','id',other,'expected_version',1));
 ASSERT receipt->'row'->>'state'='cancelled';
 ASSERT (SELECT count(*) FROM pg_tables WHERE schemaname='private_isg' AND tablename LIKE 'pilot_training_%' AND rowsecurity)=3;
 ASSERT NOT has_table_privilege('authenticated','private_isg.pilot_training_records','INSERT');
 ASSERT NOT has_function_privilege('anon','public.isg_pilot_training_save_v1(uuid,uuid,jsonb)','EXECUTE');
 RAISE NOTICE 'PASS: create, snapshot, replay, conflict, attendance, cross-company, atomicity, edit, version, completion, immutability, expiry, future guards, cancellation, RLS and grants';
END $$;
ROLLBACK;
