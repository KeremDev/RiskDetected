-- P05 relational/backfill candidate. Synthetic schema only, NOT a production migration.
-- The runner refuses live/existing databases and creates an isolated disposable container.
BEGIN;
CREATE ROLE isg_workplace_owner NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE isg_workplace_reader NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE SCHEMA isg_workplace_fixture AUTHORIZATION isg_workplace_owner;
SET LOCAL ROLE isg_workplace_owner;
-- PUBLIC EXECUTE is a global default; a per-schema REVOKE cannot subtract it.
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
CREATE TABLE isg_workplace_fixture.legacy_companies (
  id uuid PRIMARY KEY, owner_id uuid NOT NULL, name text NOT NULL,
  hazard_class text, address text, department text, is_archived boolean NOT NULL DEFAULT false,
  UNIQUE(id, owner_id)
);
CREATE TABLE isg_workplace_fixture.workplaces (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), company_id uuid NOT NULL, owner_id uuid NOT NULL,
  name text NOT NULL CHECK (length(btrim(name)) > 0), address text,
  hazard_class text CHECK (hazard_class IN ('low','medium','high')),
  jurisdiction text, needs_review boolean NOT NULL DEFAULT true,
  is_archived boolean NOT NULL DEFAULT false,
  legacy_company_id uuid UNIQUE,
  version bigint NOT NULL DEFAULT 1 CHECK (version > 0),
  UNIQUE(company_id, id),
  FOREIGN KEY(company_id, owner_id) REFERENCES isg_workplace_fixture.legacy_companies(id, owner_id),
  CHECK (legacy_company_id IS NULL OR legacy_company_id = company_id),
  CHECK (needs_review OR (hazard_class IS NOT NULL AND jurisdiction IS NOT NULL AND length(btrim(jurisdiction)) > 0))
);
-- A tiny referencing entity tests composite scope; this is NOT the full department domain.
CREATE TABLE isg_workplace_fixture.department_refs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), company_id uuid NOT NULL, workplace_id uuid NOT NULL,
  FOREIGN KEY(company_id, workplace_id) REFERENCES isg_workplace_fixture.workplaces(company_id, id)
);
CREATE TABLE isg_workplace_fixture.audit (
  workplace_id uuid PRIMARY KEY REFERENCES isg_workplace_fixture.workplaces(id),
  action text NOT NULL CHECK (action = 'legacy_default_initialized')
);
CREATE TABLE isg_workplace_fixture.outbox (
  workplace_id uuid PRIMARY KEY REFERENCES isg_workplace_fixture.workplaces(id),
  event_type text NOT NULL CHECK (event_type = 'workplace.initialized'),
  schema_version integer NOT NULL CHECK (schema_version = 1)
);
ALTER TABLE isg_workplace_fixture.legacy_companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE isg_workplace_fixture.workplaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE isg_workplace_fixture.department_refs ENABLE ROW LEVEL SECURITY;
ALTER TABLE isg_workplace_fixture.audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE isg_workplace_fixture.outbox ENABLE ROW LEVEL SECURITY;
GRANT USAGE ON SCHEMA isg_workplace_fixture TO isg_workplace_reader;
GRANT SELECT ON isg_workplace_fixture.workplaces TO isg_workplace_reader;
-- Test-only verified-sub stand-in; it does NOT verify a JWT or a live Auth session.
CREATE POLICY owned_read ON isg_workplace_fixture.workplaces FOR SELECT TO isg_workplace_reader
  USING (owner_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid);

-- Internal initializer, invoker-only and unavailable to client roles. Parent row lock
-- serializes backfill and old-client catch-up without a global lock or name-based merging.
CREATE FUNCTION isg_workplace_fixture.ensure_default(p_company uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE company isg_workplace_fixture.legacy_companies; result uuid;
BEGIN
  SELECT * INTO company FROM isg_workplace_fixture.legacy_companies WHERE id = p_company FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'COMPANY_NOT_FOUND'; END IF;
  SELECT id INTO result FROM isg_workplace_fixture.workplaces WHERE legacy_company_id = p_company;
  IF FOUND THEN RETURN result; END IF;
  INSERT INTO isg_workplace_fixture.workplaces(company_id, owner_id, name, address, hazard_class, is_archived, legacy_company_id)
    VALUES (company.id, company.owner_id, company.name, company.address,
      CASE WHEN company.hazard_class IN ('low','medium','high') THEN company.hazard_class ELSE NULL END,
      company.is_archived, company.id) RETURNING id INTO result;
  INSERT INTO isg_workplace_fixture.audit VALUES (result, 'legacy_default_initialized');
  INSERT INTO isg_workplace_fixture.outbox VALUES (result, 'workplace.initialized', 1);
  RETURN result;
END $$;
CREATE FUNCTION isg_workplace_fixture.inject_failure() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
  IF current_setting('isg_workplace_fixture.fail_at', true) = TG_TABLE_NAME THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'INJECTED_FAILURE';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER audit_fault BEFORE INSERT ON isg_workplace_fixture.audit FOR EACH ROW EXECUTE FUNCTION isg_workplace_fixture.inject_failure();
CREATE TRIGGER outbox_fault BEFORE INSERT ON isg_workplace_fixture.outbox FOR EACH ROW EXECUTE FUNCTION isg_workplace_fixture.inject_failure();
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA isg_workplace_fixture FROM PUBLIC;
COMMIT;
