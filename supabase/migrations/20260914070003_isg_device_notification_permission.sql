-- Additive P12 device permission. No legacy table, helper or rollout changes.
BEGIN;
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
  PERFORM private_isg.notification_gate(true);
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

-- Read-only, internal worker source. No authorization from platform aggregate
-- heartbeat/user_metadata. Multiple active devices require a delivery strategy;
-- never guess a primary device or silently fan out a single dispatch lease.
CREATE FUNCTION private_isg.notification_registered_device(p_job uuid,p_now timestamptz,p_max_age_seconds integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE result jsonb; candidates integer;
BEGIN
  PERFORM private_isg.notification_gate(false);
  IF p_job IS NULL OR p_now IS NULL OR NOT isfinite(p_now) OR p_max_age_seconds IS NULL OR p_max_age_seconds NOT BETWEEN 1 AND 86400 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT count(*), (jsonb_agg(x.value)->0) INTO candidates,result FROM (
    SELECT jsonb_build_object('token_id',t.id,'owner_id',e.owner_id,'app_build',d.app_build,
      'os_authorized',d.os_authorized,'provider',t.provider,'token',t.token,
      'environment',t.environment,'application_id',t.application_id,'provider_environment',t.provider_environment) value
    FROM private_isg.notification_jobs j JOIN private_isg.notification_episodes e USING(episode_id)
    JOIN public.push_device_tokens t ON t.user_id=e.owner_id
    JOIN private_isg.notification_device_permissions d ON d.token_id=t.id AND d.owner_id=t.user_id
    JOIN auth.sessions s ON s.id=d.session_id AND s.user_id=d.owner_id
    JOIN auth.users u ON u.id=d.owner_id
    WHERE j.job_id=p_job AND j.channel='push' AND t.notifications_enabled
      AND d.token_fingerprint=md5(t.token) AND d.observed_at<=p_now
      AND d.observed_at>=p_now-make_interval(secs=>p_max_age_seconds)
      AND (s.not_after IS NULL OR s.not_after>p_now) AND u.deleted_at IS NULL AND NOT u.is_anonymous
      AND (u.banned_until IS NULL OR u.banned_until<=p_now)
    LIMIT 2
  ) x;
  RETURN jsonb_build_object('schema_version',1,'job_id',p_job,'device',CASE WHEN candidates=1 THEN result ELSE NULL END,
    'reason',CASE WHEN candidates=0 THEN 'DEVICE_UNAVAILABLE' WHEN candidates>1 THEN 'DEVICE_STRATEGY_REQUIRED' ELSE NULL END);
END $$;
REVOKE ALL ON FUNCTION private_isg.notification_registered_device(uuid,timestamptz,integer) FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
