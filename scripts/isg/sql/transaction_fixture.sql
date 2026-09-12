-- SYNTHETIC TEST PROTOTYPE ONLY. Not a Supabase migration or production API.
-- A fresh no-network container is required. No real auth, company or health data.
BEGIN;
CREATE ROLE isg_fixture_owner NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE isg_fixture_client NOLOGIN NOSUPERUSER NOBYPASSRLS;
GRANT isg_fixture_owner TO supabase_admin;
CREATE SCHEMA isg_fixture AUTHORIZATION isg_fixture_owner;
SET LOCAL ROLE isg_fixture_owner;
-- Function EXECUTE starts as a global PUBLIC default; a per-schema REVOKE cannot
-- remove that global grant. This isolated NOLOGIN owner has no other schemas.
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
CREATE TABLE isg_fixture.actors (id uuid PRIMARY KEY, active boolean NOT NULL DEFAULT true);
CREATE TABLE isg_fixture.companies (id uuid PRIMARY KEY, owner_id uuid NOT NULL REFERENCES isg_fixture.actors);
CREATE TABLE isg_fixture.counters (
  company_id uuid NOT NULL REFERENCES isg_fixture.companies, id uuid NOT NULL,
  value integer NOT NULL DEFAULT 0, version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  PRIMARY KEY (company_id, id)
);
CREATE TABLE isg_fixture.mutation_receipts (
  actor_id uuid NOT NULL REFERENCES isg_fixture.actors, mutation_id uuid NOT NULL,
  canonical_payload jsonb NOT NULL, response jsonb NOT NULL,
  PRIMARY KEY (actor_id, mutation_id)
);
CREATE TABLE isg_fixture.audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), actor_id uuid NOT NULL REFERENCES isg_fixture.actors,
  company_id uuid NOT NULL, aggregate_id uuid NOT NULL, version bigint NOT NULL,
  FOREIGN KEY (company_id, aggregate_id) REFERENCES isg_fixture.counters(company_id, id),
  UNIQUE (company_id, aggregate_id, version)
);
CREATE TABLE isg_fixture.outbox (
  event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), company_id uuid NOT NULL, aggregate_id uuid NOT NULL,
  aggregate_version bigint NOT NULL, type text NOT NULL CHECK (type = 'fixture.counter.changed'),
  schema_version integer NOT NULL CHECK (schema_version = 1), payload jsonb NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'done', 'dead')),
  lease_token uuid, lease_until timestamptz, attempts integer NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 3),
  FOREIGN KEY (company_id, aggregate_id) REFERENCES isg_fixture.counters(company_id, id),
  UNIQUE (company_id, aggregate_id, aggregate_version)
);
CREATE TABLE isg_fixture.consumer_receipts (
  event_id uuid NOT NULL REFERENCES isg_fixture.outbox, consumer text NOT NULL CHECK (consumer = 'fixture_projection_v1'),
  PRIMARY KEY (event_id, consumer)
);
CREATE TABLE isg_fixture.projections (
  company_id uuid NOT NULL, aggregate_id uuid NOT NULL, version bigint NOT NULL, value integer NOT NULL, applied_count integer NOT NULL,
  PRIMARY KEY (company_id, aggregate_id), FOREIGN KEY (company_id, aggregate_id) REFERENCES isg_fixture.counters(company_id, id)
);
-- Private tables, RLS as defense in depth; only owner functions write. No broad table grants.
ALTER TABLE isg_fixture.actors ENABLE ROW LEVEL SECURITY;
ALTER TABLE isg_fixture.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE isg_fixture.counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE isg_fixture.mutation_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE isg_fixture.audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE isg_fixture.outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE isg_fixture.consumer_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE isg_fixture.projections ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION isg_fixture.mutate(p_mutation uuid, p_company uuid, p_entity uuid, p_expected bigint, p_delta integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid; payload jsonb; receipt isg_fixture.mutation_receipts; entity isg_fixture.counters; result jsonb;
BEGIN
  -- Test adapter for verified JWT sub. This does NOT implement real session/JWT validation.
  actor := nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
  IF actor IS NULL OR NOT EXISTS (SELECT 1 FROM isg_fixture.actors WHERE id = actor AND active) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'AUTH_REQUIRED';
  END IF;
  PERFORM 1 FROM isg_fixture.companies WHERE id = p_company AND owner_id = actor FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ACCESS_DENIED'; END IF;
  IF p_mutation IS NULL OR p_entity IS NULL OR p_expected IS NULL OR p_expected < 0 OR p_delta IS NULL OR p_delta NOT BETWEEN -100 AND 100 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'VALIDATION_ERROR';
  END IF;
  payload := jsonb_build_object('schema_version', 1, 'company_id', p_company, 'entity_id', p_entity, 'expected_version', p_expected, 'delta', p_delta);
  -- Hash collisions only serialize unrelated keys; equality is exact canonical jsonb.
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text || ':' || p_mutation::text, 0));
  SELECT * INTO receipt FROM isg_fixture.mutation_receipts WHERE actor_id = actor AND mutation_id = p_mutation;
  IF FOUND THEN
    IF receipt.canonical_payload <> payload THEN RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'IDEMPOTENCY_CONFLICT'; END IF;
    RETURN receipt.response;
  END IF;
  SELECT * INTO entity FROM isg_fixture.counters WHERE company_id = p_company AND id = p_entity FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ACCESS_DENIED'; END IF;
  IF entity.version <> p_expected THEN RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'VERSION_CONFLICT'; END IF;
  UPDATE isg_fixture.counters SET value = value + p_delta, version = version + 1
    WHERE company_id = p_company AND id = p_entity RETURNING * INTO entity;
  result := jsonb_build_object('version', entity.version, 'value', entity.value);
  INSERT INTO isg_fixture.audit(actor_id, company_id, aggregate_id, version) VALUES (actor, p_company, p_entity, entity.version);
  INSERT INTO isg_fixture.outbox(company_id, aggregate_id, aggregate_version, type, schema_version, payload)
    VALUES (p_company, p_entity, entity.version, 'fixture.counter.changed', 1, result);
  INSERT INTO isg_fixture.mutation_receipts(actor_id, mutation_id, canonical_payload, response) VALUES (actor, p_mutation, payload, result);
  RETURN result;
END $$;
GRANT USAGE ON SCHEMA isg_fixture TO isg_fixture_client;
GRANT EXECUTE ON FUNCTION isg_fixture.mutate(uuid, uuid, uuid, bigint, integer) TO isg_fixture_client;

-- Internal worker prototype. p_now is a deterministic TEST clock, not a client-supplied production clock.
CREATE FUNCTION isg_fixture.claim(p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE event isg_fixture.outbox;
BEGIN
  IF p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'VALIDATION_ERROR'; END IF;
  UPDATE isg_fixture.outbox SET status = 'dead', lease_token = NULL, lease_until = NULL
    WHERE status = 'processing' AND lease_until <= p_now AND attempts >= 3;
  SELECT * INTO event FROM isg_fixture.outbox AS candidate
    WHERE (status = 'pending' OR (status = 'processing' AND lease_until <= p_now)) AND attempts < 3
      AND NOT EXISTS (SELECT 1 FROM isg_fixture.outbox AS prior WHERE prior.company_id = candidate.company_id
        AND prior.aggregate_id = candidate.aggregate_id AND prior.aggregate_version < candidate.aggregate_version AND prior.status <> 'done')
    ORDER BY aggregate_version, event_id FOR UPDATE SKIP LOCKED LIMIT 1;
  IF NOT FOUND THEN RETURN NULL; END IF;
  UPDATE isg_fixture.outbox SET status = 'processing', attempts = attempts + 1, lease_token = gen_random_uuid(), lease_until = p_now + interval '30 seconds'
    WHERE event_id = event.event_id RETURNING * INTO event;
  RETURN jsonb_build_object('event_id', event.event_id, 'lease_token', event.lease_token, 'attempts', event.attempts);
END $$;
CREATE FUNCTION isg_fixture.complete(p_event uuid, p_token uuid, p_now timestamptz) RETURNS boolean
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE event isg_fixture.outbox;
BEGIN
  IF p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'VALIDATION_ERROR'; END IF;
  SELECT * INTO event FROM isg_fixture.outbox WHERE event_id = p_event FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'LEASE_LOST'; END IF;
  IF event.status = 'done' AND EXISTS (SELECT 1 FROM isg_fixture.consumer_receipts WHERE event_id = p_event AND consumer = 'fixture_projection_v1') THEN RETURN false; END IF;
  IF p_token IS NULL OR event.status <> 'processing' OR event.lease_token IS DISTINCT FROM p_token OR event.lease_until <= p_now THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'LEASE_LOST';
  END IF;
  INSERT INTO isg_fixture.consumer_receipts VALUES (p_event, 'fixture_projection_v1');
  INSERT INTO isg_fixture.projections VALUES (event.company_id, event.aggregate_id, event.aggregate_version, (event.payload->>'value')::integer, 1)
    ON CONFLICT (company_id, aggregate_id) DO UPDATE SET version = excluded.version, value = excluded.value, applied_count = isg_fixture.projections.applied_count + 1;
  UPDATE isg_fixture.outbox SET status = 'done', lease_token = NULL, lease_until = NULL WHERE event_id = p_event;
  RETURN true;
END $$;

-- Test-only failure injection: a thrown error must roll back the entire mutation/consumer transaction.
CREATE FUNCTION isg_fixture.inject_failure() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
  IF current_setting('isg_fixture.fail_at', true) = TG_TABLE_NAME THEN RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'INJECTED_FAILURE'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER audit_fault BEFORE INSERT ON isg_fixture.audit FOR EACH ROW EXECUTE FUNCTION isg_fixture.inject_failure();
CREATE TRIGGER outbox_fault BEFORE INSERT ON isg_fixture.outbox FOR EACH ROW EXECUTE FUNCTION isg_fixture.inject_failure();
CREATE TRIGGER projection_fault BEFORE INSERT OR UPDATE ON isg_fixture.projections FOR EACH ROW EXECUTE FUNCTION isg_fixture.inject_failure();
COMMIT;
