BEGIN;
INSERT INTO auth.users VALUES ('40000000-0000-0000-0000-000000000001'),('40000000-0000-0000-0000-000000000002');
INSERT INTO public.profiles SELECT id FROM auth.users;
SELECT set_config('request.jwt.claims','{"sub":"40000000-0000-0000-0000-000000000001","session_id":"50000000-0000-0000-0000-000000000001"}',true);
DO $$ BEGIN
 ASSERT NOT (public.isg_notebook_rollout_v1()->>'enabled')::boolean,'forward migration must default closed';
END $$;
UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='personal_notes';
INSERT INTO auth.sessions(id,user_id) VALUES('50000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001');
INSERT INTO public.notification_preferences VALUES('40000000-0000-0000-0000-000000000001',true,true);
INSERT INTO public.push_device_tokens VALUES(gen_random_uuid(),'40000000-0000-0000-0000-000000000001','fixture-token','apns','60000000-0000-0000-0000-000000000001',true,'sandbox','com.riskdetected.app.osgbpilot');
SELECT public.isg_notification_device_permission_v1('fixture-token','apns',130,true);
DO $$ DECLARE v jsonb; r uuid; o uuid; jobs jsonb; BEGIN
 v:=public.isg_notebook_reminder_mutate_v1(gen_random_uuid(),'create',null,null,null,0,'Hatırlatma','daily','12:00:00',(now() AT TIME ZONE 'Europe/Istanbul')::date+1,'Europe/Istanbul',null,'60000000-0000-0000-0000-000000000001');
 r:=(v->>'reminder_id')::uuid;
 ASSERT r IS NOT NULL AND v->>'delivery_strategy'='server_push','create server reminder';
 SELECT occurrence_id INTO o FROM private_isg.reminder_occurrences WHERE reminder_id=r ORDER BY occurrence_no LIMIT 1;
 UPDATE private_isg.reminder_occurrences SET due_at=clock_timestamp()-interval '1 minute' WHERE occurrence_id=o;
 jobs:=public.isg_notebook_delivery_claim_v1(25);
 ASSERT jsonb_array_length(jobs)=1,'claim due reminder';
 ASSERT jsonb_array_length(public.isg_notebook_delivery_claim_v1(25))=0,'no double claim';
 v:=public.isg_notebook_delivery_snapshot_v1((jobs->0->>'id')::uuid,(jobs->0->>'claim_token')::uuid);
 ASSERT v->>'token'='fixture-token','authorized installation';
 PERFORM public.isg_notebook_reminder_mutate_v1(gen_random_uuid(),'snooze',r,null,o,1,null,null,null,null,null,now()+interval '1 hour',null);
 v:=public.isg_notebook_delivery_snapshot_v1((jobs->0->>'id')::uuid,(jobs->0->>'claim_token')::uuid);
 ASSERT v IS NULL,'snooze invalidates stale dispatch';
 PERFORM public.isg_notebook_reminder_mutate_v1(gen_random_uuid(),'complete',r,null,o,1,null,null,null,null,null,null,null);
 ASSERT (SELECT state='completed' FROM private_isg.reminder_occurrences WHERE occurrence_id=o),'complete occurrence';
 PERFORM public.isg_notebook_reminder_mutate_v1(gen_random_uuid(),'cancel',r,null,null,1,null,null,null,null,null,null,null);
 ASSERT (SELECT state='cancelled' FROM private_isg.personal_reminders WHERE reminder_id=r),'cancel series';
END $$;
DO $$ DECLARE n uuid:=gen_random_uuid(); m uuid:=gen_random_uuid(); v jsonb; BEGIN
 v:=public.isg_notebook_mutate_v1(m,n,'sync',0,'Kişisel başlık','Kişisel içerik',null);
 ASSERT v->>'state'='created','create note';
 v:=public.isg_notebook_mutate_v1(m,n,'sync',0,'Kişisel başlık','Kişisel içerik',null);
 ASSERT (v->>'replayed')::boolean,'replay note';
 v:=public.isg_notebook_mutate_v1(gen_random_uuid(),n,'sync',1,'Yeni başlık','Yeni içerik',null);
 ASSERT (v->>'version')::int=2,'edit note';
 v:=public.isg_notebook_mutate_v1(gen_random_uuid(),n,'sync',1,'Çevrimdışı başlık','Çevrimdışı içerik',null);
 ASSERT v->>'state'='conflict','preserve offline conflict';
 v:=public.isg_notebook_read_v1(n,null);
 ASSERT jsonb_array_length(v->'note'->'conflicts')=1,'read conflicts';
 PERFORM set_config('request.jwt.claims','{"sub":"40000000-0000-0000-0000-000000000002","session_id":"50000000-0000-0000-0000-000000000002"}',true);
 BEGIN
   PERFORM public.isg_notebook_read_v1(n,null);
   RAISE EXCEPTION 'foreign note exposed';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'ACCESS_DENIED' THEN RAISE; END IF; END;
END $$;
ROLLBACK;
