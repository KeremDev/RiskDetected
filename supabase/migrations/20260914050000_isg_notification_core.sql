-- P12/D12 first slice: one notification backbone with four separate purposes,
-- consent provenance, producer ownership with a shadow mode, and a send-time
-- gate that re-checks everything the enqueue time could not know.
-- Additive; rollout OFF; no client grant. The legacy notification queue, its
-- kind CHECK and its producers are not read for authority and never written.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE private_isg.rollout DROP CONSTRAINT rollout_feature_check;
ALTER TABLE private_isg.rollout ADD CONSTRAINT rollout_feature_check
  CHECK(feature IN ('personnel','event_dispatch','quota_ledger','file_core','rule_engine','training','risk',
    'nonconformity','modules','documents','imports','notifications'));
INSERT INTO private_isg.rollout(feature) VALUES('notifications');

-- Four classes. Sharing APNs and FCM does not make them share a consent or a
-- timing rule. The candidate caps come from V5 and are not approved policy.
CREATE TABLE private_isg.notification_purposes (
  purpose text PRIMARY KEY CHECK(purpose IN ('obligation','personal_reminder','operational','marketing')),
  honours_quiet_hours boolean NOT NULL,
  quiet_start time NOT NULL DEFAULT '21:00', quiet_end time NOT NULL DEFAULT '08:00',
  daily_cap integer CHECK(daily_cap IS NULL OR daily_cap BETWEEN 1 AND 100),
  weekly_cap integer CHECK(weekly_cap IS NULL OR weekly_cap BETWEEN 1 AND 100),
  caps_approved boolean NOT NULL DEFAULT false,
  requires_explicit_consent boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO private_isg.notification_purposes(purpose,honours_quiet_hours,daily_cap,weekly_cap,requires_explicit_consent) VALUES
  ('obligation',true,NULL,NULL,false),
  ('personal_reminder',false,NULL,NULL,false),
  ('operational',true,2,NULL,false),
  ('marketing',true,NULL,1,true);
-- Consent carries where it came from. An OS permission prompt is not a
-- marketing consent, and e-mail consent is its own record.
CREATE TABLE private_isg.notification_consents (
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  purpose text NOT NULL REFERENCES private_isg.notification_purposes(purpose),
  channel text NOT NULL CHECK(channel IN ('push','email')),
  granted boolean NOT NULL,
  source text NOT NULL CHECK(source IN ('onboarding','settings','os_permission','legacy_migration')),
  captured_at timestamptz NOT NULL, revoked_at timestamptz,
  note text CHECK(note IS NULL OR length(note)<=500),
  PRIMARY KEY(owner_id,purpose,channel),
  CHECK(source<>'os_permission' OR purpose<>'marketing'),
  CHECK(source<>'os_permission' OR channel='push'),
  CHECK((revoked_at IS NOT NULL)=(NOT granted))
);
-- Exactly one owner per purpose and episode kind. Shadow means the new engine
-- may produce but must never send.
CREATE TABLE private_isg.producer_ownership (
  purpose text NOT NULL REFERENCES private_isg.notification_purposes(purpose),
  episode_kind text NOT NULL CHECK(episode_kind ~ '^[a-z][a-z0-9_.]{2,60}$'),
  owner text NOT NULL CHECK(owner IN ('legacy','isg_engine')),
  mode text NOT NULL DEFAULT 'shadow' CHECK(mode IN ('live','shadow')),
  watermark timestamptz NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(purpose,episode_kind),
  CHECK(owner<>'legacy' OR mode='live')
);
CREATE TABLE private_isg.notification_episodes (
  episode_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  company_id uuid,
  purpose text NOT NULL REFERENCES private_isg.notification_purposes(purpose),
  episode_kind text NOT NULL,
  source_ref text NOT NULL CHECK(btrim(source_ref)<>'' AND length(source_ref)<=200),
  schedule_version integer NOT NULL CHECK(schedule_version BETWEEN 1 AND 100000),
  rule_version integer CHECK(rule_version IS NULL OR rule_version>=1),
  produced_by text NOT NULL CHECK(produced_by IN ('legacy','isg_engine')),
  explicit_alarm boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(owner_id,purpose,episode_kind,source_ref,schedule_version),
  CHECK(NOT explicit_alarm OR purpose='personal_reminder')
);
CREATE TABLE private_isg.notification_jobs (
  job_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  episode_id uuid NOT NULL REFERENCES private_isg.notification_episodes(episode_id) ON DELETE CASCADE,
  channel text NOT NULL CHECK(channel IN ('push','email')),
  route text NOT NULL CHECK(route ~ '^[a-z][a-z0-9_/.:-]{2,120}$'),
  fallback_route text NOT NULL CHECK(fallback_route ~ '^[a-z][a-z0-9_/.:-]{2,120}$'),
  minimum_build integer NOT NULL CHECK(minimum_build BETWEEN 1 AND 2147483647),
  scheduled_for timestamptz NOT NULL,
  timezone text NOT NULL,
  state text NOT NULL DEFAULT 'queued' CHECK(state IN ('queued','suppressed','sent','failed','cancelled')),
  suppression_code text CHECK(suppression_code IS NULL OR suppression_code ~ '^[A-Z][A-Z0-9_]{2,49}$'),
  resolved_route text,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(episode_id,channel),
  CHECK((state IN ('suppressed','cancelled'))=(suppression_code IS NOT NULL))
);
-- A provider accepting a payload is not delivery and is certainly not a read.
CREATE TABLE private_isg.delivery_attempts (
  attempt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id uuid NOT NULL REFERENCES private_isg.notification_jobs(job_id) ON DELETE CASCADE,
  attempt_no integer NOT NULL CHECK(attempt_no BETWEEN 1 AND 10),
  provider text NOT NULL CHECK(provider IN ('apns','fcm','email')),
  provider_state text NOT NULL CHECK(provider_state IN ('accepted','rejected','error')),
  failure_code text CHECK(failure_code IS NULL OR failure_code ~ '^[A-Z][A-Z0-9_]{2,49}$'),
  delivery_confirmed boolean NOT NULL DEFAULT false CHECK(NOT delivery_confirmed),
  read_confirmed boolean NOT NULL DEFAULT false CHECK(NOT read_confirmed),
  attempted_at timestamptz NOT NULL,
  UNIQUE(job_id,attempt_no),
  CHECK((provider_state='accepted')=(failure_code IS NULL))
);
CREATE INDEX consent_owner_idx ON private_isg.notification_consents(owner_id,granted);
CREATE INDEX consent_purpose_idx ON private_isg.notification_consents(purpose);
CREATE INDEX episode_purpose_idx ON private_isg.notification_episodes(purpose);
CREATE INDEX episode_owner_idx ON private_isg.notification_episodes(owner_id,purpose);
CREATE INDEX episode_company_idx ON private_isg.notification_episodes(company_id);
CREATE INDEX job_state_idx ON private_isg.notification_jobs(state,scheduled_for);
CREATE INDEX job_episode_idx ON private_isg.notification_jobs(episode_id);
CREATE INDEX attempt_job_idx ON private_isg.delivery_attempts(job_id);
ALTER TABLE private_isg.notification_purposes ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.notification_consents ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.producer_ownership ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.notification_episodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.notification_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.delivery_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.notification_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM private_isg.rollout WHERE feature='notifications' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $$;
-- An existing opt-out survives migration: a legacy import can record it, never
-- overturn it.
CREATE FUNCTION private_isg.record_notification_consent(p_owner uuid,p_purpose text,p_channel text,p_granted boolean,
  p_source text,p_note text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE prior private_isg.notification_consents;
BEGIN
  PERFORM private_isg.notification_gate(true);
  IF p_owner IS NULL OR p_purpose IS NULL OR p_channel IS NULL OR p_granted IS NULL OR p_source IS NULL OR
     p_now IS NULL OR p_channel NOT IN ('push','email') OR
     p_source NOT IN ('onboarding','settings','os_permission','legacy_migration') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  PERFORM 1 FROM private_isg.notification_purposes WHERE purpose=p_purpose;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  -- The operating system prompt is a device capability, not a marketing consent.
  IF p_source='os_permission' AND (p_purpose='marketing' OR p_channel<>'push') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='OS_PERMISSION_IS_NOT_CONSENT'; END IF;
  SELECT * INTO prior FROM private_isg.notification_consents
    WHERE owner_id=p_owner AND purpose=p_purpose AND channel=p_channel FOR UPDATE;
  IF FOUND AND p_source='legacy_migration' AND NOT prior.granted AND p_granted THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEGACY_OPT_OUT_PRESERVED'; END IF;
  INSERT INTO private_isg.notification_consents(owner_id,purpose,channel,granted,source,captured_at,revoked_at,note)
    VALUES(p_owner,p_purpose,p_channel,p_granted,p_source,p_now,CASE WHEN p_granted THEN NULL ELSE p_now END,p_note)
  ON CONFLICT(owner_id,purpose,channel) DO UPDATE SET granted=excluded.granted,source=excluded.source,
    captured_at=excluded.captured_at,revoked_at=excluded.revoked_at,note=excluded.note;
  RETURN jsonb_build_object('schema_version',1,'owner_id',p_owner,'purpose',p_purpose,'channel',p_channel,
    'granted',p_granted,'source',p_source,'os_permission_counts_as_marketing_consent',false);
END $$;
-- Handing an episode kind to another producer cancels what the previous owner
-- had pending, so a cutover cannot double produce and a rollback cannot either.
CREATE FUNCTION private_isg.set_producer_ownership(p_purpose text,p_kind text,p_owner text,p_mode text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE prior private_isg.producer_ownership; cancelled integer:=0;
BEGIN
  PERFORM private_isg.notification_gate(true);
  IF p_purpose IS NULL OR p_kind IS NULL OR p_owner IS NULL OR p_mode IS NULL OR p_now IS NULL OR
     p_owner NOT IN ('legacy','isg_engine') OR p_mode NOT IN ('live','shadow') OR
     (p_owner='legacy' AND p_mode<>'live') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO prior FROM private_isg.producer_ownership WHERE purpose=p_purpose AND episode_kind=p_kind FOR UPDATE;
  IF FOUND AND prior.owner=p_owner AND prior.mode=p_mode THEN
    RETURN jsonb_build_object('schema_version',1,'purpose',p_purpose,'episode_kind',p_kind,'owner',p_owner,
      'mode',p_mode,'cancelled_pending',0,'replayed',true); END IF;
  IF FOUND AND prior.owner<>p_owner THEN
    WITH stale AS (
      UPDATE private_isg.notification_jobs j SET state='cancelled',suppression_code='PRODUCER_HANDOVER',updated_at=p_now
        FROM private_isg.notification_episodes e
        WHERE e.episode_id=j.episode_id AND e.purpose=p_purpose AND e.episode_kind=p_kind
          AND e.produced_by=prior.owner AND j.state='queued' RETURNING j.job_id)
    SELECT count(*) INTO cancelled FROM stale;
  END IF;
  INSERT INTO private_isg.producer_ownership(purpose,episode_kind,owner,mode,watermark,updated_at)
    VALUES(p_purpose,p_kind,p_owner,p_mode,p_now,p_now)
  ON CONFLICT(purpose,episode_kind) DO UPDATE SET owner=excluded.owner,mode=excluded.mode,
    watermark=excluded.watermark,updated_at=excluded.updated_at;
  RETURN jsonb_build_object('schema_version',1,'purpose',p_purpose,'episode_kind',p_kind,'owner',p_owner,
    'mode',p_mode,'cancelled_pending',cancelled,'replayed',false);
END $$;
CREATE FUNCTION private_isg.open_notification_episode(p_owner uuid,p_company uuid,p_purpose text,p_kind text,
  p_source_ref text,p_schedule_version integer,p_rule_version integer,p_producer text,p_explicit_alarm boolean,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE registry private_isg.producer_ownership; episode uuid; existing uuid; reference text;
BEGIN
  PERFORM private_isg.notification_gate(true);
  IF p_owner IS NULL OR p_purpose IS NULL OR p_kind IS NULL OR p_source_ref IS NULL OR p_schedule_version IS NULL OR
     p_producer IS NULL OR p_now IS NULL OR p_producer NOT IN ('legacy','isg_engine') OR
     p_explicit_alarm IS NULL OR (p_explicit_alarm AND p_purpose<>'personal_reminder') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO registry FROM private_isg.producer_ownership WHERE purpose=p_purpose AND episode_kind=p_kind FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PRODUCER_NOT_REGISTERED'; END IF;
  -- Only the registered owner may produce this episode kind.
  IF registry.owner<>p_producer THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PRODUCER_NOT_OWNER'; END IF;
  reference:=private_isg.text_value(p_source_ref,200);
  SELECT episode_id INTO existing FROM private_isg.notification_episodes WHERE owner_id=p_owner AND purpose=p_purpose
    AND episode_kind=p_kind AND source_ref=reference AND schedule_version=p_schedule_version;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'episode_id',existing,'replayed',true); END IF;
  INSERT INTO private_isg.notification_episodes(owner_id,company_id,purpose,episode_kind,source_ref,schedule_version,
      rule_version,produced_by,explicit_alarm,created_at)
    VALUES(p_owner,p_company,p_purpose,p_kind,reference,p_schedule_version,p_rule_version,p_producer,p_explicit_alarm,p_now)
    RETURNING episode_id INTO episode;
  RETURN jsonb_build_object('schema_version',1,'episode_id',episode,'purpose',p_purpose,'mode',registry.mode,'replayed',false);
END $$;
CREATE FUNCTION private_isg.enqueue_notification(p_episode uuid,p_channel text,p_route text,p_fallback text,
  p_minimum_build integer,p_scheduled_for timestamptz,p_timezone text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE episode private_isg.notification_episodes; job uuid; existing uuid;
BEGIN
  PERFORM private_isg.notification_gate(true);
  IF p_episode IS NULL OR p_channel IS NULL OR p_route IS NULL OR p_fallback IS NULL OR p_minimum_build IS NULL OR
     p_scheduled_for IS NULL OR p_timezone IS NULL OR p_now IS NULL OR p_channel NOT IN ('push','email') OR
     NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name=p_timezone) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO episode FROM private_isg.notification_episodes WHERE episode_id=p_episode FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  -- One job per episode and channel: the same episode never queues twice.
  SELECT job_id INTO existing FROM private_isg.notification_jobs WHERE episode_id=p_episode AND channel=p_channel;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'job_id',existing,'replayed',true); END IF;
  INSERT INTO private_isg.notification_jobs(episode_id,channel,route,fallback_route,minimum_build,scheduled_for,
      timezone,created_at,updated_at)
    VALUES(p_episode,p_channel,p_route,p_fallback,p_minimum_build,p_scheduled_for,p_timezone,p_now,p_now)
    RETURNING job_id INTO job;
  RETURN jsonb_build_object('schema_version',1,'job_id',job,'state','queued','replayed',false);
END $$;
-- Everything is re-checked here, at send time: ownership mode, account, device,
-- category, channel consent, quiet hours, frequency and the route this build
-- actually understands.
CREATE FUNCTION private_isg.dispatch_notification(p_job uuid,p_device jsonb,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE job private_isg.notification_jobs; episode private_isg.notification_episodes;
  policy private_isg.notification_purposes; registry private_isg.producer_ownership;
  consent private_isg.notification_consents; has_consent boolean; code text; resolved text;
  local_time time; local_day date; used integer; device_owner uuid; device_build integer; category boolean;
BEGIN
  PERFORM private_isg.notification_gate(true);
  IF p_job IS NULL OR p_now IS NULL OR p_device IS NULL OR jsonb_typeof(p_device)<>'object' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  device_owner:=(p_device->>'owner_id')::uuid; device_build:=(p_device->>'app_build')::integer;
  category:=coalesce((p_device->>'category_enabled')::boolean,false);
  IF device_owner IS NULL OR device_build IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO job FROM private_isg.notification_jobs WHERE job_id=p_job FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF job.state<>'queued' THEN
    RETURN jsonb_build_object('schema_version',1,'job_id',p_job,'state',job.state,
      'suppression_code',job.suppression_code,'replayed',true); END IF;
  SELECT * INTO episode FROM private_isg.notification_episodes WHERE episode_id=job.episode_id FOR SHARE;
  SELECT * INTO policy FROM private_isg.notification_purposes AS n WHERE n.purpose=episode.purpose;
  SELECT * INTO registry FROM private_isg.producer_ownership
    WHERE purpose=episode.purpose AND episode_kind=episode.episode_kind FOR SHARE;
  SELECT * INTO consent FROM private_isg.notification_consents
    WHERE owner_id=episode.owner_id AND purpose=episode.purpose AND channel=job.channel;
  has_consent:=FOUND;
  local_time:=(job.scheduled_for AT TIME ZONE job.timezone)::time;
  local_day:=(job.scheduled_for AT TIME ZONE job.timezone)::date;
  IF registry.owner<>episode.produced_by THEN code:='PRODUCER_HANDOVER';
  ELSIF registry.mode='shadow' THEN code:='SHADOW_MODE_NO_SEND';
  ELSIF device_owner<>episode.owner_id THEN code:='DEVICE_OWNER_MISMATCH';
  ELSIF NOT category THEN code:='CATEGORY_DISABLED';
  ELSIF NOT has_consent THEN
    IF policy.requires_explicit_consent THEN code:='CONSENT_MISSING'; END IF;
  ELSIF NOT consent.granted THEN code:='CONSENT_REVOKED';
  END IF;
  -- A personal alarm the user set on purpose is not silenced by quiet hours or
  -- by a campaign frequency cap.
  IF code IS NULL AND policy.honours_quiet_hours AND NOT episode.explicit_alarm AND
     (local_time>=policy.quiet_start OR local_time<policy.quiet_end) THEN code:='QUIET_HOURS'; END IF;
  IF code IS NULL AND NOT episode.explicit_alarm AND policy.daily_cap IS NOT NULL THEN
    SELECT count(*) INTO used FROM private_isg.notification_jobs j
      JOIN private_isg.notification_episodes e ON e.episode_id=j.episode_id
      WHERE e.owner_id=episode.owner_id AND e.purpose=episode.purpose AND j.state='sent'
        AND (j.scheduled_for AT TIME ZONE j.timezone)::date=local_day;
    IF used>=policy.daily_cap THEN code:='FREQUENCY_CAP'; END IF;
  END IF;
  IF code IS NULL AND NOT episode.explicit_alarm AND policy.weekly_cap IS NOT NULL THEN
    SELECT count(*) INTO used FROM private_isg.notification_jobs j
      JOIN private_isg.notification_episodes e ON e.episode_id=j.episode_id
      WHERE e.owner_id=episode.owner_id AND e.purpose=episode.purpose AND j.state='sent'
        AND (j.scheduled_for AT TIME ZONE j.timezone)::date>local_day-7
        AND (j.scheduled_for AT TIME ZONE j.timezone)::date<=local_day;
    IF used>=policy.weekly_cap THEN code:='FREQUENCY_CAP'; END IF;
  END IF;
  IF code IS NOT NULL THEN
    UPDATE private_isg.notification_jobs SET state='suppressed',suppression_code=code,updated_at=p_now WHERE job_id=p_job;
    RETURN jsonb_build_object('schema_version',1,'job_id',p_job,'state','suppressed','suppression_code',code,
      'delivered',false,'replayed',false);
  END IF;
  -- An older build that does not know the new deep link gets the safe existing
  -- screen. A route is never rewritten towards another company.
  resolved:=CASE WHEN device_build<job.minimum_build THEN job.fallback_route ELSE job.route END;
  UPDATE private_isg.notification_jobs SET resolved_route=resolved,updated_at=p_now WHERE job_id=p_job;
  RETURN jsonb_build_object('schema_version',1,'job_id',p_job,'state','queued','allowed',true,
    'resolved_route',resolved,'route_downgraded',device_build<job.minimum_build,
    'purpose',episode.purpose,'channel',job.channel,'delivered',false);
END $$;
CREATE FUNCTION private_isg.record_delivery_attempt(p_job uuid,p_provider text,p_state text,p_failure text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE job private_isg.notification_jobs; attempts integer; attempt uuid;
BEGIN
  PERFORM private_isg.notification_gate(true);
  IF p_job IS NULL OR p_provider IS NULL OR p_state IS NULL OR p_now IS NULL OR
     p_provider NOT IN ('apns','fcm','email') OR p_state NOT IN ('accepted','rejected','error') OR
     (p_state='accepted')<>(p_failure IS NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO job FROM private_isg.notification_jobs WHERE job_id=p_job FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF job.state NOT IN ('queued','failed') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='JOB_NOT_SENDABLE'; END IF;
  IF job.resolved_route IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SEND_TIME_CHECK_REQUIRED'; END IF;
  SELECT count(*) INTO attempts FROM private_isg.delivery_attempts WHERE job_id=p_job;
  INSERT INTO private_isg.delivery_attempts(job_id,attempt_no,provider,provider_state,failure_code,attempted_at)
    VALUES(p_job,attempts+1,p_provider,p_state,p_failure,p_now) RETURNING attempt_id INTO attempt;
  UPDATE private_isg.notification_jobs SET state=CASE WHEN p_state='accepted' THEN 'sent' ELSE 'failed' END,
    updated_at=p_now WHERE job_id=p_job;
  -- Accepted means the provider took the payload. Delivery and read are not
  -- claimed anywhere in this slice.
  RETURN jsonb_build_object('schema_version',1,'attempt_id',attempt,'attempt_no',attempts+1,
    'provider_state',p_state,'job_state',CASE WHEN p_state='accepted' THEN 'sent' ELSE 'failed' END,
    'delivery_confirmed',false,'read_confirmed',false);
END $$;
REVOKE ALL ON FUNCTION private_isg.notification_gate(boolean),
  private_isg.record_notification_consent(uuid,text,text,boolean,text,text,timestamptz),
  private_isg.set_producer_ownership(text,text,text,text,timestamptz),
  private_isg.open_notification_episode(uuid,uuid,text,text,text,integer,integer,text,boolean,timestamptz),
  private_isg.enqueue_notification(uuid,text,text,text,integer,timestamptz,text,timestamptz),
  private_isg.dispatch_notification(uuid,jsonb,timestamptz),
  private_isg.record_delivery_attempt(uuid,text,text,text,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
