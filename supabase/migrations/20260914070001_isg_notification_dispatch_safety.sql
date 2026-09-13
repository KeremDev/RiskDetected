-- Generated with `supabase migration new`; ordered immediately after the
-- repository's latest (future-dated) 20260914070000 dependency, not before P12.
-- P12 dispatch safety. No provider/network call, client grant or rollout change.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE private_isg.notification_jobs DROP CONSTRAINT notification_jobs_state_check;
ALTER TABLE private_isg.notification_jobs ADD CONSTRAINT notification_jobs_state_check
  CHECK(state IN ('queued','suppressed','sent','failed','cancelled','dispatching','uncertain','dead'));
ALTER TABLE private_isg.notification_jobs
  ADD COLUMN dispatch_token uuid,
  ADD COLUMN authorized_at timestamptz,
  ADD COLUMN dispatch_expires_at timestamptz,
  ADD COLUMN next_attempt_at timestamptz,
  ADD COLUMN accepted_at timestamptz;
ALTER TABLE private_isg.delivery_attempts ADD COLUMN dispatch_token uuid UNIQUE;
ALTER TABLE private_isg.notification_episodes ADD CONSTRAINT notification_episode_company_owner_fk
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id);
CREATE INDEX notification_episode_company_owner_idx ON private_isg.notification_episodes(company_id,owner_id);
-- Old checks cannot authorize a new send; existing sent rows remain sent.
UPDATE private_isg.notification_jobs SET resolved_route=NULL WHERE state IN ('queued','failed');
UPDATE private_isg.notification_jobs j SET accepted_at=(
  SELECT max(a.attempted_at) FROM private_isg.delivery_attempts a WHERE a.job_id=j.job_id AND a.provider_state='accepted')
  WHERE j.state='sent';

CREATE OR REPLACE FUNCTION private_isg.dispatch_notification(p_job uuid,p_device jsonb,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE item private_isg.notification_jobs; ep private_isg.notification_episodes;
  rules private_isg.notification_purposes; producer private_isg.producer_ownership;
  consent_row private_isg.notification_consents; has_consent boolean; reason text; resolved text;
  wall_time time; wall_day date; used integer; attempts integer; claim uuid;
  device_owner uuid; device_build integer;
BEGIN
  PERFORM private_isg.notification_gate(true);
  IF p_job IS NULL OR p_now IS NULL OR NOT isfinite(p_now) OR p_device IS NULL OR jsonb_typeof(p_device)<>'object' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  device_owner:=(p_device->>'owner_id')::uuid; device_build:=(p_device->>'app_build')::integer;
  IF device_owner IS NULL OR device_build IS NULL OR device_build<1 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT e.* INTO ep FROM private_isg.notification_episodes e JOIN private_isg.notification_jobs j USING(episode_id) WHERE j.job_id=p_job;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  -- Lock order: producer -> owner -> job. Owner lock reserves frequency slots
  -- across different jobs and purposes; consent writes use this same lock.
  SELECT * INTO producer FROM private_isg.producer_ownership WHERE purpose=ep.purpose AND episode_kind=ep.episode_kind FOR SHARE;
  PERFORM 1 FROM public.profiles WHERE id=ep.owner_id FOR UPDATE;
  SELECT * INTO item FROM private_isg.notification_jobs WHERE job_id=p_job FOR UPDATE;
  IF item.state='dispatching' AND item.dispatch_expires_at<=p_now THEN
    UPDATE private_isg.notification_jobs SET state='uncertain',updated_at=p_now WHERE job_id=p_job;
    item.state:='uncertain';
  END IF;
  IF item.state NOT IN ('queued','failed') THEN
    RETURN jsonb_build_object('schema_version',1,'job_id',p_job,'state',item.state,'allowed',false,'replayed',true); END IF;
  IF item.scheduled_for>p_now OR item.next_attempt_at>p_now THEN
    RETURN jsonb_build_object('schema_version',1,'job_id',p_job,'state',item.state,'allowed',false,'reason','NOT_DUE'); END IF;
  SELECT * INTO rules FROM private_isg.notification_purposes WHERE purpose=ep.purpose;
  SELECT * INTO consent_row FROM private_isg.notification_consents WHERE owner_id=ep.owner_id AND purpose=ep.purpose AND channel=item.channel;
  has_consent:=FOUND;
  wall_time:=(p_now AT TIME ZONE item.timezone)::time;
  wall_day:=(p_now AT TIME ZONE item.timezone)::date;
  IF producer.owner IS NULL OR producer.owner<>ep.produced_by THEN reason:='PRODUCER_HANDOVER';
  ELSIF producer.mode<>'live' THEN reason:='SHADOW_MODE_NO_SEND';
  ELSIF device_owner<>ep.owner_id THEN reason:='DEVICE_OWNER_MISMATCH';
  ELSIF ep.company_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.companies WHERE id=ep.company_id AND user_id=ep.owner_id AND NOT is_archived) THEN reason:='COMPANY_UNAVAILABLE';
  ELSIF NOT coalesce((p_device->>'category_enabled')::boolean,false) THEN reason:='CATEGORY_DISABLED';
  ELSIF item.channel='push' AND NOT coalesce((p_device->>'os_authorized')::boolean,false) THEN reason:='OS_PERMISSION_REQUIRED';
  ELSIF has_consent AND NOT consent_row.granted THEN reason:='CONSENT_REVOKED';
  ELSIF NOT has_consent AND (rules.requires_explicit_consent OR item.channel='email') THEN reason:='CONSENT_MISSING';
  END IF;
  IF reason IS NULL AND NOT rules.caps_approved THEN
    RETURN jsonb_build_object('schema_version',1,'job_id',p_job,'state',item.state,'allowed',false,'reason','POLICY_UNAPPROVED'); END IF;
  IF reason IS NULL AND rules.honours_quiet_hours AND NOT ep.explicit_alarm AND
    ((rules.quiet_start<rules.quiet_end AND wall_time>=rules.quiet_start AND wall_time<rules.quiet_end) OR
     (rules.quiet_start>rules.quiet_end AND (wall_time>=rules.quiet_start OR wall_time<rules.quiet_end))) THEN reason:='QUIET_HOURS'; END IF;
  -- Active and ambiguous sends reserve a slot too. An expired/unknown result
  -- is NOT a licence to send again. Count the actual send day, not queue day.
  IF reason IS NULL AND NOT ep.explicit_alarm THEN
    SELECT count(*) FILTER(WHERE (coalesce(j.accepted_at,j.authorized_at) AT TIME ZONE item.timezone)::date=wall_day),count(*)
      INTO used,attempts FROM private_isg.notification_jobs j JOIN private_isg.notification_episodes e USING(episode_id)
      WHERE e.owner_id=ep.owner_id AND e.purpose=ep.purpose AND j.state IN ('sent','dispatching','uncertain')
        AND (coalesce(j.accepted_at,j.authorized_at) AT TIME ZONE item.timezone)::date>wall_day-7
        AND (coalesce(j.accepted_at,j.authorized_at) AT TIME ZONE item.timezone)::date<=wall_day;
    IF (rules.daily_cap IS NOT NULL AND used>=rules.daily_cap) OR (rules.weekly_cap IS NOT NULL AND attempts>=rules.weekly_cap) THEN reason:='FREQUENCY_CAP'; END IF;
  END IF;
  IF reason IS NOT NULL THEN
    UPDATE private_isg.notification_jobs SET state='suppressed',suppression_code=reason,resolved_route=NULL,updated_at=p_now WHERE job_id=p_job;
    RETURN jsonb_build_object('schema_version',1,'job_id',p_job,'state','suppressed','allowed',false,'suppression_code',reason); END IF;
  SELECT count(*) INTO attempts FROM private_isg.delivery_attempts WHERE job_id=p_job;
  IF attempts>=10 THEN
    UPDATE private_isg.notification_jobs SET state='dead',updated_at=p_now WHERE job_id=p_job;
    RETURN jsonb_build_object('schema_version',1,'job_id',p_job,'state','dead','allowed',false); END IF;
  claim:=gen_random_uuid();
  resolved:=CASE WHEN device_build<item.minimum_build THEN item.fallback_route ELSE item.route END;
  UPDATE private_isg.notification_jobs SET state='dispatching',dispatch_token=claim,authorized_at=p_now,
    dispatch_expires_at=p_now+interval '60 seconds',next_attempt_at=NULL,resolved_route=resolved,updated_at=p_now WHERE job_id=p_job;
  RETURN jsonb_build_object('schema_version',1,'job_id',p_job,'state','dispatching','allowed',true,'dispatch_token',claim,
    'expires_at',p_now+interval '60 seconds','resolved_route',resolved,'route_downgraded',device_build<item.minimum_build,
    'purpose',ep.purpose,'channel',item.channel,'delivered',false);
END $$;

-- Retire the unfenced prototype entry point; no caller may reuse a historical
-- resolved_route as permission for a second attempt.
CREATE OR REPLACE FUNCTION private_isg.record_delivery_attempt(p_job uuid,p_provider text,p_state text,p_failure text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM private_isg.notification_gate(true);
  RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DISPATCH_TOKEN_REQUIRED';
END $$;

CREATE FUNCTION private_isg.complete_notification_delivery(p_job uuid,p_token uuid,p_provider text,p_state text,p_failure text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE item private_isg.notification_jobs; previous private_isg.delivery_attempts; owner_key uuid;
  count_attempts integer; next_state text; retry_at timestamptz; receipt uuid;
BEGIN
  PERFORM private_isg.notification_gate(true);
  IF p_job IS NULL OR p_token IS NULL OR p_now IS NULL OR NOT isfinite(p_now) OR p_provider IS NULL OR p_state IS NULL OR
    p_provider NOT IN ('apns','fcm','email') OR p_state NOT IN ('accepted','rejected','error') OR
    (p_state='accepted')<>(p_failure IS NULL) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT e.owner_id INTO owner_key FROM private_isg.notification_episodes e JOIN private_isg.notification_jobs j USING(episode_id) WHERE j.job_id=p_job;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  PERFORM 1 FROM public.profiles WHERE id=owner_key FOR UPDATE;
  SELECT * INTO item FROM private_isg.notification_jobs WHERE job_id=p_job FOR UPDATE;
  SELECT * INTO previous FROM private_isg.delivery_attempts WHERE dispatch_token=p_token;
  IF FOUND THEN
    IF previous.job_id<>p_job OR previous.provider<>p_provider OR previous.provider_state<>p_state OR previous.failure_code IS DISTINCT FROM p_failure THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN jsonb_build_object('schema_version',1,'attempt_id',previous.attempt_id,'replayed',true,'job_state',item.state,'delivery_confirmed',false,'read_confirmed',false);
  END IF;
  IF item.state NOT IN ('dispatching','uncertain') OR item.dispatch_token IS DISTINCT FROM p_token THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEASE_LOST'; END IF;
  IF p_now<item.authorized_at OR (item.channel='email')<>(p_provider='email') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT count(*) INTO count_attempts FROM private_isg.delivery_attempts WHERE job_id=p_job;
  IF p_state='accepted' THEN next_state:='sent';
  ELSIF p_state='error' THEN next_state:='uncertain';
  ELSIF p_failure IN ('RATE_LIMITED','PROVIDER_UNAVAILABLE','TEMPORARY_FAILURE') AND count_attempts<9 THEN
    next_state:='failed';retry_at:=p_now+make_interval(secs=>least(3600,30*power(2,count_attempts)::integer));
  ELSE next_state:='dead'; END IF;
  INSERT INTO private_isg.delivery_attempts(job_id,attempt_no,provider,provider_state,failure_code,attempted_at,dispatch_token)
    VALUES(p_job,count_attempts+1,p_provider,p_state,p_failure,p_now,p_token) RETURNING attempt_id INTO receipt;
  UPDATE private_isg.notification_jobs SET state=next_state,next_attempt_at=retry_at,
    accepted_at=CASE WHEN p_state='accepted' THEN p_now ELSE accepted_at END,updated_at=p_now WHERE job_id=p_job;
  RETURN jsonb_build_object('schema_version',1,'attempt_id',receipt,'attempt_no',count_attempts+1,'job_state',next_state,
    'next_attempt_at',retry_at,'replayed',false,'delivery_confirmed',false,'read_confirmed',false);
END $$;

-- Serialise even a first consent insert against a concurrent opt-out.
ALTER FUNCTION private_isg.record_notification_consent(uuid,text,text,boolean,text,text,timestamptz) RENAME TO record_notification_consent_v1_impl;
CREATE FUNCTION private_isg.record_notification_consent(p_owner uuid,p_purpose text,p_channel text,p_granted boolean,p_source text,p_note text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM private_isg.notification_gate(true);
  IF p_now IS NULL OR NOT isfinite(p_now) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  PERFORM 1 FROM public.profiles WHERE id=p_owner FOR UPDATE;
  IF EXISTS(SELECT 1 FROM private_isg.notification_consents WHERE owner_id=p_owner AND purpose=p_purpose AND channel=p_channel
    AND (captured_at>p_now OR (captured_at=p_now AND NOT granted AND p_granted))) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='STALE_CONSENT'; END IF;
  RETURN private_isg.record_notification_consent_v1_impl(p_owner,p_purpose,p_channel,p_granted,p_source,p_note,p_now);
END $$;
ALTER FUNCTION private_isg.set_producer_ownership(text,text,text,text,timestamptz) RENAME TO set_producer_ownership_v1_impl;
CREATE FUNCTION private_isg.set_producer_ownership(p_purpose text,p_kind text,p_owner text,p_mode text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE previous_owner text; result jsonb; cancelled_failed integer;
BEGIN
  PERFORM private_isg.notification_gate(true);
  -- A missing registry row cannot be row-locked. Serialise first registration
  -- too, so a racing handover must see the newly committed owner/inflight jobs.
  PERFORM pg_advisory_xact_lock(hashtextextended('isg.notification.producer:'||coalesce(p_purpose,'')||':'||coalesce(p_kind,''),0));
  SELECT owner INTO previous_owner FROM private_isg.producer_ownership WHERE purpose=p_purpose AND episode_kind=p_kind FOR UPDATE;
  IF previous_owner IS DISTINCT FROM p_owner AND EXISTS(
    SELECT 1 FROM private_isg.notification_jobs j JOIN private_isg.notification_episodes e USING(episode_id)
    WHERE e.purpose=p_purpose AND e.episode_kind=p_kind AND j.state IN ('dispatching','uncertain')) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DISPATCH_IN_FLIGHT'; END IF;
  result:=private_isg.set_producer_ownership_v1_impl(p_purpose,p_kind,p_owner,p_mode,p_now);
  IF previous_owner IS DISTINCT FROM p_owner THEN
    UPDATE private_isg.notification_jobs j SET state='cancelled',suppression_code='PRODUCER_HANDOVER',updated_at=p_now
      FROM private_isg.notification_episodes e WHERE j.episode_id=e.episode_id AND e.purpose=p_purpose
        AND e.episode_kind=p_kind AND e.produced_by=previous_owner AND j.state='failed';
    GET DIAGNOSTICS cancelled_failed=ROW_COUNT;
    result:=jsonb_set(result,'{cancelled_pending}',to_jsonb((result->>'cancelled_pending')::integer+cancelled_failed));
  END IF;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION private_isg.complete_notification_delivery(uuid,uuid,text,text,text,timestamptz),
  private_isg.record_notification_consent(uuid,text,text,boolean,text,text,timestamptz),
  private_isg.set_producer_ownership(text,text,text,text,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
