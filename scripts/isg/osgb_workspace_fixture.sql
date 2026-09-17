-- Disposable PostgreSQL fixture for the undeployed OSGB workspace candidate.
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE ROLE service_role;
CREATE SCHEMA auth;
CREATE SCHEMA private_isg;
CREATE SCHEMA private;
CREATE TABLE public.profiles(id uuid PRIMARY KEY);
CREATE TABLE public.companies(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name text NOT NULL,
  hazard_class text NOT NULL CHECK(hazard_class IN ('low','medium','high')),
  logo_path text,
  is_archived boolean NOT NULL DEFAULT false,
  address text,
  contact_person text,
  department text,
  default_responsible text,
  default_due_days integer,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(id,user_id)
);
CREATE FUNCTION private.company_limit_for_user(uuid) RETURNS integer
LANGUAGE sql STABLE SET search_path='' AS $$ SELECT 25 $$;
CREATE FUNCTION private.enforce_company_write_rules() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  NEW.name:=btrim(NEW.name); NEW.logo_path:=nullif(btrim(coalesce(NEW.logo_path,'')),'');
  IF NEW.name='' THEN RAISE EXCEPTION 'company_name_required'; END IF;
  IF NEW.user_id IS NULL THEN RAISE EXCEPTION 'company_owner_required'; END IF;
  NEW.updated_at:=clock_timestamp(); RETURN NEW;
END $$;
CREATE TRIGGER companies_enforce_write_rules BEFORE INSERT OR UPDATE ON public.companies
FOR EACH ROW EXECUTE FUNCTION private.enforce_company_write_rules();
CREATE TABLE private_isg.workplaces(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  owner_id uuid NOT NULL,
  name text NOT NULL,
  address text,
  hazard_class text CHECK(hazard_class IN ('low','medium','high')),
  jurisdiction text,
  timezone text,
  needs_review boolean NOT NULL DEFAULT true,
  is_archived boolean NOT NULL DEFAULT false,
  legacy_company_id uuid UNIQUE,
  version bigint NOT NULL DEFAULT 0,
  code text NOT NULL,
  context_version bigint NOT NULL DEFAULT 0,
  UNIQUE(company_id,id),UNIQUE(company_id,code),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
CREATE TABLE private_isg.departments(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),company_id uuid NOT NULL,owner_id uuid NOT NULL,
  workplace_id uuid NOT NULL,code text NOT NULL,name text NOT NULL,is_archived boolean NOT NULL DEFAULT false,
  parent_id uuid,version bigint NOT NULL DEFAULT 0,
  UNIQUE(company_id,id),UNIQUE(company_id,workplace_id,code),UNIQUE(company_id,workplace_id,id),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
CREATE TABLE private_isg.employees(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),company_id uuid NOT NULL,owner_id uuid NOT NULL,
  employee_code text NOT NULL,full_name text NOT NULL,intake_department_id uuid,hired_on date,
  employment_ends_before date,registered_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  record_version bigint NOT NULL DEFAULT 0,is_archived boolean NOT NULL DEFAULT false,
  employer_org_id uuid,employer_version bigint NOT NULL DEFAULT 0,assignment_version bigint NOT NULL DEFAULT 0,
  UNIQUE(company_id,id),UNIQUE(company_id,employee_code),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,intake_department_id) REFERENCES private_isg.departments(company_id,id)
);
CREATE TABLE auth.users(
  id uuid PRIMARY KEY,
  email text,
  email_confirmed_at timestamptz
);
INSERT INTO public.profiles(id) VALUES
  ('20000000-0000-0000-0000-000000000001'),
  ('20000000-0000-0000-0000-000000000002'),
  ('20000000-0000-0000-0000-000000000003'),
  ('20000000-0000-0000-0000-000000000004');
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES
  ('20000000-0000-0000-0000-000000000001','owner@example.test',clock_timestamp()),
  ('20000000-0000-0000-0000-000000000002','admin@example.test',clock_timestamp()),
  ('20000000-0000-0000-0000-000000000003','expert@example.test',clock_timestamp()),
  ('20000000-0000-0000-0000-000000000004','other@example.test',clock_timestamp());
-- Minimal legacy personal-analysis authority used by the transition bridge.
-- Production owns the richer versions of these two tables; the candidate must
-- prove that it reads them without changing or re-parenting personal data.
CREATE TABLE public.analyses(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  company_id uuid REFERENCES public.companies(id) ON DELETE SET NULL,
  title text NOT NULL DEFAULT 'Adsız analiz',
  kind text NOT NULL DEFAULT 'photo',
  status text NOT NULL DEFAULT 'completed',
  primary_method text NOT NULL DEFAULT 'fine_kinney',
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE public.findings(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  analysis_id uuid NOT NULL REFERENCES public.analyses(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  ordinal integer NOT NULL,
  title text NOT NULL,
  category text,
  description text,
  recommended_action text,
  references_text text,
  responsible text,
  fk_probability numeric,
  fk_frequency numeric,
  fk_severity numeric,
  fk_score numeric,
  fk_band text NOT NULL DEFAULT 'unknown',
  m5_probability integer,
  m5_severity integer,
  m5_score integer,
  m5_band text NOT NULL DEFAULT 'unknown',
  is_scored boolean NOT NULL DEFAULT true,
  item_class text NOT NULL DEFAULT 'observed_finding',
  is_user_deleted boolean NOT NULL DEFAULT false,
  finding_version integer NOT NULL DEFAULT 1,
  source_photo_indices integer[] NOT NULL DEFAULT '{}',
  display_order integer,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(analysis_id,ordinal)
);
CREATE TABLE private_isg.pilot_training_catalog(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  code text NOT NULL,
  title text NOT NULL,
  rules jsonb NOT NULL DEFAULT '{}'::jsonb,
  source_url text,
  content_approved boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE private_isg.pilot_training_sessions(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  catalog_id uuid REFERENCES private_isg.pilot_training_catalog(id),
  catalog_snapshot jsonb,
  title text NOT NULL,
  trainer text NOT NULL,
  method text NOT NULL DEFAULT 'face_to_face' CHECK(method IN ('face_to_face','online','mixed')),
  held_on date NOT NULL,
  location text NOT NULL DEFAULT '',
  notes text NOT NULL DEFAULT '',
  version bigint NOT NULL DEFAULT 1,
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE private_isg.pilot_training_records(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  owner_id uuid NOT NULL,
  title text NOT NULL,
  trainer text NOT NULL,
  location text NOT NULL DEFAULT '',
  notes text NOT NULL DEFAULT '',
  starts_at timestamptz NOT NULL,
  duration_minutes integer NOT NULL CHECK(duration_minutes BETWEEN 1 AND 100000),
  valid_until date,
  state text NOT NULL DEFAULT 'planned' CHECK(state IN ('planned','completed','cancelled')),
  version bigint NOT NULL DEFAULT 1,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  session_id uuid REFERENCES private_isg.pilot_training_sessions(id),
  company_snapshot jsonb,
  UNIQUE(company_id,id),
  UNIQUE(session_id,company_id),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
CREATE TABLE private_isg.pilot_training_participants(
  company_id uuid NOT NULL,
  training_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  employee_name text NOT NULL,
  attended boolean NOT NULL DEFAULT false,
  PRIMARY KEY(training_id,employee_id),
  FOREIGN KEY(company_id,training_id) REFERENCES private_isg.pilot_training_records(company_id,id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,employee_id) REFERENCES private_isg.employees(company_id,id)
);
CREATE TABLE private_isg.pilot_training_session_revisions(
  session_id uuid NOT NULL REFERENCES private_isg.pilot_training_sessions(id) ON DELETE CASCADE,
  version bigint NOT NULL,
  snapshot jsonb NOT NULL,
  changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(session_id,version)
);
CREATE TABLE private_isg.pilot_training_receipts(
  actor_id uuid NOT NULL,
  mutation_id uuid NOT NULL,
  company_id uuid NOT NULL,
  request_hash bytea NOT NULL,
  response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(actor_id,mutation_id)
);
CREATE TABLE private_isg.pilot_training_session_receipts(
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  mutation_id uuid NOT NULL,
  request_hash bytea NOT NULL,
  response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(owner_id,mutation_id)
);
CREATE TABLE private_isg.risk_assessments(
  assessment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  owner_id uuid NOT NULL,
  workplace_id uuid NOT NULL,
  current_version integer NOT NULL DEFAULT 0,
  base_assessment_on date,
  valid_until date,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(company_id,workplace_id),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
CREATE TABLE private_isg.risk_assessment_versions(
  assessment_id uuid NOT NULL REFERENCES private_isg.risk_assessments(assessment_id) ON DELETE CASCADE,
  version integer NOT NULL,
  kind text NOT NULL CHECK(kind IN ('full','partial','metadata','rescan')),
  previous_version integer,
  assessment_on date NOT NULL,
  revision_on date,
  scope jsonb,
  reason text,
  source_snapshot jsonb,
  state text NOT NULL DEFAULT 'draft' CHECK(state IN ('draft','final','superseded')),
  date_needs_review boolean NOT NULL DEFAULT false,
  period_years integer,
  period_source text,
  period_needs_review boolean NOT NULL DEFAULT false,
  valid_until date,
  source_drift boolean NOT NULL DEFAULT false,
  drift_note text,
  verified_by uuid REFERENCES public.profiles(id),
  finalized_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(assessment_id,version)
);
CREATE TABLE private_isg.risk_source_links(
  link_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assessment_id uuid NOT NULL,
  version integer NOT NULL,
  analysis_id uuid NOT NULL,
  finding_id uuid NOT NULL,
  source_version bigint NOT NULL,
  copied_fields jsonb NOT NULL,
  selected_at timestamptz NOT NULL,
  UNIQUE(assessment_id,version,analysis_id,finding_id),
  FOREIGN KEY(assessment_id,version) REFERENCES private_isg.risk_assessment_versions(assessment_id,version) ON DELETE CASCADE
);
CREATE TABLE private_isg.nonconformities(
  nonconformity_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  owner_id uuid NOT NULL,
  workplace_id uuid NOT NULL,
  source_kind text NOT NULL CHECK(source_kind IN ('checklist','risk_version','legacy_finding','manual')),
  source_ref text,
  title text NOT NULL,
  severity text NOT NULL CHECK(severity IN ('low','medium','high','critical')),
  opened_on date NOT NULL,
  due_on date,
  assignee_contact text,
  state text NOT NULL DEFAULT 'draft' CHECK(state IN ('draft','open','assigned','in_progress','pending_verification','closed','reopened','cancelled')),
  version bigint NOT NULL DEFAULT 0,
  closed_on date,
  cancelled_reason text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(company_id,source_kind,source_ref),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
CREATE TABLE private_isg.nonconformity_state_edges(
  from_state text NOT NULL,
  to_state text NOT NULL,
  requires_reason boolean NOT NULL DEFAULT false,
  requires_assignee boolean NOT NULL DEFAULT false,
  requires_verification boolean NOT NULL DEFAULT false,
  PRIMARY KEY(from_state,to_state)
);
INSERT INTO private_isg.nonconformity_state_edges(from_state,to_state,requires_reason,requires_assignee,requires_verification) VALUES
  ('draft','open',false,false,false),('draft','cancelled',true,false,false),
  ('open','assigned',false,true,false),('open','cancelled',true,false,false),
  ('assigned','in_progress',false,false,false),('assigned','open',true,false,false),
  ('assigned','cancelled',true,false,false),('in_progress','pending_verification',false,false,false),
  ('in_progress','assigned',true,true,false),('in_progress','cancelled',true,false,false),
  ('pending_verification','closed',false,false,true),('pending_verification','in_progress',true,false,false),
  ('closed','reopened',true,false,false),('reopened','assigned',false,true,false),
  ('reopened','in_progress',false,false,false),('reopened','cancelled',true,false,false);
CREATE TABLE private_isg.nonconformity_transitions(
  transition_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nonconformity_id uuid NOT NULL REFERENCES private_isg.nonconformities(nonconformity_id) ON DELETE CASCADE,
  version bigint NOT NULL,
  from_state text NOT NULL,
  to_state text NOT NULL,
  reason text,
  actor_id uuid NOT NULL REFERENCES public.profiles(id),
  occurred_at timestamptz NOT NULL,
  UNIQUE(nonconformity_id,version)
);
CREATE TABLE private_isg.nonconformity_actions(
  action_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nonconformity_id uuid NOT NULL REFERENCES private_isg.nonconformities(nonconformity_id) ON DELETE CASCADE,
  description text NOT NULL,
  assignee_contact text,
  due_on date,
  state text NOT NULL DEFAULT 'planned',
  external_ref text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE private_isg.verification_records(
  verification_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nonconformity_id uuid NOT NULL REFERENCES private_isg.nonconformities(nonconformity_id) ON DELETE CASCADE,
  cycle bigint NOT NULL,
  outcome text NOT NULL CHECK(outcome IN ('accepted','rejected')),
  verified_by uuid NOT NULL REFERENCES public.profiles(id),
  verified_on date NOT NULL,
  note text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(nonconformity_id,cycle)
);
CREATE TABLE private_isg.checklist_templates(
  template_code text PRIMARY KEY,
  title text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE private_isg.checklist_template_versions(
  template_code text NOT NULL REFERENCES private_isg.checklist_templates(template_code) ON DELETE CASCADE,
  version integer NOT NULL,
  status text NOT NULL DEFAULT 'draft',
  approved_by uuid REFERENCES public.profiles(id),
  approval_note text,
  published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(template_code,version)
);
CREATE TABLE private_isg.checklist_template_items(
  template_code text NOT NULL,
  version integer NOT NULL,
  item_code text NOT NULL,
  prompt text NOT NULL,
  allows_not_applicable boolean NOT NULL DEFAULT true,
  position integer NOT NULL,
  PRIMARY KEY(template_code,version,item_code),
  FOREIGN KEY(template_code,version) REFERENCES private_isg.checklist_template_versions(template_code,version) ON DELETE CASCADE
);
CREATE TABLE private_isg.checklist_runs(
  run_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  owner_id uuid NOT NULL,
  workplace_id uuid NOT NULL,
  template_code text NOT NULL,
  template_version integer NOT NULL,
  state text NOT NULL DEFAULT 'open' CHECK(state IN ('open','submitted','cancelled')),
  started_on date NOT NULL,
  submitted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE,
  FOREIGN KEY(template_code,template_version) REFERENCES private_isg.checklist_template_versions(template_code,version)
);
CREATE TABLE private_isg.checklist_run_items(
  run_id uuid NOT NULL REFERENCES private_isg.checklist_runs(run_id) ON DELETE CASCADE,
  item_code text NOT NULL,
  result text NOT NULL CHECK(result IN ('conform','nonconform','not_applicable')),
  note text,
  nonconformity_id uuid REFERENCES private_isg.nonconformities(nonconformity_id) ON DELETE SET NULL,
  recorded_at timestamptz NOT NULL,
  PRIMARY KEY(run_id,item_code)
);
CREATE TABLE private_isg.emergency_plan_versions(
  plan_id uuid NOT NULL DEFAULT gen_random_uuid(),
  version integer NOT NULL,
  company_id uuid NOT NULL,
  owner_id uuid NOT NULL,
  workplace_id uuid NOT NULL,
  scope text NOT NULL,
  prepared_on date NOT NULL,
  valid_until date,
  team_snapshot jsonb NOT NULL,
  state text NOT NULL DEFAULT 'active' CHECK(state IN ('active','superseded')),
  needs_review boolean NOT NULL DEFAULT true,
  review_note text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(plan_id,version),
  UNIQUE(company_id,plan_id,version),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
CREATE TABLE private_isg.drill_records(
  drill_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  workplace_id uuid NOT NULL,
  plan_id uuid NOT NULL,
  plan_version integer NOT NULL,
  planned_on date NOT NULL,
  performed_on date,
  state text NOT NULL DEFAULT 'planned' CHECK(state IN ('planned','performed','cancelled')),
  participants jsonb,
  observation text,
  improvement text,
  cancelled_reason text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY(company_id,plan_id,plan_version) REFERENCES private_isg.emergency_plan_versions(company_id,plan_id,version),
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
CREATE TABLE private_isg.appointments(
  appointment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  kind text NOT NULL CHECK(kind IN ('representative','support_staff','team_member','first_aid','fire_team')),
  scope_workplace_id uuid NOT NULL,
  starts_on date NOT NULL,
  ends_before date,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY(company_id,employee_id) REFERENCES private_isg.employees(company_id,id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,scope_workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
CREATE TABLE private_isg.ppe_handovers(
  handover_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  item text NOT NULL,
  quantity numeric(12,3) NOT NULL CHECK(quantity>0),
  unit text NOT NULL CHECK(unit IN ('piece','pair','set','metre','litre')),
  handed_on date NOT NULL,
  signed_copy boolean NOT NULL DEFAULT false,
  external_ref text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(company_id,employee_id,external_ref),
  FOREIGN KEY(company_id,employee_id) REFERENCES private_isg.employees(company_id,id) ON DELETE CASCADE
);
CREATE TABLE private_isg.ppe_returns(
  return_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  handover_id uuid NOT NULL REFERENCES private_isg.ppe_handovers(handover_id) ON DELETE CASCADE,
  quantity numeric(12,3) NOT NULL CHECK(quantity>0),
  returned_on date NOT NULL,
  condition text NOT NULL CHECK(condition IN ('reusable','worn','damaged','lost')),
  note text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE private_isg.equipment_items(
  equipment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  owner_id uuid NOT NULL,
  workplace_id uuid NOT NULL,
  equipment_type text NOT NULL,
  serial_tag text NOT NULL,
  acquired_on date,
  location_note text,
  is_archived boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(company_id,serial_tag),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
CREATE TABLE private_isg.equipment_inspection_rules(
  company_id uuid NOT NULL,
  equipment_type text NOT NULL,
  period_months integer NOT NULL CHECK(period_months BETWEEN 1 AND 240),
  period_source text NOT NULL CHECK(period_source IN ('manufacturer','rule_version','unapproved_fixture','regulation_default')),
  exception_note text,
  needs_review boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(company_id,equipment_type)
);
CREATE TABLE private_isg.equipment_inspections(
  inspection_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  equipment_id uuid NOT NULL REFERENCES private_isg.equipment_items(equipment_id) ON DELETE CASCADE,
  performed_on date NOT NULL,
  result text NOT NULL CHECK(result IN ('pass','fail','conditional')),
  next_due_on date,
  period_months integer CHECK(period_months IS NULL OR period_months BETWEEN 1 AND 240),
  inspector text,
  evidence_asset_id uuid,
  external_ref text,
  note text,
  due_source text CHECK(due_source IS NULL OR due_source IN ('period','expert')),
  katip_assignment_declared boolean NOT NULL DEFAULT false,
  katip_declared_note text,
  katip_official_verification boolean NOT NULL DEFAULT false CHECK(NOT katip_official_verification),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(equipment_id,performed_on)
);
CREATE TABLE private_isg.equipment_type_suggestions(
  equipment_type text PRIMARY KEY,
  ordinal integer NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO private_isg.equipment_type_suggestions(equipment_type,ordinal) VALUES
  ('lifting_equipment',1),('crane',2),('forklift',3),('pressure_vessel',4),('compressor',5),
  ('boiler',6),('lift',7),('scaffold',8),('ladder',9),('electrical_installation',10),
  ('earthing',11),('fire_extinguisher',12),('fire_detection',13),('ventilation',14),
  ('power_tool',15),('welding_set',16),('conveyor',17),('press_machine',18),('lathe',19),
  ('other_equipment',20);
CREATE TABLE private_isg.equipment_default_periods(
  equipment_type text PRIMARY KEY REFERENCES private_isg.equipment_type_suggestions(equipment_type),
  period_months integer NOT NULL CHECK(period_months BETWEEN 1 AND 240),
  basis_note text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO private_isg.equipment_default_periods(equipment_type,period_months,basis_note)
SELECT equipment_type,12,'Genel başlangıç süresi; uzman üretici, standart ve sektör koşullarına göre doğrulamalıdır.'
FROM private_isg.equipment_type_suggestions;
CREATE TABLE private_isg.katip_contracts(
  contract_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),company_id uuid NOT NULL,owner_id uuid NOT NULL,
  workplace_id uuid NOT NULL,counterparty text NOT NULL,expert_contact text NOT NULL,scope text NOT NULL,
  starts_on date NOT NULL,ends_before date,state text NOT NULL DEFAULT 'active' CHECK(state IN ('active','archived')),
  asset_id uuid,
  official_integration boolean NOT NULL DEFAULT false CHECK(NOT official_integration),
  declared_monthly_minutes integer,declared_note text,contract_location text,is_deleted boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
CREATE TABLE private_isg.annual_work_plans(
  plan_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),company_id uuid NOT NULL,owner_id uuid NOT NULL,
  workplace_id uuid NOT NULL,plan_year integer NOT NULL,state text NOT NULL DEFAULT 'active',closed_on date,
  is_deleted boolean NOT NULL DEFAULT false,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
CREATE TABLE private_isg.annual_work_plan_items(
  item_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),plan_id uuid NOT NULL REFERENCES private_isg.annual_work_plans(plan_id) ON DELETE CASCADE,
  activity text NOT NULL,responsible_contact text,planned_on date NOT NULL,performed_on date,
  state text NOT NULL DEFAULT 'planned',carry_over_reason text,carried_to_plan_id uuid,
  is_deleted boolean NOT NULL DEFAULT false,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE private_isg.board_meetings(
  meeting_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),company_id uuid NOT NULL,owner_id uuid NOT NULL,
  workplace_id uuid NOT NULL,applicability text NOT NULL,counts_towards_legal_score boolean NOT NULL,
  planned_on date NOT NULL,held_on date,agenda jsonb NOT NULL,attendance jsonb,state text NOT NULL DEFAULT 'planned',
  minutes_asset_id uuid,
  cancelled_reason text,is_deleted boolean NOT NULL DEFAULT false,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
CREATE TABLE private_isg.board_decisions(
  decision_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),meeting_id uuid NOT NULL REFERENCES private_isg.board_meetings(meeting_id) ON DELETE CASCADE,
  decision_no integer NOT NULL,decision_text text NOT NULL,responsible_contact text,due_on date,
  state text NOT NULL DEFAULT 'open',is_deleted boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),UNIQUE(meeting_id,decision_no)
);
CREATE TABLE private_isg.work_permit_forms(
  permit_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),company_id uuid NOT NULL,owner_id uuid NOT NULL,
  workplace_id uuid NOT NULL,template_code text NOT NULL,template_version integer NOT NULL,job_description text NOT NULL,
  parties jsonb NOT NULL,planned_on date NOT NULL,state text NOT NULL DEFAULT 'draft',signed_copy boolean NOT NULL DEFAULT false,
  rendered_asset_id uuid,
  authorises_work boolean NOT NULL DEFAULT false CHECK(NOT authorises_work),work_location text,starts_at timestamptz,
  ends_at timestamptz,risk_precautions text,is_deleted boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
CREATE TABLE private_isg.site_visits(
  visit_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),company_id uuid NOT NULL,owner_id uuid NOT NULL,
  workplace_id uuid NOT NULL,visited_on date NOT NULL,location_note text,expert_note text NOT NULL,
  responsible_contact text,is_deleted boolean NOT NULL DEFAULT false,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
CREATE TABLE private_isg.site_visit_observations(
  observation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),visit_id uuid NOT NULL REFERENCES private_isg.site_visits(visit_id) ON DELETE CASCADE,
  note text NOT NULL,nonconformity_id uuid,external_ref text,is_deleted boolean NOT NULL DEFAULT false,
  evidence_asset_id uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE private_isg.notebook_archive_entries(
  entry_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),company_id uuid NOT NULL,owner_id uuid NOT NULL,
  workplace_id uuid NOT NULL,notebook_ref text NOT NULL,entry_on date NOT NULL,ai_draft_ref text,
  asset_id uuid NOT NULL,
  ai_text_is_official_record boolean NOT NULL DEFAULT false CHECK(NOT ai_text_is_official_record),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
CREATE FUNCTION private_isg.active_actor() RETURNS uuid
LANGUAGE sql STABLE SET search_path='' AS $$
  SELECT nullif(current_setting('test.actor',true),'')::uuid
$$;
