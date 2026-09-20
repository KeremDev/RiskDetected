-- D1/D2 tenant-native advanced personnel and training domains.
-- NOT DEPLOYED; the existing personnel/training rollout switches remain OFF by default.
-- Personal owner-scoped tables and RPCs are not exposed or rewritten by this slice.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='35s';

ALTER TABLE private_isg.workspace_audit DROP CONSTRAINT workspace_audit_entity_type_check;
ALTER TABLE private_isg.workspace_audit ADD CONSTRAINT workspace_audit_entity_type_check CHECK(entity_type IN
  ('workspace','membership','invitation','company','assignment','seat','subscription','wallet','asset','handover',
   'workplace','department','employee','domain','training','risk','nonconformity','checklist','emergency_plan',
   'drill','appointment','ppe','equipment','katip_contract','annual_plan','board','work_permit','site_visit',
   'notebook_archive','file_entry','file_reference','analysis','export','notification','job_role','contractor',
   'contractor_engagement','personnel_assignment','curriculum','annual_training_plan','training_attempt','certificate'));
ALTER TABLE private_isg.workspace_outbox DROP CONSTRAINT workspace_outbox_aggregate_type_check;
ALTER TABLE private_isg.workspace_outbox ADD CONSTRAINT workspace_outbox_aggregate_type_check CHECK(aggregate_type IN
  ('workspace','membership','invitation','company','assignment','seat','subscription','wallet','asset','handover',
   'workplace','department','employee','domain','training','risk','nonconformity','checklist','emergency_plan',
   'drill','appointment','ppe','equipment','katip_contract','annual_plan','board','work_permit','site_visit',
   'notebook_archive','file_entry','file_reference','analysis','export','notification','job_role','contractor',
   'contractor_engagement','personnel_assignment','curriculum','annual_training_plan','training_attempt','certificate'));

CREATE TABLE private_isg.workspace_job_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  company_id uuid NOT NULL,
  code text NOT NULL CHECK(octet_length(code) BETWEEN 1 AND 80),
  name text NOT NULL CHECK(octet_length(name) BETWEEN 1 AND 200),
  description text NOT NULL DEFAULT '' CHECK(octet_length(description)<=1000),
  is_archived boolean NOT NULL DEFAULT false,
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  created_by_user_id uuid NOT NULL,
  updated_by_user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(workspace_id,company_id,id),
  UNIQUE(workspace_id,company_id,code),
  FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT
);

CREATE TABLE private_isg.workspace_contractor_organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  company_id uuid NOT NULL,
  name text NOT NULL CHECK(octet_length(name) BETWEEN 1 AND 240),
  relation_kind text NOT NULL CHECK(relation_kind IN ('subcontractor','contractor','supplier','other')),
  tax_identifier text NOT NULL DEFAULT '' CHECK(octet_length(tax_identifier)<=80),
  contact_name text NOT NULL DEFAULT '' CHECK(octet_length(contact_name)<=200),
  contact_value text NOT NULL DEFAULT '' CHECK(octet_length(contact_value)<=320),
  is_archived boolean NOT NULL DEFAULT false,
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  created_by_user_id uuid NOT NULL,
  updated_by_user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(workspace_id,company_id,id),
  FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT
);

CREATE TABLE private_isg.workspace_contractor_engagements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  company_id uuid NOT NULL,
  contractor_id uuid NOT NULL,
  workplace_id uuid NOT NULL,
  scope text NOT NULL CHECK(octet_length(scope) BETWEEN 1 AND 1000),
  starts_on date NOT NULL CHECK(isfinite(starts_on)),
  ends_before date CHECK(ends_before IS NULL OR isfinite(ends_before)),
  state text NOT NULL DEFAULT 'active' CHECK(state IN ('active','ended')),
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  created_by_user_id uuid NOT NULL,
  updated_by_user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(workspace_id,company_id,id),
  FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,company_id,contractor_id)
    REFERENCES private_isg.workspace_contractor_organizations(workspace_id,company_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,company_id,workplace_id)
    REFERENCES private_isg.workplaces(workspace_id,company_id,id) ON DELETE RESTRICT,
  CHECK(ends_before IS NULL OR starts_on<ends_before),
  CHECK((state='active' AND ends_before IS NULL) OR (state='ended' AND ends_before IS NOT NULL))
);

CREATE TABLE private_isg.workspace_personnel_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  company_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  department_id uuid,
  job_role_id uuid,
  contractor_engagement_id uuid,
  effective_from date NOT NULL CHECK(isfinite(effective_from)),
  effective_before date CHECK(effective_before IS NULL OR isfinite(effective_before)),
  employee_name_snapshot text NOT NULL CHECK(octet_length(employee_name_snapshot) BETWEEN 1 AND 200),
  department_name_snapshot text NOT NULL DEFAULT '' CHECK(octet_length(department_name_snapshot)<=200),
  job_role_name_snapshot text NOT NULL DEFAULT '' CHECK(octet_length(job_role_name_snapshot)<=200),
  employer_name_snapshot text NOT NULL CHECK(octet_length(employer_name_snapshot) BETWEEN 1 AND 240),
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  created_by_user_id uuid NOT NULL,
  updated_by_user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(workspace_id,company_id,id),
  FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,company_id,employee_id)
    REFERENCES private_isg.employees(workspace_id,company_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,company_id,department_id)
    REFERENCES private_isg.departments(workspace_id,company_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,company_id,job_role_id)
    REFERENCES private_isg.workspace_job_roles(workspace_id,company_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,company_id,contractor_engagement_id)
    REFERENCES private_isg.workspace_contractor_engagements(workspace_id,company_id,id) ON DELETE RESTRICT,
  CHECK(department_id IS NOT NULL OR job_role_id IS NOT NULL OR contractor_engagement_id IS NOT NULL),
  CHECK(effective_before IS NULL OR effective_from<effective_before)
);

CREATE INDEX workspace_job_roles_page ON private_isg.workspace_job_roles(workspace_id,company_id,is_archived,id);
CREATE INDEX workspace_contractors_page ON private_isg.workspace_contractor_organizations(workspace_id,company_id,is_archived,id);
CREATE INDEX workspace_engagements_page ON private_isg.workspace_contractor_engagements(workspace_id,company_id,state,id);
CREATE INDEX workspace_personnel_assignments_page ON private_isg.workspace_personnel_assignments(workspace_id,company_id,employee_id,effective_from,id);

ALTER TABLE private_isg.workspace_job_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_contractor_organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_contractor_engagements ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_personnel_assignments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.workspace_job_roles,private_isg.workspace_contractor_organizations,
  private_isg.workspace_contractor_engagements,private_isg.workspace_personnel_assignments
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.workspace_personnel_advanced_read(p_workspace uuid,p_company uuid,p_kind text,
  p_after uuid,p_limit integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE rows jsonb; next_id uuid;
BEGIN
  PERFORM private_isg.workspace_domain_gate('personnel',false);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,false);
  IF p_kind NOT IN ('job_roles','contractors','engagements','assignments') OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_kind='job_roles' THEN
    WITH visible AS (SELECT r.* FROM private_isg.workspace_job_roles r
      WHERE r.workspace_id=p_workspace AND r.company_id=p_company AND NOT r.is_archived
        AND (p_after IS NULL OR r.id>p_after) ORDER BY r.id LIMIT p_limit+1),
    page AS (SELECT * FROM visible ORDER BY id LIMIT p_limit)
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'kind','job_role','code',code,'name',name,
      'description',description,'is_archived',is_archived,'version',version) ORDER BY id),'[]'::jsonb),
      CASE WHEN (SELECT count(*) FROM visible)>p_limit THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END
      INTO rows,next_id FROM page;
  ELSIF p_kind='contractors' THEN
    WITH visible AS (SELECT c.* FROM private_isg.workspace_contractor_organizations c
      WHERE c.workspace_id=p_workspace AND c.company_id=p_company AND NOT c.is_archived
        AND (p_after IS NULL OR c.id>p_after) ORDER BY c.id LIMIT p_limit+1),
    page AS (SELECT * FROM visible ORDER BY id LIMIT p_limit)
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'kind','contractor','name',name,
      'relation_kind',relation_kind,'tax_identifier',tax_identifier,'contact_name',contact_name,
      'contact_value',contact_value,'is_archived',is_archived,'version',version) ORDER BY id),'[]'::jsonb),
      CASE WHEN (SELECT count(*) FROM visible)>p_limit THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END
      INTO rows,next_id FROM page;
  ELSIF p_kind='engagements' THEN
    WITH visible AS (SELECT e.*,c.name contractor_name,w.name workplace_name
      FROM private_isg.workspace_contractor_engagements e
      JOIN private_isg.workspace_contractor_organizations c ON c.workspace_id=e.workspace_id AND c.company_id=e.company_id AND c.id=e.contractor_id
      JOIN private_isg.workplaces w ON w.workspace_id=e.workspace_id AND w.company_id=e.company_id AND w.id=e.workplace_id
      WHERE e.workspace_id=p_workspace AND e.company_id=p_company AND (p_after IS NULL OR e.id>p_after)
      ORDER BY e.id LIMIT p_limit+1),page AS (SELECT * FROM visible ORDER BY id LIMIT p_limit)
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'kind','engagement','contractor_id',contractor_id,
      'contractor_name',contractor_name,'workplace_id',workplace_id,'workplace_name',workplace_name,
      'scope',scope,'starts_on',starts_on,'ends_before',ends_before,'state',state,'version',version) ORDER BY id),'[]'::jsonb),
      CASE WHEN (SELECT count(*) FROM visible)>p_limit THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END
      INTO rows,next_id FROM page;
  ELSE
    WITH visible AS (SELECT a.* FROM private_isg.workspace_personnel_assignments a
      WHERE a.workspace_id=p_workspace AND a.company_id=p_company AND (p_after IS NULL OR a.id>p_after)
      ORDER BY a.id LIMIT p_limit+1),page AS (SELECT * FROM visible ORDER BY id LIMIT p_limit)
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'kind','assignment','employee_id',employee_id,
      'employee_name',employee_name_snapshot,'department_id',department_id,'department_name',department_name_snapshot,
      'job_role_id',job_role_id,'job_role_name',job_role_name_snapshot,'contractor_engagement_id',contractor_engagement_id,
      'employer_name',employer_name_snapshot,'effective_from',effective_from,'effective_before',effective_before,
      'is_current',(effective_from<=CURRENT_DATE AND (effective_before IS NULL OR effective_before>CURRENT_DATE)),
      'version',version) ORDER BY id),'[]'::jsonb),
      CASE WHEN (SELECT count(*) FROM visible)>p_limit THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END
      INTO rows,next_id FROM page;
  END IF;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'kind',p_kind,'rows',rows,'next',next_id);
END $$;

CREATE TABLE private_isg.workspace_training_curricula (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  company_id uuid NOT NULL,
  series_id uuid NOT NULL,
  revision integer NOT NULL CHECK(revision>0),
  title text NOT NULL CHECK(octet_length(title) BETWEEN 1 AND 240),
  cycle text NOT NULL CHECK(cycle IN ('initial','periodic_repeat','onboarding','task_specific','other')),
  hazard_class text CHECK(hazard_class IS NULL OR hazard_class IN ('low','medium','high')),
  target_group text NOT NULL DEFAULT '' CHECK(octet_length(target_group)<=500),
  assessment_required boolean NOT NULL DEFAULT false,
  pass_score integer CHECK(pass_score IS NULL OR pass_score BETWEEN 0 AND 100),
  state text NOT NULL DEFAULT 'draft' CHECK(state IN ('draft','published','superseded','retired')),
  published_at timestamptz,
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  created_by_user_id uuid NOT NULL,
  updated_by_user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(workspace_id,company_id,id),
  UNIQUE(workspace_id,company_id,series_id,revision),
  FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT,
  CHECK((assessment_required AND pass_score IS NOT NULL) OR (NOT assessment_required AND pass_score IS NULL)),
  CHECK((state='published' AND published_at IS NOT NULL) OR (state<>'published'))
);
CREATE UNIQUE INDEX workspace_training_curriculum_one_draft
  ON private_isg.workspace_training_curricula(workspace_id,company_id,series_id) WHERE state='draft';
CREATE UNIQUE INDEX workspace_training_curriculum_one_published
  ON private_isg.workspace_training_curricula(workspace_id,company_id,series_id) WHERE state='published';

CREATE TABLE private_isg.workspace_training_curriculum_topics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  company_id uuid NOT NULL,
  curriculum_id uuid NOT NULL,
  position integer NOT NULL CHECK(position BETWEEN 1 AND 999),
  title text NOT NULL CHECK(octet_length(title) BETWEEN 1 AND 240),
  description text NOT NULL DEFAULT '' CHECK(octet_length(description)<=2000),
  duration_minutes integer NOT NULL CHECK(duration_minutes BETWEEN 1 AND 100000),
  created_by_user_id uuid NOT NULL,
  updated_by_user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(workspace_id,company_id,id),
  UNIQUE(workspace_id,company_id,curriculum_id,position),
  FOREIGN KEY(workspace_id,company_id,curriculum_id)
    REFERENCES private_isg.workspace_training_curricula(workspace_id,company_id,id) ON DELETE RESTRICT
);

CREATE TABLE private_isg.workspace_annual_training_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  company_id uuid NOT NULL,
  workplace_id uuid NOT NULL,
  plan_year integer NOT NULL CHECK(plan_year BETWEEN 2000 AND 2200),
  title text NOT NULL CHECK(octet_length(title) BETWEEN 1 AND 240),
  state text NOT NULL DEFAULT 'draft' CHECK(state IN ('draft','active','closed')),
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  created_by_user_id uuid NOT NULL,
  updated_by_user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(workspace_id,company_id,id),
  UNIQUE(workspace_id,company_id,workplace_id,plan_year),
  FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,company_id,workplace_id)
    REFERENCES private_isg.workplaces(workspace_id,company_id,id) ON DELETE RESTRICT
);

CREATE TABLE private_isg.workspace_annual_training_plan_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  company_id uuid NOT NULL,
  plan_id uuid NOT NULL,
  curriculum_id uuid,
  title text NOT NULL CHECK(octet_length(title) BETWEEN 1 AND 240),
  target_group text NOT NULL DEFAULT '' CHECK(octet_length(target_group)<=500),
  planned_on date NOT NULL CHECK(isfinite(planned_on)),
  duration_minutes integer NOT NULL CHECK(duration_minutes BETWEEN 1 AND 100000),
  responsible text NOT NULL DEFAULT '' CHECK(octet_length(responsible)<=240),
  realised_training_id uuid,
  state text NOT NULL DEFAULT 'planned' CHECK(state IN ('planned','realised','cancelled')),
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  created_by_user_id uuid NOT NULL,
  updated_by_user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(workspace_id,company_id,id),
  FOREIGN KEY(workspace_id,company_id,plan_id)
    REFERENCES private_isg.workspace_annual_training_plans(workspace_id,company_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,company_id,curriculum_id)
    REFERENCES private_isg.workspace_training_curricula(workspace_id,company_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,company_id,realised_training_id)
    REFERENCES private_isg.pilot_training_records(workspace_id,company_id,id) ON DELETE RESTRICT,
  CHECK((state='realised' AND realised_training_id IS NOT NULL) OR
        (state IN ('planned','cancelled') AND realised_training_id IS NULL))
);

CREATE TABLE private_isg.workspace_training_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  company_id uuid NOT NULL,
  training_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  attempt_no integer NOT NULL CHECK(attempt_no BETWEEN 1 AND 3),
  score integer NOT NULL CHECK(score BETWEEN 0 AND 100),
  passed boolean NOT NULL,
  taken_on date NOT NULL CHECK(isfinite(taken_on)),
  notes text NOT NULL DEFAULT '' CHECK(octet_length(notes)<=1000),
  created_by_user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(workspace_id,company_id,id),
  UNIQUE(workspace_id,company_id,training_id,employee_id,attempt_no),
  FOREIGN KEY(workspace_id,company_id,training_id)
    REFERENCES private_isg.pilot_training_records(workspace_id,company_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,company_id,employee_id)
    REFERENCES private_isg.employees(workspace_id,company_id,id) ON DELETE RESTRICT
);

CREATE TABLE private_isg.workspace_training_certificates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  company_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  training_id uuid,
  file_entry_id uuid,
  certificate_kind text NOT NULL CHECK(certificate_kind IN ('internal_training','external_training','qualification')),
  certificate_no text NOT NULL CHECK(octet_length(certificate_no) BETWEEN 1 AND 120),
  issuer text NOT NULL CHECK(octet_length(issuer) BETWEEN 1 AND 240),
  issued_on date NOT NULL CHECK(isfinite(issued_on)),
  expires_on date CHECK(expires_on IS NULL OR isfinite(expires_on)),
  verification_state text NOT NULL DEFAULT 'self_declared' CHECK(verification_state IN ('self_declared','verified','rejected','revoked')),
  employee_name_snapshot text NOT NULL CHECK(octet_length(employee_name_snapshot) BETWEEN 1 AND 200),
  department_name_snapshot text NOT NULL DEFAULT '' CHECK(octet_length(department_name_snapshot)<=200),
  job_role_name_snapshot text NOT NULL DEFAULT '' CHECK(octet_length(job_role_name_snapshot)<=200),
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  created_by_user_id uuid NOT NULL,
  updated_by_user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(workspace_id,company_id,id),
  UNIQUE(workspace_id,company_id,certificate_no),
  FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,company_id,employee_id)
    REFERENCES private_isg.employees(workspace_id,company_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,company_id,training_id)
    REFERENCES private_isg.pilot_training_records(workspace_id,company_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,company_id,file_entry_id)
    REFERENCES private_isg.workspace_file_entries(workspace_id,company_id,id) ON DELETE RESTRICT,
  CHECK(expires_on IS NULL OR issued_on<expires_on)
);

ALTER TABLE private_isg.pilot_training_records ADD COLUMN workspace_curriculum_id uuid;
ALTER TABLE private_isg.pilot_training_records ADD COLUMN curriculum_snapshot jsonb;
ALTER TABLE private_isg.pilot_training_records ADD CONSTRAINT pilot_training_workspace_curriculum_fk
  FOREIGN KEY(workspace_id,company_id,workspace_curriculum_id)
  REFERENCES private_isg.workspace_training_curricula(workspace_id,company_id,id) ON DELETE RESTRICT;

CREATE OR REPLACE FUNCTION private_isg.workspace_training_row(p_workspace uuid,p_company uuid,p_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT jsonb_build_object(
    'training_id',r.id,'session_id',r.session_id,'company_id',r.company_id,'title',r.title,
    'trainer',r.trainer,'method',s.method,'location',r.location,'notes',r.notes,
    'starts_at',r.starts_at,'duration_minutes',r.duration_minutes,'valid_until',r.valid_until,
    'state',r.state,'version',r.version,'completed_at',r.completed_at,
    'workspace_curriculum_id',r.workspace_curriculum_id,'curriculum_snapshot',r.curriculum_snapshot,
    'created_by_user_id',r.created_by_user_id,
    'participants',coalesce((SELECT jsonb_agg(jsonb_build_object(
      'employee_id',p.employee_id,'name',p.employee_name,'attended',p.attended)
      ORDER BY p.employee_name,p.employee_id)
      FROM private_isg.pilot_training_participants p
      WHERE p.workspace_id=p_workspace AND p.company_id=p_company AND p.training_id=r.id),'[]'::jsonb))
  FROM private_isg.pilot_training_records r
  JOIN private_isg.pilot_training_sessions s ON s.workspace_id=r.workspace_id AND s.id=r.session_id
  WHERE r.workspace_id=p_workspace AND r.company_id=p_company AND r.id=p_id
$$;

CREATE INDEX workspace_curricula_page ON private_isg.workspace_training_curricula(workspace_id,company_id,state,id);
CREATE INDEX workspace_curriculum_topics_page ON private_isg.workspace_training_curriculum_topics(workspace_id,company_id,curriculum_id,position,id);
CREATE INDEX workspace_annual_training_page ON private_isg.workspace_annual_training_plans(workspace_id,company_id,plan_year,id);
CREATE INDEX workspace_annual_training_items_page ON private_isg.workspace_annual_training_plan_items(workspace_id,company_id,plan_id,state,id);
CREATE INDEX workspace_training_attempts_page ON private_isg.workspace_training_attempts(workspace_id,company_id,training_id,employee_id,id);
CREATE INDEX workspace_training_certificates_page ON private_isg.workspace_training_certificates(workspace_id,company_id,employee_id,id);

ALTER TABLE private_isg.workspace_training_curricula ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_training_curriculum_topics ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_annual_training_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_annual_training_plan_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_training_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_training_certificates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.workspace_training_curricula,private_isg.workspace_training_curriculum_topics,
  private_isg.workspace_annual_training_plans,private_isg.workspace_annual_training_plan_items,
  private_isg.workspace_training_attempts,private_isg.workspace_training_certificates
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.workspace_training_completion_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE curriculum private_isg.workspace_training_curricula;
BEGIN
  IF NEW.workspace_id IS NULL OR NEW.workspace_curriculum_id IS NULL OR NEW.state<>'completed'
    OR (TG_OP='UPDATE' AND OLD.state='completed') THEN RETURN NEW; END IF;
  SELECT * INTO curriculum FROM private_isg.workspace_training_curricula
    WHERE workspace_id=NEW.workspace_id AND company_id=NEW.company_id AND id=NEW.workspace_curriculum_id FOR SHARE;
  IF curriculum.id IS NULL OR curriculum.state<>'published' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PUBLISHED_CURRICULUM_REQUIRED'; END IF;
  IF curriculum.assessment_required AND EXISTS(
    SELECT 1 FROM private_isg.pilot_training_participants p
    WHERE p.workspace_id=NEW.workspace_id AND p.company_id=NEW.company_id AND p.training_id=NEW.id AND p.attended
      AND NOT EXISTS(SELECT 1 FROM private_isg.workspace_training_attempts a
        WHERE a.workspace_id=p.workspace_id AND a.company_id=p.company_id AND a.training_id=p.training_id
          AND a.employee_id=p.employee_id AND a.passed)) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PASSED_ASSESSMENT_REQUIRED'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER pilot_training_completion_guard_before
BEFORE UPDATE OF state ON private_isg.pilot_training_records
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_training_completion_guard();

CREATE FUNCTION private_isg.workspace_training_advanced_read(p_workspace uuid,p_company uuid,p_kind text,
  p_after uuid,p_limit integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE rows jsonb; next_id uuid;
BEGIN
  PERFORM private_isg.workspace_domain_gate('training',false);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,false);
  IF p_kind NOT IN ('curricula','annual_plans','annual_items','attempts','certificates') OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_kind='curricula' THEN
    WITH visible AS (SELECT c.* FROM private_isg.workspace_training_curricula c
      WHERE c.workspace_id=p_workspace AND c.company_id=p_company AND c.state<>'superseded'
        AND (p_after IS NULL OR c.id>p_after) ORDER BY c.id LIMIT p_limit+1),page AS (SELECT * FROM visible ORDER BY id LIMIT p_limit)
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'kind','curriculum','series_id',series_id,'revision',revision,
      'title',title,'cycle',cycle,'hazard_class',hazard_class,'target_group',target_group,
      'assessment_required',assessment_required,'pass_score',pass_score,'state',state,'version',version,
      'topic_count',(SELECT count(*) FROM private_isg.workspace_training_curriculum_topics t
        WHERE t.workspace_id=p_workspace AND t.company_id=p_company AND t.curriculum_id=page.id),
      'total_minutes',(SELECT coalesce(sum(t.duration_minutes),0) FROM private_isg.workspace_training_curriculum_topics t
        WHERE t.workspace_id=p_workspace AND t.company_id=p_company AND t.curriculum_id=page.id),
      'topics',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'position',t.position,'title',t.title,
        'description',t.description,'duration_minutes',t.duration_minutes) ORDER BY t.position,t.id),'[]'::jsonb)
        FROM private_isg.workspace_training_curriculum_topics t WHERE t.workspace_id=p_workspace
          AND t.company_id=p_company AND t.curriculum_id=page.id)) ORDER BY id),'[]'::jsonb),
      CASE WHEN (SELECT count(*) FROM visible)>p_limit THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END
      INTO rows,next_id FROM page;
  ELSIF p_kind='annual_plans' THEN
    WITH visible AS (SELECT p.*,w.name workplace_name FROM private_isg.workspace_annual_training_plans p
      JOIN private_isg.workplaces w ON w.workspace_id=p.workspace_id AND w.company_id=p.company_id AND w.id=p.workplace_id
      WHERE p.workspace_id=p_workspace AND p.company_id=p_company AND (p_after IS NULL OR p.id>p_after)
      ORDER BY p.id LIMIT p_limit+1),page AS (SELECT * FROM visible ORDER BY id LIMIT p_limit)
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'kind','annual_plan','workplace_id',workplace_id,
      'workplace_name',workplace_name,'plan_year',plan_year,'title',title,'state',state,'version',version,
      'planned_count',(SELECT count(*) FROM private_isg.workspace_annual_training_plan_items i
        WHERE i.workspace_id=p_workspace AND i.company_id=p_company AND i.plan_id=page.id AND i.state='planned'),
      'realised_count',(SELECT count(*) FROM private_isg.workspace_annual_training_plan_items i
        WHERE i.workspace_id=p_workspace AND i.company_id=p_company AND i.plan_id=page.id AND i.state='realised')) ORDER BY id),'[]'::jsonb),
      CASE WHEN (SELECT count(*) FROM visible)>p_limit THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END
      INTO rows,next_id FROM page;
  ELSIF p_kind='annual_items' THEN
    WITH visible AS (SELECT i.* FROM private_isg.workspace_annual_training_plan_items i
      WHERE i.workspace_id=p_workspace AND i.company_id=p_company AND (p_after IS NULL OR i.id>p_after)
      ORDER BY i.id LIMIT p_limit+1),page AS (SELECT * FROM visible ORDER BY id LIMIT p_limit)
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'kind','annual_item','plan_id',plan_id,
      'curriculum_id',curriculum_id,'title',title,'target_group',target_group,'planned_on',planned_on,
      'duration_minutes',duration_minutes,'responsible',responsible,'realised_training_id',realised_training_id,
      'state',state,'version',version) ORDER BY id),'[]'::jsonb),
      CASE WHEN (SELECT count(*) FROM visible)>p_limit THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END
      INTO rows,next_id FROM page;
  ELSIF p_kind='attempts' THEN
    WITH visible AS (SELECT a.*,e.full_name employee_name,r.title training_title FROM private_isg.workspace_training_attempts a
      JOIN private_isg.employees e ON e.workspace_id=a.workspace_id AND e.company_id=a.company_id AND e.id=a.employee_id
      JOIN private_isg.pilot_training_records r ON r.workspace_id=a.workspace_id AND r.company_id=a.company_id AND r.id=a.training_id
      WHERE a.workspace_id=p_workspace AND a.company_id=p_company AND (p_after IS NULL OR a.id>p_after)
      ORDER BY a.id LIMIT p_limit+1),page AS (SELECT * FROM visible ORDER BY id LIMIT p_limit)
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'kind','attempt','training_id',training_id,
      'training_title',training_title,'employee_id',employee_id,'employee_name',employee_name,
      'attempt_no',attempt_no,'score',score,'passed',passed,'taken_on',taken_on,'notes',notes) ORDER BY id),'[]'::jsonb),
      CASE WHEN (SELECT count(*) FROM visible)>p_limit THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END
      INTO rows,next_id FROM page;
  ELSE
    WITH visible AS (SELECT c.* FROM private_isg.workspace_training_certificates c
      WHERE c.workspace_id=p_workspace AND c.company_id=p_company AND (p_after IS NULL OR c.id>p_after)
      ORDER BY c.id LIMIT p_limit+1),page AS (SELECT * FROM visible ORDER BY id LIMIT p_limit)
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'kind','certificate','employee_id',employee_id,
      'employee_name',employee_name_snapshot,'training_id',training_id,'file_entry_id',file_entry_id,
      'certificate_kind',certificate_kind,'certificate_no',certificate_no,'issuer',issuer,
      'issued_on',issued_on,'expires_on',expires_on,'verification_state',verification_state,
      'department_name',department_name_snapshot,'job_role_name',job_role_name_snapshot,'version',version) ORDER BY id),'[]'::jsonb),
      CASE WHEN (SELECT count(*) FROM visible)>p_limit THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END
      INTO rows,next_id FROM page;
  END IF;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'kind',p_kind,'rows',rows,'next',next_id);
END $$;


CREATE FUNCTION private_isg.workspace_personnel_advanced_mutate(p_mutation uuid,p_workspace uuid,p_company uuid,
  p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); member private_isg.workspace_memberships; action text; target uuid;
  expected bigint; fingerprint bytea; replay jsonb; before_state jsonb; result jsonb; entity_type text;
  entity_id uuid; version_ bigint; clean_code text; clean_name text; clean_description text;
  clean_relation text; clean_tax text; clean_contact_name text; clean_contact_value text; clean_scope text;
  v_contractor_id uuid; v_workplace_id uuid; v_employee_id uuid; v_department_id uuid;
  v_job_role_id uuid; v_engagement_id uuid;
  starts date; ending date; employee_name text; department_name text:=''; role_name text:=''; employer_name text;
BEGIN
  PERFORM private_isg.workspace_domain_gate('personnel',true);
  member:=private_isg.workspace_require_company(p_workspace,p_company,true);
  IF p_mutation IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>32768
    OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN
      ('action','id','expected_version','code','name','description','relation_kind','tax_identifier','contact_name',
       'contact_value','contractor_id','workplace_id','scope','starts_on','ends_before','employee_id',
       'department_id','job_role_id','engagement_id','effective_from','effective_before')) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  action:=p_payload->>'action'; target:=(p_payload->>'id')::uuid;
  expected:=coalesce((p_payload->>'expected_version')::bigint,0);
  IF action NOT IN ('job_role_save','job_role_archive','contractor_save','contractor_archive',
      'engagement_create','engagement_end','assignment_create','assignment_end') OR expected<0 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF action IN ('job_role_save','contractor_save') AND target IS NULL AND expected<>0 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF action IN ('job_role_archive','contractor_archive','engagement_end','assignment_end') AND target IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF action IN ('engagement_create','assignment_create') AND (target IS NOT NULL OR expected<>0) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF member.role='expert' AND action NOT IN ('assignment_create','assignment_end') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_company,p_payload)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'personnel.advanced.'||action,fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;

  IF action LIKE 'job_role_%' THEN
    entity_type:='job_role';
    IF action='job_role_save' THEN
      clean_code:=private_isg.workspace_text(p_payload->>'code',80);
      clean_name:=private_isg.workspace_text(p_payload->>'name',200);
      clean_description:=normalize(btrim(coalesce(p_payload->>'description','')),NFC);
      IF octet_length(clean_description)>1000 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      IF target IS NULL THEN
        INSERT INTO private_isg.workspace_job_roles(workspace_id,company_id,code,name,description,created_by_user_id,updated_by_user_id)
          VALUES(p_workspace,p_company,clean_code,clean_name,clean_description,actor,actor)
          RETURNING id,version INTO entity_id,version_;
      ELSE
        SELECT to_jsonb(r) INTO before_state FROM private_isg.workspace_job_roles r
          WHERE workspace_id=p_workspace AND company_id=p_company AND id=target FOR UPDATE;
        IF before_state IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
        IF (before_state->>'version')::bigint<>expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
        UPDATE private_isg.workspace_job_roles SET code=clean_code,name=clean_name,description=clean_description,
          version=version+1,updated_by_user_id=actor,updated_at=clock_timestamp() WHERE id=target
          RETURNING id,version INTO entity_id,version_;
      END IF;
    ELSE
      SELECT to_jsonb(r) INTO before_state FROM private_isg.workspace_job_roles r
        WHERE workspace_id=p_workspace AND company_id=p_company AND id=target FOR UPDATE;
      IF before_state IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      IF (before_state->>'version')::bigint<>expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
      UPDATE private_isg.workspace_job_roles SET is_archived=true,version=version+1,updated_by_user_id=actor,
        updated_at=clock_timestamp() WHERE id=target RETURNING id,version INTO entity_id,version_;
    END IF;
  ELSIF action LIKE 'contractor_%' THEN
    entity_type:='contractor';
    IF action='contractor_save' THEN
      clean_name:=private_isg.workspace_text(p_payload->>'name',240);
      clean_relation:=p_payload->>'relation_kind';
      clean_tax:=normalize(btrim(coalesce(p_payload->>'tax_identifier','')),NFC);
      clean_contact_name:=normalize(btrim(coalesce(p_payload->>'contact_name','')),NFC);
      clean_contact_value:=normalize(btrim(coalesce(p_payload->>'contact_value','')),NFC);
      IF clean_relation NOT IN ('subcontractor','contractor','supplier','other') OR octet_length(clean_tax)>80
        OR octet_length(clean_contact_name)>200 OR octet_length(clean_contact_value)>320 THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      IF target IS NULL THEN
        INSERT INTO private_isg.workspace_contractor_organizations(workspace_id,company_id,name,relation_kind,
          tax_identifier,contact_name,contact_value,created_by_user_id,updated_by_user_id)
          VALUES(p_workspace,p_company,clean_name,clean_relation,clean_tax,clean_contact_name,clean_contact_value,actor,actor)
          RETURNING id,version INTO entity_id,version_;
      ELSE
        SELECT to_jsonb(c) INTO before_state FROM private_isg.workspace_contractor_organizations c
          WHERE workspace_id=p_workspace AND company_id=p_company AND id=target FOR UPDATE;
        IF before_state IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
        IF (before_state->>'version')::bigint<>expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
        UPDATE private_isg.workspace_contractor_organizations SET name=clean_name,relation_kind=clean_relation,
          tax_identifier=clean_tax,contact_name=clean_contact_name,contact_value=clean_contact_value,
          version=version+1,updated_by_user_id=actor,updated_at=clock_timestamp() WHERE id=target
          RETURNING id,version INTO entity_id,version_;
      END IF;
    ELSE
      SELECT to_jsonb(c) INTO before_state FROM private_isg.workspace_contractor_organizations c
        WHERE workspace_id=p_workspace AND company_id=p_company AND id=target FOR UPDATE;
      IF before_state IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      IF (before_state->>'version')::bigint<>expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
      IF EXISTS(SELECT 1 FROM private_isg.workspace_contractor_engagements e WHERE e.workspace_id=p_workspace
        AND e.company_id=p_company AND e.contractor_id=target AND e.state='active') THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACTIVE_ENGAGEMENT_EXISTS'; END IF;
      UPDATE private_isg.workspace_contractor_organizations SET is_archived=true,version=version+1,
        updated_by_user_id=actor,updated_at=clock_timestamp() WHERE id=target RETURNING id,version INTO entity_id,version_;
    END IF;
  ELSIF action LIKE 'engagement_%' THEN
    entity_type:='contractor_engagement';
    IF action='engagement_create' THEN
      v_contractor_id:=(p_payload->>'contractor_id')::uuid; v_workplace_id:=(p_payload->>'workplace_id')::uuid;
      starts:=(p_payload->>'starts_on')::date; ending:=(p_payload->>'ends_before')::date;
      clean_scope:=private_isg.workspace_text(p_payload->>'scope',1000);
      IF starts IS NULL OR NOT isfinite(starts) OR ending IS NOT NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      IF NOT EXISTS(SELECT 1 FROM private_isg.workspace_contractor_organizations WHERE workspace_id=p_workspace
          AND company_id=p_company AND id=v_contractor_id AND NOT is_archived)
        OR NOT EXISTS(SELECT 1 FROM private_isg.workplaces WHERE workspace_id=p_workspace
          AND company_id=p_company AND id=v_workplace_id AND NOT is_archived) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      INSERT INTO private_isg.workspace_contractor_engagements(workspace_id,company_id,contractor_id,workplace_id,
        scope,starts_on,created_by_user_id,updated_by_user_id)
        VALUES(p_workspace,p_company,v_contractor_id,v_workplace_id,clean_scope,starts,actor,actor)
        RETURNING id,version INTO entity_id,version_;
    ELSE
      ending:=(p_payload->>'ends_before')::date;
      SELECT to_jsonb(e) INTO before_state FROM private_isg.workspace_contractor_engagements e
        WHERE workspace_id=p_workspace AND company_id=p_company AND id=target FOR UPDATE;
      IF before_state IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      IF (before_state->>'version')::bigint<>expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
      IF ending IS NULL OR NOT isfinite(ending) OR ending<=(before_state->>'starts_on')::date THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      IF EXISTS(SELECT 1 FROM private_isg.workspace_personnel_assignments a WHERE a.workspace_id=p_workspace
        AND a.company_id=p_company AND a.contractor_engagement_id=target AND
        (a.effective_before IS NULL OR a.effective_before>ending)) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACTIVE_ASSIGNMENT_EXISTS'; END IF;
      UPDATE private_isg.workspace_contractor_engagements SET state='ended',ends_before=ending,version=version+1,
        updated_by_user_id=actor,updated_at=clock_timestamp() WHERE id=target RETURNING id,version INTO entity_id,version_;
    END IF;
  ELSE
    entity_type:='personnel_assignment';
    IF action='assignment_create' THEN
      v_employee_id:=(p_payload->>'employee_id')::uuid; v_department_id:=(p_payload->>'department_id')::uuid;
      v_job_role_id:=(p_payload->>'job_role_id')::uuid; v_engagement_id:=(p_payload->>'engagement_id')::uuid;
      starts:=(p_payload->>'effective_from')::date; ending:=(p_payload->>'effective_before')::date;
      IF starts IS NULL OR NOT isfinite(starts) OR (ending IS NOT NULL AND (NOT isfinite(ending) OR starts>=ending)) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      SELECT full_name INTO employee_name FROM private_isg.employees WHERE workspace_id=p_workspace
        AND company_id=p_company AND id=v_employee_id AND NOT is_archived FOR UPDATE;
      IF employee_name IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      IF v_department_id IS NOT NULL THEN SELECT name INTO department_name FROM private_isg.departments
        WHERE workspace_id=p_workspace AND company_id=p_company AND id=v_department_id AND NOT is_archived; END IF;
      IF v_department_id IS NOT NULL AND department_name IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      IF v_job_role_id IS NOT NULL THEN SELECT name INTO role_name FROM private_isg.workspace_job_roles
        WHERE workspace_id=p_workspace AND company_id=p_company AND id=v_job_role_id AND NOT is_archived; END IF;
      IF v_job_role_id IS NOT NULL AND role_name IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      IF v_engagement_id IS NULL THEN
        SELECT name INTO employer_name FROM private_isg.workspace_companies WHERE workspace_id=p_workspace AND id=p_company;
      ELSE
        SELECT c.name INTO employer_name FROM private_isg.workspace_contractor_engagements e
          JOIN private_isg.workspace_contractor_organizations c ON c.workspace_id=e.workspace_id AND c.company_id=e.company_id AND c.id=e.contractor_id
          WHERE e.workspace_id=p_workspace AND e.company_id=p_company AND e.id=v_engagement_id AND e.state='active'
            AND e.starts_on<=starts AND (e.ends_before IS NULL OR (ending IS NOT NULL AND e.ends_before>=ending));
      END IF;
      IF employer_name IS NULL OR (v_department_id IS NULL AND v_job_role_id IS NULL AND v_engagement_id IS NULL) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      PERFORM pg_advisory_xact_lock(hashtextextended(
        'workspace-personnel-assignment:'||p_workspace::text||':'||p_company::text||':'||v_employee_id::text,0));
      PERFORM 1 FROM private_isg.workspace_personnel_assignments a WHERE a.workspace_id=p_workspace
        AND a.company_id=p_company AND a.employee_id=v_employee_id
        AND daterange(a.effective_from,a.effective_before,'[)') && daterange(starts,ending,'[)') FOR UPDATE;
      IF FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSIGNMENT_OVERLAP'; END IF;
      INSERT INTO private_isg.workspace_personnel_assignments(workspace_id,company_id,employee_id,department_id,
        job_role_id,contractor_engagement_id,effective_from,effective_before,employee_name_snapshot,
        department_name_snapshot,job_role_name_snapshot,employer_name_snapshot,created_by_user_id,updated_by_user_id)
        VALUES(p_workspace,p_company,v_employee_id,v_department_id,v_job_role_id,v_engagement_id,starts,ending,employee_name,
          coalesce(department_name,''),coalesce(role_name,''),employer_name,actor,actor)
        RETURNING id,version INTO entity_id,version_;
    ELSE
      ending:=(p_payload->>'effective_before')::date;
      SELECT to_jsonb(a) INTO before_state FROM private_isg.workspace_personnel_assignments a
        WHERE workspace_id=p_workspace AND company_id=p_company AND id=target FOR UPDATE;
      IF before_state IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      IF (before_state->>'version')::bigint<>expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
      IF before_state->>'effective_before' IS NOT NULL OR ending IS NULL OR NOT isfinite(ending)
        OR ending<=(before_state->>'effective_from')::date THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      UPDATE private_isg.workspace_personnel_assignments SET effective_before=ending,version=version+1,
        updated_by_user_id=actor,updated_at=clock_timestamp() WHERE id=target RETURNING id,version INTO entity_id,version_;
    END IF;
  END IF;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'action',action,'entity_id',entity_id,'version',version_);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'personnel.advanced.'||action,fingerprint,p_workspace,
    entity_type,entity_id,version_,before_state,result,NULL,result);
END $$;

CREATE FUNCTION private_isg.workspace_training_advanced_mutate(p_mutation uuid,p_workspace uuid,p_company uuid,
  p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); action text; target uuid; expected bigint;
  fingerprint bytea; replay jsonb; before_state jsonb; result jsonb; entity_type text; entity_id uuid; version_ bigint;
  curriculum private_isg.workspace_training_curricula; source_curriculum private_isg.workspace_training_curricula;
  plan private_isg.workspace_annual_training_plans; plan_item private_isg.workspace_annual_training_plan_items;
  training private_isg.pilot_training_records; certificate private_isg.workspace_training_certificates;
  v_topic_id uuid; series uuid; v_workplace_id uuid; v_employee_id uuid; v_file_entry_id uuid;
  v_curriculum_id uuid; v_plan_id uuid; v_training_id uuid;
  clean_title text; clean_description text; clean_target text; clean_responsible text; clean_notes text;
  clean_kind text; clean_number text; clean_issuer text; clean_cycle text; clean_hazard text;
  position_ integer; minutes integer; year_ integer; score_ integer; attempt_no_ integer; pass_score_ integer;
  assessment_ boolean; passed_ boolean; day_ date; expires_ date; employee_name text; department_name text:=''; role_name text:='';
BEGIN
  PERFORM private_isg.workspace_domain_gate('training',true);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,true);
  IF p_mutation IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>65536
    OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN
      ('action','id','expected_version','curriculum_id','plan_id','training_id','employee_id','file_entry_id',
       'workplace_id','title','cycle','hazard_class','target_group','assessment_required','pass_score','topic_id',
       'position','description','duration_minutes','plan_year','planned_on','responsible','attempt_no','score','passed',
       'taken_on','notes','certificate_kind','certificate_no','issuer','issued_on','expires_on')) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  action:=p_payload->>'action'; target:=(p_payload->>'id')::uuid;
  expected:=coalesce((p_payload->>'expected_version')::bigint,0);
  IF action NOT IN ('curriculum_create','curriculum_revise','curriculum_topic_save','curriculum_topic_delete',
      'curriculum_publish','curriculum_retire','training_link_curriculum','plan_create','plan_activate',
      'plan_item_save','plan_item_realise','plan_item_cancel','plan_close','attempt_record',
      'certificate_issue','certificate_verify','certificate_revoke') OR expected<0 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_company,p_payload)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'training.advanced.'||action,fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;

  IF action='curriculum_create' THEN
    IF target IS NOT NULL OR expected<>0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    clean_title:=private_isg.workspace_text(p_payload->>'title',240); clean_cycle:=p_payload->>'cycle';
    clean_hazard:=p_payload->>'hazard_class'; clean_target:=normalize(btrim(coalesce(p_payload->>'target_group','')),NFC);
    assessment_:=coalesce((p_payload->>'assessment_required')::boolean,false);
    pass_score_:=(p_payload->>'pass_score')::integer;
    IF clean_cycle NOT IN ('initial','periodic_repeat','onboarding','task_specific','other')
      OR (clean_hazard IS NOT NULL AND clean_hazard NOT IN ('low','medium','high')) OR octet_length(clean_target)>500
      OR (assessment_ AND pass_score_ NOT BETWEEN 0 AND 100) OR (NOT assessment_ AND pass_score_ IS NOT NULL) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    entity_id:=gen_random_uuid(); series:=entity_id;
    INSERT INTO private_isg.workspace_training_curricula(id,workspace_id,company_id,series_id,revision,title,cycle,
      hazard_class,target_group,assessment_required,pass_score,created_by_user_id,updated_by_user_id)
      VALUES(entity_id,p_workspace,p_company,series,1,clean_title,clean_cycle,clean_hazard,clean_target,
        assessment_,pass_score_,actor,actor) RETURNING * INTO curriculum;
    version_:=curriculum.version; entity_type:='curriculum';
  ELSIF action='curriculum_revise' THEN
    SELECT * INTO source_curriculum FROM private_isg.workspace_training_curricula
      WHERE workspace_id=p_workspace AND company_id=p_company AND id=target FOR UPDATE;
    IF source_curriculum.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF source_curriculum.version<>expected OR source_curriculum.state NOT IN ('published','retired') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    IF EXISTS(SELECT 1 FROM private_isg.workspace_training_curricula c WHERE c.workspace_id=p_workspace
      AND c.company_id=p_company AND c.series_id=source_curriculum.series_id AND c.state='draft') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DRAFT_ALREADY_EXISTS'; END IF;
    entity_id:=gen_random_uuid();
    INSERT INTO private_isg.workspace_training_curricula(id,workspace_id,company_id,series_id,revision,title,cycle,
      hazard_class,target_group,assessment_required,pass_score,created_by_user_id,updated_by_user_id)
      VALUES(entity_id,p_workspace,p_company,source_curriculum.series_id,source_curriculum.revision+1,
        source_curriculum.title,source_curriculum.cycle,source_curriculum.hazard_class,source_curriculum.target_group,
        source_curriculum.assessment_required,source_curriculum.pass_score,actor,actor) RETURNING * INTO curriculum;
    INSERT INTO private_isg.workspace_training_curriculum_topics(workspace_id,company_id,curriculum_id,position,
      title,description,duration_minutes,created_by_user_id,updated_by_user_id)
      SELECT p_workspace,p_company,entity_id,position,title,description,duration_minutes,actor,actor
      FROM private_isg.workspace_training_curriculum_topics WHERE workspace_id=p_workspace
        AND company_id=p_company AND curriculum_id=source_curriculum.id;
    before_state:=to_jsonb(source_curriculum); version_:=curriculum.version; entity_type:='curriculum';
  ELSIF action IN ('curriculum_topic_save','curriculum_topic_delete') THEN
    v_curriculum_id:=(p_payload->>'curriculum_id')::uuid; v_topic_id:=(p_payload->>'topic_id')::uuid;
    SELECT * INTO curriculum FROM private_isg.workspace_training_curricula
      WHERE workspace_id=p_workspace AND company_id=p_company AND id=v_curriculum_id FOR UPDATE;
    IF curriculum.id IS NULL OR curriculum.state<>'draft' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CURRICULUM_LOCKED'; END IF;
    IF curriculum.version<>expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    before_state:=to_jsonb(curriculum);
    IF action='curriculum_topic_save' THEN
      position_:=(p_payload->>'position')::integer; minutes:=(p_payload->>'duration_minutes')::integer;
      clean_title:=private_isg.workspace_text(p_payload->>'title',240);
      clean_description:=normalize(btrim(coalesce(p_payload->>'description','')),NFC);
      IF position_ NOT BETWEEN 1 AND 999 OR minutes NOT BETWEEN 1 AND 100000 OR octet_length(clean_description)>2000 THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      IF v_topic_id IS NULL THEN
        INSERT INTO private_isg.workspace_training_curriculum_topics(workspace_id,company_id,curriculum_id,position,
          title,description,duration_minutes,created_by_user_id,updated_by_user_id)
          VALUES(p_workspace,p_company,curriculum.id,position_,clean_title,clean_description,minutes,actor,actor)
          RETURNING id INTO v_topic_id;
      ELSE
        UPDATE private_isg.workspace_training_curriculum_topics AS t SET position=position_,title=clean_title,
          description=clean_description,duration_minutes=minutes,updated_by_user_id=actor,updated_at=clock_timestamp()
          WHERE t.workspace_id=p_workspace AND t.company_id=p_company
            AND t.curriculum_id=curriculum.id AND t.id=v_topic_id;
        IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      END IF;
    ELSE
      IF v_topic_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      DELETE FROM private_isg.workspace_training_curriculum_topics AS t WHERE t.workspace_id=p_workspace
        AND t.company_id=p_company AND t.curriculum_id=curriculum.id AND t.id=v_topic_id;
      IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    END IF;
    UPDATE private_isg.workspace_training_curricula SET version=version+1,updated_by_user_id=actor,
      updated_at=clock_timestamp() WHERE id=curriculum.id RETURNING * INTO curriculum;
    entity_id:=curriculum.id; version_:=curriculum.version; entity_type:='curriculum';
  ELSIF action IN ('curriculum_publish','curriculum_retire') THEN
    SELECT * INTO curriculum FROM private_isg.workspace_training_curricula
      WHERE workspace_id=p_workspace AND company_id=p_company AND id=target FOR UPDATE;
    IF curriculum.id IS NULL OR curriculum.version<>expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    before_state:=to_jsonb(curriculum);
    IF action='curriculum_publish' THEN
      IF curriculum.state<>'draft' OR NOT EXISTS(SELECT 1 FROM private_isg.workspace_training_curriculum_topics t
        WHERE t.workspace_id=p_workspace AND t.company_id=p_company AND t.curriculum_id=curriculum.id) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CURRICULUM_TOPICS_REQUIRED'; END IF;
      UPDATE private_isg.workspace_training_curricula SET state='superseded',version=version+1,
        updated_by_user_id=actor,updated_at=clock_timestamp() WHERE workspace_id=p_workspace
        AND company_id=p_company AND series_id=curriculum.series_id AND state='published';
      UPDATE private_isg.workspace_training_curricula SET state='published',published_at=clock_timestamp(),
        version=version+1,updated_by_user_id=actor,updated_at=clock_timestamp() WHERE id=curriculum.id RETURNING * INTO curriculum;
    ELSE
      IF curriculum.state<>'published' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CURRICULUM_LOCKED'; END IF;
      UPDATE private_isg.workspace_training_curricula SET state='retired',version=version+1,
        updated_by_user_id=actor,updated_at=clock_timestamp() WHERE id=curriculum.id RETURNING * INTO curriculum;
    END IF;
    entity_id:=curriculum.id; version_:=curriculum.version; entity_type:='curriculum';
  ELSIF action='training_link_curriculum' THEN
    v_curriculum_id:=(p_payload->>'curriculum_id')::uuid;
    SELECT * INTO training FROM private_isg.pilot_training_records WHERE workspace_id=p_workspace
      AND company_id=p_company AND id=target FOR UPDATE;
    SELECT * INTO curriculum FROM private_isg.workspace_training_curricula WHERE workspace_id=p_workspace
      AND company_id=p_company AND id=v_curriculum_id AND state='published' FOR SHARE;
    IF training.id IS NULL OR curriculum.id IS NULL OR training.state<>'planned' THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF training.version<>expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    before_state:=private_isg.workspace_training_row(p_workspace,p_company,training.id);
    UPDATE private_isg.pilot_training_records SET workspace_curriculum_id=curriculum.id,
      curriculum_snapshot=jsonb_build_object('series_id',curriculum.series_id,'revision',curriculum.revision,
        'title',curriculum.title,'assessment_required',curriculum.assessment_required,'pass_score',curriculum.pass_score),
      version=version+1,updated_at=clock_timestamp(),updated_by_user_id=actor WHERE id=training.id RETURNING * INTO training;
    entity_id:=training.id; version_:=training.version; entity_type:='training';
  ELSIF action IN ('plan_create','plan_activate','plan_close') THEN
    entity_type:='annual_training_plan';
    IF action='plan_create' THEN
      IF target IS NOT NULL OR expected<>0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      v_workplace_id:=(p_payload->>'workplace_id')::uuid; year_:=(p_payload->>'plan_year')::integer;
      clean_title:=private_isg.workspace_text(p_payload->>'title',240);
      IF year_ NOT BETWEEN 2000 AND 2200 OR NOT EXISTS(SELECT 1 FROM private_isg.workplaces w
        WHERE w.workspace_id=p_workspace AND w.company_id=p_company AND w.id=v_workplace_id AND NOT w.is_archived) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      INSERT INTO private_isg.workspace_annual_training_plans(workspace_id,company_id,workplace_id,plan_year,title,
        created_by_user_id,updated_by_user_id) VALUES(p_workspace,p_company,v_workplace_id,year_,clean_title,actor,actor)
        RETURNING * INTO plan;
    ELSE
      SELECT * INTO plan FROM private_isg.workspace_annual_training_plans WHERE workspace_id=p_workspace
        AND company_id=p_company AND id=target FOR UPDATE;
      IF plan.id IS NULL OR plan.version<>expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
      before_state:=to_jsonb(plan);
      IF (action='plan_activate' AND plan.state<>'draft') OR (action='plan_close' AND plan.state<>'active') THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PLAN_LOCKED'; END IF;
      IF action='plan_close' AND EXISTS(SELECT 1 FROM private_isg.workspace_annual_training_plan_items i
        WHERE i.workspace_id=p_workspace AND i.company_id=p_company AND i.plan_id=plan.id AND i.state='planned') THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PLAN_ITEMS_PENDING'; END IF;
      UPDATE private_isg.workspace_annual_training_plans SET state=CASE WHEN action='plan_activate' THEN 'active' ELSE 'closed' END,
        version=version+1,updated_by_user_id=actor,updated_at=clock_timestamp() WHERE id=plan.id RETURNING * INTO plan;
    END IF;
    entity_id:=plan.id; version_:=plan.version;
  ELSIF action IN ('plan_item_save','plan_item_realise','plan_item_cancel') THEN
    entity_type:='annual_training_plan';
    IF action='plan_item_save' THEN
      v_plan_id:=(p_payload->>'plan_id')::uuid; v_curriculum_id:=(p_payload->>'curriculum_id')::uuid;
      SELECT * INTO plan FROM private_isg.workspace_annual_training_plans WHERE workspace_id=p_workspace
        AND company_id=p_company AND id=v_plan_id AND state IN ('draft','active') FOR UPDATE;
      IF plan.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      IF v_curriculum_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private_isg.workspace_training_curricula c
        WHERE c.workspace_id=p_workspace AND c.company_id=p_company AND c.id=v_curriculum_id AND c.state='published') THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PUBLISHED_CURRICULUM_REQUIRED'; END IF;
      clean_title:=private_isg.workspace_text(p_payload->>'title',240);
      clean_target:=normalize(btrim(coalesce(p_payload->>'target_group','')),NFC);
      clean_responsible:=normalize(btrim(coalesce(p_payload->>'responsible','')),NFC);
      day_:=(p_payload->>'planned_on')::date; minutes:=(p_payload->>'duration_minutes')::integer;
      IF day_ IS NULL OR NOT isfinite(day_) OR extract(year FROM day_)::integer<>plan.plan_year
        OR minutes NOT BETWEEN 1 AND 100000 OR octet_length(clean_target)>500 OR octet_length(clean_responsible)>240 THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      IF target IS NULL THEN
        IF expected<>0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
        INSERT INTO private_isg.workspace_annual_training_plan_items(workspace_id,company_id,plan_id,curriculum_id,
          title,target_group,planned_on,duration_minutes,responsible,created_by_user_id,updated_by_user_id)
          VALUES(p_workspace,p_company,plan.id,v_curriculum_id,clean_title,clean_target,day_,minutes,clean_responsible,actor,actor)
          RETURNING * INTO plan_item;
      ELSE
        SELECT * INTO plan_item FROM private_isg.workspace_annual_training_plan_items WHERE workspace_id=p_workspace
          AND company_id=p_company AND plan_id=plan.id AND id=target FOR UPDATE;
        IF plan_item.id IS NULL OR plan_item.version<>expected OR plan_item.state<>'planned' THEN
          RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
        before_state:=to_jsonb(plan_item);
        UPDATE private_isg.workspace_annual_training_plan_items SET curriculum_id=v_curriculum_id,title=clean_title,
          target_group=clean_target,planned_on=day_,duration_minutes=minutes,responsible=clean_responsible,
          version=version+1,updated_by_user_id=actor,updated_at=clock_timestamp() WHERE id=plan_item.id RETURNING * INTO plan_item;
      END IF;
    ELSE
      v_training_id:=(p_payload->>'training_id')::uuid;
      SELECT * INTO plan_item FROM private_isg.workspace_annual_training_plan_items WHERE workspace_id=p_workspace
        AND company_id=p_company AND id=target FOR UPDATE;
      IF plan_item.id IS NULL OR plan_item.version<>expected OR plan_item.state<>'planned' THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
      before_state:=to_jsonb(plan_item);
      IF action='plan_item_realise' THEN
        SELECT * INTO training FROM private_isg.pilot_training_records WHERE workspace_id=p_workspace
          AND company_id=p_company AND id=v_training_id AND state='completed' FOR SHARE;
        IF training.id IS NULL OR (plan_item.curriculum_id IS NOT NULL AND
          training.workspace_curriculum_id IS DISTINCT FROM plan_item.curriculum_id) THEN
          RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='TRAINING_REALISATION_CONFLICT'; END IF;
        UPDATE private_isg.workspace_annual_training_plan_items SET state='realised',realised_training_id=training.id,
          version=version+1,updated_by_user_id=actor,updated_at=clock_timestamp() WHERE id=plan_item.id RETURNING * INTO plan_item;
      ELSE
        UPDATE private_isg.workspace_annual_training_plan_items SET state='cancelled',version=version+1,
          updated_by_user_id=actor,updated_at=clock_timestamp() WHERE id=plan_item.id RETURNING * INTO plan_item;
      END IF;
    END IF;
    entity_id:=plan_item.id; version_:=plan_item.version;
  ELSIF action='attempt_record' THEN
    IF target IS NOT NULL OR expected<>0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    v_training_id:=(p_payload->>'training_id')::uuid; v_employee_id:=(p_payload->>'employee_id')::uuid;
    attempt_no_:=(p_payload->>'attempt_no')::integer; score_:=(p_payload->>'score')::integer;
    passed_:=(p_payload->>'passed')::boolean; day_:=(p_payload->>'taken_on')::date;
    clean_notes:=normalize(btrim(coalesce(p_payload->>'notes','')),NFC);
    SELECT * INTO training FROM private_isg.pilot_training_records WHERE workspace_id=p_workspace
      AND company_id=p_company AND id=v_training_id AND state='planned' FOR SHARE;
    SELECT * INTO curriculum FROM private_isg.workspace_training_curricula WHERE workspace_id=p_workspace
      AND company_id=p_company AND id=training.workspace_curriculum_id AND state='published' FOR SHARE;
    IF training.id IS NULL OR curriculum.id IS NULL OR NOT curriculum.assessment_required OR attempt_no_ NOT BETWEEN 1 AND 3
      OR score_ NOT BETWEEN 0 AND 100 OR passed_ IS DISTINCT FROM (score_>=curriculum.pass_score)
      OR day_ IS NULL OR NOT isfinite(day_) OR octet_length(clean_notes)>1000
      OR NOT EXISTS(SELECT 1 FROM private_isg.pilot_training_participants p WHERE p.workspace_id=p_workspace
        AND p.company_id=p_company AND p.training_id=training.id AND p.employee_id=v_employee_id) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    INSERT INTO private_isg.workspace_training_attempts(workspace_id,company_id,training_id,employee_id,
      attempt_no,score,passed,taken_on,notes,created_by_user_id)
      VALUES(p_workspace,p_company,v_training_id,v_employee_id,attempt_no_,score_,passed_,day_,clean_notes,actor)
      RETURNING id INTO entity_id;
    version_:=attempt_no_; entity_type:='training_attempt';
  ELSE
    entity_type:='certificate';
    IF action='certificate_issue' THEN
      IF target IS NOT NULL OR expected<>0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      v_employee_id:=(p_payload->>'employee_id')::uuid; v_training_id:=(p_payload->>'training_id')::uuid;
      v_file_entry_id:=(p_payload->>'file_entry_id')::uuid; clean_kind:=p_payload->>'certificate_kind';
      clean_number:=private_isg.workspace_text(p_payload->>'certificate_no',120);
      clean_issuer:=private_isg.workspace_text(p_payload->>'issuer',240);
      day_:=(p_payload->>'issued_on')::date; expires_:=(p_payload->>'expires_on')::date;
      SELECT full_name INTO employee_name FROM private_isg.employees WHERE workspace_id=p_workspace
        AND company_id=p_company AND id=v_employee_id AND NOT is_archived FOR SHARE;
      SELECT a.department_name_snapshot,a.job_role_name_snapshot INTO department_name,role_name
        FROM private_isg.workspace_personnel_assignments a WHERE a.workspace_id=p_workspace AND a.company_id=p_company
          AND a.employee_id=v_employee_id AND a.effective_from<=day_ AND (a.effective_before IS NULL OR a.effective_before>day_)
        ORDER BY a.effective_from DESC,a.id DESC LIMIT 1;
      IF employee_name IS NULL OR clean_kind NOT IN ('internal_training','external_training','qualification')
        OR day_ IS NULL OR NOT isfinite(day_) OR (expires_ IS NOT NULL AND (NOT isfinite(expires_) OR day_>=expires_))
        OR (v_file_entry_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private_isg.workspace_file_entries f
          WHERE f.workspace_id=p_workspace AND f.company_id=p_company AND f.id=v_file_entry_id AND f.state='active')) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      IF v_training_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private_isg.pilot_training_records r
        JOIN private_isg.pilot_training_participants p ON p.workspace_id=r.workspace_id AND p.company_id=r.company_id
          AND p.training_id=r.id AND p.employee_id=v_employee_id AND p.attended
        WHERE r.workspace_id=p_workspace AND r.company_id=p_company
          AND r.id=v_training_id AND r.state='completed') THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='COMPLETED_TRAINING_REQUIRED'; END IF;
      INSERT INTO private_isg.workspace_training_certificates(workspace_id,company_id,employee_id,training_id,
        file_entry_id,certificate_kind,certificate_no,issuer,issued_on,expires_on,employee_name_snapshot,
        department_name_snapshot,job_role_name_snapshot,created_by_user_id,updated_by_user_id)
        VALUES(p_workspace,p_company,v_employee_id,v_training_id,v_file_entry_id,clean_kind,clean_number,clean_issuer,day_,expires_,
          employee_name,coalesce(department_name,''),coalesce(role_name,''),actor,actor) RETURNING * INTO certificate;
    ELSE
      SELECT * INTO certificate FROM private_isg.workspace_training_certificates WHERE workspace_id=p_workspace
        AND company_id=p_company AND id=target FOR UPDATE;
      IF certificate.id IS NULL OR certificate.version<>expected OR certificate.verification_state='revoked' THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
      before_state:=to_jsonb(certificate);
      UPDATE private_isg.workspace_training_certificates SET
        verification_state=CASE WHEN action='certificate_verify' THEN 'verified' ELSE 'revoked' END,
        version=version+1,updated_by_user_id=actor,updated_at=clock_timestamp()
        WHERE id=certificate.id RETURNING * INTO certificate;
    END IF;
    entity_id:=certificate.id; version_:=certificate.version;
  END IF;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'action',action,'entity_id',entity_id,'version',version_);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'training.advanced.'||action,fingerprint,p_workspace,
    entity_type,entity_id,version_,before_state,result,NULL,result);
END $$;

CREATE OR REPLACE FUNCTION private_isg.workspace_personnel_metrics(p_workspace uuid,p_company uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE member private_isg.workspace_memberships; result jsonb;
BEGIN
  PERFORM private_isg.workspace_domain_gate('personnel',false);
  member:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin','expert'],false);
  IF p_company IS NOT NULL THEN PERFORM private_isg.workspace_require_company(p_workspace,p_company,false); END IF;
  -- Count each domain independently. Joining all seven one-to-many tables here would
  -- multiply rows exponentially for larger companies even though DISTINCT hides the
  -- wrong cardinality in the final value.
  WITH visible_companies AS MATERIALIZED (
    SELECT c.id
    FROM private_isg.workspace_companies c
    WHERE c.workspace_id=p_workspace AND c.status='active' AND (p_company IS NULL OR c.id=p_company)
      AND (member.role IN ('owner','admin') OR EXISTS(SELECT 1 FROM private_isg.company_assignments x
        WHERE x.workspace_id=p_workspace AND x.company_id=c.id AND x.membership_id=member.id
          AND x.starts_at<=clock_timestamp() AND (x.ends_at IS NULL OR x.ends_at>clock_timestamp())))
  ), workplace_counts AS (
    SELECT count(*) FILTER(WHERE NOT x.is_archived) active,count(*) FILTER(WHERE x.is_archived) archived
    FROM private_isg.workplaces x JOIN visible_companies c ON c.id=x.company_id WHERE x.workspace_id=p_workspace
  ), department_counts AS (
    SELECT count(*) FILTER(WHERE NOT x.is_archived) active,count(*) FILTER(WHERE x.is_archived) archived
    FROM private_isg.departments x JOIN visible_companies c ON c.id=x.company_id WHERE x.workspace_id=p_workspace
  ), employee_counts AS (
    SELECT count(*) FILTER(WHERE NOT x.is_archived) active,count(*) FILTER(WHERE x.is_archived) archived
    FROM private_isg.employees x JOIN visible_companies c ON c.id=x.company_id WHERE x.workspace_id=p_workspace
  ), job_role_counts AS (
    SELECT count(*) FILTER(WHERE NOT x.is_archived) active,count(*) FILTER(WHERE x.is_archived) archived
    FROM private_isg.workspace_job_roles x JOIN visible_companies c ON c.id=x.company_id WHERE x.workspace_id=p_workspace
  ), contractor_counts AS (
    SELECT count(*) FILTER(WHERE NOT x.is_archived) active,count(*) FILTER(WHERE x.is_archived) archived
    FROM private_isg.workspace_contractor_organizations x JOIN visible_companies c ON c.id=x.company_id WHERE x.workspace_id=p_workspace
  ), engagement_counts AS (
    SELECT count(*) FILTER(WHERE x.state='active') active,count(*) FILTER(WHERE x.state='ended') ended
    FROM private_isg.workspace_contractor_engagements x JOIN visible_companies c ON c.id=x.company_id WHERE x.workspace_id=p_workspace
  ), assignment_counts AS (
    SELECT count(*) FILTER(WHERE x.effective_from<=CURRENT_DATE AND (x.effective_before IS NULL OR x.effective_before>CURRENT_DATE)) current_count,
      count(*) FILTER(WHERE x.effective_before IS NOT NULL AND x.effective_before<=CURRENT_DATE) historical
    FROM private_isg.workspace_personnel_assignments x JOIN visible_companies c ON c.id=x.company_id WHERE x.workspace_id=p_workspace
  )
  SELECT jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,'measured',true,
    'workplaces',jsonb_build_object('active',w.active,'archived',w.archived),
    'departments',jsonb_build_object('active',d.active,'archived',d.archived),
    'employees',jsonb_build_object('active',e.active,'archived',e.archived),
    'job_roles',jsonb_build_object('active',j.active,'archived',j.archived),
    'contractors',jsonb_build_object('active',o.active,'archived',o.archived),
    'engagements',jsonb_build_object('active',g.active,'ended',g.ended),
    'assignments',jsonb_build_object('current',a.current_count,'historical',a.historical)) INTO result
  FROM workplace_counts w CROSS JOIN department_counts d CROSS JOIN employee_counts e
  CROSS JOIN job_role_counts j CROSS JOIN contractor_counts o CROSS JOIN engagement_counts g
  CROSS JOIN assignment_counts a;
  RETURN result;
END $$;

CREATE OR REPLACE FUNCTION private_isg.workspace_training_metrics(p_workspace uuid,p_company uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
  PERFORM private_isg.workspace_domain_gate('training',false);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,false);
  SELECT jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,'measured',true,
    'records',jsonb_build_object('total',count(DISTINCT r.id),'planned',count(DISTINCT r.id) FILTER(WHERE r.state='planned'),
      'completed',count(DISTINCT r.id) FILTER(WHERE r.state='completed'),'cancelled',count(DISTINCT r.id) FILTER(WHERE r.state='cancelled')),
    'completed_minutes',(SELECT coalesce(sum(x.duration_minutes),0) FROM private_isg.pilot_training_records x
      WHERE x.workspace_id=p_workspace AND x.company_id=p_company AND x.state='completed'),
    'trained_people',(SELECT count(DISTINCT p.employee_id) FROM private_isg.pilot_training_participants p
      JOIN private_isg.pilot_training_records x ON x.workspace_id=p.workspace_id AND x.company_id=p.company_id AND x.id=p.training_id
      WHERE p.workspace_id=p_workspace AND p.company_id=p_company AND p.attended AND x.state='completed'),
    'person_minutes',(SELECT coalesce(sum(x.duration_minutes),0) FROM private_isg.pilot_training_participants p
      JOIN private_isg.pilot_training_records x ON x.workspace_id=p.workspace_id AND x.company_id=p.company_id AND x.id=p.training_id
      WHERE p.workspace_id=p_workspace AND p.company_id=p_company AND p.attended AND x.state='completed'),
    'people_without_completed_training',(SELECT count(*) FROM private_isg.employees e
      WHERE e.workspace_id=p_workspace AND e.company_id=p_company AND NOT e.is_archived AND NOT EXISTS(
        SELECT 1 FROM private_isg.pilot_training_participants p JOIN private_isg.pilot_training_records x
          ON x.workspace_id=p.workspace_id AND x.company_id=p.company_id AND x.id=p.training_id
        WHERE p.workspace_id=e.workspace_id AND p.company_id=e.company_id AND p.employee_id=e.id AND p.attended AND x.state='completed')),
    'curricula',jsonb_build_object('draft',(SELECT count(*) FROM private_isg.workspace_training_curricula c WHERE c.workspace_id=p_workspace AND c.company_id=p_company AND c.state='draft'),
      'published',(SELECT count(*) FROM private_isg.workspace_training_curricula c WHERE c.workspace_id=p_workspace AND c.company_id=p_company AND c.state='published')),
    'annual_plan',jsonb_build_object('open',(SELECT count(*) FROM private_isg.workspace_annual_training_plans p WHERE p.workspace_id=p_workspace AND p.company_id=p_company AND p.state IN ('draft','active')),
      'planned_items',(SELECT count(*) FROM private_isg.workspace_annual_training_plan_items i WHERE i.workspace_id=p_workspace AND i.company_id=p_company AND i.state='planned'),
      'realised_items',(SELECT count(*) FROM private_isg.workspace_annual_training_plan_items i WHERE i.workspace_id=p_workspace AND i.company_id=p_company AND i.state='realised')),
    'certificates',jsonb_build_object('active',(SELECT count(*) FROM private_isg.workspace_training_certificates c WHERE c.workspace_id=p_workspace AND c.company_id=p_company AND c.verification_state<>'revoked' AND (c.expires_on IS NULL OR c.expires_on>CURRENT_DATE)),
      'expiring_30_days',(SELECT count(*) FROM private_isg.workspace_training_certificates c WHERE c.workspace_id=p_workspace AND c.company_id=p_company AND c.verification_state<>'revoked' AND c.expires_on BETWEEN CURRENT_DATE AND CURRENT_DATE+30)),
    'assessment',jsonb_build_object('attempts',(SELECT count(*) FROM private_isg.workspace_training_attempts a WHERE a.workspace_id=p_workspace AND a.company_id=p_company),
      'passed_people',(SELECT count(DISTINCT a.employee_id) FROM private_isg.workspace_training_attempts a WHERE a.workspace_id=p_workspace AND a.company_id=p_company AND a.passed))) INTO result
  FROM private_isg.pilot_training_records r WHERE r.workspace_id=p_workspace AND r.company_id=p_company;
  RETURN result;
END $$;

CREATE FUNCTION public.isg_workspace_personnel_advanced_read_v1(p_workspace uuid,p_company uuid,p_kind text,
  p_after uuid DEFAULT NULL,p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_personnel_advanced_read(p_workspace,p_company,p_kind,p_after,p_limit)
$$;
CREATE FUNCTION public.isg_workspace_personnel_advanced_mutate_v1(p_mutation uuid,p_workspace uuid,p_company uuid,
  p_payload jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_personnel_advanced_mutate(p_mutation,p_workspace,p_company,p_payload)
$$;
CREATE FUNCTION public.isg_workspace_training_advanced_read_v1(p_workspace uuid,p_company uuid,p_kind text,
  p_after uuid DEFAULT NULL,p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_training_advanced_read(p_workspace,p_company,p_kind,p_after,p_limit)
$$;
CREATE FUNCTION public.isg_workspace_training_advanced_mutate_v1(p_mutation uuid,p_workspace uuid,p_company uuid,
  p_payload jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_training_advanced_mutate(p_mutation,p_workspace,p_company,p_payload)
$$;

REVOKE ALL ON FUNCTION private_isg.workspace_personnel_advanced_read(uuid,uuid,text,uuid,integer),
  private_isg.workspace_personnel_advanced_mutate(uuid,uuid,uuid,jsonb),
  private_isg.workspace_training_completion_guard(),
  private_isg.workspace_training_advanced_read(uuid,uuid,text,uuid,integer),
  private_isg.workspace_training_advanced_mutate(uuid,uuid,uuid,jsonb),
  public.isg_workspace_personnel_advanced_read_v1(uuid,uuid,text,uuid,integer),
  public.isg_workspace_personnel_advanced_mutate_v1(uuid,uuid,uuid,jsonb),
  public.isg_workspace_training_advanced_read_v1(uuid,uuid,text,uuid,integer),
  public.isg_workspace_training_advanced_mutate_v1(uuid,uuid,uuid,jsonb)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_personnel_advanced_read(uuid,uuid,text,uuid,integer),
  private_isg.workspace_personnel_advanced_mutate(uuid,uuid,uuid,jsonb),
  private_isg.workspace_training_advanced_read(uuid,uuid,text,uuid,integer),
  private_isg.workspace_training_advanced_mutate(uuid,uuid,uuid,jsonb),
  public.isg_workspace_personnel_advanced_read_v1(uuid,uuid,text,uuid,integer),
  public.isg_workspace_personnel_advanced_mutate_v1(uuid,uuid,uuid,jsonb),
  public.isg_workspace_training_advanced_read_v1(uuid,uuid,text,uuid,integer),
  public.isg_workspace_training_advanced_mutate_v1(uuid,uuid,uuid,jsonb)
  TO authenticated;
NOTIFY pgrst,'reload schema';
