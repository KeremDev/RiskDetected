-- Synthetic stand-ins for the tables and helpers the home feed reads. Column
-- sets are the subset the feed uses; the helpers mirror the scope rules of the
-- real ones (personal owner, organization assignment, pilot gate).
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE ROLE service_role;
CREATE SCHEMA private_isg;

CREATE TABLE public.profiles (id uuid PRIMARY KEY, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.companies (
  id uuid PRIMARY KEY, user_id uuid NOT NULL, name text NOT NULL, is_archived boolean NOT NULL DEFAULT false,
  workspace_id uuid, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.analyses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL, company_id uuid, kind text NOT NULL,
  status text NOT NULL, completed_at timestamptz, created_at timestamptz NOT NULL DEFAULT now());

CREATE TABLE private_isg.workspace_memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), workspace_id uuid NOT NULL, user_id uuid NOT NULL,
  role text NOT NULL, status text NOT NULL DEFAULT 'active', created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE private_isg.test_assignments (company_id uuid, user_id uuid);
CREATE TABLE private_isg.workspace_analyses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), workspace_id uuid, company_id uuid, kind text, status text,
  created_by_user_id uuid, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE private_isg.employees (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), company_id uuid, is_archived boolean NOT NULL DEFAULT false,
  registered_at timestamptz NOT NULL DEFAULT now(), created_by_user_id uuid);
CREATE TABLE private_isg.workplaces (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), company_id uuid, name text, is_archived boolean NOT NULL DEFAULT false);
CREATE TABLE private_isg.pilot_training_sessions (
  id uuid PRIMARY KEY, owner_id uuid, held_on date, workspace_id uuid, created_by_user_id uuid, deleted_at timestamptz);
CREATE TABLE private_isg.pilot_training_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), company_id uuid, owner_id uuid, session_id uuid, state text,
  starts_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), created_by_user_id uuid);
CREATE TABLE private_isg.pilot_training_participants (
  training_id uuid, company_id uuid, employee_id uuid, attended boolean NOT NULL DEFAULT false);
CREATE TABLE private_isg.nonconformities (
  nonconformity_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), company_id uuid, owner_id uuid, workplace_id uuid,
  state text, record_kind text, title text, severity text, version bigint NOT NULL DEFAULT 1,
  opened_on date NOT NULL DEFAULT current_date, due_on date, source_kind text, source_ref text,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), created_by_user_id uuid);
CREATE TABLE private_isg.nonconformity_details (nonconformity_id uuid PRIMARY KEY, risk_band text);
CREATE TABLE private_isg.risk_assessments (assessment_id uuid PRIMARY KEY, company_id uuid, workplace_id uuid);
CREATE TABLE private_isg.risk_assessment_versions (
  assessment_id uuid, version integer, state text, finalized_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(), created_by_user_id uuid);
CREATE TABLE private_isg.checklist_runs (
  run_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), company_id uuid, owner_id uuid, workspace_id uuid,
  state text, area_label text, equipment_label text,
  submitted_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz, created_by_user_id uuid);
CREATE TABLE private_isg.equipment_items (
  equipment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), company_id uuid, created_at timestamptz NOT NULL DEFAULT now(),
  created_by_user_id uuid);
CREATE TABLE private_isg.equipment_inspections (
  inspection_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), equipment_id uuid, created_at timestamptz NOT NULL DEFAULT now(),
  created_by_user_id uuid);
CREATE TABLE private_isg.emergency_plan_versions (
  company_id uuid, is_deleted boolean NOT NULL DEFAULT false, created_at timestamptz NOT NULL DEFAULT now(), created_by_user_id uuid);
CREATE TABLE private_isg.drill_records (
  drill_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), company_id uuid, is_deleted boolean NOT NULL DEFAULT false,
  state text, planned_on date, updated_at timestamptz NOT NULL DEFAULT now(), created_by_user_id uuid);
CREATE TABLE private_isg.ppe_handovers (
  company_id uuid, is_deleted boolean NOT NULL DEFAULT false, created_at timestamptz NOT NULL DEFAULT now(), created_by_user_id uuid);
CREATE TABLE private_isg.document_obligation_records (company_id uuid, recorded_by uuid, recorded_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE private_isg.rollout (feature text PRIMARY KEY, read_enabled boolean, write_enabled boolean NOT NULL DEFAULT true);
CREATE TABLE private_isg.module_registry (module text PRIMARY KEY, read_enabled boolean, write_enabled boolean NOT NULL DEFAULT true);
CREATE TABLE private_isg.education_controls (key text PRIMARY KEY, enabled boolean);
INSERT INTO private_isg.rollout(feature, read_enabled) VALUES ('nonconformity', true), ('risk', true), ('document_tracking', true), ('modules', true), ('personnel', true);
INSERT INTO private_isg.module_registry(module, read_enabled) VALUES ('equipment', true), ('ppe', true), ('work_permit', true), ('emergency_plan', true), ('drill', true);
INSERT INTO private_isg.education_controls VALUES ('catalog_v1', true);
CREATE TABLE private_isg.test_followup (
  owner_id uuid, kind text, company_id uuid, company_name text, record_id uuid, title text, due_on date, window_days integer);

CREATE FUNCTION private_isg.active_actor() RETURNS uuid LANGUAGE sql AS $$
  SELECT nullif(current_setting('test.actor', true), '')::uuid $$;
CREATE FUNCTION private_isg.expert_workspace() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('test.workspace', true), '')::uuid $$;
-- test.read_only makes the session read-only: personal pilots get false, an
-- organization member is refused, as workspace_require_member refuses writes.
CREATE FUNCTION private_isg.p05_pilot_account_enabled(p_actor uuid, p_write boolean) RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
  IF p_actor IS NULL OR coalesce(nullif(current_setting('test.expired', true), '')::boolean, false) THEN RETURN false; END IF;
  IF p_write AND coalesce(nullif(current_setting('test.read_only', true), '')::boolean, false) THEN
    IF private_isg.expert_workspace() IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ACCESS_DENIED'; END IF;
    RETURN false;
  END IF;
  RETURN true;
END $$;
CREATE FUNCTION private_isg.p05_pilot_can_read(p_actor uuid, p_company uuid) RETURNS boolean LANGUAGE sql AS $$
  SELECT NOT EXISTS (SELECT 1 FROM public.companies c WHERE c.id = p_company AND c.name LIKE 'Grant revoked%') $$;
CREATE FUNCTION private_isg.workspace_require_member(p_workspace uuid, p_roles text[], p_write boolean)
RETURNS private_isg.workspace_memberships LANGUAGE plpgsql AS $$
DECLARE member private_isg.workspace_memberships;
BEGIN
  SELECT * INTO member FROM private_isg.workspace_memberships m
   WHERE m.workspace_id = p_workspace AND m.user_id = private_isg.active_actor() AND m.status = 'active' AND m.role = ANY(p_roles);
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ACCESS_DENIED'; END IF;
  RETURN member;
END $$;
CREATE FUNCTION private_isg.expert_company_visible(p_owner uuid, p_company uuid, p_actor uuid) RETURNS boolean LANGUAGE sql AS $$
  SELECT CASE WHEN private_isg.expert_workspace() IS NULL THEN p_owner = p_actor
    ELSE EXISTS (SELECT 1 FROM public.companies c WHERE c.id = p_company AND c.workspace_id = private_isg.expert_workspace())
     AND (EXISTS (SELECT 1 FROM private_isg.workspace_memberships m WHERE m.workspace_id = private_isg.expert_workspace()
                   AND m.user_id = p_actor AND m.role <> 'expert')
          OR EXISTS (SELECT 1 FROM private_isg.test_assignments a WHERE a.company_id = p_company AND a.user_id = p_actor)) END $$;
-- The training register's visibility rule (private_isg.expert_session_visible).
CREATE FUNCTION private_isg.expert_session_visible(p_owner uuid, p_session uuid, p_actor uuid) RETURNS boolean LANGUAGE sql AS $$
  SELECT CASE WHEN private_isg.expert_workspace() IS NULL THEN p_owner = p_actor
    ELSE EXISTS (SELECT 1 FROM private_isg.pilot_training_sessions s WHERE s.id = p_session AND s.workspace_id = private_isg.expert_workspace())
     AND EXISTS (SELECT 1 FROM private_isg.pilot_training_records r WHERE r.session_id = p_session)
     AND NOT EXISTS (SELECT 1 FROM private_isg.pilot_training_records r WHERE r.session_id = p_session
                      AND NOT private_isg.expert_company_visible(r.owner_id, r.company_id, p_actor)) END $$;
-- The nonconformity read gate: a readable company of the session's scope.
CREATE FUNCTION private_isg.require_nonconformity_company(p_company uuid, p_write boolean) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.companies c WHERE c.id = p_company
                  AND private_isg.expert_company_visible(c.user_id, c.id, private_isg.active_actor())) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'ACCESS_DENIED';
  END IF;
  RETURN private_isg.active_actor();
END $$;
CREATE FUNCTION private_isg.pilot_followup_rows(p_actor uuid, p_company uuid)
RETURNS TABLE(kind text, company_id uuid, company_name text, record_id uuid, title text, due_on date, window_days integer)
LANGUAGE sql STABLE AS $$
  SELECT f.kind, f.company_id, f.company_name, f.record_id, f.title, f.due_on, f.window_days
    FROM private_isg.test_followup f JOIN public.companies c ON c.id = f.company_id
   WHERE private_isg.expert_company_visible(c.user_id, c.id, p_actor) AND NOT c.is_archived
     AND (p_company IS NULL OR f.company_id = p_company) $$;

-- A stand-in for the organization RPC with the allowlist shape the migration
-- edits and the same generic argument binding (jsonb_to_record) as the real one.
CREATE FUNCTION private_isg.expert_rpc(p_workspace uuid, p_function text, p_arguments jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE result jsonb; previous text := current_setting('test.workspace', true);
  target oid; names text[]; declarations text; arguments text;
BEGIN
  IF NOT p_function = ANY(ARRAY['isg_pilot_followup_v1','isg_pilot_followup_v2','isg_statistics_v1']) THEN
    RAISE EXCEPTION 'EXPERT_OPERATION_NOT_READY';
  END IF;
  PERFORM set_config('test.workspace', p_workspace::text, true);
  SELECT p.oid, p.proargnames INTO STRICT target, names FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = p_function;
  SELECT string_agg(format('%I %s', names[t.ordinality], pg_catalog.format_type(t.type, NULL)), ',' ORDER BY t.ordinality),
         string_agg(format('%I => a.%I', names[t.ordinality], names[t.ordinality]), ',' ORDER BY t.ordinality)
    INTO declarations, arguments FROM pg_catalog.pg_proc p, LATERAL unnest(p.proargtypes::oid[]) WITH ORDINALITY t(type, ordinality)
   WHERE p.oid = target AND p_arguments ? names[t.ordinality];
  IF arguments IS NULL THEN
    EXECUTE format('SELECT public.%I()', p_function) INTO result;
  ELSE
    EXECUTE format('SELECT public.%I(%s) FROM jsonb_to_record($1) AS a(%s)', p_function, arguments, declarations)
      INTO result USING p_arguments;
  END IF;
  PERFORM set_config('test.workspace', coalesce(previous, ''), true);
  RETURN jsonb_build_object('_expert_workspace_id', p_workspace, 'payload', result);
END $$;
