-- P03/D03 shadow reservation ledger and measured legacy floors.
-- The legacy SQL helpers stay the only authority: nothing here is called by an
-- existing trigger, RLS policy or RPC, no limit number is baked in, and every
-- reservation row is stamped 'shadow' so a cutover needs its own migration.
BEGIN;
SET LOCAL lock_timeout='5s';
INSERT INTO private_isg.rollout(feature) VALUES('quota_ledger');

CREATE TABLE private_isg.quota_definitions (
  quota_kind text PRIMARY KEY CHECK(quota_kind IN ('company_slot','ai_analysis','report_export','storage_bytes')),
  period_kind text NOT NULL CHECK(period_kind IN ('lifetime','day','month','year')),
  unit text NOT NULL CHECK(unit IN ('count','bytes')),
  created_at timestamptz NOT NULL DEFAULT now()
);
-- Structural kinds only. Amounts, prices and plan limits stay commercial
-- decisions and are supplied per call until P03 publishes an approved catalog.
INSERT INTO private_isg.quota_definitions(quota_kind,period_kind,unit) VALUES
  ('company_slot','lifetime','count'),('ai_analysis','day','count'),
  ('report_export','month','count'),('storage_bytes','lifetime','bytes');
-- Measured, evidence-bearing protection of an already earned entitlement.
-- Unknown is a reviewable state, never silently zero and never silently paid.
CREATE TABLE private_isg.legacy_entitlement_floors (
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  capability text NOT NULL CHECK(capability IN ('company_slot','ai_analysis','report_export','storage_bytes')),
  is_unlimited boolean NOT NULL DEFAULT false,
  floor_value bigint CHECK(floor_value IS NULL OR floor_value BETWEEN 0 AND 1000000000),
  source text NOT NULL CHECK(source IN ('contract','plan','exception','measured_usage','unknown')),
  cutoff_on date CHECK(cutoff_on IS NULL OR isfinite(cutoff_on)),
  evidence_note text CHECK(evidence_note IS NULL OR length(evidence_note)<=500),
  needs_review boolean NOT NULL DEFAULT true,
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(owner_id,capability),
  CHECK(is_unlimited=(floor_value IS NULL)),
  CHECK(source<>'unknown' OR needs_review)
);
CREATE TABLE private_isg.quota_reservations (
  reservation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  company_id uuid,
  quota_kind text NOT NULL REFERENCES private_isg.quota_definitions(quota_kind),
  period_key text NOT NULL CHECK(period_key ~ '^(lifetime|[0-9]{4}(-[0-9]{2}){0,2})$'),
  amount bigint NOT NULL CHECK(amount BETWEEN 1 AND 1000000000),
  funding_source text NOT NULL CHECK(funding_source IN ('plan','floor','gift','promotion')),
  state text NOT NULL DEFAULT 'reserved' CHECK(state IN ('reserved','settled','released','expired')),
  authority text NOT NULL DEFAULT 'shadow' CHECK(authority='shadow'),
  operation_id uuid NOT NULL, mutation_id uuid NOT NULL, request_hash bytea NOT NULL,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(owner_id,mutation_id)
);
CREATE TABLE private_isg.quota_settlements (
  settlement_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id uuid NOT NULL UNIQUE REFERENCES private_isg.quota_reservations(reservation_id) ON DELETE CASCADE,
  owner_id uuid NOT NULL, quota_kind text NOT NULL, period_key text NOT NULL,
  amount bigint NOT NULL CHECK(amount>0), evidence jsonb NOT NULL,
  settled_at timestamptz NOT NULL DEFAULT now()
);
-- Shadow comparison only. A disagreement is recorded for review; the legacy
-- counter keeps deciding what the user may do.
CREATE TABLE private_isg.quota_shadow_observations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL, quota_kind text NOT NULL, period_key text NOT NULL,
  legacy_used bigint NOT NULL CHECK(legacy_used>=0), ledger_used bigint NOT NULL CHECK(ledger_used>=0),
  agreed boolean NOT NULL, detail jsonb NOT NULL, observed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX quota_reservation_window_idx ON private_isg.quota_reservations(owner_id,quota_kind,period_key,state);
CREATE INDEX quota_reservation_kind_idx ON private_isg.quota_reservations(quota_kind);
CREATE INDEX quota_reservation_expiry_idx ON private_isg.quota_reservations(state,expires_at);
CREATE INDEX quota_reservation_company_idx ON private_isg.quota_reservations(company_id);
CREATE INDEX quota_shadow_owner_idx ON private_isg.quota_shadow_observations(owner_id,quota_kind,period_key);
ALTER TABLE private_isg.quota_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.legacy_entitlement_floors ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.quota_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.quota_settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.quota_shadow_observations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.quota_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM private_isg.rollout WHERE feature='quota_ledger' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $$;
-- An explicit timezone is required for every dated period; no zone is invented.
CREATE FUNCTION private_isg.quota_period_key(p_kind text,p_at timestamptz,p_timezone text) RETURNS text
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE period text; at_local timestamp;
BEGIN
  SELECT period_kind INTO period FROM private_isg.quota_definitions WHERE quota_kind=p_kind;
  IF period IS NULL OR p_at IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF period='lifetime' THEN RETURN 'lifetime'; END IF;
  IF p_timezone IS NULL OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name=p_timezone) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  at_local:=p_at AT TIME ZONE p_timezone;
  RETURN CASE period WHEN 'day' THEN to_char(at_local,'YYYY-MM-DD') WHEN 'month' THEN to_char(at_local,'YYYY-MM') ELSE to_char(at_local,'YYYY') END;
END $$;
CREATE FUNCTION private_isg.quota_used(p_owner uuid,p_kind text,p_period text) RETURNS bigint
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT coalesce(sum(amount),0)::bigint FROM private_isg.quota_reservations
    WHERE owner_id=p_owner AND quota_kind=p_kind AND period_key=p_period AND state IN ('reserved','settled')
$$;
CREATE FUNCTION private_isg.expire_quota_reservations(p_now timestamptz) RETURNS integer
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE expired integer;
BEGIN
  PERFORM private_isg.quota_gate(true);
  IF p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  UPDATE private_isg.quota_reservations SET state='expired',updated_at=p_now
    WHERE state='reserved' AND expires_at<=p_now;
  GET DIAGNOSTICS expired=ROW_COUNT;
  RETURN expired;
END $$;
-- Limit and unlimited are inputs decided by the caller's own authority check.
-- This ledger counts; it never derives a paid right from a profile or a gift.
CREATE FUNCTION private_isg.reserve_quota(p_owner uuid,p_company uuid,p_kind text,p_period text,p_amount bigint,
  p_funding text,p_operation uuid,p_mutation uuid,p_limit bigint,p_unlimited boolean,p_ttl_seconds integer,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE prior private_isg.quota_reservations; fingerprint bytea; used bigint; reservation uuid;
BEGIN
  PERFORM private_isg.quota_gate(true);
  IF p_owner IS NULL OR p_kind IS NULL OR p_period IS NULL OR p_amount IS NULL OR p_amount<1 OR p_amount>1000000000 OR
     p_funding IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_unlimited IS NULL OR p_now IS NULL OR
     p_ttl_seconds IS NULL OR p_ttl_seconds NOT BETWEEN 10 AND 86400 OR
     (p_unlimited AND p_limit IS NOT NULL) OR (NOT p_unlimited AND (p_limit IS NULL OR p_limit<0 OR p_limit>1000000000)) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  -- The period key must have the shape this kind's period actually produces.
  PERFORM 1 FROM private_isg.quota_definitions WHERE quota_kind=p_kind AND
    p_period ~ CASE period_kind WHEN 'lifetime' THEN '^lifetime$' WHEN 'day' THEN '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      WHEN 'month' THEN '^[0-9]{4}-[0-9]{2}$' ELSE '^[0-9]{4}$' END;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_owner,p_company,p_kind,p_period,p_amount,p_funding,p_operation,p_limit,p_unlimited)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(p_owner::text||':isg-quota:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.quota_reservations WHERE owner_id=p_owner AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN jsonb_build_object('schema_version',1,'authority','shadow','reservation_id',prior.reservation_id,
      'state',prior.state,'amount',prior.amount,'replayed',true);
  END IF;
  -- Account+period serialization; the last free slot cannot be sold twice.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_owner::text||':isg-quota-window:'||p_kind||':'||p_period,0));
  UPDATE private_isg.quota_reservations SET state='expired',updated_at=p_now
    WHERE owner_id=p_owner AND quota_kind=p_kind AND period_key=p_period AND state='reserved' AND expires_at<=p_now;
  used:=private_isg.quota_used(p_owner,p_kind,p_period);
  IF NOT p_unlimited AND used+p_amount>p_limit THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CAPACITY_EXCEEDED'; END IF;
  INSERT INTO private_isg.quota_reservations(owner_id,company_id,quota_kind,period_key,amount,funding_source,
      operation_id,mutation_id,request_hash,expires_at,created_at,updated_at)
    VALUES(p_owner,p_company,p_kind,p_period,p_amount,p_funding,p_operation,p_mutation,fingerprint,
      p_now+make_interval(secs=>p_ttl_seconds),p_now,p_now) RETURNING reservation_id INTO reservation;
  RETURN jsonb_build_object('schema_version',1,'authority','shadow','reservation_id',reservation,'state','reserved',
    'amount',p_amount,'used_before',used,'used_after',used+p_amount,
    'limit',CASE WHEN p_unlimited THEN NULL ELSE p_limit END,'is_unlimited',p_unlimited,'replayed',false);
END $$;
CREATE FUNCTION private_isg.settle_quota(p_reservation uuid,p_evidence jsonb,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.quota_reservations;
BEGIN
  PERFORM private_isg.quota_gate(true);
  IF p_reservation IS NULL OR p_now IS NULL OR p_evidence IS NULL OR jsonb_typeof(p_evidence)<>'object' OR
     octet_length(p_evidence::text)>2048 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.quota_reservations WHERE reservation_id=p_reservation FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state='settled' THEN RETURN jsonb_build_object('schema_version',1,'reservation_id',p_reservation,'state','settled','replayed',true); END IF;
  IF entry.state<>'reserved' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  UPDATE private_isg.quota_reservations SET state='settled',updated_at=p_now WHERE reservation_id=p_reservation;
  INSERT INTO private_isg.quota_settlements(reservation_id,owner_id,quota_kind,period_key,amount,evidence,settled_at)
    VALUES(p_reservation,entry.owner_id,entry.quota_kind,entry.period_key,entry.amount,p_evidence,p_now);
  RETURN jsonb_build_object('schema_version',1,'reservation_id',p_reservation,'state','settled','replayed',false);
END $$;
CREATE FUNCTION private_isg.release_quota(p_reservation uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.quota_reservations;
BEGIN
  PERFORM private_isg.quota_gate(true);
  IF p_reservation IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.quota_reservations WHERE reservation_id=p_reservation FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state='released' THEN RETURN jsonb_build_object('schema_version',1,'reservation_id',p_reservation,'state','released','replayed',true); END IF;
  -- A settled consumption is never reopened by a release; that would be a refund.
  IF entry.state<>'reserved' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  UPDATE private_isg.quota_reservations SET state='released',updated_at=p_now WHERE reservation_id=p_reservation;
  RETURN jsonb_build_object('schema_version',1,'reservation_id',p_reservation,'state','released','replayed',false);
END $$;
CREATE FUNCTION private_isg.record_quota_shadow(p_owner uuid,p_kind text,p_period text,p_legacy bigint,p_detail jsonb,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE ledger bigint; agreed boolean;
BEGIN
  PERFORM private_isg.quota_gate(true);
  IF p_owner IS NULL OR p_kind IS NULL OR p_period IS NULL OR p_legacy IS NULL OR p_legacy<0 OR p_now IS NULL OR
     p_detail IS NULL OR jsonb_typeof(p_detail)<>'object' OR octet_length(p_detail::text)>2048 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  ledger:=private_isg.quota_used(p_owner,p_kind,p_period); agreed:=ledger=p_legacy;
  INSERT INTO private_isg.quota_shadow_observations(owner_id,quota_kind,period_key,legacy_used,ledger_used,agreed,detail,observed_at)
    VALUES(p_owner,p_kind,p_period,p_legacy,ledger,agreed,p_detail,p_now);
  RETURN jsonb_build_object('schema_version',1,'authority','legacy','legacy_used',p_legacy,'ledger_used',ledger,'agreed',agreed);
END $$;
-- Read-only protection record. It reports what was measured; it grants nothing.
CREATE FUNCTION private_isg.effective_floor(p_owner uuid,p_capability text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.legacy_entitlement_floors;
BEGIN
  PERFORM private_isg.quota_gate(false);
  IF p_owner IS NULL OR p_capability IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.legacy_entitlement_floors WHERE owner_id=p_owner AND capability=p_capability;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('schema_version',1,'capability',p_capability,'recorded',false,
      'is_unlimited',false,'floor_value',NULL,'needs_review',true,'grants_access',false); END IF;
  RETURN jsonb_build_object('schema_version',1,'capability',p_capability,'recorded',true,
    'is_unlimited',entry.is_unlimited,'floor_value',entry.floor_value,'source',entry.source,'cutoff_on',entry.cutoff_on,
    'needs_review',entry.needs_review,'grants_access',false);
END $$;
REVOKE ALL ON FUNCTION private_isg.quota_gate(boolean),private_isg.quota_period_key(text,timestamptz,text),
  private_isg.quota_used(uuid,text,text),private_isg.expire_quota_reservations(timestamptz),
  private_isg.reserve_quota(uuid,uuid,text,text,bigint,text,uuid,uuid,bigint,boolean,integer,timestamptz),
  private_isg.settle_quota(uuid,jsonb,timestamptz),private_isg.release_quota(uuid,timestamptz),
  private_isg.record_quota_shadow(uuid,text,text,bigint,jsonb,timestamptz),private_isg.effective_floor(uuid,text)
  FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
