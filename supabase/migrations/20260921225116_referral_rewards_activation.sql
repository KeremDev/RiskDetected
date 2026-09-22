-- Activate the referral-only slice of P15 for the isolated pilot environment.
-- A client can issue/read its own code, claim a code and activate only its own
-- earned gift. Qualification and award production remain server-owned.
BEGIN;
SET LOCAL lock_timeout = '5s';

ALTER TABLE private_isg.campaign_budgets
  DROP CONSTRAINT IF EXISTS campaign_budgets_cap_approved_check;

UPDATE private_isg.benefit_definitions
SET value_source = 'approved_catalog',
    content_approved = true,
    needs_review = false
WHERE code = 'sponsor_gift_plus_7d';

DO $$
DECLARE
  referral_campaign uuid;
  referral_version uuid;
  approver uuid;
BEGIN
  SELECT id INTO approver
  FROM public.profiles
  ORDER BY created_at, id
  LIMIT 1;
  approver := coalesce(approver, '00000000-0000-0000-0000-000000000001'::uuid);

  INSERT INTO private_isg.campaign_definitions(code, family, family_paused)
  VALUES ('friend_referral_plus_7d', 'referral', false)
  ON CONFLICT (code) DO UPDATE SET family_paused = false
  RETURNING campaign_id INTO referral_campaign;

  INSERT INTO private_isg.campaign_versions(
    campaign_id, revision, status, qualification_days,
    qualification_window_days, inviter_reward_code, invitee_reward_code,
    value_source, content_approved, needs_review, approved_by,
    approval_note, published_at
  ) VALUES (
    referral_campaign, 1, 'published', 2, 30,
    'sponsor_gift_plus_7d', 'sponsor_gift_plus_7d',
    'approved_catalog', true, false, approver,
    'Ürün sahibi talebiyle 22 Eylül 2026 pilot davet ve çift taraflı 7 gün Plus aktivasyonu.',
    clock_timestamp()
  )
  ON CONFLICT (campaign_id, revision) DO UPDATE SET
    status = 'published',
    qualification_days = EXCLUDED.qualification_days,
    qualification_window_days = EXCLUDED.qualification_window_days,
    inviter_reward_code = EXCLUDED.inviter_reward_code,
    invitee_reward_code = EXCLUDED.invitee_reward_code,
    value_source = 'approved_catalog',
    content_approved = true,
    needs_review = false,
    approved_by = EXCLUDED.approved_by,
    approval_note = EXCLUDED.approval_note,
    published_at = coalesce(private_isg.campaign_versions.published_at, EXCLUDED.published_at),
    paused_at = NULL,
    pause_reason = NULL
  RETURNING version_id INTO referral_version;

  INSERT INTO private_isg.campaign_budgets(
    version_id, period_key, cap_amount, cap_approved
  ) VALUES (
    referral_version,
    to_char(clock_timestamp() AT TIME ZONE 'Europe/Istanbul', 'YYYY-MM'),
    100,
    true
  )
  ON CONFLICT (version_id, period_key) DO UPDATE SET
    cap_amount = EXCLUDED.cap_amount,
    cap_approved = true;
END $$;

UPDATE private_isg.rollout
SET read_enabled = true, write_enabled = true
WHERE feature IN ('billing_lifecycle', 'campaigns');

CREATE TABLE private_isg.referral_processing_errors (
  error_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  event_kind text NOT NULL,
  operation_id uuid,
  sqlstate text NOT NULL,
  message text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX referral_processing_errors_created_idx
  ON private_isg.referral_processing_errors(created_at DESC);
ALTER TABLE private_isg.referral_processing_errors ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.referral_processing_errors
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE private_isg.referral_client_events (
  event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  event_name text NOT NULL CHECK(event_name IN (
    'screen_viewed', 'code_copied', 'share_started', 'code_claimed',
    'reward_activation_started', 'reward_activated'
  )),
  context jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK(jsonb_typeof(context) = 'object' AND octet_length(context::text) <= 2048),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX referral_client_events_owner_created_idx
  ON private_isg.referral_client_events(owner_id, created_at DESC);
ALTER TABLE private_isg.referral_client_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.referral_client_events
  FROM PUBLIC, anon, authenticated, service_role;

-- Keep invalid-code probing bounded without collecting an IP address, device
-- identifier or any other fingerprint. The canonical account is sufficient.
CREATE TABLE private_isg.referral_claim_attempts (
  attempt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  attempted_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX referral_claim_attempts_owner_time_idx
  ON private_isg.referral_claim_attempts(owner_id, attempted_at DESC);
ALTER TABLE private_isg.referral_claim_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.referral_claim_attempts
  FROM PUBLIC, anon, authenticated, service_role;

-- P15 deliberately kept accounts without a separate lifecycle projection in
-- review. The pilot already has one authoritative access row per account in
-- public.user_subscriptions, so this referral-only path can classify Free,
-- monthly and annual accounts without weakening any other campaign family.
CREATE OR REPLACE FUNCTION private_isg.qualify_and_award_friend_referral(
  p_claim uuid,
  p_version uuid,
  p_period text,
  p_now timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  claim_row private_isg.referral_claims;
  version_row private_isg.campaign_versions;
  campaign_code text;
  distinct_days integer;
  branch text;
  reserved jsonb;
  invitee_gift jsonb;
  inviter_gift jsonb;
BEGIN
  SELECT c.* INTO claim_row
  FROM private_isg.referral_claims c
  WHERE c.claim_id = p_claim
  FOR UPDATE;
  IF claim_row.claim_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ACCESS_DENIED';
  END IF;
  IF claim_row.state = 'rewarded' THEN
    RETURN jsonb_build_object(
      'schema_version', 1, 'claim_id', p_claim,
      'state', 'rewarded', 'replayed', true
    );
  END IF;
  IF claim_row.state <> 'claimed' THEN
    RETURN jsonb_build_object(
      'schema_version', 1, 'claim_id', p_claim,
      'state', claim_row.state, 'replayed', true
    );
  END IF;

  SELECT v.* INTO version_row
  FROM private_isg.campaign_versions v
  WHERE v.version_id = p_version;
  SELECT d.code INTO campaign_code
  FROM private_isg.campaign_definitions d
  WHERE d.campaign_id = version_row.campaign_id;
  IF version_row.version_id IS NULL
     OR version_row.campaign_id <> claim_row.campaign_id
     OR campaign_code <> 'friend_referral_plus_7d'
     OR version_row.status <> 'published' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'CAMPAIGN_UNAVAILABLE';
  END IF;
  IF p_now > claim_row.claimed_at
      + make_interval(days => version_row.qualification_window_days) THEN
    UPDATE private_isg.referral_claims
    SET state = 'expired', reject_code = NULL, version = version + 1
    WHERE claim_id = p_claim;
    RETURN jsonb_build_object(
      'schema_version', 1, 'claim_id', p_claim,
      'state', 'expired', 'reason', 'WINDOW_CLOSED'
    );
  END IF;

  SELECT count(DISTINCT q.occurred_on) INTO distinct_days
  FROM private_isg.qualification_events q
  WHERE q.owner_id = claim_row.invitee_owner_id
    AND q.recorded_at >= claim_row.claimed_at
    AND q.recorded_at <= claim_row.claimed_at
      + make_interval(days => version_row.qualification_window_days);
  IF distinct_days < version_row.qualification_days THEN
    RETURN jsonb_build_object(
      'schema_version', 1, 'claim_id', p_claim,
      'state', 'claimed', 'distinct_days', distinct_days,
      'required_days', version_row.qualification_days
    );
  END IF;

  SELECT CASE
    WHEN s.tier IN ('plus', 'pro')
      AND s.status IN ('active', 'trialing', 'grace_period')
      AND (s.current_period_ends_at IS NULL OR s.current_period_ends_at > p_now)
      AND (
        lower(coalesce(s.period_type, '')) IN ('annual', 'yearly')
        OR lower(coalesce(s.product_id, '')) LIKE '%year%'
      ) THEN 'paid_annual'
    WHEN s.tier IN ('plus', 'pro')
      AND s.status IN ('active', 'trialing', 'grace_period')
      AND (s.current_period_ends_at IS NULL OR s.current_period_ends_at > p_now)
      THEN 'paid_monthly'
    ELSE 'free'
  END INTO branch
  FROM public.user_subscriptions s
  WHERE s.user_id = claim_row.inviter_owner_id;
  branch := coalesce(branch, 'free');

  UPDATE private_isg.referral_claims
  SET state = 'qualified',
      qualified_at = p_now,
      qualified_version_id = p_version,
      inviter_branch = branch,
      qualification_snapshot = jsonb_build_object(
        'authority', 'public.user_subscriptions',
        'plan_period', branch,
        'distinct_days', distinct_days,
        'inviter_reward_code', version_row.inviter_reward_code,
        'invitee_reward_code', version_row.invitee_reward_code
      ),
      version = version + 1
  WHERE claim_id = p_claim;

  reserved := private_isg.reserve_campaign_budget(
    p_version, p_period, claim_row.inviter_owner_id, 1, p_now
  );
  invitee_gift := private_isg.grant_benefit(
    claim_row.invitee_owner_id,
    version_row.invitee_reward_code,
    'referral-invitee:' || p_claim::text,
    'Davet koşulları doğrulandı',
    p_now
  );
  inviter_gift := private_isg.grant_benefit(
    claim_row.inviter_owner_id,
    version_row.inviter_reward_code,
    'referral-inviter:' || p_claim::text,
    'Davet edilen kişi koşulları tamamladı',
    p_now
  );
  PERFORM private_isg.settle_campaign_budget(
    (reserved->>'reservation_id')::uuid, true, p_now
  );
  UPDATE private_isg.referral_claims
  SET state = 'rewarded', rewarded_at = p_now, version = version + 1
  WHERE claim_id = p_claim;

  RETURN jsonb_build_object(
    'schema_version', 1, 'claim_id', p_claim,
    'state', 'rewarded', 'inviter_branch', branch,
    'invitee_instance', invitee_gift->'instance_id',
    'inviter_instance', inviter_gift->'instance_id',
    'values_approved', true
  );
END $$;

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
  period_key text;
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

  period_key := to_char(p_now AT TIME ZONE 'Europe/Istanbul', 'YYYY-MM');

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
    ) VALUES (version_row.version_id, period_key, 100, true)
    ON CONFLICT (version_id, period_key) DO NOTHING;

    outcome := private_isg.qualify_and_award_friend_referral(
      claim_row.claim_id, version_row.version_id, period_key, p_now
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

CREATE OR REPLACE FUNCTION private_isg.capture_employee_referral_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM private_isg.capture_referral_qualification(
    NEW.owner_id, 'employee_created', NEW.id,
    (NEW.registered_at AT TIME ZONE 'Europe/Istanbul')::date,
    NEW.registered_at
  );
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION private_isg.capture_workplace_referral_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM private_isg.capture_referral_qualification(
    NEW.owner_id, 'workplace_created', NEW.id,
    (clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date,
    clock_timestamp()
  );
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION private_isg.capture_department_referral_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM private_isg.capture_referral_qualification(
    NEW.owner_id, 'department_created', NEW.id,
    (clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date,
    clock_timestamp()
  );
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION private_isg.capture_training_referral_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM private_isg.capture_referral_qualification(
    NEW.owner_id, 'training_plan_created', NEW.id,
    (NEW.created_at AT TIME ZONE 'Europe/Istanbul')::date,
    NEW.created_at
  );
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION private_isg.capture_risk_referral_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM private_isg.capture_referral_qualification(
    NEW.owner_id, 'risk_assessment_created', NEW.assessment_id,
    (NEW.created_at AT TIME ZONE 'Europe/Istanbul')::date,
    NEW.created_at
  );
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION private_isg.capture_report_referral_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM private_isg.capture_referral_qualification(
    NEW.user_id, 'document_exported', NEW.id,
    (NEW.created_at AT TIME ZONE 'Europe/Istanbul')::date,
    NEW.created_at
  );
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION private_isg.capture_checklist_referral_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NEW.state = 'submitted'
     AND (TG_OP = 'INSERT' OR OLD.state IS DISTINCT FROM NEW.state) THEN
    PERFORM private_isg.capture_referral_qualification(
      NEW.owner_id, 'checklist_run_completed', NEW.run_id,
      (coalesce(NEW.submitted_at, clock_timestamp()) AT TIME ZONE 'Europe/Istanbul')::date,
      coalesce(NEW.submitted_at, clock_timestamp())
    );
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS referral_employee_created ON private_isg.employees;
CREATE TRIGGER referral_employee_created
AFTER INSERT ON private_isg.employees
FOR EACH ROW EXECUTE FUNCTION private_isg.capture_employee_referral_event();

DROP TRIGGER IF EXISTS referral_workplace_created ON private_isg.workplaces;
CREATE TRIGGER referral_workplace_created
AFTER INSERT ON private_isg.workplaces
FOR EACH ROW EXECUTE FUNCTION private_isg.capture_workplace_referral_event();

DROP TRIGGER IF EXISTS referral_department_created ON private_isg.departments;
CREATE TRIGGER referral_department_created
AFTER INSERT ON private_isg.departments
FOR EACH ROW EXECUTE FUNCTION private_isg.capture_department_referral_event();

DROP TRIGGER IF EXISTS referral_training_created ON private_isg.pilot_training_records;
CREATE TRIGGER referral_training_created
AFTER INSERT ON private_isg.pilot_training_records
FOR EACH ROW EXECUTE FUNCTION private_isg.capture_training_referral_event();

DROP TRIGGER IF EXISTS referral_risk_created ON private_isg.risk_assessments;
CREATE TRIGGER referral_risk_created
AFTER INSERT ON private_isg.risk_assessments
FOR EACH ROW EXECUTE FUNCTION private_isg.capture_risk_referral_event();

DROP TRIGGER IF EXISTS referral_report_exported ON public.reports;
CREATE TRIGGER referral_report_exported
AFTER INSERT ON public.reports
FOR EACH ROW EXECUTE FUNCTION private_isg.capture_report_referral_event();

DROP TRIGGER IF EXISTS referral_checklist_completed ON private_isg.checklist_runs;
CREATE TRIGGER referral_checklist_completed
AFTER INSERT OR UPDATE OF state ON private_isg.checklist_runs
FOR EACH ROW EXECUTE FUNCTION private_isg.capture_checklist_referral_event();

CREATE OR REPLACE FUNCTION public.referral_dashboard_v1()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  actor uuid := (SELECT auth.uid());
  campaign_row private_isg.campaign_definitions;
  version_row private_isg.campaign_versions;
  code_row private_isg.referral_codes;
  code_value text;
  issued jsonb;
  sent jsonb;
  rewards jsonb;
  accepted jsonb;
  invited_count integer;
  qualified_count integer;
  rewarded_count integer;
BEGIN
  IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id = actor) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'AUTH_REQUIRED';
  END IF;
  PERFORM private_isg.campaign_gate(false);

  SELECT d.* INTO campaign_row
  FROM private_isg.campaign_definitions d
  WHERE d.code = 'friend_referral_plus_7d' AND NOT d.family_paused;
  SELECT v.* INTO version_row
  FROM private_isg.campaign_versions v
  WHERE v.campaign_id = campaign_row.campaign_id AND v.status = 'published'
  ORDER BY v.revision DESC LIMIT 1;
  IF version_row.version_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'CAMPAIGN_UNAVAILABLE';
  END IF;

  SELECT r.* INTO code_row
  FROM private_isg.referral_codes r
  WHERE r.owner_id = actor AND r.campaign_id = campaign_row.campaign_id;
  IF code_row.code_id IS NULL THEN
    code_value := upper(substr(md5(actor::text || ':' || campaign_row.campaign_id::text), 1, 10));
    issued := private_isg.issue_referral_code(actor, campaign_row.campaign_id, code_value, clock_timestamp());
    SELECT r.* INTO code_row
    FROM private_isg.referral_codes r
    WHERE r.code_id = (issued->>'code_id')::uuid;
  END IF;

  SELECT count(*),
         count(*) FILTER (WHERE state IN ('qualified', 'rewarded')),
         count(*) FILTER (WHERE state = 'rewarded')
  INTO invited_count, qualified_count, rewarded_count
  FROM private_isg.referral_claims
  WHERE inviter_owner_id = actor AND campaign_id = campaign_row.campaign_id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'claim_id', c.claim_id,
    'state', c.state,
    'claimed_at', c.claimed_at,
    'qualified_at', c.qualified_at,
    'rewarded_at', c.rewarded_at
  ) ORDER BY c.claimed_at DESC), '[]'::jsonb)
  INTO sent
  FROM private_isg.referral_claims c
  WHERE c.inviter_owner_id = actor AND c.campaign_id = campaign_row.campaign_id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'instance_id', i.instance_id,
    'state', CASE
      WHEN i.state = 'active' AND i.expires_at <= clock_timestamp() THEN 'expired'
      ELSE i.state END,
    'earned_at', i.earned_at,
    'activated_at', i.activated_at,
    'expires_at', i.expires_at,
    'capability', d.capability,
    'duration_hours', d.duration_hours
  ) ORDER BY i.earned_at DESC), '[]'::jsonb)
  INTO rewards
  FROM private_isg.benefit_instances i
  JOIN private_isg.benefit_definitions d ON d.definition_id = i.definition_id
  WHERE i.owner_id = actor AND d.code = 'sponsor_gift_plus_7d';

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'claim_id', c.claim_id,
    'state', c.state,
    'claimed_at', c.claimed_at,
    'qualified_at', c.qualified_at,
    'rewarded_at', c.rewarded_at,
    'distinct_days', (
      SELECT count(DISTINCT q.occurred_on)
      FROM private_isg.qualification_events q
      WHERE q.owner_id = actor AND q.recorded_at >= c.claimed_at
    ),
    'required_days', version_row.qualification_days
  ) ORDER BY c.claimed_at DESC), '[]'::jsonb)
  INTO accepted
  FROM private_isg.referral_claims c
  WHERE c.invitee_owner_id = actor AND c.campaign_id = campaign_row.campaign_id;

  RETURN jsonb_build_object(
    'schema_version', 1,
    'campaign', jsonb_build_object(
      'code', campaign_row.code,
      'qualification_days', version_row.qualification_days,
      'qualification_window_days', version_row.qualification_window_days,
      'reward_days', 7,
      'double_sided', true
    ),
    'referral_code', code_row.code,
    'share_url', 'io.supabase.riskdetected://invite?code=' || code_row.code,
    'share_message', 'RiskDetected ile iş güvenliği süreçlerini kolaylaştır. Davet kodum: ' ||
      code_row.code || E'\nDavet bağlantısı: io.supabase.riskdetected://invite?code=' || code_row.code ||
      E'\nUygulama: https://apps.apple.com/tr/app/id6769498181',
    'counts', jsonb_build_object(
      'invited', coalesce(invited_count, 0),
      'qualified', coalesce(qualified_count, 0),
      'rewarded', coalesce(rewarded_count, 0)
    ),
    'sent_invites', sent,
    'accepted_invites', accepted,
    'rewards', rewards
  );
END $$;

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
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'RATE_LIMITED';
  END IF;
  INSERT INTO private_isg.referral_claim_attempts(owner_id) VALUES(actor);
  IF normalized !~ '^[A-Z0-9]{6,12}$' THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'INVALID_REFERRAL_CODE';
  END IF;
  SELECT r.* INTO code_row
  FROM private_isg.referral_codes r
  JOIN private_isg.campaign_definitions d ON d.campaign_id = r.campaign_id
  WHERE r.code = normalized AND r.is_active AND d.code = 'friend_referral_plus_7d';
  IF code_row.code_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'INVALID_REFERRAL_CODE';
  END IF;
  SELECT c.* INTO prior
  FROM private_isg.referral_claims c
  WHERE c.campaign_id = code_row.campaign_id AND c.invitee_owner_id = actor;
  IF prior.claim_id IS NOT NULL THEN
    IF prior.code_id <> code_row.code_id THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ALREADY_CLAIMED';
    END IF;
    RETURN jsonb_build_object(
      'schema_version', 1, 'claim_id', prior.claim_id,
      'state', prior.state, 'replayed', true
    );
  END IF;

  result := private_isg.claim_referral(normalized, actor, clock_timestamp());
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

CREATE OR REPLACE FUNCTION public.referral_activate_reward_v1(p_instance uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  actor uuid := (SELECT auth.uid());
  instance_row private_isg.benefit_instances;
  definition_row private_isg.benefit_definitions;
  activation jsonb;
  active_paid boolean;
  another_gift_active boolean;
BEGIN
  IF actor IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'AUTH_REQUIRED';
  END IF;
  SELECT i.* INTO instance_row
  FROM private_isg.benefit_instances i
  WHERE i.instance_id = p_instance AND i.owner_id = actor
  FOR UPDATE;
  IF instance_row.instance_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ACCESS_DENIED';
  END IF;
  SELECT d.* INTO definition_row
  FROM private_isg.benefit_definitions d
  WHERE d.definition_id = instance_row.definition_id
    AND d.code = 'sponsor_gift_plus_7d';
  IF definition_row.definition_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ACCESS_DENIED';
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM public.user_subscriptions s
    WHERE s.user_id = actor
      AND s.source <> 'referral_reward'
      AND s.tier IN ('plus', 'pro')
      AND s.status IN ('active', 'trialing', 'grace_period')
      AND (s.current_period_ends_at IS NULL OR s.current_period_ends_at > clock_timestamp())
  ) INTO active_paid;
  IF active_paid THEN
    RETURN jsonb_build_object(
      'schema_version', 1, 'activated', false,
      'reason', 'PAID_ACCESS_ACTIVE', 'state', instance_row.state
    );
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM private_isg.benefit_instances i
    JOIN private_isg.benefit_definitions d ON d.definition_id = i.definition_id
    WHERE i.owner_id = actor AND i.instance_id <> p_instance
      AND i.state = 'active' AND i.expires_at > clock_timestamp()
      AND d.benefit_kind = 'gift_access'
  ) INTO another_gift_active;
  IF another_gift_active THEN
    RETURN jsonb_build_object(
      'schema_version', 1, 'activated', false,
      'reason', 'GIFT_ALREADY_ACTIVE', 'state', instance_row.state
    );
  END IF;

  IF instance_row.state = 'earned' THEN
    PERFORM private_isg.advance_benefit(
      p_instance, 'available', 'Davet ödülü kullanıma hazırlandı', clock_timestamp()
    );
  END IF;
  activation := private_isg.activate_gift(p_instance, clock_timestamp());

  INSERT INTO public.user_subscriptions(
    user_id, tier, source, status, entitlement_id, entitlement_ids,
    current_period_ends_at, updated_at
  ) VALUES (
    actor, 'plus', 'referral_reward', 'active', 'plus', ARRAY['plus']::text[],
    (activation->>'expires_at')::timestamptz, clock_timestamp()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    tier = 'plus',
    source = 'referral_reward',
    status = 'active',
    entitlement_id = 'plus',
    entitlement_ids = ARRAY['plus']::text[],
    current_period_ends_at = EXCLUDED.current_period_ends_at,
    updated_at = EXCLUDED.updated_at;

  INSERT INTO private_isg.referral_client_events(owner_id, event_name, context)
  VALUES(actor, 'reward_activated', jsonb_build_object('instance_id', p_instance));

  RETURN activation || jsonb_build_object(
    'activated', true, 'tier', 'plus', 'reward_days', 7
  );
END $$;

CREATE OR REPLACE FUNCTION public.referral_event_v1(
  p_event text,
  p_context jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  actor uuid := (SELECT auth.uid());
  created uuid;
BEGIN
  IF actor IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'AUTH_REQUIRED';
  END IF;
  IF p_event NOT IN (
    'screen_viewed', 'code_copied', 'share_started',
    'reward_activation_started'
  ) OR p_context IS NULL OR jsonb_typeof(p_context) <> 'object'
     OR octet_length(p_context::text) > 2048 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'VALIDATION_ERROR';
  END IF;
  INSERT INTO private_isg.referral_client_events(owner_id, event_name, context)
  VALUES(actor, p_event, p_context)
  RETURNING event_id INTO created;
  RETURN jsonb_build_object('schema_version', 1, 'event_id', created);
END $$;

-- The legacy access helper now recognises an active, server-clock sponsor gift.
-- Store subscriptions remain authoritative for paid purchases.
CREATE OR REPLACE FUNCTION private.user_plan_tier(p_user_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT CASE
    WHEN EXISTS (
      SELECT 1 FROM public.user_subscriptions s
      WHERE s.user_id = p_user_id AND s.tier = 'pro'
        AND s.status IN ('active', 'trialing', 'grace_period')
        AND (s.current_period_ends_at IS NULL OR s.current_period_ends_at > clock_timestamp())
    ) THEN 'pro'
    WHEN EXISTS (
      SELECT 1 FROM public.user_subscriptions s
      WHERE s.user_id = p_user_id AND s.tier = 'plus'
        AND s.status IN ('active', 'trialing', 'grace_period')
        AND (s.current_period_ends_at IS NULL OR s.current_period_ends_at > clock_timestamp())
    ) OR EXISTS (
      SELECT 1
      FROM private_isg.benefit_instances i
      JOIN private_isg.benefit_definitions d ON d.definition_id = i.definition_id
      WHERE i.owner_id = p_user_id AND i.state = 'active'
        AND i.expires_at > clock_timestamp()
        AND d.grants_capability AND d.capability = 'plus_access'
    ) THEN 'plus'
    ELSE 'free'
  END;
$$;

REVOKE ALL ON FUNCTION
  private_isg.qualify_and_award_friend_referral(uuid, uuid, text, timestamptz),
  private_isg.capture_referral_qualification(uuid, text, uuid, date, timestamptz),
  private_isg.capture_employee_referral_event(),
  private_isg.capture_workplace_referral_event(),
  private_isg.capture_department_referral_event(),
  private_isg.capture_training_referral_event(),
  private_isg.capture_risk_referral_event(),
  private_isg.capture_report_referral_event(),
  private_isg.capture_checklist_referral_event()
FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION
  public.referral_dashboard_v1(),
  public.referral_claim_v1(text),
  public.referral_activate_reward_v1(uuid),
  public.referral_event_v1(text, jsonb)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION
  public.referral_dashboard_v1(),
  public.referral_claim_v1(text),
  public.referral_activate_reward_v1(uuid),
  public.referral_event_v1(text, jsonb)
TO authenticated, service_role;

REVOKE ALL ON FUNCTION private.user_plan_tier(uuid)
FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
