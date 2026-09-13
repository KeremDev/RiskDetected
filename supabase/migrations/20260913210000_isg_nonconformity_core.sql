-- P09/D09 first slice: a server-defined nonconformity state machine, corrective
-- actions, expert verification, and versioned checklist templates whose runs
-- snapshot the version they were filled with.
-- Additive; rollout OFF; no client grant. The legacy findings table is never
-- read for authority and never written: its is_resolved flag closes nothing here.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE private_isg.rollout DROP CONSTRAINT rollout_feature_check;
ALTER TABLE private_isg.rollout ADD CONSTRAINT rollout_feature_check
  CHECK(feature IN ('personnel','event_dispatch','quota_ledger','file_core','rule_engine','training','risk','nonconformity'));
INSERT INTO private_isg.rollout(feature) VALUES('nonconformity');

-- The transition matrix is data, not scattered IF branches, so every allowed
-- and forbidden edge can be enumerated and tested.
CREATE TABLE private_isg.nonconformity_state_edges (
  from_state text NOT NULL, to_state text NOT NULL,
  requires_reason boolean NOT NULL DEFAULT false,
  requires_assignee boolean NOT NULL DEFAULT false,
  requires_verification boolean NOT NULL DEFAULT false,
  PRIMARY KEY(from_state,to_state),
  CHECK(from_state<>to_state),
  CHECK(from_state IN ('draft','open','assigned','in_progress','pending_verification','closed','reopened','cancelled')),
  CHECK(to_state IN ('draft','open','assigned','in_progress','pending_verification','closed','reopened','cancelled'))
);
INSERT INTO private_isg.nonconformity_state_edges(from_state,to_state,requires_reason,requires_assignee,requires_verification) VALUES
  ('draft','open',false,false,false),('draft','cancelled',true,false,false),
  ('open','assigned',false,true,false),('open','cancelled',true,false,false),
  ('assigned','in_progress',false,false,false),('assigned','open',true,false,false),('assigned','cancelled',true,false,false),
  ('in_progress','pending_verification',false,false,false),('in_progress','assigned',true,true,false),('in_progress','cancelled',true,false,false),
  ('pending_verification','closed',false,false,true),('pending_verification','in_progress',true,false,false),
  ('closed','reopened',true,false,false),
  ('reopened','assigned',false,true,false),('reopened','in_progress',false,false,false),('reopened','cancelled',true,false,false);
CREATE TABLE private_isg.nonconformities (
  nonconformity_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL, workplace_id uuid NOT NULL,
  source_kind text NOT NULL CHECK(source_kind IN ('checklist','risk_version','legacy_finding','manual')),
  source_ref text CHECK(source_ref IS NULL OR (btrim(source_ref)<>'' AND length(source_ref)<=200)),
  title text NOT NULL CHECK(btrim(title)<>'' AND length(title)<=300),
  severity text NOT NULL CHECK(severity IN ('low','medium','high','critical')),
  opened_on date NOT NULL CHECK(isfinite(opened_on)),
  due_on date CHECK(due_on IS NULL OR isfinite(due_on)),
  -- A report person, never a new application user: no FK to profiles or auth.
  assignee_contact text CHECK(assignee_contact IS NULL OR (btrim(assignee_contact)<>'' AND length(assignee_contact)<=200)),
  state text NOT NULL DEFAULT 'draft'
    CHECK(state IN ('draft','open','assigned','in_progress','pending_verification','closed','reopened','cancelled')),
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  closed_on date CHECK(closed_on IS NULL OR isfinite(closed_on)),
  cancelled_reason text,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK((state='closed')=(closed_on IS NOT NULL)),
  CHECK(due_on IS NULL OR due_on>=opened_on),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
-- One nonconformity per source reference: clicking twice creates nothing new.
CREATE UNIQUE INDEX nonconformity_source_idx ON private_isg.nonconformities(company_id,source_kind,source_ref)
  WHERE source_ref IS NOT NULL;
CREATE TABLE private_isg.nonconformity_transitions (
  transition_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nonconformity_id uuid NOT NULL REFERENCES private_isg.nonconformities(nonconformity_id) ON DELETE CASCADE,
  version bigint NOT NULL, from_state text NOT NULL, to_state text NOT NULL,
  reason text CHECK(reason IS NULL OR length(reason) BETWEEN 5 AND 2000),
  actor_id uuid NOT NULL REFERENCES public.profiles(id), occurred_at timestamptz NOT NULL,
  UNIQUE(nonconformity_id,version)
);
CREATE TABLE private_isg.nonconformity_actions (
  action_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nonconformity_id uuid NOT NULL REFERENCES private_isg.nonconformities(nonconformity_id) ON DELETE CASCADE,
  description text NOT NULL CHECK(btrim(description)<>'' AND length(description)<=1000),
  assignee_contact text CHECK(assignee_contact IS NULL OR length(assignee_contact)<=200),
  due_on date CHECK(due_on IS NULL OR isfinite(due_on)),
  state text NOT NULL DEFAULT 'planned' CHECK(state IN ('planned','in_progress','done','cancelled')),
  external_ref text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(nonconformity_id,external_ref)
);
-- The expert verifies. The verification carries who, when and the evidence.
CREATE TABLE private_isg.verification_records (
  verification_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nonconformity_id uuid NOT NULL REFERENCES private_isg.nonconformities(nonconformity_id) ON DELETE CASCADE,
  cycle bigint NOT NULL, outcome text NOT NULL CHECK(outcome IN ('accepted','rejected')),
  verified_by uuid NOT NULL REFERENCES public.profiles(id), verified_on date NOT NULL CHECK(isfinite(verified_on)),
  evidence_asset_id uuid REFERENCES private_isg.file_assets(asset_id),
  note text CHECK(note IS NULL OR length(note)<=2000),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(nonconformity_id,cycle)
);
CREATE TABLE private_isg.checklist_templates (
  template_code text PRIMARY KEY CHECK(template_code ~ '^[a-z][a-z0-9_]{2,60}$'),
  title text NOT NULL CHECK(btrim(title)<>'' AND length(title)<=200),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE private_isg.checklist_template_versions (
  template_code text NOT NULL REFERENCES private_isg.checklist_templates(template_code) ON DELETE CASCADE,
  version integer NOT NULL CHECK(version BETWEEN 1 AND 1000),
  status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','published','superseded')),
  approved_by uuid REFERENCES public.profiles(id), approval_note text, published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(template_code,version),
  CHECK(status<>'published' OR (approved_by IS NOT NULL AND approval_note IS NOT NULL AND published_at IS NOT NULL))
);
CREATE UNIQUE INDEX checklist_single_published_idx ON private_isg.checklist_template_versions(template_code) WHERE status='published';
CREATE TABLE private_isg.checklist_template_items (
  template_code text NOT NULL, version integer NOT NULL,
  item_code text NOT NULL CHECK(item_code ~ '^[a-z0-9_]{2,40}$'),
  prompt text NOT NULL CHECK(btrim(prompt)<>'' AND length(prompt)<=500),
  allows_not_applicable boolean NOT NULL DEFAULT true,
  position integer NOT NULL CHECK(position BETWEEN 1 AND 500),
  PRIMARY KEY(template_code,version,item_code),
  UNIQUE(template_code,version,position),
  FOREIGN KEY(template_code,version) REFERENCES private_isg.checklist_template_versions(template_code,version) ON DELETE CASCADE
);
-- A run pins the template version it was filled with. Publishing a newer
-- template never edits a past run.
CREATE TABLE private_isg.checklist_runs (
  run_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL, workplace_id uuid NOT NULL,
  template_code text NOT NULL, template_version integer NOT NULL,
  state text NOT NULL DEFAULT 'open' CHECK(state IN ('open','submitted','cancelled')),
  started_on date NOT NULL CHECK(isfinite(started_on)), submitted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK((state='submitted')=(submitted_at IS NOT NULL)),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE,
  FOREIGN KEY(template_code,template_version) REFERENCES private_isg.checklist_template_versions(template_code,version)
);
CREATE TABLE private_isg.checklist_run_items (
  run_id uuid NOT NULL REFERENCES private_isg.checklist_runs(run_id) ON DELETE CASCADE,
  item_code text NOT NULL,
  result text NOT NULL CHECK(result IN ('conform','nonconform','not_applicable')),
  note text CHECK(note IS NULL OR length(note)<=1000),
  evidence_asset_id uuid REFERENCES private_isg.file_assets(asset_id),
  nonconformity_id uuid REFERENCES private_isg.nonconformities(nonconformity_id) ON DELETE SET NULL,
  recorded_at timestamptz NOT NULL,
  PRIMARY KEY(run_id,item_code),
  CHECK(nonconformity_id IS NULL OR result='nonconform')
);
CREATE TABLE private_isg.nonconformity_reconciliations (
  ran_on date PRIMARY KEY CHECK(isfinite(ran_on)),
  report jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX nonconformity_scope_idx ON private_isg.nonconformities(company_id,workplace_id,state);
CREATE INDEX nonconformity_owner_idx ON private_isg.nonconformities(company_id,owner_id);
CREATE INDEX nonconformity_due_idx ON private_isg.nonconformities(state,due_on);
CREATE INDEX transition_actor_idx ON private_isg.nonconformity_transitions(actor_id);
CREATE INDEX verification_verifier_idx ON private_isg.verification_records(verified_by);
CREATE INDEX verification_asset_idx ON private_isg.verification_records(evidence_asset_id);
CREATE INDEX action_scope_idx ON private_isg.nonconformity_actions(nonconformity_id,state);
CREATE INDEX checklist_run_scope_idx ON private_isg.checklist_runs(company_id,workplace_id,state);
CREATE INDEX checklist_run_owner_idx ON private_isg.checklist_runs(company_id,owner_id);
CREATE INDEX checklist_run_template_idx ON private_isg.checklist_runs(template_code,template_version);
CREATE INDEX checklist_item_asset_idx ON private_isg.checklist_run_items(evidence_asset_id);
CREATE INDEX checklist_item_nonconformity_idx ON private_isg.checklist_run_items(nonconformity_id);
CREATE INDEX checklist_version_approver_idx ON private_isg.checklist_template_versions(approved_by);
ALTER TABLE private_isg.nonconformity_state_edges ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.nonconformities ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.nonconformity_transitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.nonconformity_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.verification_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.checklist_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.checklist_template_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.checklist_template_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.checklist_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.checklist_run_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.nonconformity_reconciliations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.nonconformity_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM private_isg.rollout WHERE feature='nonconformity' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $$;
CREATE FUNCTION private_isg.open_nonconformity(p_company uuid,p_workplace uuid,p_source_kind text,p_source_ref text,
  p_title text,p_severity text,p_opened_on date,p_due_on date,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE workplace private_isg.workplaces; existing private_isg.nonconformities; record_id uuid; reference text;
BEGIN
  PERFORM private_isg.nonconformity_gate(true);
  IF p_company IS NULL OR p_workplace IS NULL OR p_source_kind IS NULL OR p_title IS NULL OR p_severity IS NULL OR
     p_opened_on IS NULL OR NOT isfinite(p_opened_on) OR p_now IS NULL OR
     p_source_kind NOT IN ('checklist','risk_version','legacy_finding','manual') OR
     p_severity NOT IN ('low','medium','high','critical') OR
     (p_source_kind<>'manual' AND p_source_ref IS NULL) OR
     (p_due_on IS NOT NULL AND p_due_on<p_opened_on) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO workplace FROM private_isg.workplaces WHERE company_id=p_company AND id=p_workplace FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  reference:=CASE WHEN p_source_ref IS NULL THEN NULL ELSE private_isg.text_value(p_source_ref,200) END;
  IF reference IS NOT NULL THEN
    SELECT * INTO existing FROM private_isg.nonconformities
      WHERE company_id=p_company AND source_kind=p_source_kind AND source_ref=reference FOR UPDATE;
    -- The same finding clicked twice returns the record it already has.
    IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'nonconformity_id',existing.nonconformity_id,
      'state',existing.state,'version',existing.version,'replayed',true); END IF;
  END IF;
  INSERT INTO private_isg.nonconformities(company_id,owner_id,workplace_id,source_kind,source_ref,title,severity,
      opened_on,due_on,created_at,updated_at)
    VALUES(p_company,workplace.owner_id,p_workplace,p_source_kind,reference,private_isg.text_value(p_title,300),
      p_severity,p_opened_on,p_due_on,p_now,p_now) RETURNING nonconformity_id INTO record_id;
  RETURN jsonb_build_object('schema_version',1,'nonconformity_id',record_id,'state','draft','version',0,
    'legacy_finding_written',false,'replayed',false);
END $$;
-- Every transition is checked against the matrix table, carries the expected
-- version and writes its own audit row.
CREATE FUNCTION private_isg.transition_nonconformity(p_nonconformity uuid,p_to_state text,p_expected_version bigint,
  p_reason text,p_assignee text,p_actor uuid,p_closed_on date,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.nonconformities; edge private_isg.nonconformity_state_edges;
  next_version bigint; reason text; assignee text; closing date;
BEGIN
  PERFORM private_isg.nonconformity_gate(true);
  IF p_nonconformity IS NULL OR p_to_state IS NULL OR p_expected_version IS NULL OR p_actor IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.nonconformities WHERE nonconformity_id=p_nonconformity FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.version<>p_expected_version THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  SELECT * INTO edge FROM private_isg.nonconformity_state_edges
    WHERE from_state=entry.state AND to_state=p_to_state;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='TRANSITION_NOT_ALLOWED'; END IF;
  IF edge.requires_reason THEN
    reason:=private_isg.text_value(p_reason,2000);
  ELSIF p_reason IS NOT NULL THEN reason:=private_isg.text_value(p_reason,2000); END IF;
  assignee:=coalesce(CASE WHEN p_assignee IS NULL THEN NULL ELSE private_isg.text_value(p_assignee,200) END,entry.assignee_contact);
  IF edge.requires_assignee AND assignee IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSIGNEE_REQUIRED'; END IF;
  IF edge.requires_verification THEN
    -- Only an accepted expert verification of this cycle can close the record.
    PERFORM 1 FROM private_isg.verification_records
      WHERE nonconformity_id=p_nonconformity AND cycle=entry.version AND outcome='accepted' FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERIFICATION_REQUIRED'; END IF;
    IF p_closed_on IS NULL OR NOT isfinite(p_closed_on) OR p_closed_on<entry.opened_on THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    closing:=p_closed_on;
  ELSIF p_closed_on IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  next_version:=entry.version+1;
  UPDATE private_isg.nonconformities SET state=p_to_state,version=next_version,assignee_contact=assignee,
    closed_on=CASE WHEN p_to_state='closed' THEN closing ELSE NULL END,
    cancelled_reason=CASE WHEN p_to_state='cancelled' THEN reason ELSE cancelled_reason END,
    updated_at=p_now WHERE nonconformity_id=p_nonconformity;
  INSERT INTO private_isg.nonconformity_transitions(nonconformity_id,version,from_state,to_state,reason,actor_id,occurred_at)
    VALUES(p_nonconformity,next_version,entry.state,p_to_state,reason,p_actor,p_now);
  RETURN jsonb_build_object('schema_version',1,'nonconformity_id',p_nonconformity,'from_state',entry.state,
    'state',p_to_state,'version',next_version,'closed_on',CASE WHEN p_to_state='closed' THEN closing END);
END $$;
CREATE FUNCTION private_isg.add_corrective_action(p_nonconformity uuid,p_description text,p_assignee text,
  p_due_on date,p_external_ref text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.nonconformities; action uuid; existing uuid; reference text;
BEGIN
  PERFORM private_isg.nonconformity_gate(true);
  IF p_nonconformity IS NULL OR p_description IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.nonconformities WHERE nonconformity_id=p_nonconformity FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state IN ('closed','cancelled') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  reference:=CASE WHEN p_external_ref IS NULL THEN NULL ELSE private_isg.text_value(p_external_ref,200) END;
  IF reference IS NOT NULL THEN
    SELECT action_id INTO existing FROM private_isg.nonconformity_actions
      WHERE nonconformity_id=p_nonconformity AND external_ref=reference;
    IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'action_id',existing,'replayed',true); END IF;
  END IF;
  INSERT INTO private_isg.nonconformity_actions(nonconformity_id,description,assignee_contact,due_on,external_ref,created_at,updated_at)
    VALUES(p_nonconformity,private_isg.text_value(p_description,1000),
      CASE WHEN p_assignee IS NULL THEN NULL ELSE private_isg.text_value(p_assignee,200) END,p_due_on,reference,p_now,p_now)
    RETURNING action_id INTO action;
  RETURN jsonb_build_object('schema_version',1,'action_id',action,'assignee_is_application_user',false,'replayed',false);
END $$;
CREATE FUNCTION private_isg.record_verification(p_nonconformity uuid,p_outcome text,p_verified_by uuid,
  p_verified_on date,p_asset uuid,p_note text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.nonconformities; verification uuid; existing private_isg.verification_records;
BEGIN
  PERFORM private_isg.nonconformity_gate(true);
  IF p_nonconformity IS NULL OR p_outcome IS NULL OR p_verified_by IS NULL OR p_verified_on IS NULL OR
     NOT isfinite(p_verified_on) OR p_now IS NULL OR p_outcome NOT IN ('accepted','rejected') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.nonconformities WHERE nonconformity_id=p_nonconformity FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state<>'pending_verification' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_asset IS NOT NULL THEN
    PERFORM 1 FROM private_isg.file_assets WHERE asset_id=p_asset AND scan_status='clean' FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  SELECT * INTO existing FROM private_isg.verification_records
    WHERE nonconformity_id=p_nonconformity AND cycle=entry.version;
  IF FOUND THEN
    IF existing.outcome IS DISTINCT FROM p_outcome THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN jsonb_build_object('schema_version',1,'verification_id',existing.verification_id,'outcome',existing.outcome,'replayed',true);
  END IF;
  INSERT INTO private_isg.verification_records(nonconformity_id,cycle,outcome,verified_by,verified_on,evidence_asset_id,note,created_at)
    VALUES(p_nonconformity,entry.version,p_outcome,p_verified_by,p_verified_on,p_asset,p_note,p_now)
    RETURNING verification_id INTO verification;
  RETURN jsonb_build_object('schema_version',1,'verification_id',verification,'outcome',p_outcome,'cycle',entry.version,'replayed',false);
END $$;
CREATE FUNCTION private_isg.publish_checklist_version(p_code text,p_version integer,p_approver uuid,p_note text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.checklist_template_versions; previous integer; items integer;
BEGIN
  PERFORM private_isg.nonconformity_gate(true);
  IF p_code IS NULL OR p_version IS NULL OR p_approver IS NULL OR p_note IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.checklist_template_versions
    WHERE template_code=p_code AND version=p_version FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.status='published' THEN RETURN jsonb_build_object('schema_version',1,'template_code',p_code,'version',p_version,'status','published','replayed',true); END IF;
  IF entry.status<>'draft' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT count(*) INTO items FROM private_isg.checklist_template_items WHERE template_code=p_code AND version=p_version;
  IF items=0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT version INTO previous FROM private_isg.checklist_template_versions WHERE template_code=p_code AND status='published' FOR UPDATE;
  IF previous IS NOT NULL THEN
    UPDATE private_isg.checklist_template_versions SET status='superseded' WHERE template_code=p_code AND version=previous; END IF;
  UPDATE private_isg.checklist_template_versions SET status='published',approved_by=p_approver,
    approval_note=private_isg.text_value(p_note,500),published_at=p_now WHERE template_code=p_code AND version=p_version;
  RETURN jsonb_build_object('schema_version',1,'template_code',p_code,'version',p_version,'status','published',
    'items',items,'superseded_version',previous,'replayed',false);
END $$;
CREATE FUNCTION private_isg.start_checklist_run(p_company uuid,p_workplace uuid,p_code text,p_on date,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE workplace private_isg.workplaces; template private_isg.checklist_template_versions; run uuid;
BEGIN
  PERFORM private_isg.nonconformity_gate(true);
  IF p_company IS NULL OR p_workplace IS NULL OR p_code IS NULL OR p_on IS NULL OR NOT isfinite(p_on) OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO workplace FROM private_isg.workplaces WHERE company_id=p_company AND id=p_workplace FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO template FROM private_isg.checklist_template_versions WHERE template_code=p_code AND status='published' FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  -- The run pins this version; a later publish can not rewrite what was filled.
  INSERT INTO private_isg.checklist_runs(company_id,owner_id,workplace_id,template_code,template_version,started_on,created_at)
    VALUES(p_company,workplace.owner_id,p_workplace,p_code,template.version,p_on,p_now) RETURNING run_id INTO run;
  RETURN jsonb_build_object('schema_version',1,'run_id',run,'template_code',p_code,'template_version',template.version,'state','open');
END $$;
CREATE FUNCTION private_isg.record_run_item(p_run uuid,p_item text,p_result text,p_note text,p_asset uuid,
  p_open_nonconformity boolean,p_severity text,p_due_on date,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE run private_isg.checklist_runs; item private_isg.checklist_template_items;
  existing private_isg.checklist_run_items; finding jsonb; record_id uuid;
BEGIN
  PERFORM private_isg.nonconformity_gate(true);
  IF p_run IS NULL OR p_item IS NULL OR p_result IS NULL OR p_now IS NULL OR p_open_nonconformity IS NULL OR
     p_result NOT IN ('conform','nonconform','not_applicable') OR
     (p_open_nonconformity AND (p_result<>'nonconform' OR p_severity IS NULL)) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO run FROM private_isg.checklist_runs WHERE run_id=p_run FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF run.state<>'open' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RUN_SUBMITTED'; END IF;
  SELECT * INTO item FROM private_isg.checklist_template_items
    WHERE template_code=run.template_code AND version=run.template_version AND item_code=p_item;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_result='not_applicable' AND NOT item.allows_not_applicable THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_asset IS NOT NULL THEN
    PERFORM 1 FROM private_isg.file_assets WHERE asset_id=p_asset AND scan_status='clean' FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  SELECT * INTO existing FROM private_isg.checklist_run_items WHERE run_id=p_run AND item_code=p_item;
  IF FOUND AND existing.result=p_result AND existing.nonconformity_id IS NOT NULL THEN
    -- Clicking the same failing item again reuses the record it created.
    RETURN jsonb_build_object('schema_version',1,'run_id',p_run,'item_code',p_item,'result',existing.result,
      'nonconformity_id',existing.nonconformity_id,'replayed',true);
  END IF;
  IF p_open_nonconformity THEN
    finding:=private_isg.open_nonconformity(run.company_id,run.workplace_id,'checklist',p_run::text||':'||p_item,
      item.prompt,p_severity,run.started_on,p_due_on,p_now);
    record_id:=(finding->>'nonconformity_id')::uuid;
  END IF;
  INSERT INTO private_isg.checklist_run_items(run_id,item_code,result,note,evidence_asset_id,nonconformity_id,recorded_at)
    VALUES(p_run,p_item,p_result,p_note,p_asset,record_id,p_now)
  ON CONFLICT(run_id,item_code) DO UPDATE SET result=excluded.result,note=excluded.note,
    evidence_asset_id=excluded.evidence_asset_id,
    nonconformity_id=coalesce(checklist_run_items.nonconformity_id,excluded.nonconformity_id),
    recorded_at=excluded.recorded_at;
  RETURN jsonb_build_object('schema_version',1,'run_id',p_run,'item_code',p_item,'result',p_result,
    'nonconformity_id',record_id,'replayed',false);
END $$;
CREATE FUNCTION private_isg.submit_checklist_run(p_run uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE run private_isg.checklist_runs; expected integer; answered integer;
BEGIN
  PERFORM private_isg.nonconformity_gate(true);
  IF p_run IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO run FROM private_isg.checklist_runs WHERE run_id=p_run FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF run.state='submitted' THEN RETURN jsonb_build_object('schema_version',1,'run_id',p_run,'state','submitted','replayed',true); END IF;
  SELECT count(*) INTO expected FROM private_isg.checklist_template_items
    WHERE template_code=run.template_code AND version=run.template_version;
  SELECT count(*) INTO answered FROM private_isg.checklist_run_items WHERE run_id=p_run;
  IF answered<expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RUN_INCOMPLETE'; END IF;
  UPDATE private_isg.checklist_runs SET state='submitted',submitted_at=p_now WHERE run_id=p_run;
  RETURN jsonb_build_object('schema_version',1,'run_id',p_run,'state','submitted','items',answered,'replayed',false);
END $$;
CREATE FUNCTION private_isg.reconcile_nonconformities(p_on date,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE report jsonb;
BEGIN
  PERFORM private_isg.nonconformity_gate(true);
  IF p_on IS NULL OR NOT isfinite(p_on) OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT jsonb_build_object('schema_version',1,'ran_on',p_on,
    'total',(SELECT count(*) FROM private_isg.nonconformities),
    'open_states',(SELECT coalesce(jsonb_object_agg(state,total),'{}'::jsonb) FROM
      (SELECT state,count(*) AS total FROM private_isg.nonconformities GROUP BY state) s),
    'overdue',(SELECT count(*) FROM private_isg.nonconformities
      WHERE state NOT IN ('closed','cancelled') AND due_on IS NOT NULL AND due_on<p_on),
    'pending_verification',(SELECT count(*) FROM private_isg.nonconformities WHERE state='pending_verification'),
    'closed_without_verification',(SELECT count(*) FROM private_isg.nonconformities n WHERE n.state='closed'
      AND NOT EXISTS(SELECT 1 FROM private_isg.verification_records v WHERE v.nonconformity_id=n.nonconformity_id AND v.outcome='accepted')),
    'open_runs',(SELECT count(*) FROM private_isg.checklist_runs WHERE state='open'),
    'critical_open',(SELECT count(*) FROM private_isg.nonconformities
      WHERE severity='critical' AND state NOT IN ('closed','cancelled'))) INTO report;
  INSERT INTO private_isg.nonconformity_reconciliations(ran_on,report,created_at) VALUES(p_on,report,p_now)
    ON CONFLICT(ran_on) DO UPDATE SET report=excluded.report,created_at=excluded.created_at;
  RETURN report;
END $$;
REVOKE ALL ON FUNCTION private_isg.nonconformity_gate(boolean),
  private_isg.open_nonconformity(uuid,uuid,text,text,text,text,date,date,timestamptz),
  private_isg.transition_nonconformity(uuid,text,bigint,text,text,uuid,date,timestamptz),
  private_isg.add_corrective_action(uuid,text,text,date,text,timestamptz),
  private_isg.record_verification(uuid,text,uuid,date,uuid,text,timestamptz),
  private_isg.publish_checklist_version(text,integer,uuid,text,timestamptz),
  private_isg.start_checklist_run(uuid,uuid,text,date,timestamptz),
  private_isg.record_run_item(uuid,text,text,text,uuid,boolean,text,date,timestamptz),
  private_isg.submit_checklist_run(uuid,timestamptz),
  private_isg.reconcile_nonconformities(date,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
