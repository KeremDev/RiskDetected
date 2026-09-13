-- CLI-generated; ordered after the repository's future-dated 070001 dependency.
-- No rollout, provider call, worker credentials, public RPC or client grant.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE private_isg.delivery_attempts ADD COLUMN retry_after_seconds integer
  CHECK(retry_after_seconds IS NULL OR (retry_after_seconds BETWEEN 1 AND 86400
    AND provider_state='rejected' AND failure_code IN ('RATE_LIMITED','PROVIDER_UNAVAILABLE','TEMPORARY_FAILURE')));
CREATE FUNCTION private_isg.complete_notification_delivery_with_retry(
  p_job uuid,p_token uuid,p_provider text,p_state text,p_failure text,p_now timestamptz,p_retry_after_seconds integer
) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE result jsonb; prior_wait integer; next_time timestamptz;
BEGIN
  PERFORM private_isg.notification_gate(true);
  IF p_retry_after_seconds IS NOT NULL AND (p_retry_after_seconds NOT BETWEEN 1 AND 86400
    OR p_state IS DISTINCT FROM 'rejected' OR p_failure IS NULL
    OR p_failure NOT IN ('RATE_LIMITED','PROVIDER_UNAVAILABLE','TEMPORARY_FAILURE')) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  -- Existing helper retains the owner/job locks until this transaction ends.
  result:=private_isg.complete_notification_delivery(p_job,p_token,p_provider,p_state,p_failure,p_now);
  SELECT retry_after_seconds INTO prior_wait FROM private_isg.delivery_attempts WHERE dispatch_token=p_token;
  IF (result->>'replayed')::boolean THEN
    IF prior_wait IS DISTINCT FROM p_retry_after_seconds THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
  ELSE
    UPDATE private_isg.delivery_attempts SET retry_after_seconds=p_retry_after_seconds WHERE dispatch_token=p_token;
    IF result->>'job_state'='failed' THEN
      UPDATE private_isg.notification_jobs
        SET next_attempt_at=greatest(next_attempt_at,p_now+make_interval(secs=>greatest(coalesce(p_retry_after_seconds,0),
          CASE WHEN p_failure='RATE_LIMITED' THEN 60 ELSE 0 END))) WHERE job_id=p_job;
    END IF;
  END IF;
  SELECT next_attempt_at INTO next_time FROM private_isg.notification_jobs WHERE job_id=p_job;
  RETURN result||jsonb_build_object('next_attempt_at',next_time,'retry_after_seconds',p_retry_after_seconds,
    'job_id',p_job,'dispatch_token',p_token);
END $$;
REVOKE ALL ON FUNCTION private_isg.complete_notification_delivery_with_retry(uuid,uuid,text,text,text,timestamptz,integer)
  FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
