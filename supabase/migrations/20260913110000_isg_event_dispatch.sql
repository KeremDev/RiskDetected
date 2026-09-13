-- P01/D01 consumer backbone for the producers P05 already writes.
-- Additive; rollout defaults OFF; no client grant and no worker identity yet.
-- Legacy notification/analysis queues and their producers are untouched.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE private_isg.rollout DROP CONSTRAINT rollout_feature_check;
ALTER TABLE private_isg.rollout ADD CONSTRAINT rollout_feature_check
  CHECK(feature IN ('personnel','event_dispatch','quota_ledger'));
INSERT INTO private_isg.rollout(feature) VALUES('event_dispatch');

-- Producer ownership registry: a consumer that is not registered and enabled
-- cannot claim anything, and it only ever sees the event types it subscribed to.
CREATE TABLE private_isg.consumer_registry (
  consumer text PRIMARY KEY CHECK(consumer ~ '^[a-z][a-z0-9_]{2,60}_v[0-9]{1,3}$'),
  event_source text NOT NULL CHECK(event_source IN ('personnel','directory')),
  event_types text[] NOT NULL CHECK(array_length(event_types,1) BETWEEN 1 AND 32),
  owner_package text NOT NULL CHECK(owner_package ~ '^P[0-9]{2}$'),
  is_enabled boolean NOT NULL DEFAULT false,
  max_attempts integer NOT NULL DEFAULT 5 CHECK(max_attempts BETWEEN 1 AND 10),
  lease_seconds integer NOT NULL DEFAULT 30 CHECK(lease_seconds BETWEEN 5 AND 300),
  backoff_base_seconds integer NOT NULL DEFAULT 5 CHECK(backoff_base_seconds BETWEEN 1 AND 3600),
  created_at timestamptz NOT NULL DEFAULT now()
);
-- Per (event, consumer) delivery. At-least-once transport; the receipt below is
-- what makes a consumer's effect exactly-once.
CREATE TABLE private_isg.event_deliveries (
  event_id uuid NOT NULL,
  consumer text NOT NULL REFERENCES private_isg.consumer_registry(consumer) ON DELETE RESTRICT,
  event_source text NOT NULL CHECK(event_source IN ('personnel','directory')),
  event_type text NOT NULL CHECK(btrim(event_type)<>'' AND length(event_type)<=80),
  company_id uuid NOT NULL,
  aggregate_id uuid NOT NULL,
  aggregate_version bigint NOT NULL CHECK(aggregate_version BETWEEN 0 AND 9007199254740991),
  state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','processing','done','dead')),
  attempts integer NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 10),
  available_at timestamptz NOT NULL DEFAULT now(),
  lease_token uuid, lease_until timestamptz,
  last_error_code text CHECK(last_error_code IS NULL OR last_error_code ~ '^[A-Z][A-Z_]{2,39}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(event_id,consumer),
  UNIQUE(consumer,company_id,aggregate_id,aggregate_version),
  CHECK((state='processing')=(lease_token IS NOT NULL)),
  CHECK((state='processing')=(lease_until IS NOT NULL))
);
CREATE TABLE private_isg.consumer_receipts (
  event_id uuid NOT NULL, consumer text NOT NULL,
  processed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(event_id,consumer),
  FOREIGN KEY(event_id,consumer) REFERENCES private_isg.event_deliveries(event_id,consumer) ON DELETE CASCADE
);
-- A dead delivery is reviewable history, never a silently skipped event.
CREATE TABLE private_isg.dispatch_dead_letters (
  event_id uuid NOT NULL, consumer text NOT NULL,
  attempts integer NOT NULL, error_code text NOT NULL,
  failed_at timestamptz NOT NULL,
  replayed_at timestamptz, replay_reason text,
  PRIMARY KEY(event_id,consumer),
  CHECK((replayed_at IS NULL)=(replay_reason IS NULL)),
  FOREIGN KEY(event_id,consumer) REFERENCES private_isg.event_deliveries(event_id,consumer) ON DELETE CASCADE
);
CREATE TABLE private_isg.dispatch_reconciliations (
  ran_on date PRIMARY KEY CHECK(isfinite(ran_on)),
  report jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX dispatch_claimable_idx ON private_isg.event_deliveries(consumer,state,available_at,aggregate_version);
CREATE INDEX dispatch_aggregate_idx ON private_isg.event_deliveries(consumer,company_id,aggregate_id,aggregate_version);
CREATE INDEX dispatch_lease_idx ON private_isg.event_deliveries(consumer,state,lease_until);
ALTER TABLE private_isg.consumer_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.event_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.consumer_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.dispatch_dead_letters ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.dispatch_reconciliations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.dispatch_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM private_isg.rollout WHERE feature='event_dispatch' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $$;
-- One reader over both existing producers. Producers keep their own tables and
-- their own audit; this view adds no second write path.
CREATE FUNCTION private_isg.domain_events() RETURNS TABLE(
  event_id uuid,event_source text,event_type text,company_id uuid,aggregate_id uuid,aggregate_version bigint,created_at timestamptz)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT o.event_id,'personnel'::text,o.event_type,a.company_id,a.employee_id,a.version,o.created_at
    FROM private_isg.personnel_outbox o JOIN private_isg.personnel_audit a USING(event_id)
  UNION ALL
  SELECT o.event_id,'directory'::text,'directory.'||e.entity_kind||'.changed',e.company_id,e.entity_id,e.version,e.created_at
    FROM private_isg.directory_outbox o JOIN private_isg.directory_events e USING(event_id)
$$;
CREATE FUNCTION private_isg.dispatch_fanout(p_limit integer,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE created integer;
BEGIN
  PERFORM private_isg.dispatch_gate(true);
  IF p_limit IS NULL OR p_limit<1 OR p_limit>5000 OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  WITH candidate AS (
    SELECT e.event_id,c.consumer,e.event_source,e.event_type,e.company_id,e.aggregate_id,e.aggregate_version
      FROM private_isg.domain_events() e
      JOIN private_isg.consumer_registry c ON c.is_enabled AND c.event_source=e.event_source AND e.event_type=ANY(c.event_types)
     WHERE NOT EXISTS(SELECT 1 FROM private_isg.event_deliveries d WHERE d.event_id=e.event_id AND d.consumer=c.consumer)
     ORDER BY e.created_at,e.event_id LIMIT p_limit)
  INSERT INTO private_isg.event_deliveries(event_id,consumer,event_source,event_type,company_id,aggregate_id,aggregate_version,available_at,created_at,updated_at)
    SELECT event_id,consumer,event_source,event_type,company_id,aggregate_id,aggregate_version,p_now,p_now,p_now FROM candidate
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS created=ROW_COUNT;
  RETURN jsonb_build_object('schema_version',1,'created',created,
    'pending',(SELECT count(*) FROM private_isg.event_deliveries WHERE state='pending'));
END $$;
CREATE FUNCTION private_isg.claim_event(p_consumer text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE reg private_isg.consumer_registry; d private_isg.event_deliveries;
BEGIN
  PERFORM private_isg.dispatch_gate(true);
  IF p_consumer IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO reg FROM private_isg.consumer_registry WHERE consumer=p_consumer AND is_enabled FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  -- A crashed worker's lease expires. The attempt it already consumed is kept.
  UPDATE private_isg.event_deliveries SET state='pending',lease_token=NULL,lease_until=NULL,
    available_at=p_now,last_error_code='LEASE_EXPIRED',updated_at=p_now
    WHERE consumer=p_consumer AND state='processing' AND lease_until<=p_now AND attempts<reg.max_attempts;
  WITH expired AS (
    UPDATE private_isg.event_deliveries SET state='dead',lease_token=NULL,lease_until=NULL,
      last_error_code='LEASE_EXPIRED',updated_at=p_now
      WHERE consumer=p_consumer AND state='processing' AND lease_until<=p_now AND attempts>=reg.max_attempts
      RETURNING event_id,attempts)
  INSERT INTO private_isg.dispatch_dead_letters(event_id,consumer,attempts,error_code,failed_at)
    SELECT event_id,p_consumer,attempts,'LEASE_EXPIRED',p_now FROM expired
  ON CONFLICT(event_id,consumer) DO UPDATE SET attempts=excluded.attempts,error_code=excluded.error_code,
    failed_at=excluded.failed_at,replayed_at=NULL,replay_reason=NULL;
  -- Per aggregate the older version must finish first; a dead event deliberately
  -- holds its successors instead of letting a projection skip a version.
  SELECT * INTO d FROM private_isg.event_deliveries c
    WHERE c.consumer=p_consumer AND c.state='pending' AND c.available_at<=p_now AND c.attempts<reg.max_attempts
      AND NOT EXISTS(SELECT 1 FROM private_isg.event_deliveries prior WHERE prior.consumer=p_consumer
        AND prior.company_id=c.company_id AND prior.aggregate_id=c.aggregate_id
        AND prior.aggregate_version<c.aggregate_version AND prior.state<>'done')
    ORDER BY c.aggregate_version,c.event_id FOR UPDATE SKIP LOCKED LIMIT 1;
  IF NOT FOUND THEN RETURN NULL; END IF;
  UPDATE private_isg.event_deliveries SET state='processing',attempts=attempts+1,lease_token=gen_random_uuid(),
    lease_until=p_now+make_interval(secs=>reg.lease_seconds),updated_at=p_now
    WHERE event_id=d.event_id AND consumer=p_consumer RETURNING * INTO d;
  RETURN jsonb_build_object('schema_version',1,'event_id',d.event_id,'consumer',d.consumer,'lease_token',d.lease_token,
    'lease_until',d.lease_until,'attempts',d.attempts,'event_source',d.event_source,'event_type',d.event_type,
    'company_id',d.company_id,'aggregate_id',d.aggregate_id,'aggregate_version',d.aggregate_version);
END $$;
CREATE FUNCTION private_isg.complete_event(p_consumer text,p_event uuid,p_token uuid,p_now timestamptz) RETURNS boolean
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE d private_isg.event_deliveries;
BEGIN
  PERFORM private_isg.dispatch_gate(true);
  IF p_consumer IS NULL OR p_event IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO d FROM private_isg.event_deliveries WHERE event_id=p_event AND consumer=p_consumer FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEASE_LOST'; END IF;
  -- A lost acknowledgement replayed by the worker must not apply a second effect.
  IF d.state='done' AND EXISTS(SELECT 1 FROM private_isg.consumer_receipts WHERE event_id=p_event AND consumer=p_consumer) THEN
    RETURN false; END IF;
  IF p_token IS NULL OR d.state<>'processing' OR d.lease_token IS DISTINCT FROM p_token OR d.lease_until<=p_now THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEASE_LOST'; END IF;
  INSERT INTO private_isg.consumer_receipts(event_id,consumer,processed_at) VALUES(p_event,p_consumer,p_now);
  UPDATE private_isg.event_deliveries SET state='done',lease_token=NULL,lease_until=NULL,last_error_code=NULL,updated_at=p_now
    WHERE event_id=p_event AND consumer=p_consumer;
  RETURN true;
END $$;
CREATE FUNCTION private_isg.fail_event(p_consumer text,p_event uuid,p_token uuid,p_error text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE reg private_isg.consumer_registry; d private_isg.event_deliveries; wait integer; dead boolean;
BEGIN
  PERFORM private_isg.dispatch_gate(true);
  IF p_consumer IS NULL OR p_event IS NULL OR p_now IS NULL OR p_error IS NULL OR
     p_error NOT IN ('RETRYABLE_FAILURE','VALIDATION_ERROR','UNSUPPORTED_FORMAT','RULE_NEEDS_REVIEW','SCAN_PENDING') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO reg FROM private_isg.consumer_registry WHERE consumer=p_consumer FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO d FROM private_isg.event_deliveries WHERE event_id=p_event AND consumer=p_consumer FOR UPDATE;
  IF NOT FOUND OR p_token IS NULL OR d.state<>'processing' OR d.lease_token IS DISTINCT FROM p_token OR d.lease_until<=p_now THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEASE_LOST'; END IF;
  dead:=d.attempts>=reg.max_attempts;
  -- Deterministic exponential backoff with an hour ceiling; jitter belongs to the
  -- worker, not to this ledger.
  wait:=least(reg.backoff_base_seconds*(2^least(d.attempts-1,20))::bigint,3600)::integer;
  UPDATE private_isg.event_deliveries SET state=CASE WHEN dead THEN 'dead' ELSE 'pending' END,
    lease_token=NULL,lease_until=NULL,last_error_code=p_error,updated_at=p_now,
    available_at=CASE WHEN dead THEN available_at ELSE p_now+make_interval(secs=>wait) END
    WHERE event_id=p_event AND consumer=p_consumer RETURNING * INTO d;
  IF dead THEN
    INSERT INTO private_isg.dispatch_dead_letters(event_id,consumer,attempts,error_code,failed_at)
      VALUES(p_event,p_consumer,d.attempts,p_error,p_now)
    ON CONFLICT(event_id,consumer) DO UPDATE SET attempts=excluded.attempts,error_code=excluded.error_code,
      failed_at=excluded.failed_at,replayed_at=NULL,replay_reason=NULL;
  END IF;
  RETURN jsonb_build_object('schema_version',1,'event_id',p_event,'consumer',p_consumer,'state',d.state,
    'attempts',d.attempts,'retry_in_seconds',CASE WHEN dead THEN NULL ELSE wait END,'error_code',p_error);
END $$;
CREATE FUNCTION private_isg.replay_dead_event(p_consumer text,p_event uuid,p_reason text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE d private_isg.event_deliveries; reason text;
BEGIN
  PERFORM private_isg.dispatch_gate(true);
  IF p_consumer IS NULL OR p_event IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  reason:=private_isg.text_value(p_reason,200);
  SELECT * INTO d FROM private_isg.event_deliveries WHERE event_id=p_event AND consumer=p_consumer FOR UPDATE;
  -- Only a reviewed dead letter is replayed; nothing here auto-skips a version.
  IF NOT FOUND OR d.state<>'dead' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  UPDATE private_isg.dispatch_dead_letters SET replayed_at=p_now,replay_reason=reason
    WHERE event_id=p_event AND consumer=p_consumer;
  UPDATE private_isg.event_deliveries SET state='pending',attempts=0,available_at=p_now,last_error_code=NULL,updated_at=p_now
    WHERE event_id=p_event AND consumer=p_consumer RETURNING * INTO d;
  RETURN jsonb_build_object('schema_version',1,'event_id',p_event,'consumer',p_consumer,'state',d.state,'attempts',d.attempts);
END $$;
CREATE FUNCTION private_isg.reconcile_dispatch(p_on date,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE report jsonb;
BEGIN
  PERFORM private_isg.dispatch_gate(true);
  IF p_on IS NULL OR NOT isfinite(p_on) OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT jsonb_build_object('schema_version',1,'ran_on',p_on,
    'producer_events',(SELECT count(*) FROM private_isg.domain_events()),
    'subscribed_events',(SELECT count(*) FROM private_isg.domain_events() e JOIN private_isg.consumer_registry c
        ON c.is_enabled AND c.event_source=e.event_source AND e.event_type=ANY(c.event_types)),
    'deliveries',(SELECT count(*) FROM private_isg.event_deliveries),
    'undelivered',(SELECT count(*) FROM private_isg.domain_events() e JOIN private_isg.consumer_registry c
        ON c.is_enabled AND c.event_source=e.event_source AND e.event_type=ANY(c.event_types)
        WHERE NOT EXISTS(SELECT 1 FROM private_isg.event_deliveries d WHERE d.event_id=e.event_id AND d.consumer=c.consumer)),
    'receipts',(SELECT count(*) FROM private_isg.consumer_receipts),
    'done_without_receipt',(SELECT count(*) FROM private_isg.event_deliveries d WHERE d.state='done'
        AND NOT EXISTS(SELECT 1 FROM private_isg.consumer_receipts r WHERE r.event_id=d.event_id AND r.consumer=d.consumer)),
    'stale_leases',(SELECT count(*) FROM private_isg.event_deliveries WHERE state='processing' AND lease_until<=p_now),
    'open_dead_letters',(SELECT count(*) FROM private_isg.dispatch_dead_letters WHERE replayed_at IS NULL),
    'oldest_pending_age_seconds',(SELECT coalesce(max(extract(epoch FROM p_now-created_at))::bigint,0)
        FROM private_isg.event_deliveries WHERE state='pending'),
    'by_state',(SELECT coalesce(jsonb_object_agg(state,total),'{}'::jsonb) FROM
        (SELECT state,count(*) AS total FROM private_isg.event_deliveries GROUP BY state) s),
    'by_consumer',(SELECT coalesce(jsonb_object_agg(consumer,total),'{}'::jsonb) FROM
        (SELECT consumer,count(*) AS total FROM private_isg.event_deliveries GROUP BY consumer) c))
    INTO report;
  INSERT INTO private_isg.dispatch_reconciliations(ran_on,report,created_at) VALUES(p_on,report,p_now)
    ON CONFLICT(ran_on) DO UPDATE SET report=excluded.report,created_at=excluded.created_at;
  RETURN report;
END $$;
-- No grant: there is no worker identity yet. The consumer runtime and its role
-- binding are P06/P12 work; until then only the schema owner can run these.
-- Existing client RPC grants are left exactly as the P05 migrations set them.
REVOKE ALL ON FUNCTION private_isg.dispatch_gate(boolean),private_isg.domain_events(),
  private_isg.dispatch_fanout(integer,timestamptz),private_isg.claim_event(text,timestamptz),
  private_isg.complete_event(text,uuid,uuid,timestamptz),private_isg.fail_event(text,uuid,uuid,text,timestamptz),
  private_isg.replay_dead_event(text,uuid,text,timestamptz),private_isg.reconcile_dispatch(date,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
