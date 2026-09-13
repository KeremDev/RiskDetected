-- P10 second slice: seven more §7.5 modules behind their own switches.
-- Additive; rollout OFF; no client grant. Nothing here claims an official
-- integration, approves work, or turns an AI draft into an official record.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE private_isg.module_registry DROP CONSTRAINT module_registry_module_check;
ALTER TABLE private_isg.module_registry ADD CONSTRAINT module_registry_module_check
  CHECK(module IN ('emergency_plan','drill','equipment','ppe','appointment','katip_contract','annual_work_plan',
    'annual_training_plan','board','work_permit','site_visit','notebook_archive'));
INSERT INTO private_isg.module_registry(module) VALUES
  ('katip_contract'),('annual_work_plan'),('annual_training_plan'),('board'),('work_permit'),('site_visit'),('notebook_archive');

-- ISG-KATİP: manual contract and document tracking. No login on the user's
-- behalf, no scraping and no automatic filing to the official system.
CREATE TABLE private_isg.katip_contracts (
  contract_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL, workplace_id uuid NOT NULL,
  counterparty text NOT NULL CHECK(btrim(counterparty)<>'' AND length(counterparty)<=200),
  expert_contact text NOT NULL CHECK(btrim(expert_contact)<>'' AND length(expert_contact)<=200),
  scope text NOT NULL CHECK(btrim(scope)<>'' AND length(scope)<=300),
  starts_on date NOT NULL CHECK(isfinite(starts_on)),
  ends_before date CHECK(ends_before IS NULL OR isfinite(ends_before)),
  -- An open ended contract is its own state, not an unknown end date.
  term_state text GENERATED ALWAYS AS(CASE WHEN ends_before IS NULL THEN 'open_ended' ELSE 'fixed_term' END) STORED,
  asset_id uuid REFERENCES private_isg.file_assets(asset_id),
  state text NOT NULL DEFAULT 'active' CHECK(state IN ('active','archived')),
  official_integration boolean NOT NULL DEFAULT false CHECK(NOT official_integration),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id,counterparty,scope,starts_on),
  CHECK(ends_before IS NULL OR ends_before>starts_on),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
-- Annual work plan: one plan per workplace and calendar year. Closing a plan
-- does not perform anything; an item that slips needs a written carry-over.
CREATE TABLE private_isg.annual_work_plans (
  plan_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL, workplace_id uuid NOT NULL,
  plan_year integer NOT NULL CHECK(plan_year BETWEEN 2000 AND 2100),
  state text NOT NULL DEFAULT 'active' CHECK(state IN ('active','closed')),
  closed_on date CHECK(closed_on IS NULL OR isfinite(closed_on)),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id,workplace_id,plan_year),
  CHECK((state='closed')=(closed_on IS NOT NULL)),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
CREATE TABLE private_isg.annual_work_plan_items (
  item_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id uuid NOT NULL REFERENCES private_isg.annual_work_plans(plan_id) ON DELETE CASCADE,
  activity text NOT NULL CHECK(btrim(activity)<>'' AND length(activity)<=300),
  responsible_contact text CHECK(responsible_contact IS NULL OR length(responsible_contact)<=200),
  planned_on date NOT NULL CHECK(isfinite(planned_on)),
  performed_on date CHECK(performed_on IS NULL OR isfinite(performed_on)),
  state text NOT NULL DEFAULT 'planned' CHECK(state IN ('planned','performed','carried_over','cancelled')),
  carry_over_reason text CHECK(carry_over_reason IS NULL OR length(carry_over_reason) BETWEEN 10 AND 1000),
  carried_to_plan_id uuid REFERENCES private_isg.annual_work_plans(plan_id),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(plan_id,activity,planned_on),
  CHECK((state='performed')=(performed_on IS NOT NULL)),
  CHECK((state='carried_over')=(carry_over_reason IS NOT NULL)),
  CHECK(carried_to_plan_id IS NULL OR state='carried_over')
);
-- Annual training plan: a planned need, never a completion record.
CREATE TABLE private_isg.annual_training_plans (
  plan_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL, workplace_id uuid NOT NULL,
  plan_year integer NOT NULL CHECK(plan_year BETWEEN 2000 AND 2100),
  catalog_code text NOT NULL, target_group text NOT NULL CHECK(btrim(target_group)<>'' AND length(target_group)<=200),
  planned_sessions integer NOT NULL CHECK(planned_sessions BETWEEN 1 AND 500),
  realised_plan_id uuid REFERENCES private_isg.training_plans(plan_id),
  state text NOT NULL DEFAULT 'planned' CHECK(state IN ('planned','realised','cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id,workplace_id,plan_year,catalog_code,target_group),
  CHECK((state='realised')=(realised_plan_id IS NOT NULL)),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
-- Board meetings: voluntary use is recorded as voluntary and stays out of the
-- main legal score. Attendance is a snapshot, not an account or a role.
CREATE TABLE private_isg.board_meetings (
  meeting_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL, workplace_id uuid NOT NULL,
  applicability text NOT NULL CHECK(applicability IN ('mandatory','voluntary')),
  counts_towards_legal_score boolean NOT NULL,
  planned_on date NOT NULL CHECK(isfinite(planned_on)),
  held_on date CHECK(held_on IS NULL OR isfinite(held_on)),
  agenda jsonb NOT NULL, attendance jsonb,
  minutes_asset_id uuid REFERENCES private_isg.file_assets(asset_id),
  state text NOT NULL DEFAULT 'planned' CHECK(state IN ('planned','held','cancelled')),
  cancelled_reason text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK(counts_towards_legal_score=(applicability='mandatory')),
  CHECK((state='held')=(held_on IS NOT NULL)),
  CHECK((state='held')=(attendance IS NOT NULL)),
  CHECK((state='cancelled')=(cancelled_reason IS NOT NULL)),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
CREATE TABLE private_isg.board_decisions (
  decision_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id uuid NOT NULL REFERENCES private_isg.board_meetings(meeting_id) ON DELETE CASCADE,
  decision_no integer NOT NULL CHECK(decision_no BETWEEN 1 AND 500),
  decision_text text NOT NULL CHECK(btrim(decision_text)<>'' AND length(decision_text)<=2000),
  responsible_contact text CHECK(responsible_contact IS NULL OR length(responsible_contact)<=200),
  due_on date CHECK(due_on IS NULL OR isfinite(due_on)),
  state text NOT NULL DEFAULT 'open' CHECK(state IN ('open','done','cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(meeting_id,decision_no)
);
-- Work permit form: a document, not an authorisation machine. There is no
-- approved/started state and no column that could grant permission to work.
CREATE TABLE private_isg.work_permit_forms (
  permit_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL, workplace_id uuid NOT NULL,
  template_code text NOT NULL CHECK(template_code ~ '^[a-z][a-z0-9_]{2,60}$'),
  template_version integer NOT NULL CHECK(template_version BETWEEN 1 AND 1000),
  job_description text NOT NULL CHECK(btrim(job_description)<>'' AND length(job_description)<=1000),
  parties jsonb NOT NULL,
  planned_on date NOT NULL CHECK(isfinite(planned_on)),
  state text NOT NULL DEFAULT 'draft' CHECK(state IN ('draft','rendered','archived')),
  rendered_asset_id uuid REFERENCES private_isg.file_assets(asset_id),
  signed_copy boolean NOT NULL DEFAULT false,
  authorises_work boolean NOT NULL DEFAULT false CHECK(NOT authorises_work),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK((state='draft')=(rendered_asset_id IS NULL)),
  CHECK(NOT signed_copy OR rendered_asset_id IS NOT NULL),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
-- Site visit: a company scoped expert record. It never merges with the private
-- notebook and carries no health or clinical field.
CREATE TABLE private_isg.site_visits (
  visit_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL, workplace_id uuid NOT NULL,
  visited_on date NOT NULL CHECK(isfinite(visited_on)),
  location_note text CHECK(location_note IS NULL OR length(location_note)<=300),
  expert_note text NOT NULL CHECK(btrim(expert_note)<>'' AND length(expert_note)<=4000),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
CREATE TABLE private_isg.site_visit_observations (
  observation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  visit_id uuid NOT NULL REFERENCES private_isg.site_visits(visit_id) ON DELETE CASCADE,
  note text NOT NULL CHECK(btrim(note)<>'' AND length(note)<=2000),
  evidence_asset_id uuid REFERENCES private_isg.file_assets(asset_id),
  nonconformity_id uuid REFERENCES private_isg.nonconformities(nonconformity_id) ON DELETE SET NULL,
  external_ref text, created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(visit_id,external_ref)
);
-- Approved notebook archive: only a scanned, signed copy is the record. An AI
-- draft may be referenced as provenance and is never the official entry.
CREATE TABLE private_isg.notebook_archive_entries (
  entry_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL, workplace_id uuid NOT NULL,
  notebook_ref text NOT NULL CHECK(btrim(notebook_ref)<>'' AND length(notebook_ref)<=200),
  entry_on date NOT NULL CHECK(isfinite(entry_on)),
  asset_id uuid NOT NULL REFERENCES private_isg.file_assets(asset_id),
  ai_draft_ref text CHECK(ai_draft_ref IS NULL OR length(ai_draft_ref)<=200),
  ai_text_is_official_record boolean NOT NULL DEFAULT false CHECK(NOT ai_text_is_official_record),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id,notebook_ref,entry_on),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
CREATE INDEX katip_scope_idx ON private_isg.katip_contracts(company_id,workplace_id,state);
CREATE INDEX katip_owner_idx ON private_isg.katip_contracts(company_id,owner_id);
CREATE INDEX katip_asset_idx ON private_isg.katip_contracts(asset_id);
CREATE INDEX work_plan_owner_idx ON private_isg.annual_work_plans(company_id,owner_id);
CREATE INDEX work_plan_item_state_idx ON private_isg.annual_work_plan_items(plan_id,state);
CREATE INDEX work_plan_item_carry_idx ON private_isg.annual_work_plan_items(carried_to_plan_id);
CREATE INDEX training_plan_owner_idx ON private_isg.annual_training_plans(company_id,owner_id);
CREATE INDEX training_plan_realised_idx ON private_isg.annual_training_plans(realised_plan_id);
CREATE INDEX board_scope_idx ON private_isg.board_meetings(company_id,workplace_id,state);
CREATE INDEX board_owner_idx ON private_isg.board_meetings(company_id,owner_id);
CREATE INDEX board_asset_idx ON private_isg.board_meetings(minutes_asset_id);
CREATE INDEX permit_scope_idx ON private_isg.work_permit_forms(company_id,workplace_id,state);
CREATE INDEX permit_owner_idx ON private_isg.work_permit_forms(company_id,owner_id);
CREATE INDEX permit_asset_idx ON private_isg.work_permit_forms(rendered_asset_id);
CREATE UNIQUE INDEX visit_identity_idx ON private_isg.site_visits(company_id,workplace_id,visited_on,md5(expert_note));
CREATE INDEX visit_scope_idx ON private_isg.site_visits(company_id,workplace_id,visited_on);
CREATE INDEX visit_owner_idx ON private_isg.site_visits(company_id,owner_id);
CREATE INDEX observation_asset_idx ON private_isg.site_visit_observations(evidence_asset_id);
CREATE INDEX observation_nonconformity_idx ON private_isg.site_visit_observations(nonconformity_id);
CREATE INDEX notebook_scope_idx ON private_isg.notebook_archive_entries(company_id,workplace_id,entry_on);
CREATE INDEX notebook_owner_idx ON private_isg.notebook_archive_entries(company_id,owner_id);
CREATE INDEX notebook_asset_idx ON private_isg.notebook_archive_entries(asset_id);
ALTER TABLE private_isg.katip_contracts ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.annual_work_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.annual_work_plan_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.annual_training_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.board_meetings ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.board_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.work_permit_forms ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.site_visits ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.site_visit_observations ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.notebook_archive_entries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.clean_asset(p_asset uuid) RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
BEGIN
  IF p_asset IS NULL THEN RETURN NULL; END IF;
  PERFORM 1 FROM private_isg.file_assets WHERE asset_id=p_asset AND scan_status='clean';
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  RETURN p_asset;
END $$;
CREATE FUNCTION private_isg.record_katip_contract(p_company uuid,p_workplace uuid,p_counterparty text,p_expert text,
  p_scope text,p_starts_on date,p_ends_before date,p_asset uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE owner uuid; contract uuid; existing private_isg.katip_contracts; party text; contract_scope text;
BEGIN
  owner:=private_isg.module_scope('katip_contract',p_company,p_workplace,true);
  IF p_counterparty IS NULL OR p_expert IS NULL OR p_scope IS NULL OR p_starts_on IS NULL OR
     NOT isfinite(p_starts_on) OR p_now IS NULL OR (p_ends_before IS NOT NULL AND p_ends_before<=p_starts_on) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  PERFORM private_isg.clean_asset(p_asset);
  party:=private_isg.text_value(p_counterparty,200); contract_scope:=private_isg.text_value(p_scope,300);
  SELECT * INTO existing FROM private_isg.katip_contracts
    WHERE company_id=p_company AND counterparty=party AND scope=contract_scope AND starts_on=p_starts_on;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'contract_id',existing.contract_id,
    'term_state',existing.term_state,'official_integration',false,'replayed',true); END IF;
  INSERT INTO private_isg.katip_contracts(company_id,owner_id,workplace_id,counterparty,expert_contact,scope,
      starts_on,ends_before,asset_id,created_at,updated_at)
    VALUES(p_company,owner,p_workplace,party,private_isg.text_value(p_expert,200),contract_scope,p_starts_on,p_ends_before,
      p_asset,p_now,p_now) RETURNING contract_id INTO contract;
  RETURN jsonb_build_object('schema_version',1,'contract_id',contract,
    'term_state',CASE WHEN p_ends_before IS NULL THEN 'open_ended' ELSE 'fixed_term' END,
    'official_integration',false,'official_submission_made',false,'replayed',false);
END $$;
CREATE FUNCTION private_isg.open_annual_work_plan(p_company uuid,p_workplace uuid,p_year integer,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE owner uuid; plan uuid; existing private_isg.annual_work_plans;
BEGIN
  owner:=private_isg.module_scope('annual_work_plan',p_company,p_workplace,true);
  IF p_year IS NULL OR p_year NOT BETWEEN 2000 AND 2100 OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO existing FROM private_isg.annual_work_plans
    WHERE company_id=p_company AND workplace_id=p_workplace AND plan_year=p_year;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'plan_id',existing.plan_id,'plan_year',p_year,
    'state',existing.state,'replayed',true); END IF;
  INSERT INTO private_isg.annual_work_plans(company_id,owner_id,workplace_id,plan_year,created_at,updated_at)
    VALUES(p_company,owner,p_workplace,p_year,p_now,p_now) RETURNING plan_id INTO plan;
  RETURN jsonb_build_object('schema_version',1,'plan_id',plan,'plan_year',p_year,'state','active','replayed',false);
END $$;
CREATE FUNCTION private_isg.add_work_plan_item(p_plan uuid,p_activity text,p_responsible text,p_planned_on date,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE plan private_isg.annual_work_plans; item uuid; label text; existing uuid;
BEGIN
  PERFORM private_isg.module_gate('annual_work_plan',true);
  IF p_plan IS NULL OR p_activity IS NULL OR p_planned_on IS NULL OR NOT isfinite(p_planned_on) OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO plan FROM private_isg.annual_work_plans WHERE plan_id=p_plan FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF plan.state<>'active' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PLAN_CLOSED'; END IF;
  -- The planned date belongs to the plan's own calendar year.
  IF extract(year FROM p_planned_on)<>plan.plan_year THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PLAN_YEAR_MISMATCH'; END IF;
  label:=private_isg.text_value(p_activity,300);
  SELECT item_id INTO existing FROM private_isg.annual_work_plan_items
    WHERE plan_id=p_plan AND activity=label AND planned_on=p_planned_on;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'item_id',existing,'replayed',true); END IF;
  INSERT INTO private_isg.annual_work_plan_items(plan_id,activity,responsible_contact,planned_on,created_at,updated_at)
    VALUES(p_plan,label,CASE WHEN p_responsible IS NULL THEN NULL ELSE private_isg.text_value(p_responsible,200) END,
      p_planned_on,p_now,p_now) RETURNING item_id INTO item;
  RETURN jsonb_build_object('schema_version',1,'item_id',item,'state','planned','replayed',false);
END $$;
CREATE FUNCTION private_isg.settle_work_plan_item(p_item uuid,p_state text,p_performed_on date,p_reason text,
  p_carry_to uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.annual_work_plan_items; plan private_isg.annual_work_plans; target private_isg.annual_work_plans;
BEGIN
  PERFORM private_isg.module_gate('annual_work_plan',true);
  IF p_item IS NULL OR p_state IS NULL OR p_now IS NULL OR p_state NOT IN ('performed','carried_over','cancelled') OR
     (p_state='performed')<>(p_performed_on IS NOT NULL) OR (p_state='carried_over')<>(p_carry_to IS NOT NULL) OR
     (p_state<>'performed' AND p_reason IS NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.annual_work_plan_items WHERE item_id=p_item FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state<>'planned' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO plan FROM private_isg.annual_work_plans WHERE plan_id=entry.plan_id FOR SHARE;
  IF p_state='carried_over' THEN
    SELECT * INTO target FROM private_isg.annual_work_plans WHERE plan_id=p_carry_to FOR SHARE;
    -- Carrying over moves an activity to a later plan year, with a reason.
    IF NOT FOUND OR target.company_id<>plan.company_id OR target.workplace_id<>plan.workplace_id OR
       target.plan_year<=plan.plan_year THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CARRY_OVER_INVALID'; END IF;
  END IF;
  UPDATE private_isg.annual_work_plan_items SET state=p_state,performed_on=p_performed_on,
    carry_over_reason=CASE WHEN p_state='performed' THEN NULL ELSE private_isg.text_value(p_reason,1000) END,
    carried_to_plan_id=p_carry_to,updated_at=p_now WHERE item_id=p_item;
  RETURN jsonb_build_object('schema_version',1,'item_id',p_item,'state',p_state,'performed_on',p_performed_on,
    'carried_to_plan_id',p_carry_to);
END $$;
CREATE FUNCTION private_isg.close_annual_work_plan(p_plan uuid,p_closed_on date,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE plan private_isg.annual_work_plans; open_items integer; performed integer;
BEGIN
  PERFORM private_isg.module_gate('annual_work_plan',true);
  IF p_plan IS NULL OR p_closed_on IS NULL OR NOT isfinite(p_closed_on) OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO plan FROM private_isg.annual_work_plans WHERE plan_id=p_plan FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF plan.state='closed' THEN RETURN jsonb_build_object('schema_version',1,'plan_id',p_plan,'state','closed','replayed',true); END IF;
  SELECT count(*) FILTER (WHERE state='planned'),count(*) FILTER (WHERE state='performed')
    INTO open_items,performed FROM private_isg.annual_work_plan_items WHERE plan_id=p_plan;
  UPDATE private_isg.annual_work_plans SET state='closed',closed_on=p_closed_on,updated_at=p_now WHERE plan_id=p_plan;
  -- Closing a plan is an administrative act. It performs nothing.
  RETURN jsonb_build_object('schema_version',1,'plan_id',p_plan,'state','closed','performed_items',performed,
    'still_planned_items',open_items,'items_marked_performed_by_closing',0,'replayed',false);
END $$;
CREATE FUNCTION private_isg.plan_annual_training(p_company uuid,p_workplace uuid,p_year integer,p_catalog text,
  p_target_group text,p_sessions integer,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE owner uuid; plan uuid; existing uuid; target text;
BEGIN
  owner:=private_isg.module_scope('annual_training_plan',p_company,p_workplace,true);
  IF p_year IS NULL OR p_year NOT BETWEEN 2000 AND 2100 OR p_catalog IS NULL OR p_target_group IS NULL OR
     p_sessions IS NULL OR p_sessions NOT BETWEEN 1 AND 500 OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  PERFORM 1 FROM private_isg.training_catalogs WHERE catalog_code=p_catalog;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  target:=private_isg.text_value(p_target_group,200);
  SELECT plan_id INTO existing FROM private_isg.annual_training_plans WHERE company_id=p_company AND
    workplace_id=p_workplace AND plan_year=p_year AND catalog_code=p_catalog AND target_group=target;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'plan_id',existing,'is_training_completion',false,'replayed',true); END IF;
  INSERT INTO private_isg.annual_training_plans(company_id,owner_id,workplace_id,plan_year,catalog_code,target_group,
      planned_sessions,created_at,updated_at)
    VALUES(p_company,owner,p_workplace,p_year,p_catalog,target,p_sessions,p_now,p_now) RETURNING plan_id INTO plan;
  -- An annual training plan is a need, never a completion of any training.
  RETURN jsonb_build_object('schema_version',1,'plan_id',plan,'plan_year',p_year,'state','planned',
    'is_training_completion',false,'replayed',false);
END $$;
CREATE FUNCTION private_isg.link_annual_training_realisation(p_plan uuid,p_training_plan uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.annual_training_plans; training private_isg.training_plans; completions integer;
BEGIN
  PERFORM private_isg.module_gate('annual_training_plan',true);
  IF p_plan IS NULL OR p_training_plan IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.annual_training_plans WHERE plan_id=p_plan FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO training FROM private_isg.training_plans WHERE plan_id=p_training_plan FOR SHARE;
  IF NOT FOUND OR training.company_id<>entry.company_id OR training.workplace_id<>entry.workplace_id THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.realised_plan_id IS NOT NULL THEN
    RETURN jsonb_build_object('schema_version',1,'plan_id',p_plan,'state','realised','replayed',true); END IF;
  UPDATE private_isg.annual_training_plans SET state='realised',realised_plan_id=p_training_plan,updated_at=p_now
    WHERE plan_id=p_plan;
  SELECT count(*) INTO completions FROM private_isg.training_completions c
    JOIN private_isg.training_enrolments e ON e.enrolment_id=c.enrolment_id
    JOIN private_isg.training_sessions s ON s.session_id=e.session_id WHERE s.plan_id=p_training_plan;
  -- Linking records which training plan answered the need; the completions
  -- themselves stay in P07 and are not copied here.
  RETURN jsonb_build_object('schema_version',1,'plan_id',p_plan,'state','realised','training_plan_id',p_training_plan,
    'completions_in_training_domain',completions,'is_training_completion',false,'replayed',false);
END $$;
CREATE FUNCTION private_isg.record_board_meeting(p_company uuid,p_workplace uuid,p_applicability text,p_planned_on date,
  p_agenda jsonb,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE owner uuid; meeting uuid;
BEGIN
  owner:=private_isg.module_scope('board',p_company,p_workplace,true);
  IF p_applicability IS NULL OR p_applicability NOT IN ('mandatory','voluntary') OR p_planned_on IS NULL OR
     NOT isfinite(p_planned_on) OR p_agenda IS NULL OR jsonb_typeof(p_agenda)<>'array' OR
     jsonb_array_length(p_agenda) NOT BETWEEN 1 AND 100 OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  INSERT INTO private_isg.board_meetings(company_id,owner_id,workplace_id,applicability,counts_towards_legal_score,
      planned_on,agenda,created_at,updated_at)
    VALUES(p_company,owner,p_workplace,p_applicability,p_applicability='mandatory',p_planned_on,p_agenda,p_now,p_now)
    RETURNING meeting_id INTO meeting;
  -- Voluntary use is recorded as voluntary and stays out of the legal score.
  RETURN jsonb_build_object('schema_version',1,'meeting_id',meeting,'applicability',p_applicability,
    'counts_towards_legal_score',p_applicability='mandatory','state','planned','creates_account_or_role',false);
END $$;
CREATE FUNCTION private_isg.hold_board_meeting(p_meeting uuid,p_held_on date,p_attendance jsonb,p_asset uuid,
  p_decisions jsonb,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.board_meetings; decision jsonb; ordinal integer:=0;
BEGIN
  PERFORM private_isg.module_gate('board',true);
  IF p_meeting IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.board_meetings WHERE meeting_id=p_meeting FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state='held' THEN RETURN jsonb_build_object('schema_version',1,'meeting_id',p_meeting,'state','held','replayed',true); END IF;
  IF entry.state<>'planned' OR p_held_on IS NULL OR NOT isfinite(p_held_on) OR p_attendance IS NULL OR
     jsonb_typeof(p_attendance)<>'array' OR jsonb_array_length(p_attendance) NOT BETWEEN 1 AND 200 OR
     p_decisions IS NULL OR jsonb_typeof(p_decisions)<>'array' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  PERFORM private_isg.clean_asset(p_asset);
  UPDATE private_isg.board_meetings SET state='held',held_on=p_held_on,attendance=p_attendance,
    minutes_asset_id=p_asset,updated_at=p_now WHERE meeting_id=p_meeting;
  FOR decision IN SELECT * FROM jsonb_array_elements(p_decisions) LOOP
    ordinal:=ordinal+1;
    INSERT INTO private_isg.board_decisions(meeting_id,decision_no,decision_text,responsible_contact,due_on,created_at)
      VALUES(p_meeting,ordinal,private_isg.text_value(decision->>'text',2000),decision->>'responsible',
        (decision->>'due_on')::date,p_now);
  END LOOP;
  RETURN jsonb_build_object('schema_version',1,'meeting_id',p_meeting,'state','held','decisions',ordinal,
    'counts_towards_legal_score',entry.counts_towards_legal_score);
END $$;
CREATE FUNCTION private_isg.draft_work_permit(p_company uuid,p_workplace uuid,p_template text,p_version integer,
  p_job text,p_parties jsonb,p_planned_on date,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE owner uuid; permit uuid;
BEGIN
  owner:=private_isg.module_scope('work_permit',p_company,p_workplace,true);
  IF p_template IS NULL OR p_version IS NULL OR p_job IS NULL OR p_planned_on IS NULL OR NOT isfinite(p_planned_on) OR
     p_parties IS NULL OR jsonb_typeof(p_parties)<>'array' OR jsonb_array_length(p_parties) NOT BETWEEN 1 AND 50 OR
     p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  INSERT INTO private_isg.work_permit_forms(company_id,owner_id,workplace_id,template_code,template_version,
      job_description,parties,planned_on,created_at,updated_at)
    VALUES(p_company,owner,p_workplace,p_template,p_version,private_isg.text_value(p_job,1000),p_parties,p_planned_on,
      p_now,p_now) RETURNING permit_id INTO permit;
  -- This is a form. It does not approve a permit or start any work.
  RETURN jsonb_build_object('schema_version',1,'permit_id',permit,'state','draft','authorises_work',false,
    'approval_workflow',false);
END $$;
CREATE FUNCTION private_isg.render_work_permit(p_permit uuid,p_asset uuid,p_signed boolean,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.work_permit_forms;
BEGIN
  PERFORM private_isg.module_gate('work_permit',true);
  IF p_permit IS NULL OR p_asset IS NULL OR p_signed IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.work_permit_forms WHERE permit_id=p_permit FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state='rendered' THEN RETURN jsonb_build_object('schema_version',1,'permit_id',p_permit,'state','rendered','replayed',true); END IF;
  IF entry.state<>'draft' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  PERFORM private_isg.clean_asset(p_asset);
  UPDATE private_isg.work_permit_forms SET state='rendered',rendered_asset_id=p_asset,signed_copy=p_signed,updated_at=p_now
    WHERE permit_id=p_permit;
  RETURN jsonb_build_object('schema_version',1,'permit_id',p_permit,'state','rendered','signed_copy',p_signed,
    'authorises_work',false,'replayed',false);
END $$;
CREATE FUNCTION private_isg.record_site_visit(p_company uuid,p_workplace uuid,p_visited_on date,p_location text,
  p_note text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE owner uuid; visit uuid; existing uuid; note text;
BEGIN
  owner:=private_isg.module_scope('site_visit',p_company,p_workplace,true);
  IF p_visited_on IS NULL OR NOT isfinite(p_visited_on) OR p_note IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  note:=private_isg.text_value(p_note,4000);
  SELECT visit_id INTO existing FROM private_isg.site_visits WHERE company_id=p_company AND
    workplace_id=p_workplace AND visited_on=p_visited_on AND expert_note=note;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'visit_id',existing,'replayed',true); END IF;
  INSERT INTO private_isg.site_visits(company_id,owner_id,workplace_id,visited_on,location_note,expert_note,created_at)
    VALUES(p_company,owner,p_workplace,p_visited_on,
      CASE WHEN p_location IS NULL THEN NULL ELSE private_isg.text_value(p_location,300) END,note,p_now)
    RETURNING visit_id INTO visit;
  -- A company scoped expert record; it never merges with the private notebook.
  RETURN jsonb_build_object('schema_version',1,'visit_id',visit,'company_scoped',true,
    'merged_with_personal_notes',false,'replayed',false);
END $$;
CREATE FUNCTION private_isg.record_site_observation(p_visit uuid,p_note text,p_asset uuid,p_external_ref text,
  p_open_nonconformity boolean,p_severity text,p_due_on date,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE visit private_isg.site_visits; observation uuid; existing private_isg.site_visit_observations;
  finding jsonb; record_id uuid; reference text;
BEGIN
  PERFORM private_isg.module_gate('site_visit',true);
  IF p_visit IS NULL OR p_note IS NULL OR p_now IS NULL OR p_open_nonconformity IS NULL OR
     (p_open_nonconformity AND p_severity IS NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO visit FROM private_isg.site_visits WHERE visit_id=p_visit FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  PERFORM private_isg.clean_asset(p_asset);
  reference:=CASE WHEN p_external_ref IS NULL THEN NULL ELSE private_isg.text_value(p_external_ref,200) END;
  IF reference IS NOT NULL THEN
    SELECT * INTO existing FROM private_isg.site_visit_observations WHERE visit_id=p_visit AND external_ref=reference;
    IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'observation_id',existing.observation_id,
      'nonconformity_id',existing.nonconformity_id,'replayed',true); END IF;
  END IF;
  IF p_open_nonconformity THEN
    finding:=private_isg.open_nonconformity(visit.company_id,visit.workplace_id,'manual',NULL,
      private_isg.text_value(p_note,300),p_severity,visit.visited_on,p_due_on,p_now);
    record_id:=(finding->>'nonconformity_id')::uuid;
  END IF;
  INSERT INTO private_isg.site_visit_observations(visit_id,note,evidence_asset_id,nonconformity_id,external_ref,created_at)
    VALUES(p_visit,private_isg.text_value(p_note,2000),p_asset,record_id,reference,p_now) RETURNING observation_id INTO observation;
  RETURN jsonb_build_object('schema_version',1,'observation_id',observation,'nonconformity_id',record_id,'replayed',false);
END $$;
-- Only a scanned signed copy is the archived record. An AI draft reference is
-- provenance, never the official entry.
CREATE FUNCTION private_isg.archive_notebook_entry(p_company uuid,p_workplace uuid,p_ref text,p_entry_on date,
  p_asset uuid,p_ai_draft_ref text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE owner uuid; entry uuid; existing uuid; reference text;
BEGIN
  owner:=private_isg.module_scope('notebook_archive',p_company,p_workplace,true);
  IF p_ref IS NULL OR p_entry_on IS NULL OR NOT isfinite(p_entry_on) OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_asset IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SIGNED_COPY_REQUIRED'; END IF;
  PERFORM private_isg.clean_asset(p_asset);
  reference:=private_isg.text_value(p_ref,200);
  SELECT entry_id INTO existing FROM private_isg.notebook_archive_entries
    WHERE company_id=p_company AND notebook_ref=reference AND entry_on=p_entry_on;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'entry_id',existing,'ai_text_is_official_record',false,'replayed',true); END IF;
  INSERT INTO private_isg.notebook_archive_entries(company_id,owner_id,workplace_id,notebook_ref,entry_on,asset_id,
      ai_draft_ref,created_at)
    VALUES(p_company,owner,p_workplace,reference,p_entry_on,p_asset,
      CASE WHEN p_ai_draft_ref IS NULL THEN NULL ELSE private_isg.text_value(p_ai_draft_ref,200) END,p_now)
    RETURNING entry_id INTO entry;
  RETURN jsonb_build_object('schema_version',1,'entry_id',entry,'has_signed_copy',true,
    'ai_draft_ref',p_ai_draft_ref,'ai_text_is_official_record',false,'replayed',false);
END $$;
REVOKE ALL ON FUNCTION private_isg.clean_asset(uuid),
  private_isg.record_katip_contract(uuid,uuid,text,text,text,date,date,uuid,timestamptz),
  private_isg.open_annual_work_plan(uuid,uuid,integer,timestamptz),
  private_isg.add_work_plan_item(uuid,text,text,date,timestamptz),
  private_isg.settle_work_plan_item(uuid,text,date,text,uuid,timestamptz),
  private_isg.close_annual_work_plan(uuid,date,timestamptz),
  private_isg.plan_annual_training(uuid,uuid,integer,text,text,integer,timestamptz),
  private_isg.link_annual_training_realisation(uuid,uuid,timestamptz),
  private_isg.record_board_meeting(uuid,uuid,text,date,jsonb,timestamptz),
  private_isg.hold_board_meeting(uuid,date,jsonb,uuid,jsonb,timestamptz),
  private_isg.draft_work_permit(uuid,uuid,text,integer,text,jsonb,date,timestamptz),
  private_isg.render_work_permit(uuid,uuid,boolean,timestamptz),
  private_isg.record_site_visit(uuid,uuid,date,text,text,timestamptz),
  private_isg.record_site_observation(uuid,text,uuid,text,boolean,text,date,timestamptz),
  private_isg.archive_notebook_entry(uuid,uuid,text,date,uuid,text,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
