-- P05 relational candidate; test-only, applied after workplace_fixture.sql.
-- No production migration/API, employment-law calculation or health data fields.
BEGIN;
CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA extensions;
GRANT USAGE ON SCHEMA extensions TO isg_workplace_owner;
SET LOCAL ROLE isg_workplace_owner;
SET LOCAL search_path = isg_workplace_fixture, extensions, pg_catalog;
CREATE TABLE isg_workplace_fixture.departments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), company_id uuid NOT NULL, owner_id uuid NOT NULL,
  workplace_id uuid NOT NULL, code text NOT NULL CHECK (code = btrim(code) AND code <> ''),
  name text NOT NULL CHECK (btrim(name) <> ''), is_archived boolean NOT NULL DEFAULT false,
  UNIQUE(company_id, workplace_id, code), UNIQUE(company_id, workplace_id, id),
  FOREIGN KEY(company_id, owner_id) REFERENCES isg_workplace_fixture.legacy_companies(id, owner_id),
  FOREIGN KEY(company_id, workplace_id) REFERENCES isg_workplace_fixture.workplaces(company_id, id)
);
CREATE TABLE isg_workplace_fixture.job_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), company_id uuid NOT NULL, owner_id uuid NOT NULL,
  code text NOT NULL CHECK (code = btrim(code) AND code <> ''),
  title text NOT NULL CHECK (btrim(title) <> ''), is_archived boolean NOT NULL DEFAULT false,
  UNIQUE(company_id, code), UNIQUE(company_id, id),
  FOREIGN KEY(company_id, owner_id) REFERENCES isg_workplace_fixture.legacy_companies(id, owner_id)
);
CREATE TABLE isg_workplace_fixture.employees (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), company_id uuid NOT NULL, owner_id uuid NOT NULL,
  employee_code text NOT NULL CHECK (employee_code = btrim(employee_code) AND employee_code <> ''),
  full_name text NOT NULL CHECK (btrim(full_name) <> ''),
  hired_on date NOT NULL CHECK (isfinite(hired_on)),
  employment_ends_before date CHECK (isfinite(employment_ends_before) AND employment_ends_before > hired_on),
  is_archived boolean NOT NULL DEFAULT false,
  UNIQUE(company_id, employee_code), UNIQUE(company_id, id),
  FOREIGN KEY(company_id, owner_id) REFERENCES isg_workplace_fixture.legacy_companies(id, owner_id)
);
CREATE TABLE isg_workplace_fixture.employee_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), company_id uuid NOT NULL, owner_id uuid NOT NULL,
  employee_id uuid NOT NULL, workplace_id uuid NOT NULL, department_id uuid NOT NULL, job_role_id uuid NOT NULL,
  kind text NOT NULL DEFAULT 'primary' CHECK (kind = 'primary'),
  starts_on date NOT NULL CHECK (isfinite(starts_on)),
  ends_before date CHECK (isfinite(ends_before) AND ends_before > starts_on),
  effective_dates daterange GENERATED ALWAYS AS (daterange(starts_on, ends_before, '[)')) STORED,
  department_name_snapshot text NOT NULL, job_title_snapshot text NOT NULL,
  FOREIGN KEY(company_id, owner_id) REFERENCES isg_workplace_fixture.legacy_companies(id, owner_id),
  FOREIGN KEY(company_id, employee_id) REFERENCES isg_workplace_fixture.employees(company_id, id),
  FOREIGN KEY(company_id, workplace_id, department_id) REFERENCES isg_workplace_fixture.departments(company_id, workplace_id, id),
  FOREIGN KEY(company_id, job_role_id) REFERENCES isg_workplace_fixture.job_roles(company_id, id),
  -- Global across the employee's workplaces, including historical intervals.
  CONSTRAINT one_primary_assignment EXCLUDE USING gist (company_id WITH =, employee_id WITH =, effective_dates WITH &&)
);
ALTER TABLE isg_workplace_fixture.departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE isg_workplace_fixture.job_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE isg_workplace_fixture.employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE isg_workplace_fixture.employee_assignments ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON isg_workplace_fixture.departments, isg_workplace_fixture.job_roles,
  isg_workplace_fixture.employees, isg_workplace_fixture.employee_assignments TO isg_workplace_reader;
CREATE POLICY owned_read ON isg_workplace_fixture.departments FOR SELECT TO isg_workplace_reader
  USING (owner_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid);
CREATE POLICY owned_read ON isg_workplace_fixture.job_roles FOR SELECT TO isg_workplace_reader
  USING (owner_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid);
CREATE POLICY owned_read ON isg_workplace_fixture.employees FOR SELECT TO isg_workplace_reader
  USING (owner_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid);
CREATE POLICY owned_read ON isg_workplace_fixture.employee_assignments FOR SELECT TO isg_workplace_reader
  USING (owner_id = nullif(current_setting('request.jwt.claim.sub', true), '')::uuid);

CREATE FUNCTION isg_workplace_fixture.assignment_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE employee isg_workplace_fixture.employees;
        department isg_workplace_fixture.departments; job isg_workplace_fixture.job_roles;
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM 1 FROM isg_workplace_fixture.legacy_companies WHERE id=NEW.company_id AND NOT is_archived FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='ASSIGNMENT_SCOPE_INVALID'; END IF;
  END IF;
  IF TG_OP = 'UPDATE' AND ROW(NEW.id,NEW.company_id,NEW.owner_id,NEW.employee_id,NEW.workplace_id,NEW.department_id,NEW.job_role_id,NEW.kind,NEW.starts_on,NEW.department_name_snapshot,NEW.job_title_snapshot)
    IS DISTINCT FROM ROW(OLD.id,OLD.company_id,OLD.owner_id,OLD.employee_id,OLD.workplace_id,OLD.department_id,OLD.job_role_id,OLD.kind,OLD.starts_on,OLD.department_name_snapshot,OLD.job_title_snapshot) THEN
    RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='ASSIGNMENT_IMMUTABLE';
  END IF;
  -- Closing/shortening is allowed. Reopening or extending a closed interval needs
  -- a future explicit correction workflow, not an unreviewed history rewrite.
  IF TG_OP = 'UPDATE' AND OLD.ends_before IS NOT NULL AND (NEW.ends_before IS NULL OR NEW.ends_before > OLD.ends_before) THEN
    RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='ASSIGNMENT_EXTENSION_REQUIRES_REVIEW';
  END IF;
  -- Synchronizes with employment-date edits and other assignment writes for this employee.
  SELECT * INTO employee FROM isg_workplace_fixture.employees WHERE company_id=NEW.company_id AND id=NEW.employee_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='ASSIGNMENT_SCOPE_INVALID'; END IF;
  IF NEW.starts_on < employee.hired_on OR
     (employee.employment_ends_before IS NOT NULL AND (NEW.ends_before IS NULL OR NEW.ends_before > employee.employment_ends_before)) THEN
    RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='EMPLOYMENT_INTERVAL_INVALID';
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF employee.is_archived THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='ASSIGNMENT_PARENT_ARCHIVED'; END IF;
    PERFORM 1 FROM isg_workplace_fixture.workplaces WHERE company_id=NEW.company_id AND id=NEW.workplace_id AND NOT is_archived FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='ASSIGNMENT_SCOPE_INVALID'; END IF;
    SELECT * INTO department FROM isg_workplace_fixture.departments WHERE company_id=NEW.company_id AND workplace_id=NEW.workplace_id AND id=NEW.department_id FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='ASSIGNMENT_SCOPE_INVALID'; END IF;
    SELECT * INTO job FROM isg_workplace_fixture.job_roles WHERE company_id=NEW.company_id AND id=NEW.job_role_id FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='ASSIGNMENT_SCOPE_INVALID'; END IF;
    IF department.is_archived OR job.is_archived THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='ASSIGNMENT_PARENT_ARCHIVED'; END IF;
    -- Caller-supplied labels are ignored; rename never rewrites historical snapshots.
    NEW.department_name_snapshot := department.name; NEW.job_title_snapshot := job.title;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER assignment_guard BEFORE INSERT OR UPDATE ON isg_workplace_fixture.employee_assignments
  FOR EACH ROW EXECUTE FUNCTION isg_workplace_fixture.assignment_guard();
CREATE FUNCTION isg_workplace_fixture.employment_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM isg_workplace_fixture.employee_assignments WHERE company_id=OLD.company_id AND employee_id=OLD.id
      AND (starts_on < NEW.hired_on OR (NEW.employment_ends_before IS NOT NULL AND (ends_before IS NULL OR ends_before > NEW.employment_ends_before)))) THEN
    RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='EMPLOYMENT_INTERVAL_INVALID';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER employment_guard BEFORE UPDATE OF hired_on,employment_ends_before ON isg_workplace_fixture.employees
  FOR EACH ROW EXECUTE FUNCTION isg_workplace_fixture.employment_guard();
REVOKE ALL ON FUNCTION isg_workplace_fixture.assignment_guard(), isg_workplace_fixture.employment_guard() FROM PUBLIC;
COMMIT;
