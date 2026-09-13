-- P14/D14 first slice: one canonical billing lifecycle ledger, a structural
-- separation between a gift and a discount, and the quote/intent/settlement
-- chain that binds a campaign benefit to exactly one real store payment.
-- Additive; rollout OFF; no client grant. The existing RevenueCat wiring, the
-- store catalogue, the legacy paid helpers and every earned right are untouched:
-- the projection is locked to access_authority='legacy' so nothing here can
-- decide what a user may do until a separate, human-approved cutover.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE private_isg.rollout DROP CONSTRAINT rollout_feature_check;
ALTER TABLE private_isg.rollout ADD CONSTRAINT rollout_feature_check
  CHECK(feature IN ('personnel','event_dispatch','quota_ledger','file_core','rule_engine','training','risk',
    'nonconformity','modules','documents','imports','notifications','personal_notes','billing_lifecycle'));
INSERT INTO private_isg.rollout(feature) VALUES('billing_lifecycle');

-- Append-only observation of what a store actually said. A webhook, a client
-- sync and a restore are three sources of the same truth, never three truths.
CREATE TABLE private_isg.billing_lifecycle_evidence (
  evidence_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  environment text NOT NULL CHECK(environment IN ('sandbox','production')),
  store text NOT NULL CHECK(store IN ('apple','google')),
  product_id text NOT NULL CHECK(product_id ~ '^[A-Za-z0-9][A-Za-z0-9._-]{2,119}$'),
  purchase_ref text NOT NULL CHECK(purchase_ref ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{3,199}$'),
  event_kind text NOT NULL CHECK(event_kind IN ('purchase','renewal','cancellation','expiration','billing_issue',
    'grace_start','hold_start','pause','resume','refund','revoke','restore','sync')),
  lifecycle_state text NOT NULL CHECK(lifecycle_state IN ('active','in_trial','grace','on_hold','paused',
    'expired','refunded','revoked','unknown')),
  store_event_at timestamptz NOT NULL,
  sequence_no bigint NOT NULL CHECK(sequence_no BETWEEN 0 AND 9007199254740991),
  source text NOT NULL CHECK(source IN ('webhook','client_sync','restore','reconciliation')),
  payload_hash bytea NOT NULL,
  observed_at timestamptz NOT NULL DEFAULT now(),
  -- An unreadable lifecycle is a reviewable fact, never a silent Free user.
  needs_review boolean NOT NULL DEFAULT false,
  CHECK(lifecycle_state<>'unknown' OR needs_review),
  UNIQUE(store,environment,purchase_ref,event_kind,sequence_no)
);
-- One current row per subscription. It reports; it does not authorise.
CREATE TABLE private_isg.billing_lifecycle_projection (
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  store text NOT NULL, environment text NOT NULL, product_id text NOT NULL,
  lifecycle_state text NOT NULL CHECK(lifecycle_state IN ('active','in_trial','grace','on_hold','paused',
    'expired','refunded','revoked','unknown')),
  state_since timestamptz NOT NULL,
  applied_event_at timestamptz NOT NULL,
  applied_sequence_no bigint NOT NULL,
  evidence_id uuid NOT NULL REFERENCES private_isg.billing_lifecycle_evidence(evidence_id),
  auto_renew_enabled boolean,
  expires_at timestamptz,
  needs_review boolean NOT NULL DEFAULT false,
  access_authority text NOT NULL DEFAULT 'legacy' CHECK(access_authority='legacy'),
  version bigint NOT NULL DEFAULT 1 CHECK(version>=1),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(owner_id,store,environment,product_id),
  CHECK(lifecycle_state<>'unknown' OR needs_review)
);
-- The whole point of P14: a gift carries a capability, a discount never can.
-- Both are impossible to confuse because the CHECK forbids the other shape.
CREATE TABLE private_isg.benefit_definitions (
  definition_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE CHECK(code ~ '^[a-z][a-z0-9_]{2,49}$'),
  benefit_kind text NOT NULL CHECK(benefit_kind IN ('gift_access','discount_coupon')),
  grants_capability boolean NOT NULL,
  capability text CHECK(capability IS NULL OR capability IN ('plus_access','pro_access')),
  duration_hours integer CHECK(duration_hours IS NULL OR duration_hours BETWEEN 1 AND 8760),
  discount_percent integer CHECK(discount_percent IS NULL OR discount_percent BETWEEN 1 AND 99),
  funding_source text NOT NULL CHECK(funding_source IN ('sponsor','store','partner')),
  -- A gift is sponsor access on the server clock, not a store auto-renew trial,
  -- and it never resets a quota period that the user already consumed.
  resets_quota boolean NOT NULL DEFAULT false CHECK(NOT resets_quota),
  is_store_trial boolean NOT NULL DEFAULT false CHECK(NOT is_store_trial),
  family_scope text NOT NULL CHECK(family_scope IN ('none','lifetime_once','period_once')),
  value_source text NOT NULL DEFAULT 'unapproved_fixture' CHECK(value_source IN ('unapproved_fixture','approved_catalog')),
  content_approved boolean NOT NULL DEFAULT false,
  needs_review boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK(benefit_kind<>'discount_coupon' OR (NOT grants_capability AND capability IS NULL AND duration_hours IS NULL AND discount_percent IS NOT NULL)),
  CHECK(benefit_kind<>'gift_access' OR (grants_capability AND capability IS NOT NULL AND duration_hours IS NOT NULL AND discount_percent IS NULL)),
  CHECK(value_source<>'unapproved_fixture' OR (NOT content_approved AND needs_review))
);
-- The benefit state machine lives as rows, so a reader can see every legal move.
CREATE TABLE private_isg.benefit_state_edges (
  from_state text NOT NULL, to_state text NOT NULL, note text NOT NULL,
  PRIMARY KEY(from_state,to_state)
);
CREATE TABLE private_isg.benefit_instances (
  instance_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  definition_id uuid NOT NULL REFERENCES private_isg.benefit_definitions(definition_id),
  state text NOT NULL DEFAULT 'earned' CHECK(state IN ('earned','available','deferred','reserved',
    'awaiting_store','scheduled','review','consumed','active','expired','adjusted')),
  family_key text CHECK(family_key IS NULL OR family_key ~ '^[a-z0-9][a-z0-9:_-]{2,99}$'),
  reason text NOT NULL CHECK(length(reason) BETWEEN 3 AND 200),
  earned_at timestamptz NOT NULL,
  activated_at timestamptz,
  expires_at timestamptz,
  version bigint NOT NULL DEFAULT 1 CHECK(version>=1),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK(state<>'active' OR (activated_at IS NOT NULL AND expires_at IS NOT NULL))
);
-- A campaign family may be used once; the payment key below stays family-free.
CREATE UNIQUE INDEX benefit_family_once_idx ON private_isg.benefit_instances(definition_id,family_key)
  WHERE family_key IS NOT NULL;
-- The real store offer. The signing material stays outside the database and
-- outside the app; the price always comes from the store, never from a formula.
CREATE TABLE private_isg.store_offer_mappings (
  mapping_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  definition_id uuid NOT NULL REFERENCES private_isg.benefit_definitions(definition_id),
  store text NOT NULL CHECK(store IN ('apple','google')),
  environment text NOT NULL CHECK(environment IN ('sandbox','production')),
  product_id text NOT NULL CHECK(product_id ~ '^[A-Za-z0-9][A-Za-z0-9._-]{2,119}$'),
  offer_id text NOT NULL CHECK(offer_id ~ '^[A-Za-z0-9][A-Za-z0-9._-]{2,119}$'),
  base_plan_id text CHECK(base_plan_id IS NULL OR base_plan_id ~ '^[A-Za-z0-9][A-Za-z0-9._-]{2,119}$'),
  offer_kind text NOT NULL CHECK(offer_kind IN ('promotional','developer_determined')),
  replacement_mode text CHECK(replacement_mode IN ('without_proration','charge_prorated_price','deferred')),
  signature_required boolean NOT NULL DEFAULT false,
  offer_token_required boolean NOT NULL DEFAULT false,
  signature_material_stored boolean NOT NULL DEFAULT false CHECK(NOT signature_material_stored),
  price_authority text NOT NULL DEFAULT 'store' CHECK(price_authority='store'),
  -- An old binary must not pick a campaign offer inside a normal purchase; this
  -- catalogue tag is a client hint and never replaces the server quote below.
  excluded_from_default_offering boolean NOT NULL DEFAULT true CHECK(excluded_from_default_offering),
  limit_approved boolean NOT NULL DEFAULT false CHECK(NOT limit_approved),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(store,environment,product_id,offer_id),
  CHECK(store<>'apple' OR (signature_required AND replacement_mode IS NULL AND base_plan_id IS NULL)),
  CHECK(store<>'google' OR (offer_token_required AND replacement_mode IS NOT NULL AND base_plan_id IS NOT NULL))
);
-- The server quote is the eligibility authority. A visible offering is not one.
CREATE TABLE private_isg.discount_quotes (
  quote_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  instance_id uuid NOT NULL REFERENCES private_isg.benefit_instances(instance_id) ON DELETE CASCADE,
  mapping_id uuid NOT NULL REFERENCES private_isg.store_offer_mappings(mapping_id),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  currency text NOT NULL CHECK(currency ~ '^[A-Z]{3}$'),
  current_price_micros bigint NOT NULL CHECK(current_price_micros BETWEEN 0 AND 1000000000000),
  offer_price_micros bigint NOT NULL CHECK(offer_price_micros BETWEEN 0 AND 1000000000000),
  price_observed_at timestamptz NOT NULL,
  advantage boolean NOT NULL,
  state text NOT NULL CHECK(state IN ('issued','rejected','consumed','expired')),
  rejection_code text CHECK(rejection_code IS NULL OR rejection_code ~ '^[A-Z][A-Z0-9_]{2,49}$'),
  eligibility_authority text NOT NULL DEFAULT 'server' CHECK(eligibility_authority='server'),
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  -- No advantage, no live quote: a 100 → 120 "discount" can never be issued.
  CHECK(advantage=(offer_price_micros<current_price_micros)),
  CHECK(advantage OR state='rejected'),
  CHECK(state<>'rejected' OR rejection_code IS NOT NULL)
);
CREATE TABLE private_isg.checkout_intents (
  intent_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_id uuid NOT NULL REFERENCES private_isg.discount_quotes(quote_id) ON DELETE CASCADE,
  installation_id uuid NOT NULL,
  state text NOT NULL DEFAULT 'awaiting_store' CHECK(state IN ('awaiting_store','settled','review','abandoned')),
  opened_at timestamptz NOT NULL,
  timeout_at timestamptz NOT NULL,
  closed_at timestamptz,
  CHECK(state='awaiting_store' OR closed_at IS NOT NULL)
);
-- One live checkout per quote: a timeout can never produce a second economic use.
CREATE UNIQUE INDEX checkout_intent_live_idx ON private_isg.checkout_intents(quote_id) WHERE state='awaiting_store';
-- The economic key. Family is deliberately absent, so a referral and a winback
-- can never both settle against the same discounted billing period.
CREATE TABLE private_isg.benefit_settlements (
  settlement_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  instance_id uuid NOT NULL REFERENCES private_isg.benefit_instances(instance_id),
  intent_id uuid NOT NULL UNIQUE REFERENCES private_isg.checkout_intents(intent_id),
  evidence_id uuid NOT NULL REFERENCES private_isg.billing_lifecycle_evidence(evidence_id),
  environment text NOT NULL CHECK(environment IN ('sandbox','production')),
  store text NOT NULL CHECK(store IN ('apple','google')),
  purchase_ref text NOT NULL,
  billing_period daterange NOT NULL CHECK(NOT isempty(billing_period)),
  state text NOT NULL DEFAULT 'consumed' CHECK(state IN ('consumed','adjusted')),
  settled_at timestamptz NOT NULL,
  UNIQUE(environment,store,purchase_ref,billing_period)
);
CREATE TABLE private_isg.settlement_adjustments (
  adjustment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  settlement_id uuid NOT NULL REFERENCES private_isg.benefit_settlements(settlement_id) ON DELETE CASCADE,
  adjustment_kind text NOT NULL CHECK(adjustment_kind IN ('refund','revoke','chargeback','correction')),
  reason text NOT NULL CHECK(length(reason) BETWEEN 3 AND 300),
  evidence jsonb NOT NULL,
  adjusted_at timestamptz NOT NULL
);
CREATE TABLE private_isg.billing_reconciliation_jobs (
  job_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ran_for date NOT NULL UNIQUE CHECK(isfinite(ran_for)),
  evidence_seen bigint NOT NULL CHECK(evidence_seen>=0),
  projections_reviewed bigint NOT NULL CHECK(projections_reviewed>=0),
  benefits_in_review bigint NOT NULL CHECK(benefits_in_review>=0),
  settlements_open bigint NOT NULL CHECK(settlements_open>=0),
  detail jsonb NOT NULL,
  ran_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO private_isg.benefit_state_edges(from_state,to_state,note) VALUES
  ('earned','available','qualified and ready to use'),
  ('earned','deferred','held for a later eligible period'),
  ('deferred','available','the eligible period arrived'),
  ('deferred','expired','the window closed unused'),
  ('available','reserved','a server quote was issued'),
  ('available','active','a sponsor gift was activated by an explicit action'),
  ('available','expired','the window closed unused'),
  ('reserved','awaiting_store','a checkout was opened'),
  ('reserved','available','a definite cancellation returns the benefit'),
  ('awaiting_store','scheduled','the store accepted and evidence exists'),
  ('awaiting_store','review','the outcome is uncertain, never assumed'),
  ('awaiting_store','available','a definite store cancellation'),
  ('scheduled','consumed','the discounted payment is proven'),
  ('scheduled','review','the proof went missing again'),
  ('review','available','a human cleared the uncertainty'),
  ('review','consumed','the payment proof arrived late'),
  ('consumed','adjusted','a refund or revoke was reported'),
  ('active','expired','the gift window ran out on the server clock');
-- Structural fixtures only: neither the seven day window nor the twenty percent
-- is an approved commercial number, so both stay unapproved and reviewable.
INSERT INTO private_isg.benefit_definitions(code,benefit_kind,grants_capability,capability,duration_hours,
    discount_percent,funding_source,family_scope) VALUES
  ('sponsor_gift_plus_7d','gift_access',true,'plus_access',168,NULL,'sponsor','period_once'),
  ('monthly_discount_one_period','discount_coupon',false,NULL,NULL,20,'store','lifetime_once');

CREATE INDEX billing_evidence_owner_idx ON private_isg.billing_lifecycle_evidence(owner_id,store,environment,product_id);
CREATE INDEX billing_evidence_ref_idx ON private_isg.billing_lifecycle_evidence(store,environment,purchase_ref);
CREATE INDEX billing_evidence_review_idx ON private_isg.billing_lifecycle_evidence(needs_review) WHERE needs_review;
CREATE INDEX billing_projection_evidence_idx ON private_isg.billing_lifecycle_projection(evidence_id);
CREATE INDEX billing_projection_review_idx ON private_isg.billing_lifecycle_projection(needs_review) WHERE needs_review;
CREATE INDEX benefit_instance_owner_idx ON private_isg.benefit_instances(owner_id,state);
CREATE INDEX benefit_instance_definition_idx ON private_isg.benefit_instances(definition_id);
CREATE INDEX store_offer_definition_idx ON private_isg.store_offer_mappings(definition_id);
CREATE INDEX discount_quote_instance_idx ON private_isg.discount_quotes(instance_id);
CREATE INDEX discount_quote_mapping_idx ON private_isg.discount_quotes(mapping_id);
CREATE INDEX discount_quote_owner_idx ON private_isg.discount_quotes(owner_id,state);
CREATE INDEX checkout_intent_quote_idx ON private_isg.checkout_intents(quote_id);
CREATE INDEX benefit_settlement_instance_idx ON private_isg.benefit_settlements(instance_id);
CREATE INDEX benefit_settlement_evidence_idx ON private_isg.benefit_settlements(evidence_id);
CREATE INDEX settlement_adjustment_idx ON private_isg.settlement_adjustments(settlement_id);

ALTER TABLE private_isg.billing_lifecycle_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.billing_lifecycle_projection ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.benefit_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.benefit_state_edges ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.benefit_instances ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.store_offer_mappings ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.discount_quotes ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.checkout_intents ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.benefit_settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.settlement_adjustments ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.billing_reconciliation_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.billing_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM private_isg.rollout WHERE feature='billing_lifecycle' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $$;
-- A duplicate or replayed webhook is recorded once. A purchase that already
-- belongs to another account is refused before anything is written.
CREATE FUNCTION private_isg.record_billing_evidence(p_owner uuid,p_environment text,p_store text,p_product text,
  p_purchase_ref text,p_event_kind text,p_lifecycle_state text,p_store_event_at timestamptz,p_sequence bigint,
  p_source text,p_payload jsonb,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE existing_owner uuid; prior uuid; created uuid; fingerprint bytea;
BEGIN
  PERFORM private_isg.billing_gate(true);
  IF p_owner IS NULL OR p_environment IS NULL OR p_store IS NULL OR p_product IS NULL OR p_purchase_ref IS NULL OR
     p_event_kind IS NULL OR p_lifecycle_state IS NULL OR p_store_event_at IS NULL OR p_sequence IS NULL OR
     p_sequence<0 OR p_source IS NULL OR p_now IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR
     octet_length(p_payload::text)>8192 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('isg-billing:'||p_store||':'||p_environment||':'||p_purchase_ref,0));
  SELECT owner_id INTO existing_owner FROM private_isg.billing_lifecycle_evidence
    WHERE store=p_store AND environment=p_environment AND purchase_ref=p_purchase_ref LIMIT 1;
  IF existing_owner IS NOT NULL AND existing_owner<>p_owner THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PURCHASE_OWNED_ELSEWHERE'; END IF;
  SELECT evidence_id INTO prior FROM private_isg.billing_lifecycle_evidence
    WHERE store=p_store AND environment=p_environment AND purchase_ref=p_purchase_ref
      AND event_kind=p_event_kind AND sequence_no=p_sequence;
  IF prior IS NOT NULL THEN
    RETURN jsonb_build_object('schema_version',1,'evidence_id',prior,'replayed',true,'access_authority','legacy'); END IF;
  fingerprint:=sha256(convert_to(p_payload::text,'UTF8'));
  INSERT INTO private_isg.billing_lifecycle_evidence(owner_id,environment,store,product_id,purchase_ref,event_kind,
      lifecycle_state,store_event_at,sequence_no,source,payload_hash,observed_at,needs_review)
    VALUES(p_owner,p_environment,p_store,p_product,p_purchase_ref,p_event_kind,p_lifecycle_state,p_store_event_at,
      p_sequence,p_source,fingerprint,p_now,p_lifecycle_state='unknown') RETURNING evidence_id INTO created;
  RETURN jsonb_build_object('schema_version',1,'evidence_id',created,'replayed',false,
    'needs_review',p_lifecycle_state='unknown','access_authority','legacy');
END $$;
-- An older or out-of-order store event never rewrites a newer projection.
CREATE FUNCTION private_isg.project_billing_lifecycle(p_evidence uuid,p_auto_renew boolean,p_expires_at timestamptz,
  p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.billing_lifecycle_evidence; current_row private_isg.billing_lifecycle_projection;
BEGIN
  PERFORM private_isg.billing_gate(true);
  IF p_evidence IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.billing_lifecycle_evidence WHERE evidence_id=p_evidence;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO current_row FROM private_isg.billing_lifecycle_projection
    WHERE owner_id=entry.owner_id AND store=entry.store AND environment=entry.environment
      AND product_id=entry.product_id FOR UPDATE;
  IF FOUND AND (entry.store_event_at,entry.sequence_no)<=(current_row.applied_event_at,current_row.applied_sequence_no) THEN
    RETURN jsonb_build_object('schema_version',1,'applied',false,'reason','out_of_order',
      'lifecycle_state',current_row.lifecycle_state,'version',current_row.version,'access_authority','legacy'); END IF;
  INSERT INTO private_isg.billing_lifecycle_projection(owner_id,store,environment,product_id,lifecycle_state,
      state_since,applied_event_at,applied_sequence_no,evidence_id,auto_renew_enabled,expires_at,needs_review,updated_at)
    VALUES(entry.owner_id,entry.store,entry.environment,entry.product_id,entry.lifecycle_state,entry.store_event_at,
      entry.store_event_at,entry.sequence_no,entry.evidence_id,p_auto_renew,p_expires_at,
      entry.lifecycle_state='unknown',p_now)
    ON CONFLICT(owner_id,store,environment,product_id) DO UPDATE SET
      lifecycle_state=EXCLUDED.lifecycle_state,
      state_since=CASE WHEN private_isg.billing_lifecycle_projection.lifecycle_state=EXCLUDED.lifecycle_state
        THEN private_isg.billing_lifecycle_projection.state_since ELSE EXCLUDED.state_since END,
      applied_event_at=EXCLUDED.applied_event_at,applied_sequence_no=EXCLUDED.applied_sequence_no,
      evidence_id=EXCLUDED.evidence_id,auto_renew_enabled=EXCLUDED.auto_renew_enabled,
      expires_at=EXCLUDED.expires_at,needs_review=EXCLUDED.needs_review,
      version=private_isg.billing_lifecycle_projection.version+1,updated_at=EXCLUDED.updated_at;
  SELECT * INTO current_row FROM private_isg.billing_lifecycle_projection
    WHERE owner_id=entry.owner_id AND store=entry.store AND environment=entry.environment AND product_id=entry.product_id;
  RETURN jsonb_build_object('schema_version',1,'applied',true,'lifecycle_state',current_row.lifecycle_state,
    'version',current_row.version,'needs_review',current_row.needs_review,'access_authority','legacy');
END $$;
-- Three separated sources, one report, zero authority. A discount appears here
-- only to say, in as many words, that it opens nothing.
CREATE FUNCTION private_isg.effective_billing_access(p_owner uuid,p_environment text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE paid_state text; gift_row private_isg.benefit_instances; gift_capability text; floor_report jsonb; quota_open boolean;
BEGIN
  PERFORM private_isg.billing_gate(false);
  IF p_owner IS NULL OR p_environment IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  -- A sandbox purchase never reports a paid production tier.
  IF p_environment='production' THEN
    SELECT lifecycle_state INTO paid_state FROM private_isg.billing_lifecycle_projection
      WHERE owner_id=p_owner AND environment='production'
      ORDER BY applied_event_at DESC,applied_sequence_no DESC LIMIT 1;
  END IF;
  SELECT * INTO gift_row FROM private_isg.benefit_instances
    WHERE owner_id=p_owner AND state='active' AND expires_at>p_now ORDER BY expires_at DESC LIMIT 1;
  IF gift_row.instance_id IS NOT NULL THEN
    SELECT capability INTO gift_capability FROM private_isg.benefit_definitions WHERE definition_id=gift_row.definition_id; END IF;
  SELECT read_enabled INTO quota_open FROM private_isg.rollout WHERE feature='quota_ledger';
  IF coalesce(quota_open,false) THEN floor_report:=private_isg.effective_floor(p_owner,'company_slot');
  ELSE floor_report:=jsonb_build_object('recorded',false,'floor_source','unavailable','needs_review',true); END IF;
  RETURN jsonb_build_object('schema_version',1,'access_authority','legacy','decides_access',false,
    'billing_tier',jsonb_build_object('lifecycle_state',coalesce(paid_state,'unknown'),
      'is_paid',coalesce(paid_state,'unknown') IN ('active','in_trial','grace'),
      'needs_review',paid_state IS NULL OR paid_state='unknown'),
    'gift_capability',jsonb_build_object('active',gift_capability IS NOT NULL,'capability',gift_capability,
      'expires_at',gift_row.expires_at,'quota_reset',false,'is_store_trial',false),
    'capacity_floor',floor_report,
    'discount_grants_access',false);
END $$;
CREATE FUNCTION private_isg.grant_benefit(p_owner uuid,p_code text,p_family text,p_reason text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE def_row private_isg.benefit_definitions; created uuid; taken uuid;
BEGIN
  PERFORM private_isg.billing_gate(true);
  IF p_owner IS NULL OR p_code IS NULL OR p_reason IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO def_row FROM private_isg.benefit_definitions WHERE code=p_code;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF def_row.family_scope<>'none' AND p_family IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_family IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('isg-benefit-family:'||def_row.definition_id::text||':'||p_family,0));
    SELECT instance_id INTO taken FROM private_isg.benefit_instances
      WHERE definition_id=def_row.definition_id AND family_key=p_family;
    IF taken IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FAMILY_ALREADY_USED'; END IF; END IF;
  INSERT INTO private_isg.benefit_instances(owner_id,definition_id,family_key,reason,earned_at,updated_at)
    VALUES(p_owner,def_row.definition_id,p_family,p_reason,p_now,p_now) RETURNING instance_id INTO created;
  RETURN jsonb_build_object('schema_version',1,'instance_id',created,'state','earned',
    'benefit_kind',def_row.benefit_kind,'grants_capability',def_row.grants_capability,
    'content_approved',def_row.content_approved,'needs_review',def_row.needs_review);
END $$;
-- Every move is a row in benefit_state_edges; an unlisted move does not exist.
CREATE FUNCTION private_isg.advance_benefit(p_instance uuid,p_target text,p_reason text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.benefit_instances; allowed boolean;
BEGIN
  PERFORM private_isg.billing_gate(true);
  IF p_instance IS NULL OR p_target IS NULL OR p_reason IS NULL OR p_now IS NULL OR
     length(p_reason) NOT BETWEEN 3 AND 200 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.benefit_instances WHERE instance_id=p_instance FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state=p_target THEN
    RETURN jsonb_build_object('schema_version',1,'instance_id',p_instance,'state',entry.state,'replayed',true); END IF;
  SELECT true INTO allowed FROM private_isg.benefit_state_edges WHERE from_state=entry.state AND to_state=p_target;
  IF NOT coalesce(allowed,false) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='BENEFIT_STATE_INVALID'; END IF;
  -- Activation carries a clock and belongs to activate_gift alone.
  IF p_target='active' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='BENEFIT_STATE_INVALID'; END IF;
  UPDATE private_isg.benefit_instances SET state=p_target,reason=p_reason,version=version+1,updated_at=p_now
    WHERE instance_id=p_instance;
  RETURN jsonb_build_object('schema_version',1,'instance_id',p_instance,'state',p_target,'replayed',false);
END $$;
-- Sponsor access on the server clock. It never resets a quota period and it is
-- not a store trial; a second device activating the same gift changes nothing.
CREATE FUNCTION private_isg.activate_gift(p_instance uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.benefit_instances; def_row private_isg.benefit_definitions; ends_at timestamptz;
BEGIN
  PERFORM private_isg.billing_gate(true);
  IF p_instance IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.benefit_instances WHERE instance_id=p_instance FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO def_row FROM private_isg.benefit_definitions WHERE definition_id=entry.definition_id;
  IF def_row.benefit_kind<>'gift_access' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='BENEFIT_STATE_INVALID'; END IF;
  IF entry.state='active' THEN
    RETURN jsonb_build_object('schema_version',1,'instance_id',p_instance,'state','active',
      'expires_at',entry.expires_at,'activated_at',entry.activated_at,'replayed',true,'quota_reset',false); END IF;
  IF entry.state<>'available' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='BENEFIT_STATE_INVALID'; END IF;
  ends_at:=p_now+make_interval(hours=>def_row.duration_hours);
  UPDATE private_isg.benefit_instances SET state='active',activated_at=p_now,expires_at=ends_at,
    version=version+1,updated_at=p_now WHERE instance_id=p_instance;
  RETURN jsonb_build_object('schema_version',1,'instance_id',p_instance,'state','active','activated_at',p_now,
    'expires_at',ends_at,'duration_hours',def_row.duration_hours,'replayed',false,
    'quota_reset',false,'is_store_trial',false,'funding_source',def_row.funding_source,
    'duration_approved',def_row.content_approved);
END $$;
-- The prices are the store's own observed numbers. If the offer is not actually
-- cheaper for this user, the quote is written down as rejected, never issued.
CREATE FUNCTION private_isg.issue_discount_quote(p_instance uuid,p_mapping uuid,p_currency text,p_current bigint,
  p_offer bigint,p_observed timestamptz,p_ttl_seconds integer,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.benefit_instances; def_row private_isg.benefit_definitions;
  mapping_row private_isg.store_offer_mappings; better boolean; created uuid;
BEGIN
  PERFORM private_isg.billing_gate(true);
  IF p_instance IS NULL OR p_mapping IS NULL OR p_currency IS NULL OR p_current IS NULL OR p_offer IS NULL OR
     p_observed IS NULL OR p_now IS NULL OR p_ttl_seconds IS NULL OR p_ttl_seconds NOT BETWEEN 60 AND 86400 OR
     p_current<0 OR p_offer<0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.benefit_instances WHERE instance_id=p_instance FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO def_row FROM private_isg.benefit_definitions WHERE definition_id=entry.definition_id;
  SELECT * INTO mapping_row FROM private_isg.store_offer_mappings WHERE mapping_id=p_mapping;
  IF NOT FOUND OR mapping_row.definition_id<>entry.definition_id THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF def_row.benefit_kind<>'discount_coupon' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='BENEFIT_STATE_INVALID'; END IF;
  IF entry.state<>'available' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='BENEFIT_STATE_INVALID'; END IF;
  better:=p_offer<p_current;
  INSERT INTO private_isg.discount_quotes(instance_id,mapping_id,owner_id,currency,current_price_micros,
      offer_price_micros,price_observed_at,advantage,state,rejection_code,expires_at,created_at)
    VALUES(p_instance,p_mapping,entry.owner_id,p_currency,p_current,p_offer,p_observed,better,
      CASE WHEN better THEN 'issued' ELSE 'rejected' END,CASE WHEN better THEN NULL ELSE 'NO_ADVANTAGE' END,
      p_now+make_interval(secs=>p_ttl_seconds),p_now) RETURNING quote_id INTO created;
  IF NOT better THEN
    RETURN jsonb_build_object('schema_version',1,'quote_id',created,'state','rejected','advantage',false,
      'rejection_code','NO_ADVANTAGE','current_price_micros',p_current,'offer_price_micros',p_offer,
      'price_authority','store'); END IF;
  PERFORM private_isg.advance_benefit(p_instance,'reserved','a server quote was issued',p_now);
  RETURN jsonb_build_object('schema_version',1,'quote_id',created,'state','issued','advantage',true,
    'currency',p_currency,'current_price_micros',p_current,'offer_price_micros',p_offer,
    'price_authority','store','eligibility_authority','server','percent_approved',mapping_row.limit_approved,
    'signature_material_stored',false);
END $$;
-- One live checkout per quote. A second attempt is refused, not queued.
CREATE FUNCTION private_isg.open_checkout_intent(p_quote uuid,p_installation uuid,p_timeout_seconds integer,
  p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE quote_row private_isg.discount_quotes; live uuid; created uuid;
BEGIN
  PERFORM private_isg.billing_gate(true);
  IF p_quote IS NULL OR p_installation IS NULL OR p_now IS NULL OR p_timeout_seconds IS NULL OR
     p_timeout_seconds NOT BETWEEN 30 AND 3600 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO quote_row FROM private_isg.discount_quotes WHERE quote_id=p_quote FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF quote_row.state<>'issued' OR NOT quote_row.advantage THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='BENEFIT_STATE_INVALID'; END IF;
  IF quote_row.expires_at<=p_now THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='QUOTE_EXPIRED'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('isg-checkout:'||p_quote::text,0));
  SELECT intent_id INTO live FROM private_isg.checkout_intents WHERE quote_id=p_quote AND state='awaiting_store';
  IF live IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='INTENT_ALREADY_OPEN'; END IF;
  INSERT INTO private_isg.checkout_intents(quote_id,installation_id,opened_at,timeout_at)
    VALUES(p_quote,p_installation,p_now,p_now+make_interval(secs=>p_timeout_seconds)) RETURNING intent_id INTO created;
  PERFORM private_isg.advance_benefit(quote_row.instance_id,'awaiting_store','a checkout was opened',p_now);
  RETURN jsonb_build_object('schema_version',1,'intent_id',created,'state','awaiting_store',
    'timeout_at',p_now+make_interval(secs=>p_timeout_seconds),'second_checkout_possible',false);
END $$;
-- A timeout is uncertainty, not a cancellation; the benefit waits in review.
CREATE FUNCTION private_isg.resolve_checkout_timeout(p_intent uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE intent_row private_isg.checkout_intents; quote_row private_isg.discount_quotes;
BEGIN
  PERFORM private_isg.billing_gate(true);
  IF p_intent IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO intent_row FROM private_isg.checkout_intents WHERE intent_id=p_intent FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF intent_row.state='review' THEN
    RETURN jsonb_build_object('schema_version',1,'intent_id',p_intent,'state','review','replayed',true); END IF;
  IF intent_row.state<>'awaiting_store' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='BENEFIT_STATE_INVALID'; END IF;
  IF intent_row.timeout_at>p_now THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  UPDATE private_isg.checkout_intents SET state='review',closed_at=p_now WHERE intent_id=p_intent;
  SELECT * INTO quote_row FROM private_isg.discount_quotes WHERE quote_id=intent_row.quote_id;
  PERFORM private_isg.advance_benefit(quote_row.instance_id,'review','the checkout outcome is uncertain',p_now);
  RETURN jsonb_build_object('schema_version',1,'intent_id',p_intent,'state','review',
    'benefit_returned',false,'second_checkout_possible',false,'replayed',false);
END $$;
-- The payment identity is read from store evidence, never from the caller, and
-- one discounted billing period can be settled exactly once by exactly one
-- benefit - family is deliberately absent from the uniqueness key.
CREATE FUNCTION private_isg.settle_benefit(p_intent uuid,p_evidence uuid,p_period daterange,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE intent_row private_isg.checkout_intents; quote_row private_isg.discount_quotes;
  entry private_isg.billing_lifecycle_evidence; instance_row private_isg.benefit_instances; taken uuid; created uuid;
BEGIN
  PERFORM private_isg.billing_gate(true);
  IF p_intent IS NULL OR p_evidence IS NULL OR p_period IS NULL OR p_now IS NULL OR isempty(p_period) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO intent_row FROM private_isg.checkout_intents WHERE intent_id=p_intent FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF intent_row.state='settled' THEN
    SELECT settlement_id INTO created FROM private_isg.benefit_settlements WHERE intent_id=p_intent;
    RETURN jsonb_build_object('schema_version',1,'settlement_id',created,'state','consumed','replayed',true); END IF;
  IF intent_row.state NOT IN ('awaiting_store','review') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='BENEFIT_STATE_INVALID'; END IF;
  SELECT * INTO quote_row FROM private_isg.discount_quotes WHERE quote_id=intent_row.quote_id;
  SELECT * INTO instance_row FROM private_isg.benefit_instances WHERE instance_id=quote_row.instance_id FOR UPDATE;
  SELECT * INTO entry FROM private_isg.billing_lifecycle_evidence WHERE evidence_id=p_evidence;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.owner_id<>instance_row.owner_id THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.event_kind NOT IN ('purchase','renewal') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='NO_PAYMENT_EVIDENCE'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('isg-settlement:'||entry.store||':'||entry.environment||':'||entry.purchase_ref,0));
  SELECT settlement_id INTO taken FROM private_isg.benefit_settlements
    WHERE environment=entry.environment AND store=entry.store AND purchase_ref=entry.purchase_ref
      AND billing_period=p_period;
  IF taken IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SETTLEMENT_CONFLICT'; END IF;
  IF instance_row.state='awaiting_store' THEN
    PERFORM private_isg.advance_benefit(instance_row.instance_id,'scheduled','the store accepted the discounted purchase',p_now); END IF;
  PERFORM private_isg.advance_benefit(instance_row.instance_id,'consumed','the discounted payment is proven',p_now);
  UPDATE private_isg.checkout_intents SET state='settled',closed_at=p_now WHERE intent_id=p_intent;
  UPDATE private_isg.discount_quotes SET state='consumed' WHERE quote_id=quote_row.quote_id;
  INSERT INTO private_isg.benefit_settlements(instance_id,intent_id,evidence_id,environment,store,purchase_ref,
      billing_period,settled_at)
    VALUES(instance_row.instance_id,p_intent,p_evidence,entry.environment,entry.store,entry.purchase_ref,p_period,p_now)
    RETURNING settlement_id INTO created;
  RETURN jsonb_build_object('schema_version',1,'settlement_id',created,'state','consumed','replayed',false,
    'environment',entry.environment,'store',entry.store,'purchase_ref',entry.purchase_ref,
    'family_in_key',false,'access_authority','legacy');
END $$;
CREATE FUNCTION private_isg.adjust_settlement(p_settlement uuid,p_kind text,p_reason text,p_evidence jsonb,
  p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.benefit_settlements;
BEGIN
  PERFORM private_isg.billing_gate(true);
  IF p_settlement IS NULL OR p_kind IS NULL OR p_reason IS NULL OR p_now IS NULL OR p_evidence IS NULL OR
     jsonb_typeof(p_evidence)<>'object' OR octet_length(p_evidence::text)>4096 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.benefit_settlements WHERE settlement_id=p_settlement FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state='adjusted' THEN
    RETURN jsonb_build_object('schema_version',1,'settlement_id',p_settlement,'state','adjusted','replayed',true); END IF;
  UPDATE private_isg.benefit_settlements SET state='adjusted' WHERE settlement_id=p_settlement;
  INSERT INTO private_isg.settlement_adjustments(settlement_id,adjustment_kind,reason,evidence,adjusted_at)
    VALUES(p_settlement,p_kind,p_reason,p_evidence,p_now);
  PERFORM private_isg.advance_benefit(entry.instance_id,'adjusted',p_reason,p_now);
  -- The period stays taken: an adjusted payment does not free it for a new claim.
  RETURN jsonb_build_object('schema_version',1,'settlement_id',p_settlement,'state','adjusted','replayed',false,
    'period_released',false);
END $$;
CREATE FUNCTION private_isg.reconcile_billing(p_for date,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE seen bigint; reviewed bigint; held bigint; open_intents bigint; created uuid;
BEGIN
  PERFORM private_isg.billing_gate(true);
  IF p_for IS NULL OR p_now IS NULL OR NOT isfinite(p_for) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT count(*) INTO seen FROM private_isg.billing_lifecycle_evidence
    WHERE (observed_at AT TIME ZONE 'UTC')::date=p_for;
  SELECT count(*) INTO reviewed FROM private_isg.billing_lifecycle_projection WHERE needs_review;
  SELECT count(*) INTO held FROM private_isg.benefit_instances WHERE state='review';
  SELECT count(*) INTO open_intents FROM private_isg.checkout_intents WHERE state='awaiting_store' AND timeout_at<=p_now;
  INSERT INTO private_isg.billing_reconciliation_jobs(ran_for,evidence_seen,projections_reviewed,benefits_in_review,
      settlements_open,detail,ran_at)
    VALUES(p_for,seen,reviewed,held,open_intents,jsonb_build_object('access_authority','legacy'),p_now)
    ON CONFLICT(ran_for) DO UPDATE SET evidence_seen=EXCLUDED.evidence_seen,
      projections_reviewed=EXCLUDED.projections_reviewed,benefits_in_review=EXCLUDED.benefits_in_review,
      settlements_open=EXCLUDED.settlements_open,ran_at=EXCLUDED.ran_at
    RETURNING job_id INTO created;
  RETURN jsonb_build_object('schema_version',1,'job_id',created,'evidence_seen',seen,
    'projections_reviewed',reviewed,'benefits_in_review',held,'timed_out_checkouts',open_intents);
END $$;
REVOKE ALL ON FUNCTION private_isg.billing_gate(boolean),
  private_isg.record_billing_evidence(uuid,text,text,text,text,text,text,timestamptz,bigint,text,jsonb,timestamptz),
  private_isg.project_billing_lifecycle(uuid,boolean,timestamptz,timestamptz),
  private_isg.effective_billing_access(uuid,text,timestamptz),
  private_isg.grant_benefit(uuid,text,text,text,timestamptz),
  private_isg.advance_benefit(uuid,text,text,timestamptz),
  private_isg.activate_gift(uuid,timestamptz),
  private_isg.issue_discount_quote(uuid,uuid,text,bigint,bigint,timestamptz,integer,timestamptz),
  private_isg.open_checkout_intent(uuid,uuid,integer,timestamptz),
  private_isg.resolve_checkout_timeout(uuid,timestamptz),
  private_isg.settle_benefit(uuid,uuid,daterange,timestamptz),
  private_isg.adjust_settlement(uuid,text,text,jsonb,timestamptz),
  private_isg.reconcile_billing(date,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
