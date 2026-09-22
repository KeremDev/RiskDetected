BEGIN;
INSERT INTO auth.users VALUES ('10000000-0000-0000-0000-000000000001'),('10000000-0000-0000-0000-000000000002'),('10000000-0000-0000-0000-000000000003');
INSERT INTO private_isg.workspaces VALUES ('20000000-0000-0000-0000-000000000001'),('20000000-0000-0000-0000-000000000002');
INSERT INTO private_isg.workspace_memberships VALUES
 (gen_random_uuid(),'20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','expert','active',now()-interval '1 day',null,null),
 (gen_random_uuid(),'20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002','owner','active',now()-interval '1 day',null,null),
 (gen_random_uuid(),'20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000003','owner','active',now()-interval '1 day',null,null);
SELECT set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","session_id":"30000000-0000-0000-0000-000000000001"}',true);
DO $$ DECLARE v jsonb; BEGIN
 PERFORM public.isg_usage_presence_v1('start','20000000-0000-0000-0000-000000000001');
 UPDATE private_isg.usage_sessions SET last_seen_at=clock_timestamp()-interval '60 seconds';
 v:=public.isg_usage_presence_v1('heartbeat','20000000-0000-0000-0000-000000000001');
 ASSERT (v->>'accepted_seconds')::numeric BETWEEN 60 AND 62,'heartbeat credit';
 UPDATE private_isg.usage_sessions SET last_seen_at=clock_timestamp()-interval '5 minutes';
 v:=public.isg_usage_presence_v1('heartbeat','20000000-0000-0000-0000-000000000001');
 ASSERT (v->>'accepted_seconds')::numeric=0,'offline time must not accrue';
 PERFORM public.isg_usage_presence_v1('start','20000000-0000-0000-0000-000000000001');
 ASSERT (SELECT count(*)=1 FROM private_isg.usage_sessions),'refresh deduplication';
 PERFORM public.isg_usage_presence_v1('stop','20000000-0000-0000-0000-000000000001');
 ASSERT (SELECT NOT running FROM private_isg.usage_sessions),'stop closes presence';
 v:=public.isg_activity_self_v1();
 ASSERT (v->'summary'->>'login_count')::int=1,'summary login count';
 ASSERT (v->'summary'->>'total_seconds')::numeric>=60,'summary total';
 ASSERT NOT has_table_privilege('authenticated','private_isg.business_activity_events','SELECT'),'private journal';
END $$;
INSERT INTO private_isg.workspace_audit VALUES (1,'20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','company.update','company',gen_random_uuid(),'{"status":"active","email":"secret@example.com"}','{"status":"archived","body":"private text"}',gen_random_uuid(),now());
DO $$ DECLARE v jsonb; BEGIN
 v:=public.isg_activity_self_v1();
 ASSERT jsonb_array_length(v->'items')=1,'audit bridge';
 v:=public.isg_activity_event_detail_v1((v->'items'->0->>'id')::bigint);
 ASSERT v::text NOT LIKE '%private text%' AND v::text NOT LIKE '%secret@example.com%','privacy';
 ASSERT jsonb_array_length(v->'changes')=1,'safe changes';
END $$;
SELECT set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","session_id":"30000000-0000-0000-0000-000000000002"}',true);
DO $$ DECLARE v jsonb; BEGIN
 v:=public.isg_workspace_member_activity_v1('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001');
 ASSERT jsonb_array_length(v->'items')=1,'authorized manager';
 BEGIN
  PERFORM public.isg_workspace_member_activity_v1('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001');
  RAISE EXCEPTION 'cross tenant request accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'ACCESS_DENIED' THEN RAISE; END IF; END;
END $$;
ROLLBACK;
