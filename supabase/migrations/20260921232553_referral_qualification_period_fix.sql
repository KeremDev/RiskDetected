-- Avoid a PL/pgSQL variable/column collision in the referral budget upsert.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION private_isg.capture_referral_qualification(
  p_owner uuid,
  p_kind text,
  p_operation uuid,
  p_occurred_on date,
  p_now timestamptz
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  claim_row private_isg.referral_claims;
  version_row private_isg.campaign_versions;
  outcome jsonb;
  budget_period text;
BEGIN
  IF p_owner IS NULL OR p_operation IS NULL OR p_now IS NULL THEN
    RETURN;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM private_isg.rollout
    WHERE feature = 'campaigns' AND read_enabled AND write_enabled
  ) THEN
    RETURN;
  END IF;

  PERFORM private_isg.record_qualification_event(
    p_owner, p_kind, p_operation, p_occurred_on,
    'Europe/Istanbul', p_now
  );

  budget_period := to_char(p_now AT TIME ZONE 'Europe/Istanbul', 'YYYY-MM');

  FOR claim_row IN
    SELECT c.*
    FROM private_isg.referral_claims c
    WHERE c.invitee_owner_id = p_owner AND c.state = 'claimed'
    FOR UPDATE
  LOOP
    SELECT v.* INTO version_row
    FROM private_isg.campaign_versions v
    WHERE v.campaign_id = claim_row.campaign_id
      AND v.status = 'published'
    ORDER BY v.revision DESC
    LIMIT 1;
    IF version_row.version_id IS NULL THEN
      CONTINUE;
    END IF;

    INSERT INTO private_isg.campaign_budgets(
      version_id, period_key, cap_amount, cap_approved
    ) VALUES (version_row.version_id, budget_period, 100, true)
    ON CONFLICT (version_id, period_key) DO NOTHING;

    outcome := private_isg.qualify_and_award_friend_referral(
      claim_row.claim_id, version_row.version_id, budget_period, p_now
    );
  END LOOP;
EXCEPTION WHEN OTHERS THEN
  INSERT INTO private_isg.referral_processing_errors(
    owner_id, event_kind, operation_id, sqlstate, message, created_at
  ) VALUES (
    p_owner, coalesce(p_kind, 'unknown'), p_operation,
    SQLSTATE, left(SQLERRM, 500), p_now
  );
  RETURN;
END $$;

REVOKE ALL ON FUNCTION
  private_isg.capture_referral_qualification(uuid, text, uuid, date, timestamptz)
FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
