-- Created with `supabase migration new`, then ordered immediately after the
-- existing future-dated P12/P13 dependencies. Additive; rollout remains OFF.
BEGIN;
SET LOCAL lock_timeout='5s';

CREATE FUNCTION private_isg.read_notebook_reminders(p_after uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); rows jsonb; last_id uuid; more boolean;
BEGIN
  PERFORM private_isg.notes_gate(false);
  SELECT coalesce(jsonb_agg(x.value ORDER BY x.reminder_id),'[]'::jsonb) INTO rows FROM (
    SELECT r.reminder_id,jsonb_build_object(
      'reminder_id',r.reminder_id,'note_id',r.note_id,'title',r.title,'recurrence',r.recurrence,
      'local_time',to_char(r.local_time,'HH24:MI:SS'),'starts_on',r.starts_on,'timezone',r.timezone,
      'series_version',r.series_version,'state',r.state,'updated_at',r.updated_at,
      'delivery_strategy',c.strategy,'delivery_installation_id',c.installation_id,
      'next_occurrence',CASE WHEN o.occurrence_id IS NULL THEN NULL ELSE jsonb_build_object(
        'occurrence_id',o.occurrence_id,'occurrence_no',o.occurrence_no,'series_version',o.series_version,
        'due_at',o.due_at,'effective_due_at',coalesce(o.snoozed_until,o.due_at),
        'state',o.state,'snoozed_until',o.snoozed_until) END) value
    FROM private_isg.personal_reminders r
    LEFT JOIN private_isg.device_delivery_claims c USING(reminder_id)
    LEFT JOIN LATERAL (
      SELECT occurrence_id,occurrence_no,series_version,due_at,state,snoozed_until
      FROM private_isg.reminder_occurrences
      WHERE reminder_id=r.reminder_id AND state IN ('scheduled','snoozed')
      ORDER BY coalesce(snoozed_until,due_at),occurrence_no LIMIT 1
    ) o ON true
    WHERE r.owner_id=actor AND (p_after IS NULL OR r.reminder_id>p_after)
    ORDER BY r.reminder_id LIMIT 21
  ) x;
  more:=jsonb_array_length(rows)>20;
  IF more THEN rows:=rows-20; last_id:=(rows->19->>'reminder_id')::uuid; END IF;
  RETURN jsonb_build_object('schema_version',1,'reminders',rows,'has_more',more,'next_after',last_id,
    'delivery_mode','server_push');
END $$;

CREATE FUNCTION private_isg.mutate_notebook_reminder(p_mutation uuid,p_action text,p_reminder uuid,p_note uuid,
  p_occurrence uuid,p_expected bigint,p_title text,p_recurrence text,p_local_time time,p_starts_on date,
  p_timezone text,p_snoozed_until timestamptz,p_installation uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); receipt record; series record; occurrence record;
  fingerprint bytea; result jsonb; stamp timestamptz:=clock_timestamp(); created_id uuid; projected jsonb;
BEGIN
  PERFORM private_isg.notes_gate(true);
  IF p_mutation IS NULL OR p_action IS NULL OR p_action NOT IN ('create','complete','snooze','cancel') OR
    p_expected IS NULL OR p_expected NOT BETWEEN 0 AND 9007199254740990 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_action='create' THEN
    IF p_reminder IS NOT NULL OR p_occurrence IS NOT NULL OR p_expected<>0 OR p_installation IS NULL OR
      p_title IS NULL OR length(btrim(p_title))=0 OR length(p_title)>200 OR
      p_recurrence NOT IN ('once','daily','weekly','monthly') OR p_local_time IS NULL OR
      p_starts_on IS NULL OR NOT isfinite(p_starts_on) OR p_timezone IS NULL OR
      p_snoozed_until IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name=p_timezone) OR
      (p_starts_on+p_local_time) AT TIME ZONE p_timezone<=stamp THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  ELSE
    IF p_reminder IS NULL OR p_expected<1 OR p_note IS NOT NULL OR p_title IS NOT NULL OR
      p_recurrence IS NOT NULL OR p_local_time IS NOT NULL OR p_starts_on IS NOT NULL OR
      p_timezone IS NOT NULL OR p_installation IS NOT NULL OR
      (p_action IN ('complete','snooze')) IS DISTINCT FROM (p_occurrence IS NOT NULL) OR
      (p_action='snooze') IS DISTINCT FROM (p_snoozed_until IS NOT NULL) OR
      (p_action='snooze' AND p_snoozed_until<=stamp) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array('reminder_v1',p_action,p_reminder,p_note,p_occurrence,
    p_expected,p_title,p_recurrence,p_local_time,p_starts_on,p_timezone,p_snoozed_until,p_installation)::text,'UTF8'));
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(actor::text||p_mutation::text,7313));
  SELECT * INTO receipt FROM private_isg.note_mutation_receipts WHERE owner_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF receipt.request_hash<>fingerprint THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN receipt.response||jsonb_build_object('replayed',true);
  END IF;
  IF p_action='create' THEN
    -- Server-push is the selected first-release owner. A reminder is not
    -- accepted when that installation has no current, authorized token.
    PERFORM private_isg.notification_gate(false);
    PERFORM 1 FROM public.push_device_tokens t
      JOIN private_isg.notification_device_permissions d ON d.token_id=t.id AND d.owner_id=t.user_id
      JOIN auth.sessions s ON s.id=d.session_id AND s.user_id=d.owner_id
      JOIN public.notification_preferences p ON p.user_id=t.user_id
      WHERE t.user_id=actor AND t.installation_id=p_installation AND t.notifications_enabled AND d.os_authorized
        AND p.enabled AND p.app_reminders
        AND d.token_fingerprint=md5(t.token) AND d.observed_at>=stamp-interval '24 hours'
        AND (s.not_after IS NULL OR s.not_after>stamp) FOR SHARE OF t,d,s;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DEVICE_UNAVAILABLE'; END IF;
    result:=private_isg.create_personal_reminder(actor,p_note,p_title,p_recurrence,p_local_time,p_starts_on,p_timezone,stamp);
    created_id:=(result->>'reminder_id')::uuid;
    PERFORM private_isg.claim_reminder_delivery(created_id,p_installation,'server_push',stamp);
    projected:=private_isg.project_reminder_occurrences(created_id,8,stamp);
    result:=jsonb_build_object('schema_version',1,'mutation_id',p_mutation,'reminder_id',created_id,
      'series_version',1,'state','active','delivery_strategy','server_push',
      'projected_occurrences',(projected->>'created')::integer,'replayed',false);
  ELSE
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_reminder::text,7315));
    SELECT * INTO series FROM private_isg.personal_reminders WHERE reminder_id=p_reminder FOR UPDATE;
    IF NOT FOUND OR series.owner_id<>actor THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF series.series_version<>p_expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    IF p_action IN ('complete','snooze') THEN
      SELECT * INTO occurrence FROM private_isg.reminder_occurrences
        WHERE occurrence_id=p_occurrence AND reminder_id=p_reminder FOR UPDATE;
      IF NOT FOUND OR occurrence.series_version<>series.series_version THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      result:=private_isg.settle_reminder_occurrence(p_occurrence,p_action,p_snoozed_until,stamp);
      UPDATE private_isg.notification_jobs j SET state='cancelled',suppression_code='REMINDER_SETTLED',
        resolved_route=NULL,updated_at=stamp FROM private_isg.notification_episodes e
        WHERE j.episode_id=e.episode_id AND e.owner_id=actor AND e.purpose='personal_reminder'
          AND e.episode_kind='notebook.reminder' AND split_part(e.source_ref,':',1)=p_occurrence::text
          AND j.state IN ('queued','failed');
      IF p_action='complete' AND series.state='active' AND series.recurrence<>'once' THEN
        PERFORM private_isg.project_reminder_occurrences(p_reminder,1,stamp);
      END IF;
      result:=result||jsonb_build_object('reminder_id',p_reminder);
    ELSE
      result:=private_isg.cancel_reminder_series(p_reminder,'USER_CANCELLED',stamp);
      UPDATE private_isg.notification_jobs j SET state='cancelled',suppression_code='REMINDER_CANCELLED',
        resolved_route=NULL,updated_at=stamp FROM private_isg.notification_episodes e
        JOIN private_isg.reminder_occurrences o ON split_part(e.source_ref,':',1)=o.occurrence_id::text
        WHERE j.episode_id=e.episode_id AND e.owner_id=actor AND e.purpose='personal_reminder'
          AND e.episode_kind='notebook.reminder' AND o.reminder_id=p_reminder AND j.state IN ('queued','failed');
    END IF;
    result:=result||jsonb_build_object('schema_version',1,'mutation_id',p_mutation,'series_version',series.series_version,
      'replayed',false);
  END IF;
  INSERT INTO private_isg.note_mutation_receipts(owner_id,mutation_id,request_hash,response)
    VALUES(actor,p_mutation,fingerprint,result);
  RETURN result;
END $$;

-- Internal producer. It maintains a small future occurrence buffer and creates
-- P12 jobs only inside the caller-supplied horizon. No scheduler/cutover here.
CREATE FUNCTION private_isg.enqueue_personal_reminder_notifications(p_now timestamptz,p_horizon_seconds integer,
  p_limit integer,p_minimum_build integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE series record; item record; future_count integer; projected integer:=0; queued integer:=0;
  replayed integer:=0; episode jsonb; job jsonb; source text; effective_due timestamptz;
BEGIN
  PERFORM private_isg.notes_gate(true); PERFORM private_isg.notification_gate(true);
  IF p_now IS NULL OR NOT isfinite(p_now) OR p_horizon_seconds IS NULL OR p_horizon_seconds NOT BETWEEN 0 AND 86400 OR
    p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 500 OR p_minimum_build IS NULL OR p_minimum_build NOT BETWEEN 1 AND 2147483647 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  FOR series IN
    SELECT r.reminder_id FROM private_isg.personal_reminders r JOIN private_isg.device_delivery_claims c USING(reminder_id)
      WHERE r.state='active' AND c.strategy='server_push' ORDER BY r.reminder_id LIMIT p_limit
  LOOP
    SELECT count(*) INTO future_count FROM private_isg.reminder_occurrences o
      WHERE o.reminder_id=series.reminder_id AND o.state IN ('scheduled','snoozed')
        AND coalesce(o.snoozed_until,o.due_at)>=p_now;
    IF future_count<8 THEN
      projected:=projected+coalesce((private_isg.project_reminder_occurrences(series.reminder_id,8-future_count,p_now)->>'created')::integer,0);
    END IF;
  END LOOP;
  FOR item IN
    SELECT o.occurrence_id,o.series_version,r.owner_id,r.timezone,
      coalesce(o.snoozed_until,o.due_at) AS effective_due
    FROM private_isg.reminder_occurrences o JOIN private_isg.personal_reminders r USING(reminder_id)
      JOIN private_isg.device_delivery_claims c USING(reminder_id)
    WHERE r.state='active' AND o.series_version=r.series_version AND o.state IN ('scheduled','snoozed')
      AND c.strategy='server_push' AND coalesce(o.snoozed_until,o.due_at)>=p_now
      AND coalesce(o.snoozed_until,o.due_at)<=p_now+make_interval(secs=>p_horizon_seconds)
    ORDER BY effective_due,o.occurrence_id LIMIT p_limit
  LOOP
    effective_due:=item.effective_due;
    source:=item.occurrence_id::text||':'||to_char(effective_due AT TIME ZONE 'UTC','YYYYMMDDHH24MISS.US');
    episode:=private_isg.open_notification_episode(item.owner_id,NULL,'personal_reminder','notebook.reminder',
      source,item.series_version::integer,NULL,'isg_engine',true,p_now);
    job:=private_isg.enqueue_notification((episode->>'episode_id')::uuid,'push',
      'isg/notebook/reminder/'||item.occurrence_id::text,'profile',p_minimum_build,effective_due,item.timezone,p_now);
    IF coalesce((job->>'replayed')::boolean,false) THEN replayed:=replayed+1; ELSE queued:=queued+1; END IF;
  END LOOP;
  RETURN jsonb_build_object('schema_version',1,'projected_occurrences',projected,'queued_jobs',queued,
    'replayed_jobs',replayed,'provider_called',false);
END $$;

-- Select the explicitly claimed installation for notebook reminders. Other
-- notification kinds keep the previous single-candidate behavior.
CREATE OR REPLACE FUNCTION private_isg.notification_registered_device(p_job uuid,p_now timestamptz,p_max_age_seconds integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE result jsonb; candidates integer;
BEGIN
  PERFORM private_isg.notification_gate(false);
  IF p_job IS NULL OR p_now IS NULL OR NOT isfinite(p_now) OR p_max_age_seconds IS NULL OR p_max_age_seconds NOT BETWEEN 1 AND 86400 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT count(*),(jsonb_agg(x.value)->0) INTO candidates,result FROM (
    SELECT jsonb_build_object('token_id',t.id,'owner_id',e.owner_id,'installation_id',t.installation_id,
      'app_build',d.app_build,'category_enabled',CASE WHEN e.purpose='personal_reminder' THEN
        EXISTS(SELECT 1 FROM public.notification_preferences p WHERE p.user_id=e.owner_id AND p.enabled AND p.app_reminders)
        ELSE true END,'os_authorized',d.os_authorized,'provider',t.provider,'token',t.token,
      'environment',t.environment,'application_id',t.application_id,'provider_environment',t.provider_environment) value
    FROM private_isg.notification_jobs j JOIN private_isg.notification_episodes e USING(episode_id)
    JOIN public.push_device_tokens t ON t.user_id=e.owner_id
    JOIN private_isg.notification_device_permissions d ON d.token_id=t.id AND d.owner_id=t.user_id
    JOIN auth.sessions s ON s.id=d.session_id AND s.user_id=d.owner_id JOIN auth.users u ON u.id=d.owner_id
    LEFT JOIN private_isg.reminder_occurrences o ON e.purpose='personal_reminder' AND e.episode_kind='notebook.reminder'
      AND split_part(e.source_ref,':',1)=o.occurrence_id::text
    LEFT JOIN private_isg.personal_reminders r ON r.reminder_id=o.reminder_id
    LEFT JOIN private_isg.device_delivery_claims c ON c.reminder_id=r.reminder_id
    WHERE j.job_id=p_job AND j.channel='push' AND t.notifications_enabled AND d.token_fingerprint=md5(t.token)
      AND d.observed_at<=p_now AND d.observed_at>=p_now-make_interval(secs=>p_max_age_seconds)
      AND (s.not_after IS NULL OR s.not_after>p_now) AND u.deleted_at IS NULL AND NOT u.is_anonymous
      AND (u.banned_until IS NULL OR u.banned_until<=p_now)
      AND (e.purpose<>'personal_reminder' OR (e.episode_kind='notebook.reminder' AND c.strategy='server_push'
        AND t.installation_id=c.installation_id))
    LIMIT 2
  ) x;
  RETURN jsonb_build_object('schema_version',1,'job_id',p_job,'device',CASE WHEN candidates=1 THEN result ELSE NULL END,
    'reason',CASE WHEN candidates=0 THEN 'DEVICE_UNAVAILABLE' WHEN candidates>1 THEN 'DEVICE_STRATEGY_REQUIRED' ELSE NULL END);
END $$;

CREATE FUNCTION private_isg.dispatch_bound_notification(p_job uuid,p_device jsonb,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE ep record; item record; occurrence record; series record; claim record; reason text;
BEGIN
  SELECT e.*,j.scheduled_for,j.state INTO ep FROM private_isg.notification_episodes e
    JOIN private_isg.notification_jobs j USING(episode_id) WHERE j.job_id=p_job;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF ep.purpose<>'personal_reminder' OR ep.episode_kind<>'notebook.reminder' THEN
    RETURN private_isg.dispatch_notification(p_job,p_device,p_now); END IF;
  PERFORM private_isg.notes_gate(false);
  SELECT * INTO occurrence FROM private_isg.reminder_occurrences
    WHERE occurrence_id::text=split_part(ep.source_ref,':',1) FOR SHARE;
  IF NOT FOUND THEN reason:='REMINDER_UNAVAILABLE';
  ELSE
    SELECT * INTO series FROM private_isg.personal_reminders WHERE reminder_id=occurrence.reminder_id FOR SHARE;
    SELECT * INTO claim FROM private_isg.device_delivery_claims WHERE reminder_id=occurrence.reminder_id FOR SHARE;
    IF series.state<>'active' OR occurrence.state NOT IN ('scheduled','snoozed') THEN reason:='REMINDER_INACTIVE';
    ELSIF occurrence.series_version<>series.series_version OR ep.schedule_version<>series.series_version THEN reason:='REMINDER_VERSION_STALE';
    ELSIF coalesce(occurrence.snoozed_until,occurrence.due_at) IS DISTINCT FROM ep.scheduled_for THEN reason:='REMINDER_TIME_STALE';
    ELSIF claim.strategy IS DISTINCT FROM 'server_push' OR claim.installation_id::text IS DISTINCT FROM p_device->>'installation_id' THEN reason:='DELIVERY_OWNER_CHANGED';
    END IF;
  END IF;
  IF reason IS NOT NULL AND ep.state IN ('queued','failed') THEN
    UPDATE private_isg.notification_jobs SET state='suppressed',suppression_code=reason,resolved_route=NULL,updated_at=p_now WHERE job_id=p_job;
    RETURN jsonb_build_object('schema_version',1,'job_id',p_job,'state','suppressed','allowed',false,'suppression_code',reason);
  END IF;
  RETURN private_isg.dispatch_notification(p_job,p_device,p_now);
END $$;

CREATE FUNCTION private_isg.notification_job_snapshot(p_job uuid,p_now timestamptz,p_max_age_seconds integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE registered jsonb; device jsonb; reminder record;
BEGIN
  registered:=private_isg.notification_registered_device(p_job,p_now,p_max_age_seconds);
  device:=registered->'device';
  IF device IS NULL OR device='null'::jsonb THEN RETURN NULL; END IF;
  SELECT r.* INTO reminder FROM private_isg.notification_jobs j JOIN private_isg.notification_episodes e USING(episode_id)
    JOIN private_isg.reminder_occurrences o ON split_part(e.source_ref,':',1)=o.occurrence_id::text
    JOIN private_isg.personal_reminders r USING(reminder_id)
    WHERE j.job_id=p_job AND e.purpose='personal_reminder' AND e.episode_kind='notebook.reminder';
  IF NOT FOUND THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('job_id',p_job,'device',jsonb_build_object(
      'owner_id',device->>'owner_id','installation_id',device->>'installation_id',
      'app_build',(device->>'app_build')::integer,'category_enabled',(device->>'category_enabled')::boolean,
      'os_authorized',(device->>'os_authorized')::boolean),
    'provider',device->>'provider','token',device->>'token','title',left(reminder.title,120),
    'body','Kişisel hatırlatıcınız hazır.');
END $$;

CREATE FUNCTION public.isg_notebook_reminders_v1(p_after uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.read_notebook_reminders(p_after) $$;
CREATE FUNCTION public.isg_notebook_reminder_mutate_v1(p_mutation uuid,p_action text,p_reminder uuid,p_note uuid,
  p_occurrence uuid,p_expected bigint,p_title text,p_recurrence text,p_local_time time,p_starts_on date,
  p_timezone text,p_snoozed_until timestamptz,p_installation uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.mutate_notebook_reminder(p_mutation,p_action,p_reminder,
  p_note,p_occurrence,p_expected,p_title,p_recurrence,p_local_time,p_starts_on,p_timezone,p_snoozed_until,p_installation) $$;

REVOKE ALL ON FUNCTION private_isg.read_notebook_reminders(uuid),
  private_isg.mutate_notebook_reminder(uuid,text,uuid,uuid,uuid,bigint,text,text,time,date,text,timestamptz,uuid),
  private_isg.enqueue_personal_reminder_notifications(timestamptz,integer,integer,integer),
  private_isg.notification_registered_device(uuid,timestamptz,integer),
  private_isg.dispatch_bound_notification(uuid,jsonb,timestamptz),
  private_isg.notification_job_snapshot(uuid,timestamptz,integer),
  public.isg_notebook_reminders_v1(uuid),
  public.isg_notebook_reminder_mutate_v1(uuid,text,uuid,uuid,uuid,bigint,text,text,time,date,text,timestamptz,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.read_notebook_reminders(uuid),
  private_isg.mutate_notebook_reminder(uuid,text,uuid,uuid,uuid,bigint,text,text,time,date,text,timestamptz,uuid),
  public.isg_notebook_reminders_v1(uuid),
  public.isg_notebook_reminder_mutate_v1(uuid,text,uuid,uuid,uuid,bigint,text,text,time,date,text,timestamptz,uuid)
  TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
