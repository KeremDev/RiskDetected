-- P10 first slice: four §7.5 modules with their own domain rules, behind their
-- own per-module switches. "There is shared CRUD" never excuses skipping a
-- module rule, so each module keeps real columns, real constraints and its own
-- refusal codes. Additive; rollout OFF; no client grant.
BEGIN;
SET LOCAL lock_timeout='5s';
CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA extensions;
ALTER TABLE private_isg.rollout DROP CONSTRAINT rollout_feature_check;
ALTER TABLE private_isg.rollout ADD CONSTRAINT rollout_feature_check
  CHECK(feature IN ('personnel','event_dispatch','quota_ledger','file_core','rule_engine','training','risk','nonconformity','modules'));
INSERT INTO private_isg.rollout(feature) VALUES('modules');
-- Per-module switch on top of the feature gate: pausing one module must never
-- pause another, and read-only is a state of its own.
CREATE TABLE private_isg.module_registry (
  module text PRIMARY KEY CHECK(module IN ('emergency_plan','drill','equipment','ppe','appointment')),
  read_enabled boolean NOT NULL DEFAULT false,
  write_enabled boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK(NOT write_enabled OR read_enabled)
);
INSERT INTO private_isg.module_registry(module) VALUES
  ('emergency_plan'),('drill'),('equipment'),('ppe'),('appointment');

-- Emergency plan: a renewal is a new version. The previous document keeps its
-- own team snapshot and file; unknown legislation stays in review.
CREATE TABLE private_isg.emergency_plan_versions (
  plan_id uuid NOT NULL DEFAULT gen_random_uuid(),
  version integer NOT NULL CHECK(version BETWEEN 1 AND 1000),
  company_id uuid NOT NULL, owner_id uuid NOT NULL, workplace_id uuid NOT NULL,
  scope text NOT NULL CHECK(btrim(scope)<>'' AND length(scope)<=300),
  prepared_on date NOT NULL CHECK(isfinite(prepared_on)),
  valid_until date CHECK(valid_until IS NULL OR isfinite(valid_until)),
  team_snapshot jsonb NOT NULL, asset_id uuid REFERENCES private_isg.file_assets(asset_id),
  state text NOT NULL DEFAULT 'active' CHECK(state IN ('active','superseded')),
  needs_review boolean NOT NULL DEFAULT true, review_note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(plan_id,version),
  UNIQUE(company_id,plan_id,version),
  CHECK(valid_until IS NULL OR valid_until>prepared_on),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX emergency_plan_single_active_idx ON private_isg.emergency_plan_versions(plan_id) WHERE state='active';
-- Drill: planning is not performing. A planned row carries no realisation date.
CREATE TABLE private_isg.drill_records (
  drill_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, workplace_id uuid NOT NULL,
  plan_id uuid NOT NULL, plan_version integer NOT NULL,
  planned_on date NOT NULL CHECK(isfinite(planned_on)),
  performed_on date CHECK(performed_on IS NULL OR isfinite(performed_on)),
  state text NOT NULL DEFAULT 'planned' CHECK(state IN ('planned','performed','cancelled')),
  participants jsonb, observation text, improvement text, cancelled_reason text,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK((state='performed')=(performed_on IS NOT NULL)),
  CHECK((state='performed')=(participants IS NOT NULL)),
  CHECK((state='cancelled')=(cancelled_reason IS NOT NULL)),
  FOREIGN KEY(company_id,plan_id,plan_version) REFERENCES private_isg.emergency_plan_versions(company_id,plan_id,version),
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
-- Equipment: the inspection period belongs to the equipment type, never one
-- fixed year for everything, and an exception is written down, not hidden.
CREATE TABLE private_isg.equipment_items (
  equipment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL, workplace_id uuid NOT NULL,
  equipment_type text NOT NULL CHECK(equipment_type ~ '^[a-z][a-z0-9_]{2,40}$'),
  serial_tag text NOT NULL CHECK(btrim(serial_tag)<>'' AND length(serial_tag)<=100),
  acquired_on date CHECK(acquired_on IS NULL OR isfinite(acquired_on)),
  is_archived boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id,serial_tag),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
CREATE TABLE private_isg.equipment_inspection_rules (
  company_id uuid NOT NULL, equipment_type text NOT NULL,
  period_months integer NOT NULL CHECK(period_months BETWEEN 1 AND 240),
  period_source text NOT NULL CHECK(period_source IN ('manufacturer','rule_version','unapproved_fixture')),
  exception_note text CHECK(exception_note IS NULL OR length(exception_note) BETWEEN 10 AND 1000),
  needs_review boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(company_id,equipment_type),
  CHECK(period_source<>'unapproved_fixture' OR needs_review)
);
CREATE TABLE private_isg.equipment_inspections (
  inspection_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  equipment_id uuid NOT NULL REFERENCES private_isg.equipment_items(equipment_id) ON DELETE CASCADE,
  performed_on date NOT NULL CHECK(isfinite(performed_on)),
  result text NOT NULL CHECK(result IN ('pass','fail','conditional')),
  next_due_on date CHECK(next_due_on IS NULL OR isfinite(next_due_on)),
  period_months integer CHECK(period_months IS NULL OR period_months BETWEEN 1 AND 240),
  evidence_asset_id uuid REFERENCES private_isg.file_assets(asset_id),
  external_ref text CHECK(external_ref IS NULL OR length(external_ref)<=200),
  note text, created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(equipment_id,performed_on),
  CHECK(next_due_on IS NULL OR next_due_on>performed_on)
);
-- Appointment: the same person can not hold two overlapping appointments of the
-- same kind in the same scope.
CREATE TABLE private_isg.appointments (
  appointment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, employee_id uuid NOT NULL,
  kind text NOT NULL CHECK(kind IN ('representative','support_staff','team_member','first_aid','fire_team')),
  scope_workplace_id uuid NOT NULL,
  starts_on date NOT NULL CHECK(isfinite(starts_on)),
  ends_before date CHECK(ends_before IS NULL OR isfinite(ends_before)),
  effective_dates daterange GENERATED ALWAYS AS(daterange(starts_on,ends_before,'[)')) STORED,
  asset_id uuid REFERENCES private_isg.file_assets(asset_id),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK(ends_before IS NULL OR starts_on<ends_before),
  FOREIGN KEY(company_id,employee_id) REFERENCES private_isg.employees(company_id,id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,scope_workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE,
  EXCLUDE USING gist(company_id WITH =,employee_id WITH =,kind WITH =,scope_workplace_id WITH =,effective_dates WITH &&)
);
-- PPE: quantities are positive, a return can not precede its handover and can
-- not exceed it, and a signed copy is recorded, never assumed.
CREATE TABLE private_isg.ppe_handovers (
  handover_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, employee_id uuid NOT NULL,
  item text NOT NULL CHECK(btrim(item)<>'' AND length(item)<=200),
  quantity numeric(12,3) NOT NULL CHECK(quantity>0),
  unit text NOT NULL CHECK(unit IN ('piece','pair','set','metre','litre')),
  handed_on date NOT NULL CHECK(isfinite(handed_on)),
  evidence_asset_id uuid REFERENCES private_isg.file_assets(asset_id),
  signed_copy boolean NOT NULL DEFAULT false,
  external_ref text CHECK(external_ref IS NULL OR length(external_ref)<=200),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id,employee_id,external_ref),
  CHECK(NOT signed_copy OR evidence_asset_id IS NOT NULL),
  FOREIGN KEY(company_id,employee_id) REFERENCES private_isg.employees(company_id,id) ON DELETE CASCADE
);
CREATE TABLE private_isg.ppe_returns (
  return_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  handover_id uuid NOT NULL REFERENCES private_isg.ppe_handovers(handover_id) ON DELETE CASCADE,
  quantity numeric(12,3) NOT NULL CHECK(quantity>0),
  returned_on date NOT NULL CHECK(isfinite(returned_on)),
  condition text NOT NULL CHECK(condition IN ('reusable','worn','damaged','lost')),
  note text, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX emergency_plan_scope_idx ON private_isg.emergency_plan_versions(company_id,workplace_id,state);
CREATE INDEX emergency_plan_owner_idx ON private_isg.emergency_plan_versions(company_id,owner_id);
CREATE INDEX emergency_plan_asset_idx ON private_isg.emergency_plan_versions(asset_id);
CREATE INDEX drill_scope_idx ON private_isg.drill_records(company_id,workplace_id,state);
CREATE INDEX drill_plan_idx ON private_isg.drill_records(company_id,plan_id,plan_version);
CREATE INDEX equipment_scope_idx ON private_isg.equipment_items(company_id,workplace_id,is_archived);
CREATE INDEX equipment_owner_idx ON private_isg.equipment_items(company_id,owner_id);
CREATE INDEX equipment_type_idx ON private_isg.equipment_items(company_id,equipment_type);
CREATE INDEX inspection_due_idx ON private_isg.equipment_inspections(equipment_id,next_due_on);
CREATE INDEX inspection_asset_idx ON private_isg.equipment_inspections(evidence_asset_id);
CREATE INDEX appointment_employee_idx ON private_isg.appointments(company_id,employee_id,kind);
CREATE INDEX appointment_scope_idx ON private_isg.appointments(company_id,scope_workplace_id);
CREATE INDEX appointment_asset_idx ON private_isg.appointments(asset_id);
CREATE INDEX ppe_employee_idx ON private_isg.ppe_handovers(company_id,employee_id);
CREATE INDEX ppe_asset_idx ON private_isg.ppe_handovers(evidence_asset_id);
CREATE INDEX ppe_return_idx ON private_isg.ppe_returns(handover_id);
ALTER TABLE private_isg.module_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.emergency_plan_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.drill_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.equipment_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.equipment_inspection_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.equipment_inspections ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.ppe_handovers ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.ppe_returns ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.module_gate(p_module text,p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM private_isg.rollout WHERE feature='modules' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  PERFORM 1 FROM private_isg.module_registry WHERE module=p_module AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='MODULE_UNAVAILABLE'; END IF;
END $$;
CREATE FUNCTION private_isg.module_scope(p_module text,p_company uuid,p_workplace uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE owner uuid;
BEGIN
  PERFORM private_isg.module_gate(p_module,p_write);
  IF p_company IS NULL OR p_workplace IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT owner_id INTO owner FROM private_isg.workplaces WHERE company_id=p_company AND id=p_workplace FOR SHARE;
  IF owner IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  RETURN owner;
END $$;
CREATE FUNCTION private_isg.publish_emergency_plan(p_company uuid,p_workplace uuid,p_plan uuid,p_scope text,
  p_prepared_on date,p_valid_until date,p_team jsonb,p_asset uuid,p_review_note text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE owner uuid; plan uuid; next_version integer; review boolean; previous integer;
BEGIN
  owner:=private_isg.module_scope('emergency_plan',p_company,p_workplace,true);
  IF p_scope IS NULL OR p_prepared_on IS NULL OR NOT isfinite(p_prepared_on) OR p_now IS NULL OR
     p_team IS NULL OR jsonb_typeof(p_team)<>'array' OR jsonb_array_length(p_team) NOT BETWEEN 1 AND 200 OR
     (p_valid_until IS NOT NULL AND p_valid_until<=p_prepared_on) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_asset IS NOT NULL THEN
    PERFORM 1 FROM private_isg.file_assets WHERE asset_id=p_asset AND scan_status='clean' FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  -- An unverified legal basis stays in review; it is never silently accepted.
  review:=p_review_note IS NULL;
  plan:=coalesce(p_plan,gen_random_uuid());
  SELECT coalesce(max(version),0) INTO previous FROM private_isg.emergency_plan_versions WHERE plan_id=plan;
  IF p_plan IS NOT NULL AND previous=0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  next_version:=previous+1;
  -- Renewing supersedes the pointer only. The previous row keeps its own scope,
  -- team snapshot, dates and file.
  UPDATE private_isg.emergency_plan_versions SET state='superseded' WHERE plan_id=plan AND state='active';
  INSERT INTO private_isg.emergency_plan_versions(plan_id,version,company_id,owner_id,workplace_id,scope,prepared_on,
      valid_until,team_snapshot,asset_id,needs_review,review_note,created_at)
    VALUES(plan,next_version,p_company,owner,p_workplace,private_isg.text_value(p_scope,300),p_prepared_on,
      p_valid_until,p_team,p_asset,review,p_review_note,p_now);
  RETURN jsonb_build_object('schema_version',1,'plan_id',plan,'version',next_version,'state','active',
    'needs_review',review,'previous_version',nullif(previous,0));
END $$;
CREATE FUNCTION private_isg.plan_drill(p_company uuid,p_workplace uuid,p_plan uuid,p_plan_version integer,
  p_planned_on date,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE drill uuid;
BEGIN
  PERFORM private_isg.module_scope('drill',p_company,p_workplace,true);
  IF p_plan IS NULL OR p_plan_version IS NULL OR p_planned_on IS NULL OR NOT isfinite(p_planned_on) OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  PERFORM 1 FROM private_isg.emergency_plan_versions
    WHERE company_id=p_company AND plan_id=p_plan AND version=p_plan_version FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  INSERT INTO private_isg.drill_records(company_id,workplace_id,plan_id,plan_version,planned_on,created_at,updated_at)
    VALUES(p_company,p_workplace,p_plan,p_plan_version,p_planned_on,p_now,p_now) RETURNING drill_id INTO drill;
  -- Planning a drill is not performing one.
  RETURN jsonb_build_object('schema_version',1,'drill_id',drill,'state','planned','performed',false);
END $$;
CREATE FUNCTION private_isg.record_drill_result(p_drill uuid,p_performed_on date,p_participants jsonb,
  p_observation text,p_improvement text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.drill_records; known integer; supplied integer;
BEGIN
  IF p_drill IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.drill_records WHERE drill_id=p_drill FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  PERFORM private_isg.module_gate('drill',true);
  IF entry.state='performed' THEN RETURN jsonb_build_object('schema_version',1,'drill_id',p_drill,'state','performed','replayed',true); END IF;
  IF entry.state<>'planned' OR p_performed_on IS NULL OR NOT isfinite(p_performed_on) OR
     p_participants IS NULL OR jsonb_typeof(p_participants)<>'array' OR
     jsonb_array_length(p_participants) NOT BETWEEN 1 AND 500 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  -- Participants are this company's own employees; an outside id is refused.
  SELECT count(DISTINCT value) INTO supplied FROM jsonb_array_elements_text(p_participants) AS t(value);
  SELECT count(*) INTO known FROM private_isg.employees e
    WHERE e.company_id=entry.company_id
      AND e.id::text IN (SELECT value FROM jsonb_array_elements_text(p_participants) AS t(value));
  IF known<>supplied THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PARTICIPANT_OUT_OF_SCOPE'; END IF;
  UPDATE private_isg.drill_records SET state='performed',performed_on=p_performed_on,participants=p_participants,
    observation=p_observation,improvement=p_improvement,updated_at=p_now WHERE drill_id=p_drill;
  RETURN jsonb_build_object('schema_version',1,'drill_id',p_drill,'state','performed','performed_on',p_performed_on,
    'participants',supplied,'replayed',false);
END $$;
CREATE FUNCTION private_isg.set_equipment_inspection_rule(p_company uuid,p_type text,p_period_months integer,
  p_source text,p_exception text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE review boolean;
BEGIN
  PERFORM private_isg.module_gate('equipment',true);
  IF p_company IS NULL OR p_type IS NULL OR p_period_months IS NULL OR p_source IS NULL OR p_now IS NULL OR
     p_period_months NOT BETWEEN 1 AND 240 OR p_source NOT IN ('manufacturer','rule_version','unapproved_fixture') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  PERFORM 1 FROM public.companies WHERE id=p_company FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  review:=p_source='unapproved_fixture';
  INSERT INTO private_isg.equipment_inspection_rules(company_id,equipment_type,period_months,period_source,
      exception_note,needs_review,created_at)
    VALUES(p_company,p_type,p_period_months,p_source,p_exception,review,p_now)
  ON CONFLICT(company_id,equipment_type) DO UPDATE SET period_months=excluded.period_months,
    period_source=excluded.period_source,exception_note=excluded.exception_note,needs_review=excluded.needs_review;
  RETURN jsonb_build_object('schema_version',1,'equipment_type',p_type,'period_months',p_period_months,
    'period_source',p_source,'needs_review',review,'exception_note',p_exception);
END $$;
CREATE FUNCTION private_isg.register_equipment(p_company uuid,p_workplace uuid,p_type text,p_serial text,
  p_acquired_on date,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE owner uuid; equipment uuid; existing uuid; tag text;
BEGIN
  owner:=private_isg.module_scope('equipment',p_company,p_workplace,true);
  IF p_type IS NULL OR p_serial IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  tag:=private_isg.text_value(p_serial,100);
  SELECT equipment_id INTO existing FROM private_isg.equipment_items WHERE company_id=p_company AND serial_tag=tag;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'equipment_id',existing,'replayed',true); END IF;
  INSERT INTO private_isg.equipment_items(company_id,owner_id,workplace_id,equipment_type,serial_tag,acquired_on,created_at)
    VALUES(p_company,owner,p_workplace,p_type,tag,p_acquired_on,p_now) RETURNING equipment_id INTO equipment;
  RETURN jsonb_build_object('schema_version',1,'equipment_id',equipment,'equipment_type',p_type,'replayed',false);
END $$;
CREATE FUNCTION private_isg.record_equipment_inspection(p_equipment uuid,p_performed_on date,p_result text,
  p_asset uuid,p_external_ref text,p_note text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE item private_isg.equipment_items; rule private_isg.equipment_inspection_rules;
  inspection uuid; existing private_isg.equipment_inspections; due date;
BEGIN
  PERFORM private_isg.module_gate('equipment',true);
  IF p_equipment IS NULL OR p_performed_on IS NULL OR NOT isfinite(p_performed_on) OR p_result IS NULL OR
     p_now IS NULL OR p_result NOT IN ('pass','fail','conditional') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO item FROM private_isg.equipment_items WHERE equipment_id=p_equipment FOR SHARE;
  IF NOT FOUND OR item.is_archived THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF p_asset IS NOT NULL THEN
    PERFORM 1 FROM private_isg.file_assets WHERE asset_id=p_asset AND scan_status='clean' FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  SELECT * INTO existing FROM private_isg.equipment_inspections
    WHERE equipment_id=p_equipment AND performed_on=p_performed_on;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'inspection_id',existing.inspection_id,
    'next_due_on',existing.next_due_on,'replayed',true); END IF;
  SELECT * INTO rule FROM private_isg.equipment_inspection_rules
    WHERE company_id=item.company_id AND equipment_type=item.equipment_type FOR SHARE;
  -- No type rule means no invented due date: the period is unknown, not a year.
  IF FOUND AND p_result<>'fail' THEN
    due:=(p_performed_on+make_interval(months=>rule.period_months))::date; END IF;
  INSERT INTO private_isg.equipment_inspections(equipment_id,performed_on,result,next_due_on,period_months,
      evidence_asset_id,external_ref,note,created_at)
    VALUES(p_equipment,p_performed_on,p_result,due,rule.period_months,p_asset,p_external_ref,p_note,p_now)
    RETURNING inspection_id INTO inspection;
  RETURN jsonb_build_object('schema_version',1,'inspection_id',inspection,'result',p_result,'next_due_on',due,
    'period_months',rule.period_months,'period_source',rule.period_source,
    'period_needs_review',coalesce(rule.needs_review,true),'exception_note',rule.exception_note,'replayed',false);
END $$;
CREATE FUNCTION private_isg.record_appointment(p_company uuid,p_employee uuid,p_kind text,p_workplace uuid,
  p_starts_on date,p_ends_before date,p_asset uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE appointment uuid;
BEGIN
  PERFORM private_isg.module_scope('appointment',p_company,p_workplace,true);
  IF p_employee IS NULL OR p_kind IS NULL OR p_starts_on IS NULL OR NOT isfinite(p_starts_on) OR p_now IS NULL OR
     p_kind NOT IN ('representative','support_staff','team_member','first_aid','fire_team') OR
     (p_ends_before IS NOT NULL AND p_ends_before<=p_starts_on) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  PERFORM 1 FROM private_isg.employees WHERE company_id=p_company AND id=p_employee AND NOT is_archived FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF p_asset IS NOT NULL THEN
    PERFORM 1 FROM private_isg.file_assets WHERE asset_id=p_asset AND scan_status='clean' FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  BEGIN
    INSERT INTO private_isg.appointments(company_id,employee_id,kind,scope_workplace_id,starts_on,ends_before,asset_id,created_at,updated_at)
      VALUES(p_company,p_employee,p_kind,p_workplace,p_starts_on,p_ends_before,p_asset,p_now,p_now)
      RETURNING appointment_id INTO appointment;
  EXCEPTION WHEN exclusion_violation THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='APPOINTMENT_OVERLAP';
  END;
  RETURN jsonb_build_object('schema_version',1,'appointment_id',appointment,'kind',p_kind,'starts_on',p_starts_on,
    'ends_before',p_ends_before);
END $$;
CREATE FUNCTION private_isg.end_appointment(p_appointment uuid,p_ends_before date,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.appointments;
BEGIN
  PERFORM private_isg.module_gate('appointment',true);
  IF p_appointment IS NULL OR p_ends_before IS NULL OR NOT isfinite(p_ends_before) OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.appointments WHERE appointment_id=p_appointment FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.ends_before IS NOT NULL AND entry.ends_before=p_ends_before THEN
    RETURN jsonb_build_object('schema_version',1,'appointment_id',p_appointment,'ends_before',p_ends_before,'replayed',true); END IF;
  IF p_ends_before<=entry.starts_on THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  BEGIN
    UPDATE private_isg.appointments SET ends_before=p_ends_before,updated_at=p_now WHERE appointment_id=p_appointment;
  EXCEPTION WHEN exclusion_violation THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='APPOINTMENT_OVERLAP';
  END;
  RETURN jsonb_build_object('schema_version',1,'appointment_id',p_appointment,'ends_before',p_ends_before,'replayed',false);
END $$;
CREATE FUNCTION private_isg.record_ppe_handover(p_company uuid,p_employee uuid,p_item text,p_quantity numeric,
  p_unit text,p_handed_on date,p_asset uuid,p_signed boolean,p_external_ref text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE handover uuid; existing uuid; reference text;
BEGIN
  PERFORM private_isg.module_gate('ppe',true);
  IF p_company IS NULL OR p_employee IS NULL OR p_item IS NULL OR p_quantity IS NULL OR p_quantity<=0 OR
     p_unit IS NULL OR p_unit NOT IN ('piece','pair','set','metre','litre') OR p_handed_on IS NULL OR
     NOT isfinite(p_handed_on) OR p_signed IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  PERFORM 1 FROM private_isg.employees WHERE company_id=p_company AND id=p_employee FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  -- A signed copy is a recorded document, never an assumption.
  IF p_signed AND p_asset IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SIGNED_COPY_REQUIRED'; END IF;
  IF p_asset IS NOT NULL THEN
    PERFORM 1 FROM private_isg.file_assets WHERE asset_id=p_asset AND scan_status='clean' FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  reference:=CASE WHEN p_external_ref IS NULL THEN NULL ELSE private_isg.text_value(p_external_ref,200) END;
  IF reference IS NOT NULL THEN
    SELECT handover_id INTO existing FROM private_isg.ppe_handovers
      WHERE company_id=p_company AND employee_id=p_employee AND external_ref=reference;
    IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'handover_id',existing,'replayed',true); END IF;
  END IF;
  INSERT INTO private_isg.ppe_handovers(company_id,employee_id,item,quantity,unit,handed_on,evidence_asset_id,
      signed_copy,external_ref,created_at)
    VALUES(p_company,p_employee,private_isg.text_value(p_item,200),p_quantity,p_unit,p_handed_on,p_asset,p_signed,
      reference,p_now) RETURNING handover_id INTO handover;
  RETURN jsonb_build_object('schema_version',1,'handover_id',handover,'quantity',p_quantity,'signed_copy',p_signed,'replayed',false);
END $$;
CREATE FUNCTION private_isg.record_ppe_return(p_handover uuid,p_quantity numeric,p_returned_on date,
  p_condition text,p_note text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.ppe_handovers; returned numeric; record_id uuid;
BEGIN
  PERFORM private_isg.module_gate('ppe',true);
  IF p_handover IS NULL OR p_quantity IS NULL OR p_quantity<=0 OR p_returned_on IS NULL OR
     NOT isfinite(p_returned_on) OR p_condition IS NULL OR p_now IS NULL OR
     p_condition NOT IN ('reusable','worn','damaged','lost') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.ppe_handovers WHERE handover_id=p_handover FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  -- Nothing comes back before it was handed out.
  IF p_returned_on<entry.handed_on THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RETURN_BEFORE_HANDOVER'; END IF;
  SELECT coalesce(sum(quantity),0) INTO returned FROM private_isg.ppe_returns WHERE handover_id=p_handover;
  IF returned+p_quantity>entry.quantity THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RETURN_EXCEEDS_HANDOVER'; END IF;
  INSERT INTO private_isg.ppe_returns(handover_id,quantity,returned_on,condition,note,created_at)
    VALUES(p_handover,p_quantity,p_returned_on,p_condition,p_note,p_now) RETURNING return_id INTO record_id;
  RETURN jsonb_build_object('schema_version',1,'return_id',record_id,'returned_total',returned+p_quantity,
    'handed_quantity',entry.quantity,'outstanding',entry.quantity-(returned+p_quantity));
END $$;
REVOKE ALL ON FUNCTION private_isg.module_gate(text,boolean),private_isg.module_scope(text,uuid,uuid,boolean),
  private_isg.publish_emergency_plan(uuid,uuid,uuid,text,date,date,jsonb,uuid,text,timestamptz),
  private_isg.plan_drill(uuid,uuid,uuid,integer,date,timestamptz),
  private_isg.record_drill_result(uuid,date,jsonb,text,text,timestamptz),
  private_isg.set_equipment_inspection_rule(uuid,text,integer,text,text,timestamptz),
  private_isg.register_equipment(uuid,uuid,text,text,date,timestamptz),
  private_isg.record_equipment_inspection(uuid,date,text,uuid,text,text,timestamptz),
  private_isg.record_appointment(uuid,uuid,text,uuid,date,date,uuid,timestamptz),
  private_isg.end_appointment(uuid,date,timestamptz),
  private_isg.record_ppe_handover(uuid,uuid,text,numeric,text,date,uuid,boolean,text,timestamptz),
  private_isg.record_ppe_return(uuid,numeric,date,text,text,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
