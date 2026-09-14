-- P15/D15 first slice: referral and winback on a canonical account, where only
-- server-observed real work qualifies, a campaign family is spent once, and a
-- budget or a pause stops new production without taking anything already earned.
-- Additive; rollout OFF; no client grant. Rewards are created through the P14
-- benefit ledger, which is itself locked to access_authority='legacy', so no
-- campaign here can open a paid capability or touch the store.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE private_isg.rollout DROP CONSTRAINT rollout_feature_check;
ALTER TABLE private_isg.rollout ADD CONSTRAINT rollout_feature_check
  CHECK(feature IN ('personnel','event_dispatch','quota_ledger','file_core','rule_engine','training','risk',
    'nonconformity','modules','documents','imports','notifications','personal_notes','billing_lifecycle','campaigns'));
INSERT INTO private_isg.rollout(feature) VALUES('campaigns');

CREATE TABLE private_isg.campaign_definitions (
  campaign_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE CHECK(code ~ '^[a-z][a-z0-9_]{2,49}$'),
  family text NOT NULL CHECK(family IN ('referral','winback')),
  -- A family is paused as a whole; a channel is paused separately in P12.
  family_paused boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
-- Versioned campaign rules behind a human publication gate. Every timing and
-- amount below is a V5 candidate, never an approved commercial decision.
CREATE TABLE private_isg.campaign_versions (
  version_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES private_isg.campaign_definitions(campaign_id) ON DELETE CASCADE,
  revision integer NOT NULL CHECK(revision BETWEEN 1 AND 100000),
  status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','published','paused','retired')),
  qualification_days integer NOT NULL CHECK(qualification_days BETWEEN 1 AND 10),
  qualification_window_days integer NOT NULL CHECK(qualification_window_days BETWEEN 1 AND 180),
  wait_hours integer CHECK(wait_hours IS NULL OR wait_hours BETWEEN 1 AND 720),
  accept_days integer CHECK(accept_days IS NULL OR accept_days BETWEEN 1 AND 90),
  max_contacts integer CHECK(max_contacts IS NULL OR max_contacts BETWEEN 0 AND 5),
  second_contact_gap_days integer CHECK(second_contact_gap_days IS NULL OR second_contact_gap_days BETWEEN 1 AND 60),
  inviter_reward_code text REFERENCES private_isg.benefit_definitions(code),
  invitee_reward_code text REFERENCES private_isg.benefit_definitions(code),
  winback_reward_code text REFERENCES private_isg.benefit_definitions(code),
  value_source text NOT NULL DEFAULT 'unapproved_fixture' CHECK(value_source IN ('unapproved_fixture','approved_catalog')),
  content_approved boolean NOT NULL DEFAULT false,
  needs_review boolean NOT NULL DEFAULT true,
  approved_by uuid, approval_note text CHECK(approval_note IS NULL OR length(approval_note) BETWEEN 3 AND 500),
  published_at timestamptz, paused_at timestamptz, pause_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(campaign_id,revision),
  -- Nothing reaches a user without a recorded human decision.
  CHECK(status<>'published' OR (approved_by IS NOT NULL AND approval_note IS NOT NULL AND published_at IS NOT NULL)),
  CHECK(status<>'paused' OR (paused_at IS NOT NULL AND pause_reason IS NOT NULL)),
  CHECK(value_source<>'unapproved_fixture' OR (NOT content_approved AND needs_review))
);
-- The canonical account owns the code. There is no place to store an address,
-- an IP or a device fingerprint, so none of those can become abuse evidence.
CREATE TABLE private_isg.referral_codes (
  code_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  campaign_id uuid NOT NULL REFERENCES private_isg.campaign_definitions(campaign_id),
  code text NOT NULL UNIQUE CHECK(code ~ '^[A-Z0-9]{6,12}$'),
  is_active boolean NOT NULL DEFAULT true,
  max_claims integer NOT NULL DEFAULT 100 CHECK(max_claims BETWEEN 1 AND 10000),
  version bigint NOT NULL DEFAULT 1 CHECK(version>=1),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(owner_id,campaign_id)
);
CREATE TABLE private_isg.referral_claims (
  claim_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code_id uuid NOT NULL REFERENCES private_isg.referral_codes(code_id) ON DELETE CASCADE,
  inviter_owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  invitee_owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  campaign_id uuid NOT NULL REFERENCES private_isg.campaign_definitions(campaign_id),
  state text NOT NULL DEFAULT 'claimed' CHECK(state IN ('claimed','qualified','rewarded','rejected','expired')),
  reject_code text CHECK(reject_code IS NULL OR reject_code IN ('SELF_REFERRAL','CYCLE_DETECTED','ALREADY_CLAIMED',
    'WINDOW_CLOSED','NOT_QUALIFIED','CAMPAIGN_PAUSED','BUDGET_EXHAUSTED','UNSUPPORTED_BRANCH')),
  inviter_branch text CHECK(inviter_branch IS NULL OR inviter_branch IN ('free','paid_monthly','paid_annual','unknown')),
  claimed_at timestamptz NOT NULL,
  qualified_at timestamptz, rewarded_at timestamptz,
  qualified_version_id uuid REFERENCES private_isg.campaign_versions(version_id),
  qualification_snapshot jsonb,
  version bigint NOT NULL DEFAULT 1 CHECK(version>=1),
  CHECK(inviter_owner_id<>invitee_owner_id),
  CHECK(state<>'rejected' OR reject_code IS NOT NULL)
);
-- An invitee belongs to one campaign family exactly once, whoever invited them.
CREATE UNIQUE INDEX referral_claim_invitee_once_idx ON private_isg.referral_claims(campaign_id,invitee_owner_id);
CREATE INDEX referral_claim_qualified_version_idx ON private_isg.referral_claims(qualified_version_id);
-- Only real, server-observed work that a Free account can actually perform.
-- A heartbeat, a screen view, a personal note or a failed analysis is not here
-- and has no row shape to become one.
CREATE TABLE private_isg.qualification_events (
  event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  event_kind text NOT NULL CHECK(event_kind IN ('employee_created','workplace_created','department_created',
    'training_plan_created','risk_assessment_created','document_exported','checklist_run_completed')),
  operation_id uuid NOT NULL,
  occurred_on date NOT NULL CHECK(isfinite(occurred_on)),
  account_timezone text NOT NULL,
  proof_source text NOT NULL DEFAULT 'server_mutation' CHECK(proof_source='server_mutation'),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(owner_id,operation_id)
);
CREATE INDEX qualification_event_day_idx ON private_isg.qualification_events(owner_id,occurred_on);
-- Reserve before producing, commit when the benefit exists, release otherwise.
CREATE TABLE private_isg.campaign_budgets (
  version_id uuid NOT NULL REFERENCES private_isg.campaign_versions(version_id) ON DELETE CASCADE,
  period_key text NOT NULL CHECK(period_key ~ '^[0-9]{4}(-[0-9]{2})?$'),
  cap_amount bigint NOT NULL CHECK(cap_amount BETWEEN 0 AND 1000000),
  cap_approved boolean NOT NULL DEFAULT false CHECK(NOT cap_approved),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(version_id,period_key)
);
CREATE TABLE private_isg.budget_reservations (
  reservation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version_id uuid NOT NULL, period_key text NOT NULL,
  subject_owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  amount bigint NOT NULL CHECK(amount BETWEEN 1 AND 1000),
  state text NOT NULL DEFAULT 'reserved' CHECK(state IN ('reserved','committed','released')),
  reserved_at timestamptz NOT NULL, settled_at timestamptz,
  FOREIGN KEY(version_id,period_key) REFERENCES private_isg.campaign_budgets(version_id,period_key) ON DELETE CASCADE
);
CREATE INDEX budget_reservation_window_idx ON private_isg.budget_reservations(version_id,period_key,state);
CREATE INDEX budget_reservation_subject_idx ON private_isg.budget_reservations(subject_owner_id);
-- One winback episode per family, for the lifetime of the account.
CREATE TABLE private_isg.winback_episodes (
  episode_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  version_id uuid NOT NULL REFERENCES private_isg.campaign_versions(version_id),
  campaign_id uuid NOT NULL REFERENCES private_isg.campaign_definitions(campaign_id),
  lifecycle_state_at_open text NOT NULL,
  plan_period_at_open text NOT NULL CHECK(plan_period_at_open IN ('monthly','annual','unknown')),
  became_eligible_at timestamptz NOT NULL,
  contactable_from timestamptz NOT NULL,
  accept_until timestamptz NOT NULL,
  contact_count integer NOT NULL DEFAULT 0 CHECK(contact_count BETWEEN 0 AND 5),
  last_contact_at timestamptz,
  state text NOT NULL DEFAULT 'waiting' CHECK(state IN ('waiting','contacted','accepted','expired','suppressed')),
  closed_at timestamptz, close_reason text,
  version bigint NOT NULL DEFAULT 1 CHECK(version>=1),
  UNIQUE(campaign_id,owner_id),
  CHECK(contactable_from>became_eligible_at),
  CHECK(accept_until>contactable_from),
  CHECK(state NOT IN ('accepted','expired','suppressed') OR (closed_at IS NOT NULL AND close_reason IS NOT NULL))
);
CREATE INDEX winback_episode_version_idx ON private_isg.winback_episodes(version_id);
CREATE TABLE private_isg.winback_contacts (
  contact_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  episode_id uuid NOT NULL REFERENCES private_isg.winback_episodes(episode_id) ON DELETE CASCADE,
  ordinal integer NOT NULL CHECK(ordinal BETWEEN 1 AND 5),
  channel text NOT NULL CHECK(channel IN ('push','email')),
  consent_verified_at timestamptz NOT NULL,
  contacted_at timestamptz NOT NULL,
  -- A contact is an attempt record, never a claim that anything was delivered.
  delivery_claimed boolean NOT NULL DEFAULT false CHECK(NOT delivery_claimed),
  UNIQUE(episode_id,ordinal)
);
-- Every refusal is written down with the stage it was decided at, so a paused
-- campaign and an ineligible user never look the same afterwards.
CREATE TABLE private_isg.suppression_records (
  suppression_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  campaign_id uuid NOT NULL REFERENCES private_isg.campaign_definitions(campaign_id),
  episode_id uuid REFERENCES private_isg.winback_episodes(episode_id) ON DELETE CASCADE,
  reason text NOT NULL CHECK(reason IN ('resubscribed','gift_active','consent_missing','budget_exhausted',
    'campaign_paused','already_paid','not_eligible','contact_limit','window_closed')),
  decided_at_stage text NOT NULL CHECK(decided_at_stage IN ('open','contact','checkout','reward')),
  ttl_reset boolean NOT NULL DEFAULT false CHECK(NOT ttl_reset),
  detail jsonb NOT NULL,
  decided_at timestamptz NOT NULL
);
CREATE INDEX suppression_owner_idx ON private_isg.suppression_records(owner_id,campaign_id);
CREATE INDEX suppression_episode_idx ON private_isg.suppression_records(episode_id);
CREATE TABLE private_isg.eligibility_checks (
  check_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  campaign_id uuid NOT NULL REFERENCES private_isg.campaign_definitions(campaign_id),
  lifecycle_state text NOT NULL,
  eligible boolean NOT NULL,
  reason_code text NOT NULL CHECK(reason_code ~ '^[A-Z][A-Z0-9_]{2,49}$'),
  evidence jsonb NOT NULL,
  checked_at timestamptz NOT NULL
);
CREATE INDEX eligibility_check_owner_idx ON private_isg.eligibility_checks(owner_id,campaign_id);

CREATE INDEX referral_code_owner_idx ON private_isg.referral_codes(owner_id);
CREATE INDEX referral_code_campaign_idx ON private_isg.referral_codes(campaign_id);
CREATE INDEX referral_claim_code_idx ON private_isg.referral_claims(code_id);
CREATE INDEX referral_claim_inviter_idx ON private_isg.referral_claims(inviter_owner_id,state);
CREATE INDEX referral_claim_campaign_idx ON private_isg.referral_claims(campaign_id);
CREATE INDEX campaign_version_campaign_idx ON private_isg.campaign_versions(campaign_id,status);
CREATE INDEX campaign_version_inviter_reward_idx ON private_isg.campaign_versions(inviter_reward_code);
CREATE INDEX campaign_version_invitee_reward_idx ON private_isg.campaign_versions(invitee_reward_code);
CREATE INDEX campaign_version_winback_reward_idx ON private_isg.campaign_versions(winback_reward_code);
CREATE INDEX winback_episode_campaign_idx ON private_isg.winback_episodes(campaign_id,state);
-- Every foreign key gets its own covering index; a composite whose leading
-- column is something else does not count as one.
CREATE INDEX referral_claim_invitee_idx ON private_isg.referral_claims(invitee_owner_id);
CREATE INDEX winback_episode_owner_idx ON private_isg.winback_episodes(owner_id);
CREATE INDEX suppression_campaign_idx ON private_isg.suppression_records(campaign_id);
CREATE INDEX eligibility_check_campaign_idx ON private_isg.eligibility_checks(campaign_id);

ALTER TABLE private_isg.campaign_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.campaign_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.referral_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.referral_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.qualification_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.campaign_budgets ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.budget_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.winback_episodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.winback_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.suppression_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.eligibility_checks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.campaign_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM private_isg.rollout WHERE feature='campaigns' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $$;
-- Publication is a recorded human decision. The values stay unapproved, so
-- everything produced from this version is reviewable.
CREATE FUNCTION private_isg.publish_campaign_version(p_version uuid,p_approver uuid,p_note text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.campaign_versions;
BEGIN
  PERFORM private_isg.campaign_gate(true);
  IF p_version IS NULL OR p_approver IS NULL OR p_note IS NULL OR p_now IS NULL OR
     length(p_note) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.campaign_versions WHERE version_id=p_version FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.status='published' THEN
    RETURN jsonb_build_object('schema_version',1,'version_id',p_version,'status','published','replayed',true); END IF;
  IF entry.status<>'draft' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  UPDATE private_isg.campaign_versions SET status='published',approved_by=p_approver,approval_note=p_note,
    published_at=p_now WHERE version_id=p_version;
  RETURN jsonb_build_object('schema_version',1,'version_id',p_version,'status','published','replayed',false,
    'values_approved',entry.content_approved,'needs_review',entry.needs_review);
END $$;
-- A pause stops new production. It never revokes an earned benefit or a store
-- accepted settlement; those live in the P14 ledger and are not touched here.
CREATE FUNCTION private_isg.pause_campaign_version(p_version uuid,p_reason text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.campaign_versions; kept bigint;
BEGIN
  PERFORM private_isg.campaign_gate(true);
  IF p_version IS NULL OR p_reason IS NULL OR p_now IS NULL OR length(p_reason) NOT BETWEEN 3 AND 200 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.campaign_versions WHERE version_id=p_version FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.status='paused' THEN
    RETURN jsonb_build_object('schema_version',1,'version_id',p_version,'status','paused','replayed',true); END IF;
  IF entry.status<>'published' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  UPDATE private_isg.campaign_versions SET status='paused',paused_at=p_now,pause_reason=p_reason WHERE version_id=p_version;
  SELECT count(*) INTO kept FROM private_isg.referral_claims WHERE campaign_id=entry.campaign_id AND state='rewarded';
  RETURN jsonb_build_object('schema_version',1,'version_id',p_version,'status','paused','replayed',false,
    'rewarded_claims_kept',kept,'earned_benefits_revoked',false,'settlements_revoked',false);
END $$;
CREATE FUNCTION private_isg.issue_referral_code(p_owner uuid,p_campaign uuid,p_code text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE prior private_isg.referral_codes; created uuid;
BEGIN
  PERFORM private_isg.campaign_gate(true);
  IF p_owner IS NULL OR p_campaign IS NULL OR p_code IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO prior FROM private_isg.referral_codes WHERE owner_id=p_owner AND campaign_id=p_campaign;
  IF FOUND THEN
    RETURN jsonb_build_object('schema_version',1,'code_id',prior.code_id,'code',prior.code,'replayed',true); END IF;
  INSERT INTO private_isg.referral_codes(owner_id,campaign_id,code,created_at)
    VALUES(p_owner,p_campaign,p_code,p_now) RETURNING code_id INTO created;
  RETURN jsonb_build_object('schema_version',1,'code_id',created,'code',p_code,'replayed',false);
END $$;
-- Canonical account guards only: self, cycle and repeat. A shared address, a
-- shared network or an Apple relay alias is not stored and is not evidence.
CREATE FUNCTION private_isg.claim_referral(p_code text,p_invitee uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE code_row private_isg.referral_codes; def_row private_isg.campaign_definitions; taken uuid; created uuid; used bigint;
BEGIN
  PERFORM private_isg.campaign_gate(true);
  IF p_code IS NULL OR p_invitee IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO code_row FROM private_isg.referral_codes WHERE code=p_code;
  IF NOT FOUND OR NOT code_row.is_active THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO def_row FROM private_isg.campaign_definitions WHERE campaign_id=code_row.campaign_id;
  IF def_row.family_paused THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CAMPAIGN_PAUSED'; END IF;
  IF code_row.owner_id=p_invitee THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SELF_REFERRAL'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('isg-referral:'||code_row.campaign_id::text||':'||p_invitee::text,0));
  SELECT claim_id INTO taken FROM private_isg.referral_claims
    WHERE campaign_id=code_row.campaign_id AND invitee_owner_id=p_invitee;
  IF taken IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ALREADY_CLAIMED'; END IF;
  -- A invited B, so B cannot turn around and invite A inside the same family.
  SELECT claim_id INTO taken FROM private_isg.referral_claims
    WHERE campaign_id=code_row.campaign_id AND inviter_owner_id=p_invitee AND invitee_owner_id=code_row.owner_id;
  IF taken IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CYCLE_DETECTED'; END IF;
  SELECT count(*) INTO used FROM private_isg.referral_claims WHERE code_id=code_row.code_id AND state<>'rejected';
  IF used>=code_row.max_claims THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  INSERT INTO private_isg.referral_claims(code_id,inviter_owner_id,invitee_owner_id,campaign_id,claimed_at)
    VALUES(code_row.code_id,code_row.owner_id,p_invitee,code_row.campaign_id,p_now) RETURNING claim_id INTO created;
  RETURN jsonb_build_object('schema_version',1,'claim_id',created,'state','claimed','rewarded',false);
END $$;
-- Only a completed server mutation may be recorded, and only once per operation.
CREATE FUNCTION private_isg.record_qualification_event(p_owner uuid,p_kind text,p_operation uuid,p_occurred_on date,
  p_timezone text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE prior uuid; created uuid;
BEGIN
  PERFORM private_isg.campaign_gate(true);
  IF p_owner IS NULL OR p_kind IS NULL OR p_operation IS NULL OR p_occurred_on IS NULL OR p_timezone IS NULL OR
     p_now IS NULL OR NOT isfinite(p_occurred_on) OR
     NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name=p_timezone) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT event_id INTO prior FROM private_isg.qualification_events WHERE owner_id=p_owner AND operation_id=p_operation;
  IF prior IS NOT NULL THEN
    RETURN jsonb_build_object('schema_version',1,'event_id',prior,'replayed',true); END IF;
  INSERT INTO private_isg.qualification_events(owner_id,event_kind,operation_id,occurred_on,account_timezone,recorded_at)
    VALUES(p_owner,p_kind,p_operation,p_occurred_on,p_timezone,p_now) RETURNING event_id INTO created;
  RETURN jsonb_build_object('schema_version',1,'event_id',created,'replayed',false,'proof_source','server_mutation');
END $$;
-- Distinct days of real work inside the campaign window; nothing else counts.
CREATE FUNCTION private_isg.evaluate_referral_qualification(p_claim uuid,p_version uuid,p_now timestamptz,
  p_plan_period text DEFAULT 'unknown') RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE claim_row private_isg.referral_claims; version_row private_isg.campaign_versions; days integer; verdict boolean;
  snapshot jsonb; uncertain boolean; active_paid boolean; branch text;
BEGIN
  PERFORM private_isg.campaign_gate(true);
  IF p_claim IS NULL OR p_version IS NULL OR p_now IS NULL OR p_plan_period IS NULL OR
     p_plan_period NOT IN ('monthly','annual','unknown') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO claim_row FROM private_isg.referral_claims WHERE claim_id=p_claim FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO version_row FROM private_isg.campaign_versions WHERE version_id=p_version;
  IF NOT FOUND OR version_row.campaign_id<>claim_row.campaign_id THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF claim_row.qualified_version_id IS NOT NULL AND claim_row.qualified_version_id<>p_version THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF version_row.status<>'published' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CAMPAIGN_UNAVAILABLE'; END IF;
  IF claim_row.state IN ('qualified','rewarded') THEN
    RETURN jsonb_build_object('schema_version',1,'claim_id',p_claim,'state',claim_row.state,'replayed',true); END IF;
  IF claim_row.state<>'claimed' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_now>claim_row.claimed_at+make_interval(days=>version_row.qualification_window_days) THEN
    UPDATE private_isg.referral_claims SET state='rejected',reject_code='WINDOW_CLOSED',version=version+1 WHERE claim_id=p_claim;
    RETURN jsonb_build_object('schema_version',1,'claim_id',p_claim,'state','rejected','reject_code','WINDOW_CLOSED'); END IF;
  SELECT count(DISTINCT occurred_on) INTO days FROM private_isg.qualification_events
    WHERE owner_id=claim_row.invitee_owner_id AND recorded_at>=claim_row.claimed_at
      AND recorded_at<=claim_row.claimed_at+make_interval(days=>version_row.qualification_window_days);
  verdict:=days>=version_row.qualification_days;
  IF NOT verdict THEN
    RETURN jsonb_build_object('schema_version',1,'claim_id',p_claim,'state','claimed','qualified',false,
      'distinct_days',days,'required_days',version_row.qualification_days,'reason','NOT_QUALIFIED'); END IF;
  -- Read ALL stores in one statement. The private server caller must resolve the
  -- catalogue period before qualification; award-time hints can never change it.
  SELECT coalesce(jsonb_agg(jsonb_build_object('store',store,'product_id',product_id,
      'state',lifecycle_state,'evidence_id',evidence_id)), '[]'::jsonb),
    coalesce(bool_or(needs_review OR lifecycle_state IN ('unknown','grace','on_hold','paused','refunded','revoked')),true),
    coalesce(bool_or(lifecycle_state='active'),false)
    INTO snapshot,uncertain,active_paid
    FROM private_isg.billing_lifecycle_projection
    WHERE owner_id=claim_row.inviter_owner_id AND environment='production';
  branch:=CASE WHEN uncertain THEN 'unknown'
    WHEN active_paid AND p_plan_period='monthly' THEN 'paid_monthly'
    WHEN active_paid AND p_plan_period='annual' THEN 'paid_annual'
    WHEN active_paid THEN 'unknown' ELSE 'free' END;
  UPDATE private_isg.referral_claims SET state='qualified',qualified_at=p_now,
    qualified_version_id=p_version,inviter_branch=branch,
    qualification_snapshot=jsonb_build_object('projections',snapshot,'plan_period',p_plan_period,
      'inviter_reward_code',version_row.inviter_reward_code,'invitee_reward_code',version_row.invitee_reward_code),
    version=version+1 WHERE claim_id=p_claim;
  RETURN jsonb_build_object('schema_version',1,'claim_id',p_claim,'state','qualified','qualified',true,
    'distinct_days',days,'required_days',version_row.qualification_days,'marketing_consent_required',false);
END $$;
CREATE FUNCTION private_isg.reserve_campaign_budget(p_version uuid,p_period text,p_owner uuid,p_amount bigint,
  p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE cap bigint; used bigint; created uuid;
BEGIN
  PERFORM private_isg.campaign_gate(true);
  IF p_version IS NULL OR p_period IS NULL OR p_owner IS NULL OR p_amount IS NULL OR p_amount<1 OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('isg-campaign-budget:'||p_version::text||':'||p_period,0));
  SELECT cap_amount INTO cap FROM private_isg.campaign_budgets WHERE version_id=p_version AND period_key=p_period;
  IF cap IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT coalesce(sum(amount),0) INTO used FROM private_isg.budget_reservations
    WHERE version_id=p_version AND period_key=p_period AND state IN ('reserved','committed');
  IF used+p_amount>cap THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='BUDGET_EXHAUSTED'; END IF;
  INSERT INTO private_isg.budget_reservations(version_id,period_key,subject_owner_id,amount,reserved_at)
    VALUES(p_version,p_period,p_owner,p_amount,p_now) RETURNING reservation_id INTO created;
  RETURN jsonb_build_object('schema_version',1,'reservation_id',created,'state','reserved',
    'used_after',used+p_amount,'cap',cap,'cap_approved',false);
END $$;
CREATE FUNCTION private_isg.settle_campaign_budget(p_reservation uuid,p_commit boolean,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.budget_reservations; target_state text;
BEGIN
  PERFORM private_isg.campaign_gate(true);
  IF p_reservation IS NULL OR p_commit IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.budget_reservations WHERE reservation_id=p_reservation FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  target_state:=CASE WHEN p_commit THEN 'committed' ELSE 'released' END;
  IF entry.state=target_state THEN
    RETURN jsonb_build_object('schema_version',1,'reservation_id',p_reservation,'state',target_state,'replayed',true); END IF;
  IF entry.state<>'reserved' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  UPDATE private_isg.budget_reservations SET state=target_state,settled_at=p_now WHERE reservation_id=p_reservation;
  RETURN jsonb_build_object('schema_version',1,'reservation_id',p_reservation,'state',target_state,'replayed',false);
END $$;
-- Earning uses the qualification snapshot, never an award-time plan hint.
-- Annual policy and unreadable billing remain pending, never silently Free
-- and never a permanent rejection. Store redemption stays a separate gate.
CREATE FUNCTION private_isg.award_referral_reward(p_claim uuid,p_version uuid,p_period text,p_plan_period text,
  p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE claim_row private_isg.referral_claims; version_row private_isg.campaign_versions;
  branch text; reserved jsonb; inviter_gift jsonb; invitee_gift jsonb;
BEGIN
  PERFORM private_isg.campaign_gate(true);
  IF p_claim IS NULL OR p_version IS NULL OR p_period IS NULL OR p_plan_period IS NULL OR p_now IS NULL OR
     p_plan_period NOT IN ('monthly','annual','unknown') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO claim_row FROM private_isg.referral_claims WHERE claim_id=p_claim FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO version_row FROM private_isg.campaign_versions WHERE version_id=p_version;
  IF NOT FOUND OR version_row.campaign_id<>claim_row.campaign_id OR
     claim_row.qualified_version_id IS DISTINCT FROM p_version THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF claim_row.state='rewarded' THEN
    RETURN jsonb_build_object('schema_version',1,'claim_id',p_claim,'state','rewarded','replayed',true); END IF;
  IF claim_row.state<>'qualified' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='NOT_QUALIFIED'; END IF;
  IF version_row.status<>'published' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CAMPAIGN_PAUSED'; END IF;
  branch:=coalesce(claim_row.inviter_branch,'unknown');
  IF branch IN ('paid_annual','unknown') THEN
    RETURN jsonb_build_object('schema_version',1,'claim_id',p_claim,'state','qualified',
      'pending_reason',CASE WHEN branch='paid_annual' THEN 'ANNUAL_POLICY_PENDING' ELSE 'BILLING_REVIEW_REQUIRED' END,
      'inviter_branch',branch,'auto_plan_conversion',false,
      'treated_as_free',false); END IF;
  reserved:=private_isg.reserve_campaign_budget(p_version,p_period,claim_row.inviter_owner_id,1,p_now);
  invitee_gift:=private_isg.grant_benefit(claim_row.invitee_owner_id,claim_row.qualification_snapshot->>'invitee_reward_code',
    'referral-invitee:'||p_claim::text,'davet qualification doğrulandı',p_now);
  inviter_gift:=private_isg.grant_benefit(claim_row.inviter_owner_id,
    CASE WHEN branch='paid_monthly' THEN claim_row.qualification_snapshot->>'inviter_reward_code'
      ELSE claim_row.qualification_snapshot->>'invitee_reward_code' END,
    'referral-inviter:'||p_claim::text,'davetçi ödülü',p_now);
  PERFORM private_isg.settle_campaign_budget((reserved->>'reservation_id')::uuid,true,p_now);
  UPDATE private_isg.referral_claims SET state='rewarded',rewarded_at=p_now,inviter_branch=branch,version=version+1
    WHERE claim_id=p_claim;
  RETURN jsonb_build_object('schema_version',1,'claim_id',p_claim,'state','rewarded','inviter_branch',branch,
    'invitee_instance',invitee_gift->'instance_id','inviter_instance',inviter_gift->'instance_id',
    'inviter_reward_kind',inviter_gift->'benefit_kind','needs_review',true,'values_approved',false,
    'capability_opened',false);
END $$;
-- Winback is for an account that really finished a paid monthly period and once
-- actually paid. Everything else is refused with its own recorded reason.
CREATE FUNCTION private_isg.winback_eligibility(p_owner uuid,p_campaign uuid,p_plan_period text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE paid_state text; verdict boolean; outcome text; paid_before boolean; other_active boolean; gift_on boolean;
BEGIN
  PERFORM private_isg.campaign_gate(true);
  IF p_owner IS NULL OR p_campaign IS NULL OR p_plan_period IS NULL OR p_now IS NULL OR
     p_plan_period NOT IN ('monthly','annual','unknown') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT CASE WHEN needs_review THEN 'unknown' ELSE lifecycle_state END INTO paid_state FROM private_isg.billing_lifecycle_projection
    WHERE owner_id=p_owner AND environment='production'
    ORDER BY CASE WHEN needs_review OR lifecycle_state='unknown' THEN 0
      WHEN lifecycle_state IN ('active','in_trial','grace') THEN 1
      WHEN lifecycle_state IN ('on_hold','paused') THEN 2
      WHEN lifecycle_state IN ('refunded','revoked') THEN 3 ELSE 4 END,
      applied_event_at DESC,applied_sequence_no DESC LIMIT 1;
  SELECT EXISTS(SELECT 1 FROM private_isg.billing_lifecycle_evidence WHERE owner_id=p_owner
    AND environment='production' AND event_kind IN ('purchase','renewal') AND lifecycle_state='active') INTO paid_before;
  SELECT EXISTS(SELECT 1 FROM private_isg.billing_lifecycle_projection WHERE owner_id=p_owner
    AND environment='production' AND lifecycle_state IN ('active','in_trial','grace')) INTO other_active;
  SELECT EXISTS(SELECT 1 FROM private_isg.benefit_instances WHERE owner_id=p_owner AND state='active'
    AND expires_at>p_now) INTO gift_on;
  outcome:=CASE
    WHEN paid_state IS NULL THEN 'NEVER_SUBSCRIBED'
    WHEN paid_state='unknown' THEN 'UNKNOWN_LIFECYCLE'
    WHEN other_active THEN 'OTHER_STORE_ACTIVE'
    WHEN paid_state IN ('on_hold','paused') THEN 'HOLD_OR_PAUSE'
    WHEN paid_state IN ('refunded','revoked') THEN 'REFUNDED_OR_REVOKED'
    WHEN paid_state<>'expired' THEN 'NOT_EXPIRED'
    WHEN NOT paid_before THEN 'TRIAL_OR_GIFT_ONLY'
    WHEN p_plan_period='annual' THEN 'ANNUAL_PLAN'
    WHEN p_plan_period='unknown' THEN 'UNKNOWN_PLAN_PERIOD'
    WHEN gift_on THEN 'GIFT_ACTIVE'
    ELSE 'ELIGIBLE' END;
  verdict:=outcome='ELIGIBLE';
  INSERT INTO private_isg.eligibility_checks(owner_id,campaign_id,lifecycle_state,eligible,reason_code,evidence,checked_at)
    VALUES(p_owner,p_campaign,coalesce(paid_state,'none'),verdict,outcome,
      jsonb_build_object('positive_payment',paid_before,'other_store_active',other_active,'gift_active',gift_on,
        'plan_period',p_plan_period),p_now);
  RETURN jsonb_build_object('schema_version',1,'eligible',verdict,'reason_code',outcome,
    'lifecycle_state',coalesce(paid_state,'none'),'positive_payment',paid_before);
END $$;
CREATE FUNCTION private_isg.open_winback_episode(p_owner uuid,p_version uuid,p_plan_period text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE version_row private_isg.campaign_versions; verdict jsonb; taken uuid; created uuid;
  contact_from timestamptz; accept_end timestamptz;
BEGIN
  PERFORM private_isg.campaign_gate(true);
  IF p_owner IS NULL OR p_version IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO version_row FROM private_isg.campaign_versions WHERE version_id=p_version;
  IF NOT FOUND OR version_row.wait_hours IS NULL OR version_row.accept_days IS NULL OR
     version_row.max_contacts IS NULL OR version_row.second_contact_gap_days IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF version_row.status<>'published' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CAMPAIGN_PAUSED'; END IF;
  -- Lifetime once per family: a second episode never restarts the clock.
  SELECT episode_id INTO taken FROM private_isg.winback_episodes
    WHERE campaign_id=version_row.campaign_id AND owner_id=p_owner;
  IF taken IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='EPISODE_EXISTS'; END IF;
  verdict:=private_isg.winback_eligibility(p_owner,version_row.campaign_id,p_plan_period,p_now);
  -- A refusal is written down, so it must not be rolled back by an exception.
  IF NOT (verdict->>'eligible')::boolean THEN
    INSERT INTO private_isg.suppression_records(owner_id,campaign_id,reason,decided_at_stage,detail,decided_at)
      VALUES(p_owner,version_row.campaign_id,'not_eligible','open',verdict,p_now);
    RETURN jsonb_build_object('schema_version',1,'opened',false,'reason_code',verdict->>'reason_code',
      'lifecycle_state',verdict->>'lifecycle_state','episode_id',NULL); END IF;
  contact_from:=p_now+make_interval(hours=>version_row.wait_hours);
  accept_end:=contact_from+make_interval(days=>version_row.accept_days);
  INSERT INTO private_isg.winback_episodes(owner_id,version_id,campaign_id,lifecycle_state_at_open,plan_period_at_open,
      became_eligible_at,contactable_from,accept_until)
    VALUES(p_owner,p_version,version_row.campaign_id,verdict->>'lifecycle_state',p_plan_period,p_now,contact_from,accept_end)
    RETURNING episode_id INTO created;
  RETURN jsonb_build_object('schema_version',1,'opened',true,'episode_id',created,'state','waiting',
    'contactable_from',contact_from,'accept_until',accept_end,'max_contacts',version_row.max_contacts,
    'timing_approved',false);
END $$;
-- Send-time re-check: the waiting time, the window, the contact budget, the
-- channel consent and the lifecycle are all read again, right now.
CREATE FUNCTION private_isg.record_winback_contact(p_episode uuid,p_channel text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.winback_episodes; version_row private_isg.campaign_versions; consent_at timestamptz;
  next_no integer; eligibility jsonb; refusal text;
BEGIN
  PERFORM private_isg.campaign_gate(true);
  IF p_episode IS NULL OR p_channel IS NULL OR p_now IS NULL OR p_channel NOT IN ('push','email') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.winback_episodes WHERE episode_id=p_episode FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state NOT IN ('waiting','contacted') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SUPPRESSED'; END IF;
  SELECT * INTO version_row FROM private_isg.campaign_versions WHERE version_id=entry.version_id;
  refusal:=NULL;
  IF version_row.status<>'published' THEN refusal:='campaign_paused';
  ELSIF p_now<entry.contactable_from THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='TOO_EARLY';
  ELSIF p_now>=entry.accept_until THEN refusal:='window_closed';
  ELSIF entry.contact_count>=version_row.max_contacts THEN refusal:='contact_limit';
  ELSIF entry.last_contact_at IS NOT NULL AND
        p_now<entry.last_contact_at+make_interval(days=>version_row.second_contact_gap_days) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='TOO_EARLY';
  END IF;
  IF refusal IS NULL THEN
    -- Marketing consent for this exact channel; an OS permission is not consent.
    SELECT captured_at INTO consent_at FROM private_isg.notification_consents
      WHERE owner_id=entry.owner_id AND purpose='marketing' AND channel=p_channel AND granted;
    IF consent_at IS NULL THEN refusal:='consent_missing'; END IF; END IF;
  IF refusal IS NULL THEN
    eligibility:=private_isg.winback_eligibility(entry.owner_id,entry.campaign_id,entry.plan_period_at_open,p_now);
    IF NOT (eligibility->>'eligible')::boolean THEN
      refusal:=CASE eligibility->>'reason_code' WHEN 'OTHER_STORE_ACTIVE' THEN 'resubscribed'
        WHEN 'GIFT_ACTIVE' THEN 'gift_active' ELSE 'not_eligible' END;
    END IF; END IF;
  IF refusal IS NOT NULL THEN
    INSERT INTO private_isg.suppression_records(owner_id,campaign_id,episode_id,reason,decided_at_stage,detail,decided_at)
      VALUES(entry.owner_id,entry.campaign_id,p_episode,refusal,'contact',
        jsonb_build_object('channel',p_channel,'accept_until',entry.accept_until,'eligibility',eligibility),p_now);
    -- A missing consent is this channel's answer today, not the end of the
    -- episode; everything else really closes it. Neither resets the clock.
    IF refusal<>'consent_missing' THEN
      UPDATE private_isg.winback_episodes SET state='suppressed',closed_at=p_now,close_reason=refusal,
        version=version+1 WHERE episode_id=p_episode; END IF;
    RETURN jsonb_build_object('schema_version',1,'episode_id',p_episode,'contacted',false,'reason',refusal,
      'episode_closed',refusal<>'consent_missing','accept_until',entry.accept_until,'ttl_reset',false); END IF;
  next_no:=entry.contact_count+1;
  INSERT INTO private_isg.winback_contacts(episode_id,ordinal,channel,consent_verified_at,contacted_at)
    VALUES(p_episode,next_no,p_channel,consent_at,p_now);
  UPDATE private_isg.winback_episodes SET state='contacted',contact_count=next_no,last_contact_at=p_now,
    version=version+1 WHERE episode_id=p_episode;
  RETURN jsonb_build_object('schema_version',1,'episode_id',p_episode,'contacted',true,'ordinal',next_no,
    'channel',p_channel,'accept_until',entry.accept_until,'ttl_reset',false,'delivery_claimed',false);
END $$;
CREATE FUNCTION private_isg.resolve_winback_episode(p_episode uuid,p_outcome text,p_reason text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.winback_episodes;
BEGIN
  PERFORM private_isg.campaign_gate(true);
  IF p_episode IS NULL OR p_outcome IS NULL OR p_reason IS NULL OR p_now IS NULL OR
     p_outcome NOT IN ('accepted','expired','suppressed') OR length(p_reason) NOT BETWEEN 3 AND 200 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.winback_episodes WHERE episode_id=p_episode FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state=p_outcome THEN
    RETURN jsonb_build_object('schema_version',1,'episode_id',p_episode,'state',p_outcome,'replayed',true); END IF;
  IF entry.state NOT IN ('waiting','contacted') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SUPPRESSED'; END IF;
  UPDATE private_isg.winback_episodes SET state=p_outcome,closed_at=p_now,close_reason=p_reason,version=version+1
    WHERE episode_id=p_episode;
  RETURN jsonb_build_object('schema_version',1,'episode_id',p_episode,'state',p_outcome,'replayed',false,
    'accept_until',entry.accept_until,'ttl_reset',false);
END $$;
REVOKE ALL ON FUNCTION private_isg.campaign_gate(boolean),
  private_isg.publish_campaign_version(uuid,uuid,text,timestamptz),
  private_isg.pause_campaign_version(uuid,text,timestamptz),
  private_isg.issue_referral_code(uuid,uuid,text,timestamptz),
  private_isg.claim_referral(text,uuid,timestamptz),
  private_isg.record_qualification_event(uuid,text,uuid,date,text,timestamptz),
  private_isg.evaluate_referral_qualification(uuid,uuid,timestamptz,text),
  private_isg.reserve_campaign_budget(uuid,text,uuid,bigint,timestamptz),
  private_isg.settle_campaign_budget(uuid,boolean,timestamptz),
  private_isg.award_referral_reward(uuid,uuid,text,text,timestamptz),
  private_isg.winback_eligibility(uuid,uuid,text,timestamptz),
  private_isg.open_winback_episode(uuid,uuid,text,timestamptz),
  private_isg.record_winback_contact(uuid,text,timestamptz),
  private_isg.resolve_winback_episode(uuid,text,text,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
