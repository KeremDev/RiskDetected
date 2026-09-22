-- Expected claim refusals are returned as typed business results so the
-- account-scoped attempt counter commits instead of being rolled back with an
-- exception. Authentication and unexpected database faults still fail closed.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.referral_claim_v1(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  actor uuid := (SELECT auth.uid());
  normalized text := upper(btrim(coalesce(p_code, '')));
  code_row private_isg.referral_codes;
  prior private_isg.referral_claims;
  result jsonb;
  version_row private_isg.campaign_versions;
  refusal text;
BEGIN
  IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id = actor) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'AUTH_REQUIRED';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('referral-claim-rate:' || actor::text, 0));
  IF (
    SELECT count(*)
    FROM private_isg.referral_claim_attempts a
    WHERE a.owner_id = actor
      AND a.attempted_at > clock_timestamp() - interval '1 hour'
  ) >= 10 THEN
    RETURN jsonb_build_object(
      'schema_version', 1, 'claim_id', NULL, 'state', 'rejected',
      'replayed', false, 'error_code', 'RATE_LIMITED'
    );
  END IF;
  INSERT INTO private_isg.referral_claim_attempts(owner_id) VALUES(actor);

  IF normalized !~ '^[A-Z0-9]{6,12}$' THEN
    RETURN jsonb_build_object(
      'schema_version', 1, 'claim_id', NULL, 'state', 'rejected',
      'replayed', false, 'error_code', 'INVALID_REFERRAL_CODE'
    );
  END IF;
  SELECT r.* INTO code_row
  FROM private_isg.referral_codes r
  JOIN private_isg.campaign_definitions d ON d.campaign_id = r.campaign_id
  WHERE r.code = normalized AND r.is_active AND d.code = 'friend_referral_plus_7d';
  IF code_row.code_id IS NULL THEN
    RETURN jsonb_build_object(
      'schema_version', 1, 'claim_id', NULL, 'state', 'rejected',
      'replayed', false, 'error_code', 'INVALID_REFERRAL_CODE'
    );
  END IF;
  SELECT c.* INTO prior
  FROM private_isg.referral_claims c
  WHERE c.campaign_id = code_row.campaign_id AND c.invitee_owner_id = actor;
  IF prior.claim_id IS NOT NULL THEN
    IF prior.code_id <> code_row.code_id THEN
      RETURN jsonb_build_object(
        'schema_version', 1, 'claim_id', prior.claim_id,
        'state', prior.state, 'replayed', false,
        'error_code', 'ALREADY_CLAIMED'
      );
    END IF;
    RETURN jsonb_build_object(
      'schema_version', 1, 'claim_id', prior.claim_id,
      'state', prior.state, 'replayed', true
    );
  END IF;

  BEGIN
    result := private_isg.claim_referral(normalized, actor, clock_timestamp());
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    refusal := SQLERRM;
    IF refusal IN (
      'SELF_REFERRAL', 'CYCLE_DETECTED', 'ALREADY_CLAIMED',
      'CAMPAIGN_PAUSED', 'FEATURE_UNAVAILABLE', 'VALIDATION_ERROR',
      'ACCESS_DENIED'
    ) THEN
      RETURN jsonb_build_object(
        'schema_version', 1, 'claim_id', NULL, 'state', 'rejected',
        'replayed', false,
        'error_code', CASE
          WHEN refusal IN ('ACCESS_DENIED', 'VALIDATION_ERROR')
            THEN 'INVALID_REFERRAL_CODE'
          ELSE refusal
        END
      );
    END IF;
    RAISE;
  END;

  SELECT v.* INTO version_row
  FROM private_isg.campaign_versions v
  WHERE v.campaign_id = code_row.campaign_id AND v.status = 'published'
  ORDER BY v.revision DESC LIMIT 1;
  INSERT INTO private_isg.referral_client_events(owner_id, event_name, context)
  VALUES(actor, 'code_claimed', jsonb_build_object('claim_id', result->>'claim_id'));
  RETURN result || jsonb_build_object(
    'qualification_days', version_row.qualification_days,
    'qualification_window_days', version_row.qualification_window_days,
    'reward_days', 7
  );
END $$;

REVOKE ALL ON FUNCTION public.referral_claim_v1(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.referral_claim_v1(text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
COMMIT;
