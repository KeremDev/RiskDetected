-- Runner supplies only test-account IDs; all fixture changes are rolled back.
CREATE TEMP TABLE activity_results(test text PRIMARY KEY,passed boolean);
DO $$
DECLARE actor uuid:=auth.uid(); workspace uuid:=current_setting('isg.test_workspace')::uuid;
 sid uuid:=(auth.jwt()->>'session_id')::uuid; v jsonb; n numeric; count_before bigint;
 company uuid:=gen_random_uuid(); event bigint; page jsonb; next_page jsonb; note_event bigint;
BEGIN
 -- Isolate test-account usage inside the rollback transaction.
 DELETE FROM private_isg.usage_sessions WHERE user_id=actor;
 DELETE FROM private_isg.usage_totals WHERE user_id=actor;
 DELETE FROM private_isg.usage_membership_totals WHERE user_id=actor;
 PERFORM public.isg_usage_presence_v1('start',workspace);
 UPDATE private_isg.usage_sessions SET last_seen_at=clock_timestamp()-interval '60 seconds' WHERE session_id=sid;
 v:=public.isg_usage_presence_v1('heartbeat',workspace);
 ASSERT (v->>'accepted_seconds')::numeric BETWEEN 60 AND 61;
 UPDATE private_isg.usage_sessions SET last_seen_at=clock_timestamp()-interval '120 seconds' WHERE session_id=sid;
 ASSERT (public.isg_usage_presence_v1('heartbeat',workspace)->>'accepted_seconds')::numeric=0;
 PERFORM public.isg_usage_presence_v1('start',workspace);
 ASSERT (SELECT count(*)=1 FROM private_isg.usage_sessions WHERE user_id=actor);
 ASSERT (public.isg_usage_presence_v1('heartbeat',NULL)->>'accepted_seconds')::numeric=0;
 PERFORM public.isg_usage_presence_v1('stop',NULL);
 ASSERT (SELECT NOT running FROM private_isg.usage_sessions WHERE session_id=sid);
 INSERT INTO activity_results VALUES('60-second heartbeat, crash boundary, token refresh, workspace change, stop',true);

 SELECT id INTO company FROM public.companies WHERE workspace_id=workspace LIMIT 1;
 ASSERT company IS NOT NULL;
 UPDATE public.companies SET name='PRIVATE-TEST-TITLE',hazard_class='medium' WHERE id=company;
 SELECT id INTO event FROM private_isg.business_activity_events WHERE entity_id=company AND actor_user_id=actor AND transaction_id=txid_current();
 ASSERT event IS NOT NULL;
 UPDATE public.companies SET hazard_class='high',contact_person='PRIVATE-CONTACT',name='PRIVATE-UPDATED' WHERE id=company;
 ASSERT (SELECT count(*)=1 FROM private_isg.business_activity_events WHERE entity_id=company AND actor_user_id=actor AND transaction_id=txid_current());
 v:=public.isg_activity_event_detail_v1(event);
 ASSERT v::text NOT LIKE '%PRIVATE-%';
 ASSERT EXISTS(SELECT 1 FROM jsonb_array_elements(v->'changes') c WHERE c->>'field'='hazard_class' AND c->>'after'='high');
 SELECT count(*) INTO count_before FROM private_isg.business_activity_events WHERE actor_user_id=actor;
 UPDATE public.companies SET updated_at=now() WHERE id=company;
 ASSERT (SELECT count(*)=count_before FROM private_isg.business_activity_events WHERE actor_user_id=actor);
 INSERT INTO activity_results VALUES('atomic before/after journal, no timestamp-only log, masked details',true);

 FOR i IN 1..52 LOOP
   INSERT INTO private_isg.business_activity_events(source_key,actor_user_id,workspace_id,company_id,action,entity_type)
   VALUES('fixture:'||gen_random_uuid(),actor,workspace,company,CASE WHEN i=1 THEN 'visit.create' ELSE 'company.update' END,'company');
 END LOOP;
 page:=public.isg_activity_self_v1();
 ASSERT jsonb_array_length(page->'items')=30 AND page->>'next_cursor' IS NOT NULL;
 ASSERT page->'actions' ? 'visit.create','Facets must include records beyond first page';
 next_page:=public.isg_activity_self_v1((page->>'next_cursor')::bigint);
 ASSERT NOT EXISTS(SELECT 1 FROM jsonb_array_elements(page->'items') a JOIN jsonb_array_elements(next_page->'items') b ON a->>'id'=b->>'id');
 ASSERT jsonb_array_length(public.isg_activity_self_v1(p_action:='visit.create')->'items')>=1;
 INSERT INTO activity_results VALUES('cursor paging and complete action/company facets',true);

 SELECT active_seconds INTO n FROM private_isg.usage_totals WHERE user_id=actor AND scope='all';
 UPDATE private_isg.usage_intervals SET starts_at=starts_at-interval '25 months',ends_at=ends_at-interval '25 months' WHERE user_id=actor;
 UPDATE private_isg.business_activity_events SET created_at=now()-interval '6 years' WHERE id=event;
 PERFORM private_isg.prune_expert_activity();
 ASSERT NOT EXISTS(SELECT 1 FROM private_isg.usage_intervals WHERE user_id=actor);
 ASSERT NOT EXISTS(SELECT 1 FROM private_isg.business_activity_events WHERE id=event);
 ASSERT (SELECT active_seconds=n FROM private_isg.usage_totals WHERE user_id=actor AND scope='all');
 ASSERT (public.isg_activity_self_v1()->'summary'->>'login_count')::int=1;
 INSERT INTO activity_results VALUES('24-month / 5-year retention preserves lifetime totals and login count',true);
END $$;

DO $$
DECLARE expert uuid:=auth.uid(); workspace uuid:=current_setting('isg.test_workspace')::uuid; event bigint; v jsonb;
BEGIN
 SELECT id INTO event FROM private_isg.business_activity_events WHERE actor_user_id=expert AND workspace_id=workspace ORDER BY id DESC LIMIT 1;
 PERFORM set_config('request.jwt.claims',current_setting('isg.test_manager_claims'),true);
 v:=public.isg_workspace_member_activity_v1(workspace,expert);
 ASSERT jsonb_array_length(v->'items')>0;
 ASSERT NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v->'items') e WHERE e->>'entity_type'='personal_note');
 PERFORM public.isg_activity_event_detail_v1(event,workspace);
 BEGIN
  PERFORM public.isg_activity_event_detail_v1(event,gen_random_uuid());
  RAISE EXCEPTION 'Unexpected cross-OSGB access';
 EXCEPTION WHEN raise_exception THEN ASSERT SQLERRM='ACCESS_DENIED'; END;
 INSERT INTO activity_results VALUES('manager own workspace only and cross-OSGB detail rejection',true);
END $$;

DO $$
DECLARE actor uuid:=gen_random_uuid(); workspace uuid:=current_setting('isg.test_workspace')::uuid;
 sid uuid:=gen_random_uuid(); note uuid:=gen_random_uuid(); event bigint;
BEGIN
 INSERT INTO auth.users(id,aud,role,email,is_anonymous) VALUES(actor,'authenticated','authenticated',actor||'@riskdetected.invalid',false);
 INSERT INTO private_isg.usage_sessions(session_id,user_id) VALUES(sid,actor);
 INSERT INTO private_isg.usage_totals(user_id,scope,active_seconds) VALUES(actor,'all',90);
 INSERT INTO private_isg.business_activity_events(source_key,actor_user_id,workspace_id,action,entity_type,entity_id)
 VALUES('fixture:'||actor,actor,workspace,'personnel.create','personnel',actor) RETURNING id INTO event;
 INSERT INTO private_isg.business_activity_events(source_key,actor_user_id,action,entity_type)
 VALUES('fixture-note:'||actor,actor,'personal_note.create','personal_note');
 DELETE FROM auth.users WHERE id=actor;
 ASSERT NOT EXISTS(SELECT 1 FROM private_isg.usage_sessions WHERE user_id=actor);
 ASSERT NOT EXISTS(SELECT 1 FROM private_isg.usage_totals WHERE user_id=actor);
 ASSERT (SELECT actor_user_id IS NULL AND entity_id IS NULL AND source_key NOT LIKE '%'||actor||'%' FROM private_isg.business_activity_events WHERE id=event);
 ASSERT NOT EXISTS(SELECT 1 FROM private_isg.business_activity_events WHERE actor_user_id=actor);
 INSERT INTO activity_results VALUES('account deletion removes usage and anonymizes retained OSGB journal',true);
END $$;
SELECT * FROM activity_results ORDER BY test;
