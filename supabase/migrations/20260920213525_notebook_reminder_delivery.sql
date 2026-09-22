-- Scoped server-push reminders; independent of the undeployed P12 notification stack.
-- Additive P12 device permission. No legacy table, helper or rollout changes.
SET LOCAL lock_timeout='5s';
CREATE TABLE private_isg.notification_device_permissions (
  token_id uuid PRIMARY KEY REFERENCES public.push_device_tokens(id) ON DELETE CASCADE,
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  session_id uuid NOT NULL REFERENCES auth.sessions(id) ON DELETE CASCADE,
  token_fingerprint text NOT NULL,
  app_build integer NOT NULL CHECK(app_build BETWEEN 1 AND 2147483647),
  os_authorized boolean NOT NULL,
  observed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX notification_device_owner_idx ON private_isg.notification_device_permissions(owner_id);
CREATE INDEX notification_device_session_idx ON private_isg.notification_device_permissions(session_id);
ALTER TABLE private_isg.notification_device_permissions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.notification_device_permissions FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.record_device_permission(p_token text,p_provider text,p_build integer,p_authorized boolean) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); device public.push_device_tokens; stamp timestamptz;
BEGIN
  PERFORM private_isg.notes_gate(true);
  IF p_token IS NULL OR length(p_token) NOT BETWEEN 1 AND 4096 OR
    p_provider IS NULL OR p_provider NOT IN ('apns','fcm') OR p_build IS NULL OR p_build<1 OR p_authorized IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO device FROM public.push_device_tokens
    WHERE user_id=actor AND token=p_token AND provider=p_provider FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DEVICE_UNAVAILABLE'; END IF;
  -- Serialize the first write too. Client clocks never decide freshness.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(device.id::text,7212));
  stamp:=clock_timestamp();
  INSERT INTO private_isg.notification_device_permissions(token_id,owner_id,session_id,token_fingerprint,app_build,os_authorized,observed_at)
    VALUES(device.id,actor,(auth.jwt()->>'session_id')::uuid,md5(device.token),p_build,p_authorized,stamp)
  ON CONFLICT(token_id) DO UPDATE SET owner_id=excluded.owner_id,session_id=excluded.session_id,
    token_fingerprint=excluded.token_fingerprint,app_build=excluded.app_build,
    os_authorized=excluded.os_authorized,observed_at=excluded.observed_at;
  RETURN jsonb_build_object('schema_version',1,'recorded',true);
END $$;
CREATE FUNCTION public.isg_notification_device_permission_v1(p_token text,p_provider text,p_build integer,p_authorized boolean) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.record_device_permission(p_token,p_provider,p_build,p_authorized)
$$;
REVOKE ALL ON FUNCTION private_isg.record_device_permission(text,text,integer,boolean),
  public.isg_notification_device_permission_v1(text,text,integer,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.record_device_permission(text,text,integer,boolean),
  public.isg_notification_device_permission_v1(text,text,integer,boolean) TO authenticated;


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
    PERFORM private_isg.notes_gate(false);
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

      IF p_action='complete' AND series.state='active' AND series.recurrence<>'once' THEN
        PERFORM private_isg.project_reminder_occurrences(p_reminder,1,stamp);
      END IF;
      result:=result||jsonb_build_object('reminder_id',p_reminder);
    ELSE
      result:=private_isg.cancel_reminder_series(p_reminder,'USER_CANCELLED',stamp);

    END IF;
    result:=result||jsonb_build_object('schema_version',1,'mutation_id',p_mutation,'series_version',series.series_version,
      'replayed',false);
  END IF;
  INSERT INTO private_isg.note_mutation_receipts(owner_id,mutation_id,request_hash,response)
    VALUES(actor,p_mutation,fingerprint,result);
  RETURN result;
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
 public.isg_notebook_reminders_v1(uuid),
 public.isg_notebook_reminder_mutate_v1(uuid,text,uuid,uuid,uuid,bigint,text,text,time,date,text,timestamptz,uuid)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION private_isg.read_notebook_reminders(uuid),
 private_isg.mutate_notebook_reminder(uuid,text,uuid,uuid,uuid,bigint,text,text,time,date,text,timestamptz,uuid),
 public.isg_notebook_reminders_v1(uuid),
 public.isg_notebook_reminder_mutate_v1(uuid,text,uuid,uuid,uuid,bigint,text,text,time,date,text,timestamptz,uuid)
 TO authenticated;

CREATE TABLE private_isg.notebook_deliveries (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 occurrence_id uuid NOT NULL REFERENCES private_isg.reminder_occurrences(occurrence_id) ON DELETE CASCADE,
 effective_due_at timestamptz NOT NULL,
 claim_token uuid NOT NULL DEFAULT gen_random_uuid(),
 state text NOT NULL DEFAULT 'claimed' CHECK(state IN ('claimed','sent','failed','ambiguous','suppressed')),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 finished_at timestamptz,
 UNIQUE(occurrence_id,effective_due_at)
);
ALTER TABLE private_isg.notebook_deliveries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.notebook_deliveries FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.isg_notebook_delivery_claim_v1(p_limit integer DEFAULT 25) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE series_ref record; scheduled record; delivery private_isg.notebook_deliveries; rows jsonb:='[]';
BEGIN
 PERFORM private_isg.notes_gate(true);
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 -- Maintain recurrence beyond the initial eight items even without opening the app.
 FOR series_ref IN SELECT reminder_id FROM private_isg.personal_reminders WHERE state='active' AND recurrence<>'once'
   AND (SELECT count(*) FROM private_isg.reminder_occurrences o WHERE o.reminder_id=personal_reminders.reminder_id AND o.due_at>now() AND o.state='scheduled')<4 LIMIT 100
 LOOP PERFORM private_isg.project_reminder_occurrences(series_ref.reminder_id,8,clock_timestamp()); END LOOP;
 FOR scheduled IN SELECT o.occurrence_id,coalesce(o.snoozed_until,o.due_at) due
   FROM private_isg.reminder_occurrences o JOIN private_isg.personal_reminders r USING(reminder_id)
   WHERE r.state='active' AND o.state IN ('scheduled','snoozed') AND coalesce(o.snoozed_until,o.due_at)<=clock_timestamp()
   AND coalesce(o.snoozed_until,o.due_at)>clock_timestamp()-interval '24 hours'
   AND NOT EXISTS(SELECT 1 FROM private_isg.notebook_deliveries d WHERE d.occurrence_id=o.occurrence_id AND d.effective_due_at=coalesce(o.snoozed_until,o.due_at))
   ORDER BY coalesce(o.snoozed_until,o.due_at) LIMIT p_limit FOR UPDATE OF o SKIP LOCKED
 LOOP
   INSERT INTO private_isg.notebook_deliveries(occurrence_id,effective_due_at) VALUES(scheduled.occurrence_id,scheduled.due)
     ON CONFLICT DO NOTHING RETURNING * INTO delivery;
   IF FOUND THEN rows:=rows||jsonb_build_array(jsonb_build_object('id',delivery.id,'claim_token',delivery.claim_token)); END IF;
 END LOOP;
 RETURN rows;
END $$;

CREATE FUNCTION public.isg_notebook_delivery_snapshot_v1(p_id uuid,p_claim uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
 PERFORM private_isg.notes_gate(false);
 SELECT jsonb_build_object('token',t.token,'environment',t.environment,'application_id',t.application_id,
   'provider',t.provider,'occurrence_id',o.occurrence_id)
 INTO result FROM private_isg.notebook_deliveries d
 JOIN private_isg.reminder_occurrences o ON o.occurrence_id=d.occurrence_id
 JOIN private_isg.personal_reminders r USING(reminder_id)
 JOIN private_isg.device_delivery_claims c USING(reminder_id)
 JOIN public.push_device_tokens t ON t.user_id=r.owner_id AND t.installation_id=c.installation_id
 JOIN private_isg.notification_device_permissions p ON p.token_id=t.id AND p.owner_id=r.owner_id
 JOIN public.notification_preferences prefs ON prefs.user_id=r.owner_id
 JOIN auth.sessions s ON s.id=p.session_id AND s.user_id=r.owner_id
 JOIN auth.users u ON u.id=r.owner_id
 WHERE d.id=p_id AND d.claim_token=p_claim AND d.state='claimed' AND d.created_at>clock_timestamp()-interval '5 minutes'
   AND r.state='active' AND o.state IN ('scheduled','snoozed') AND d.effective_due_at=coalesce(o.snoozed_until,o.due_at)
   AND c.strategy='server_push' AND t.notifications_enabled AND p.os_authorized
   AND p.token_fingerprint=md5(t.token) AND prefs.enabled AND prefs.app_reminders
   AND (s.not_after IS NULL OR s.not_after>clock_timestamp()) AND u.deleted_at IS NULL
   AND (u.banned_until IS NULL OR u.banned_until<=clock_timestamp()) AND NOT u.is_anonymous
   AND t.provider='apns' AND t.application_id IN ('com.riskdetected.app','com.riskdetected.app.osgbpilot')
 ORDER BY p.observed_at DESC LIMIT 1;
 RETURN result;
END $$;

CREATE FUNCTION public.isg_notebook_delivery_complete_v1(p_id uuid,p_claim uuid,p_state text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF p_state IS NULL OR p_state NOT IN ('sent','failed','ambiguous','suppressed') THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 UPDATE private_isg.notebook_deliveries SET state=p_state,finished_at=clock_timestamp()
 WHERE id=p_id AND claim_token=p_claim AND state='claimed';
END $$;
REVOKE ALL ON FUNCTION public.isg_notebook_delivery_claim_v1(integer),public.isg_notebook_delivery_snapshot_v1(uuid,uuid),public.isg_notebook_delivery_complete_v1(uuid,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.isg_notebook_delivery_claim_v1(integer),public.isg_notebook_delivery_snapshot_v1(uuid,uuid),public.isg_notebook_delivery_complete_v1(uuid,uuid,text) TO service_role;

-- Personal events contain only the action and date, never the note title/body/tags.
CREATE FUNCTION private_isg.activity_from_note_receipt() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NEW.response->>'state' NOT IN ('created','updated','resolved','organized','deleted') OR NEW.response->>'note_id' IS NULL THEN RETURN NEW; END IF;
 INSERT INTO private_isg.business_activity_events(source_key,actor_user_id,action,entity_type)
 VALUES('note:'||encode(sha256(convert_to(NEW.owner_id::text||NEW.mutation_id::text,'UTF8')),'hex'),NEW.owner_id,
   'personal_note.'||CASE WHEN NEW.response->>'state'='created' THEN 'create' WHEN NEW.response->>'state'='deleted' THEN 'delete' ELSE 'update' END,'personal_note')
 ON CONFLICT DO NOTHING;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private_isg.activity_from_note_receipt() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER personal_note_activity AFTER INSERT ON private_isg.note_mutation_receipts FOR EACH ROW EXECUTE FUNCTION private_isg.activity_from_note_receipt();
