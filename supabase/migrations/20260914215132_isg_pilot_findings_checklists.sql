DO $$ DECLARE expression text; BEGIN
SELECT pg_get_expr(conbin,conrelid) INTO expression FROM pg_constraint WHERE conrelid='private_isg.rollout'::regclass AND conname='rollout_feature_check';
IF expression IS NULL THEN RAISE EXCEPTION 'Missing rollout constraint'; END IF;
ALTER TABLE private_isg.rollout DROP CONSTRAINT rollout_feature_check;
EXECUTE format('ALTER TABLE private_isg.rollout ADD CONSTRAINT rollout_feature_check CHECK((%s) OR feature IN (''nonconformity'',''risk''))',expression);
END $$;
-- P09/D09 first slice: a server-defined nonconformity state machine, corrective
-- actions, expert verification, and versioned checklist templates whose runs
-- snapshot the version they were filled with.
-- Additive; rollout OFF; no client grant. The legacy findings table is never
-- read for authority and never written: its is_resolved flag closes nothing here.
SET LOCAL lock_timeout='5s';
INSERT INTO private_isg.rollout(feature) VALUES('nonconformity') ON CONFLICT DO NOTHING;

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
  evidence_asset_id uuid CHECK(evidence_asset_id IS NULL),
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
  evidence_asset_id uuid CHECK(evidence_asset_id IS NULL),
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
REVOKE ALL ON private_isg.nonconformity_state_edges FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON private_isg.nonconformities FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON private_isg.nonconformity_transitions FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON private_isg.nonconformity_actions FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON private_isg.verification_records FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON private_isg.checklist_templates FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON private_isg.checklist_template_versions FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON private_isg.checklist_template_items FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON private_isg.checklist_runs FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON private_isg.checklist_run_items FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON private_isg.nonconformity_reconciliations FROM PUBLIC,anon,authenticated,service_role;

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
  IF p_asset IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FILE_STORAGE_UNAVAILABLE'; END IF;
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
  IF p_asset IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FILE_STORAGE_UNAVAILABLE'; END IF;
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

-- P09 client boundary: the owner checked entry, the mutation receipt and the two
-- public wrappers the NOVA nonconformity screens call.
-- Additive. The rollout row is NOT opened here: switching a feature on stays a
-- separate, human decision, exactly as it is for personnel.
-- public.findings and public.analyses are never written; a finding is referenced
-- by source_ref and keeps living where it already lives.
SET LOCAL lock_timeout='5s';

-- Same shape as personnel_receipts: one row per actor and mutation, so a retry
-- with the same key returns the first answer instead of opening a second record.
CREATE TABLE private_isg.nonconformity_receipts (
  actor_id uuid NOT NULL, mutation_id uuid NOT NULL, company_id uuid NOT NULL,
  operation_id uuid NOT NULL, request_hash bytea NOT NULL, response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(actor_id,mutation_id),
  FOREIGN KEY(company_id,actor_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
-- The foreign key is composite, so the covering index has to be composite too.
CREATE INDEX nonconformity_receipt_company_idx ON private_isg.nonconformity_receipts(company_id,actor_id);
ALTER TABLE private_isg.nonconformity_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.nonconformity_receipts FROM PUBLIC,anon,authenticated,service_role;

-- The legacy risk band and the nonconformity severity share four names. The
-- fifth legacy value is 'unknown', and it has no honest target here: an
-- unreadable band must reach a person, not quietly become the lowest severity.
CREATE FUNCTION private_isg.severity_for_risk_band(p_band text) RETURNS text
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
BEGIN
  IF p_band IS NULL OR p_band='unknown' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SEVERITY_UNKNOWN'; END IF;
  IF p_band NOT IN ('low','medium','high','critical') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  RETURN p_band;
END $$;

-- Session, subscription and company ownership, checked on this feature's switch.
CREATE FUNCTION private_isg.require_nonconformity_company(p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  IF NOT private_isg.p05_pilot_account_enabled(actor,p_write) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  IF p_company IS NOT NULL AND NOT private_isg.p05_pilot_can_read(actor,p_company) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  PERFORM 1 FROM private_isg.rollout WHERE feature='nonconformity' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  IF p_write THEN
    PERFORM 1 FROM public.user_subscriptions WHERE user_id=actor AND tier IN ('plus','pro') AND
      status IN ('active','trialing','grace_period') AND
      (current_period_ends_at IS NULL OR current_period_ends_at>clock_timestamp()) FOR SHARE;
    IF NOT FOUND OR private.user_plan_tier(actor) NOT IN ('plus','pro') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAID_PLAN_REQUIRED'; END IF;
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor AND NOT is_archived FOR UPDATE;
  ELSE
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor FOR SHARE;
  END IF;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  RETURN actor;
END $$;

CREATE FUNCTION private_isg.nonconformity_row(p_company uuid,p_nonconformity uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.nonconformities;
BEGIN
  SELECT * INTO entry FROM private_isg.nonconformities
    WHERE nonconformity_id=p_nonconformity AND company_id=p_company;
  IF NOT FOUND THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('id',entry.nonconformity_id,'workplace_id',entry.workplace_id,
    'source_kind',entry.source_kind,'source_ref',entry.source_ref,'title',entry.title,
    'severity',entry.severity,'state',entry.state,'version',entry.version,
    'opened_on',entry.opened_on,'due_on',entry.due_on,'closed_on',entry.closed_on,
    'assignee_contact',entry.assignee_contact,
    'actions',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',a.action_id,'description',a.description,
        'assignee',a.assignee_contact,'due_on',a.due_on,'state',a.state) ORDER BY a.created_at),'[]'::jsonb)
      FROM private_isg.nonconformity_actions a WHERE a.nonconformity_id=entry.nonconformity_id),
    'verifications',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',v.verification_id,'outcome',v.outcome,
        'verified_on',v.verified_on) ORDER BY v.verified_on),'[]'::jsonb)
      FROM private_isg.verification_records v WHERE v.nonconformity_id=entry.nonconformity_id),
    'legacy_finding_written',false);
END $$;

CREATE FUNCTION private_isg.read_nonconformities(p_company uuid,p_kind text,p_query text,p_state text,
  p_after uuid,p_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; rows jsonb; needle text;
BEGIN
  actor:=private_isg.require_nonconformity_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('list','detail','workplaces') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    rows:=private_isg.nonconformity_row(p_company,p_id);
    IF rows IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'kind','detail','row',rows);
  END IF;
  IF p_kind='workplaces' THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,'needs_review',w.needs_review)
      ORDER BY w.name),'[]'::jsonb) INTO rows
      FROM private_isg.workplaces w WHERE w.company_id=p_company AND w.owner_id=actor AND NOT w.is_archived;
    RETURN jsonb_build_object('schema_version',1,'kind','workplaces','rows',rows);
  END IF;
  IF p_state IS NOT NULL AND p_state NOT IN ('draft','open','assigned','in_progress','pending_verification',
      'closed','reopened','cancelled') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  needle:=nullif(btrim(coalesce(p_query,'')),'');
  -- 'row' is a keyword-shaped alias; name it something the parser cannot claim.
  SELECT coalesce(jsonb_agg(entry ORDER BY (entry->>'opened_on') DESC,(entry->>'id')),'[]'::jsonb) INTO rows FROM (
    SELECT jsonb_build_object('id',n.nonconformity_id,'workplace_id',n.workplace_id,'title',n.title,
      'severity',n.severity,'state',n.state,'version',n.version,'opened_on',n.opened_on,'due_on',n.due_on,
      'source_kind',n.source_kind,'source_ref',n.source_ref) AS entry
    FROM private_isg.nonconformities n
    WHERE n.company_id=p_company AND n.owner_id=actor
      AND (p_state IS NULL OR n.state=p_state)
      AND (needle IS NULL OR n.title ILIKE '%'||needle||'%')
      AND (p_after IS NULL OR n.nonconformity_id<>p_after)
    ORDER BY n.opened_on DESC,n.nonconformity_id LIMIT 200) page;
  RETURN jsonb_build_object('schema_version',1,'kind','list','rows',rows,'legacy_findings_written',false);
END $$;

-- The two checked entries are the client RPC boundary and therefore DEFINER, the
-- same as the personnel pair: they run their own session, subscription and owner
-- checks first and call the private helpers afterwards.
-- One entry point for every write. The payload keys are allowlisted per action,
-- so a client cannot smuggle a field the server never agreed to read.
CREATE FUNCTION private_isg.mutate_nonconformity(p_company uuid,p_action text,p_operation uuid,p_mutation uuid,
  p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.nonconformity_receipts;
  result jsonb; resolved_severity text; target uuid; stamp timestamptz:=clock_timestamp();
BEGIN
  actor:=private_isg.require_nonconformity_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>4096 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  allowed:=CASE p_action
    WHEN 'open_manual' THEN ARRAY['workplace_id','title','severity','opened_on','due_on','assignee']
    WHEN 'open_from_finding' THEN ARRAY['workplace_id','title','risk_band','severity','finding_id','opened_on','due_on']
    WHEN 'transition' THEN ARRAY['nonconformity_id','expected_version','to_state','reason','assignee','closed_on']
    WHEN 'add_action' THEN ARRAY['nonconformity_id','description','assignee','due_on','external_ref']
    WHEN 'verify' THEN ARRAY['nonconformity_id','outcome','verified_on','note']
    ELSE NULL END;
  IF allowed IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO offending FROM jsonb_object_keys(p_payload) AS keys(key)
    WHERE NOT (key=ANY(allowed)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;

  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-nonconformity:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.nonconformity_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN prior.response||jsonb_build_object('replayed',true);
  END IF;

  IF p_action IN ('open_manual','open_from_finding') THEN
    -- An explicitly chosen severity wins; otherwise the legacy band maps across,
    -- and an unreadable band refuses instead of guessing the lowest one.
    resolved_severity:=CASE WHEN p_payload ? 'severity' THEN p_payload->>'severity'
      ELSE private_isg.severity_for_risk_band(p_payload->>'risk_band') END;
    result:=private_isg.open_nonconformity(p_company,(p_payload->>'workplace_id')::uuid,
      CASE WHEN p_action='open_manual' THEN 'manual' ELSE 'legacy_finding' END,
      CASE WHEN p_action='open_manual' THEN NULL ELSE p_payload->>'finding_id' END,
      p_payload->>'title',resolved_severity,
      coalesce((p_payload->>'opened_on')::date,(stamp AT TIME ZONE 'Europe/Istanbul')::date),
      (p_payload->>'due_on')::date,stamp);
    target:=(result->>'nonconformity_id')::uuid;
  ELSIF p_action='transition' THEN
    target:=(p_payload->>'nonconformity_id')::uuid;
    PERFORM 1 FROM private_isg.nonconformities WHERE nonconformity_id=target AND company_id=p_company AND owner_id=actor;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    result:=private_isg.transition_nonconformity(target,p_payload->>'to_state',
      (p_payload->>'expected_version')::bigint,p_payload->>'reason',p_payload->>'assignee',actor,
      (p_payload->>'closed_on')::date,stamp);
  ELSIF p_action='add_action' THEN
    target:=(p_payload->>'nonconformity_id')::uuid;
    PERFORM 1 FROM private_isg.nonconformities WHERE nonconformity_id=target AND company_id=p_company AND owner_id=actor;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    result:=private_isg.add_corrective_action(target,p_payload->>'description',p_payload->>'assignee',
      (p_payload->>'due_on')::date,p_payload->>'external_ref',stamp);
  ELSE
    target:=(p_payload->>'nonconformity_id')::uuid;
    PERFORM 1 FROM private_isg.nonconformities WHERE nonconformity_id=target AND company_id=p_company AND owner_id=actor;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    result:=private_isg.record_verification(target,p_payload->>'outcome',actor,
      coalesce((p_payload->>'verified_on')::date,(stamp AT TIME ZONE 'Europe/Istanbul')::date),NULL,p_payload->>'note',stamp);
  END IF;

  result:=jsonb_build_object('schema_version',1,'action',p_action,'operation_id',p_operation,
    'row',private_isg.nonconformity_row(p_company,target),'outcome',result,'legacy_finding_written',false);
  INSERT INTO private_isg.nonconformity_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $$;

-- Exposed wrappers stay INVOKER; only the two checked entry points get a grant.
CREATE FUNCTION public.isg_nonconformity_read_v1(p_company uuid,p_kind text,p_query text,p_state text,
  p_after uuid,p_id uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.read_nonconformities(p_company,p_kind,p_query,p_state,p_after,p_id)
$$;
CREATE FUNCTION public.isg_nonconformity_mutate_v1(p_company uuid,p_action text,p_operation uuid,p_mutation uuid,
  p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.mutate_nonconformity(p_company,p_action,p_operation,p_mutation,p_payload)
$$;
REVOKE ALL ON FUNCTION private_isg.severity_for_risk_band(text),
  private_isg.require_nonconformity_company(uuid,boolean),
  private_isg.nonconformity_row(uuid,uuid),
  private_isg.read_nonconformities(uuid,text,text,text,uuid,uuid),
  private_isg.mutate_nonconformity(uuid,text,uuid,uuid,jsonb),
  public.isg_nonconformity_read_v1(uuid,text,text,text,uuid,uuid),
  public.isg_nonconformity_mutate_v1(uuid,text,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.read_nonconformities(uuid,text,text,text,uuid,uuid),
  private_isg.mutate_nonconformity(uuid,text,uuid,uuid,jsonb),
  public.isg_nonconformity_read_v1(uuid,text,text,text,uuid,uuid),
  public.isg_nonconformity_mutate_v1(uuid,text,uuid,uuid,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';

-- P09 second slice: the fields an expert actually fills in by hand — hazard
-- description, control measure, legislation reference, the responsible person
-- and a risk score — plus the record kind that separates an improvement
-- suggestion from a nonconformity.
-- Additive. The rollout row is NOT opened here. public.findings and
-- public.analyses stay unwritten: an expert-opinion item is referenced by
-- source_ref exactly the way a scored finding already is.
SET LOCAL lock_timeout='5s';

-- An improvement suggestion travels the same lifecycle but is not a
-- nonconformity, and must never be counted as one. Existing rows keep the
-- default, so nothing already written changes meaning.
ALTER TABLE private_isg.nonconformities ADD COLUMN record_kind text NOT NULL DEFAULT 'nonconformity';
ALTER TABLE private_isg.nonconformities ADD CONSTRAINT nonconformity_record_kind_check
  CHECK(record_kind IN ('nonconformity','improvement'));

-- The unscored expert-opinion items need their own provenance: they are not
-- scored findings and must not be filed as if they were. Widening the existing
-- constraint must fail loudly if that constraint is not where it is expected.
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_constraint
    WHERE conrelid='private_isg.nonconformities'::regclass AND conname='nonconformities_source_kind_check') THEN
    RAISE EXCEPTION 'NONCONFORMITY_SOURCE_KIND_CONSTRAINT_MISSING'; END IF;
END $$;
ALTER TABLE private_isg.nonconformities DROP CONSTRAINT nonconformities_source_kind_check;
ALTER TABLE private_isg.nonconformities ADD CONSTRAINT nonconformities_source_kind_check
  CHECK(source_kind IN ('checklist','risk_version','legacy_finding','legacy_expert_item','manual'));

-- One detail row per record. The score is GENERATED from the inputs, so a
-- client-supplied number can never be stored as a risk score, and the band is
-- generated from the score, so a band can never be claimed either.
CREATE TABLE private_isg.nonconformity_details (
  nonconformity_id uuid PRIMARY KEY REFERENCES private_isg.nonconformities(nonconformity_id) ON DELETE CASCADE,
  hazard_description text CHECK(hazard_description IS NULL OR (btrim(hazard_description)<>'' AND length(hazard_description)<=2000)),
  control_measure text CHECK(control_measure IS NULL OR (btrim(control_measure)<>'' AND length(control_measure)<=2000)),
  legislation_ref text CHECK(legislation_ref IS NULL OR (btrim(legislation_ref)<>'' AND length(legislation_ref)<=500)),
  responsible_contact text CHECK(responsible_contact IS NULL OR (btrim(responsible_contact)<>'' AND length(responsible_contact)<=200)),
  risk_method text CHECK(risk_method IS NULL OR risk_method IN ('fine_kinney','matrix_5x5')),
  fk_probability numeric CHECK(fk_probability IS NULL OR fk_probability IN (0.2,0.5,1,3,6,10)),
  fk_frequency numeric CHECK(fk_frequency IS NULL OR fk_frequency IN (0.5,1,2,3,6,10)),
  fk_severity numeric CHECK(fk_severity IS NULL OR fk_severity IN (1,3,7,15,40,100)),
  m5_probability integer CHECK(m5_probability IS NULL OR m5_probability BETWEEN 1 AND 5),
  m5_severity integer CHECK(m5_severity IS NULL OR m5_severity BETWEEN 1 AND 5),
  risk_score numeric GENERATED ALWAYS AS
    (coalesce(fk_probability*fk_frequency*fk_severity,m5_probability::numeric*m5_severity::numeric)) STORED,
  risk_band text GENERATED ALWAYS AS (CASE
    WHEN risk_method='fine_kinney' THEN
      CASE WHEN fk_probability*fk_frequency*fk_severity<=70 THEN 'low'::text
           WHEN fk_probability*fk_frequency*fk_severity<=200 THEN 'medium'::text
           WHEN fk_probability*fk_frequency*fk_severity<=400 THEN 'high'::text ELSE 'critical'::text END
    WHEN risk_method='matrix_5x5' THEN
      CASE WHEN m5_probability*m5_severity<=4 THEN 'low'::text
           WHEN m5_probability*m5_severity<=9 THEN 'medium'::text
           WHEN m5_probability*m5_severity<=19 THEN 'high'::text ELSE 'critical'::text END
    ELSE NULL::text END) STORED,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  -- No method means no scoring inputs at all: a half-filled score is not a score.
  CHECK(risk_method IS NOT NULL OR (fk_probability IS NULL AND fk_frequency IS NULL AND fk_severity IS NULL
    AND m5_probability IS NULL AND m5_severity IS NULL)),
  -- Each method carries its own inputs and nothing from the other one, so the
  -- stored score can only have come from the method the expert chose.
  CHECK(risk_method IS DISTINCT FROM 'fine_kinney' OR (fk_probability IS NOT NULL AND fk_frequency IS NOT NULL
    AND fk_severity IS NOT NULL AND m5_probability IS NULL AND m5_severity IS NULL)),
  CHECK(risk_method IS DISTINCT FROM 'matrix_5x5' OR (m5_probability IS NOT NULL AND m5_severity IS NOT NULL
    AND fk_probability IS NULL AND fk_frequency IS NULL AND fk_severity IS NULL))
);
ALTER TABLE private_isg.nonconformity_details ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.nonconformity_details FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX nonconformity_record_kind_idx ON private_isg.nonconformities(company_id,record_kind,state);

-- One implementation for both record kinds; the old signature keeps working and
-- keeps meaning 'nonconformity', so nothing that already calls it changes.
CREATE FUNCTION private_isg.open_nonconformity_record(p_company uuid,p_workplace uuid,p_source_kind text,
  p_source_ref text,p_title text,p_severity text,p_record_kind text,p_opened_on date,p_due_on date,
  p_assignee text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE workplace private_isg.workplaces; existing private_isg.nonconformities; record_id uuid; reference text;
  contact text;
BEGIN
  PERFORM private_isg.nonconformity_gate(true);
  IF p_company IS NULL OR p_workplace IS NULL OR p_source_kind IS NULL OR p_title IS NULL OR p_severity IS NULL OR
     p_opened_on IS NULL OR NOT isfinite(p_opened_on) OR p_now IS NULL OR
     p_source_kind NOT IN ('checklist','risk_version','legacy_finding','legacy_expert_item','manual') OR
     p_severity NOT IN ('low','medium','high','critical') OR
     p_record_kind IS NULL OR p_record_kind NOT IN ('nonconformity','improvement') OR
     (p_source_kind<>'manual' AND p_source_ref IS NULL) OR
     (p_due_on IS NOT NULL AND p_due_on<p_opened_on) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO workplace FROM private_isg.workplaces WHERE company_id=p_company AND id=p_workplace FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  reference:=CASE WHEN p_source_ref IS NULL THEN NULL ELSE private_isg.text_value(p_source_ref,200) END;
  contact:=CASE WHEN p_assignee IS NULL THEN NULL ELSE private_isg.text_value(p_assignee,200) END;
  IF reference IS NOT NULL THEN
    SELECT * INTO existing FROM private_isg.nonconformities
      WHERE company_id=p_company AND source_kind=p_source_kind AND source_ref=reference FOR UPDATE;
    -- The same finding or the same expert item clicked twice returns the record
    -- it already has instead of opening a second one.
    IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'nonconformity_id',existing.nonconformity_id,
      'state',existing.state,'version',existing.version,'record_kind',existing.record_kind,'replayed',true); END IF;
  END IF;
  INSERT INTO private_isg.nonconformities(company_id,owner_id,workplace_id,source_kind,source_ref,title,severity,
      record_kind,opened_on,due_on,assignee_contact,created_at,updated_at)
    VALUES(p_company,workplace.owner_id,p_workplace,p_source_kind,reference,private_isg.text_value(p_title,300),
      p_severity,p_record_kind,p_opened_on,p_due_on,contact,p_now,p_now) RETURNING nonconformity_id INTO record_id;
  RETURN jsonb_build_object('schema_version',1,'nonconformity_id',record_id,'state','draft','version',0,
    'record_kind',p_record_kind,'legacy_finding_written',false,'replayed',false);
END $$;

CREATE OR REPLACE FUNCTION private_isg.open_nonconformity(p_company uuid,p_workplace uuid,p_source_kind text,
  p_source_ref text,p_title text,p_severity text,p_opened_on date,p_due_on date,p_now timestamptz) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.open_nonconformity_record(p_company,p_workplace,p_source_kind,p_source_ref,p_title,
    p_severity,'nonconformity',p_opened_on,p_due_on,NULL,p_now)
$$;

-- The detail row is replaced as a whole: the client sends the detail it is
-- showing, so a field it cleared really is cleared. The score and the band are
-- generated columns and are never accepted from the caller.
CREATE FUNCTION private_isg.set_nonconformity_detail(p_nonconformity uuid,p_description text,p_measure text,
  p_legislation text,p_responsible text,p_method text,p_fk_probability numeric,p_fk_frequency numeric,
  p_fk_severity numeric,p_m5_probability integer,p_m5_severity integer,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE stored private_isg.nonconformity_details;
  description text:=nullif(btrim(coalesce(p_description,'')),'');
  measure text:=nullif(btrim(coalesce(p_measure,'')),'');
  legislation text:=nullif(btrim(coalesce(p_legislation,'')),'');
  responsible text:=nullif(btrim(coalesce(p_responsible,'')),'');
BEGIN
  PERFORM private_isg.nonconformity_gate(true);
  IF p_nonconformity IS NULL OR p_now IS NULL OR
     (p_method IS NOT NULL AND p_method NOT IN ('fine_kinney','matrix_5x5')) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  -- A method without its own three (or two) inputs is a refusal, not a partial
  -- score; an input without a method is a refusal too.
  IF p_method='fine_kinney' AND (p_fk_probability IS NULL OR p_fk_frequency IS NULL OR p_fk_severity IS NULL
      OR p_m5_probability IS NOT NULL OR p_m5_severity IS NOT NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RISK_INPUT_INCOMPLETE'; END IF;
  IF p_method='matrix_5x5' AND (p_m5_probability IS NULL OR p_m5_severity IS NULL
      OR p_fk_probability IS NOT NULL OR p_fk_frequency IS NOT NULL OR p_fk_severity IS NOT NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RISK_INPUT_INCOMPLETE'; END IF;
  IF p_method IS NULL AND (p_fk_probability IS NOT NULL OR p_fk_frequency IS NOT NULL OR p_fk_severity IS NOT NULL
      OR p_m5_probability IS NOT NULL OR p_m5_severity IS NOT NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RISK_INPUT_INCOMPLETE'; END IF;
  INSERT INTO private_isg.nonconformity_details(nonconformity_id,hazard_description,control_measure,legislation_ref,
      responsible_contact,risk_method,fk_probability,fk_frequency,fk_severity,m5_probability,m5_severity,
      created_at,updated_at)
    VALUES(p_nonconformity,
      CASE WHEN description IS NULL THEN NULL ELSE private_isg.text_value(description,2000) END,
      CASE WHEN measure IS NULL THEN NULL ELSE private_isg.text_value(measure,2000) END,
      CASE WHEN legislation IS NULL THEN NULL ELSE private_isg.text_value(legislation,500) END,
      CASE WHEN responsible IS NULL THEN NULL ELSE private_isg.text_value(responsible,200) END,
      p_method,p_fk_probability,p_fk_frequency,p_fk_severity,p_m5_probability,p_m5_severity,p_now,p_now)
    ON CONFLICT(nonconformity_id) DO UPDATE SET
      hazard_description=excluded.hazard_description,control_measure=excluded.control_measure,
      legislation_ref=excluded.legislation_ref,responsible_contact=excluded.responsible_contact,
      risk_method=excluded.risk_method,fk_probability=excluded.fk_probability,fk_frequency=excluded.fk_frequency,
      fk_severity=excluded.fk_severity,m5_probability=excluded.m5_probability,m5_severity=excluded.m5_severity,
      updated_at=excluded.updated_at
    RETURNING * INTO stored;
  RETURN jsonb_build_object('schema_version',1,'nonconformity_id',stored.nonconformity_id,
    'risk_method',stored.risk_method,'risk_score',stored.risk_score,'risk_band',stored.risk_band,
    'score_authority','generated_column','legacy_finding_written',false);
END $$;

CREATE OR REPLACE FUNCTION private_isg.nonconformity_row(p_company uuid,p_nonconformity uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.nonconformities; extra private_isg.nonconformity_details;
BEGIN
  SELECT * INTO entry FROM private_isg.nonconformities
    WHERE nonconformity_id=p_nonconformity AND company_id=p_company;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO extra FROM private_isg.nonconformity_details WHERE nonconformity_id=entry.nonconformity_id;
  RETURN jsonb_build_object('id',entry.nonconformity_id,'workplace_id',entry.workplace_id,
    'source_kind',entry.source_kind,'source_ref',entry.source_ref,'title',entry.title,
    'severity',entry.severity,'state',entry.state,'version',entry.version,
    'record_kind',entry.record_kind,
    'opened_on',entry.opened_on,'due_on',entry.due_on,'closed_on',entry.closed_on,
    'assignee_contact',entry.assignee_contact,
    -- Absent detail reads as absent, never as an empty or zero score.
    'detail',CASE WHEN extra.nonconformity_id IS NULL THEN NULL ELSE jsonb_build_object(
      'description',extra.hazard_description,'control_measure',extra.control_measure,
      'legislation_ref',extra.legislation_ref,'responsible_contact',extra.responsible_contact,
      'risk_method',extra.risk_method,'fk_probability',extra.fk_probability,'fk_frequency',extra.fk_frequency,
      'fk_severity',extra.fk_severity,'m5_probability',extra.m5_probability,'m5_severity',extra.m5_severity,
      'risk_score',extra.risk_score,'risk_band',extra.risk_band,'score_authority','generated_column') END,
    'actions',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',a.action_id,'description',a.description,
        'assignee',a.assignee_contact,'due_on',a.due_on,'state',a.state) ORDER BY a.created_at),'[]'::jsonb)
      FROM private_isg.nonconformity_actions a WHERE a.nonconformity_id=entry.nonconformity_id),
    'verifications',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',v.verification_id,'outcome',v.outcome,
        'verified_on',v.verified_on) ORDER BY v.verified_on),'[]'::jsonb)
      FROM private_isg.verification_records v WHERE v.nonconformity_id=entry.nonconformity_id),
    'legacy_finding_written',false);
END $$;

CREATE OR REPLACE FUNCTION private_isg.read_nonconformities(p_company uuid,p_kind text,p_query text,p_state text,
  p_after uuid,p_id uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; rows jsonb; needle text;
BEGIN
  actor:=private_isg.require_nonconformity_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('list','detail','workplaces') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    rows:=private_isg.nonconformity_row(p_company,p_id);
    IF rows IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'kind','detail','row',rows);
  END IF;
  IF p_kind='workplaces' THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,'needs_review',w.needs_review)
      ORDER BY w.name),'[]'::jsonb) INTO rows
      FROM private_isg.workplaces w WHERE w.company_id=p_company AND w.owner_id=actor AND NOT w.is_archived;
    RETURN jsonb_build_object('schema_version',1,'kind','workplaces','rows',rows);
  END IF;
  IF p_state IS NOT NULL AND p_state NOT IN ('draft','open','assigned','in_progress','pending_verification',
      'closed','reopened','cancelled') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  needle:=nullif(btrim(coalesce(p_query,'')),'');
  -- 'row' is a keyword-shaped alias; name it something the parser cannot claim.
  SELECT coalesce(jsonb_agg(entry ORDER BY (entry->>'opened_on') DESC,(entry->>'id')),'[]'::jsonb) INTO rows FROM (
    SELECT jsonb_build_object('id',n.nonconformity_id,'workplace_id',n.workplace_id,'title',n.title,
      'severity',n.severity,'state',n.state,'version',n.version,'opened_on',n.opened_on,'due_on',n.due_on,
      'record_kind',n.record_kind,'risk_band',d.risk_band,
      'source_kind',n.source_kind,'source_ref',n.source_ref) AS entry
    FROM private_isg.nonconformities n
    LEFT JOIN private_isg.nonconformity_details d ON d.nonconformity_id=n.nonconformity_id
    WHERE n.company_id=p_company AND n.owner_id=actor
      AND (p_state IS NULL OR n.state=p_state)
      AND (needle IS NULL OR n.title ILIKE '%'||needle||'%')
      AND (p_after IS NULL OR n.nonconformity_id<>p_after)
    ORDER BY n.opened_on DESC,n.nonconformity_id LIMIT 200) page;
  RETURN jsonb_build_object('schema_version',1,'kind','list','rows',rows,'legacy_findings_written',false);
END $$;

CREATE OR REPLACE FUNCTION private_isg.mutate_nonconformity(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.nonconformity_receipts;
  result jsonb; detail jsonb; resolved_severity text; resolved_kind text; target uuid;
  stamp timestamptz:=clock_timestamp();
BEGIN
  actor:=private_isg.require_nonconformity_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>8192 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  allowed:=CASE p_action
    WHEN 'open_manual' THEN ARRAY['workplace_id','title','severity','opened_on','due_on','assignee']
    WHEN 'open_from_finding' THEN ARRAY['workplace_id','title','risk_band','severity','finding_id','opened_on','due_on']
    -- An expert-opinion item arrives unscored. There is deliberately no
    -- 'risk_band' key here: nothing can be mapped from a score that does not exist.
    WHEN 'open_from_expert_item' THEN ARRAY['workplace_id','title','severity','record_kind','item_id',
      'opened_on','due_on','assignee','description']
    WHEN 'open_detailed' THEN ARRAY['workplace_id','title','severity','record_kind','opened_on','due_on','assignee',
      'description','control_measure','legislation_ref','responsible_contact','risk_method',
      'fk_probability','fk_frequency','fk_severity','m5_probability','m5_severity']
    WHEN 'set_detail' THEN ARRAY['nonconformity_id','description','control_measure','legislation_ref',
      'responsible_contact','risk_method','fk_probability','fk_frequency','fk_severity','m5_probability','m5_severity']
    WHEN 'transition' THEN ARRAY['nonconformity_id','expected_version','to_state','reason','assignee','closed_on']
    WHEN 'add_action' THEN ARRAY['nonconformity_id','description','assignee','due_on','external_ref']
    WHEN 'verify' THEN ARRAY['nonconformity_id','outcome','verified_on','note']
    ELSE NULL END;
  IF allowed IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO offending FROM jsonb_object_keys(p_payload) AS keys(key)
    WHERE NOT (key=ANY(allowed)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;

  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-nonconformity:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.nonconformity_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN prior.response||jsonb_build_object('replayed',true);
  END IF;

  IF p_action IN ('open_manual','open_from_finding','open_from_expert_item','open_detailed') THEN
    -- An explicitly chosen severity wins; otherwise the legacy band maps across,
    -- and an unreadable band refuses instead of guessing the lowest one.
    resolved_severity:=CASE WHEN p_payload ? 'severity' THEN p_payload->>'severity'
      ELSE private_isg.severity_for_risk_band(p_payload->>'risk_band') END;
    -- Only the two screens that can say so may file an improvement; the older
    -- two actions carry no record_kind key at all and stay nonconformities.
    resolved_kind:=coalesce(p_payload->>'record_kind','nonconformity');
    result:=private_isg.open_nonconformity_record(p_company,(p_payload->>'workplace_id')::uuid,
      CASE p_action WHEN 'open_from_finding' THEN 'legacy_finding'
                    WHEN 'open_from_expert_item' THEN 'legacy_expert_item' ELSE 'manual' END,
      CASE p_action WHEN 'open_from_finding' THEN p_payload->>'finding_id'
                    WHEN 'open_from_expert_item' THEN p_payload->>'item_id' ELSE NULL END,
      p_payload->>'title',resolved_severity,resolved_kind,
      coalesce((p_payload->>'opened_on')::date,(stamp AT TIME ZONE 'Europe/Istanbul')::date),
      (p_payload->>'due_on')::date,p_payload->>'assignee',stamp);
    target:=(result->>'nonconformity_id')::uuid;
    -- A replayed open must not overwrite the detail that is already there.
    IF (result->>'replayed')::boolean IS NOT TRUE AND p_action IN ('open_detailed','open_from_expert_item')
       AND p_payload ?| ARRAY['description','control_measure','legislation_ref','responsible_contact','risk_method',
         'fk_probability','fk_frequency','fk_severity','m5_probability','m5_severity'] THEN
      detail:=private_isg.set_nonconformity_detail(target,p_payload->>'description',
        p_payload->>'control_measure',p_payload->>'legislation_ref',p_payload->>'responsible_contact',
        p_payload->>'risk_method',(p_payload->>'fk_probability')::numeric,(p_payload->>'fk_frequency')::numeric,
        (p_payload->>'fk_severity')::numeric,(p_payload->>'m5_probability')::integer,
        (p_payload->>'m5_severity')::integer,stamp);
      result:=result||jsonb_build_object('detail',detail);
    END IF;
  ELSIF p_action='set_detail' THEN
    target:=(p_payload->>'nonconformity_id')::uuid;
    PERFORM 1 FROM private_isg.nonconformities WHERE nonconformity_id=target AND company_id=p_company AND owner_id=actor;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    result:=private_isg.set_nonconformity_detail(target,p_payload->>'description',
      p_payload->>'control_measure',p_payload->>'legislation_ref',p_payload->>'responsible_contact',
      p_payload->>'risk_method',(p_payload->>'fk_probability')::numeric,(p_payload->>'fk_frequency')::numeric,
      (p_payload->>'fk_severity')::numeric,(p_payload->>'m5_probability')::integer,
      (p_payload->>'m5_severity')::integer,stamp);
  ELSIF p_action='transition' THEN
    target:=(p_payload->>'nonconformity_id')::uuid;
    PERFORM 1 FROM private_isg.nonconformities WHERE nonconformity_id=target AND company_id=p_company AND owner_id=actor;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    result:=private_isg.transition_nonconformity(target,p_payload->>'to_state',
      (p_payload->>'expected_version')::bigint,p_payload->>'reason',p_payload->>'assignee',actor,
      (p_payload->>'closed_on')::date,stamp);
  ELSIF p_action='add_action' THEN
    target:=(p_payload->>'nonconformity_id')::uuid;
    PERFORM 1 FROM private_isg.nonconformities WHERE nonconformity_id=target AND company_id=p_company AND owner_id=actor;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    result:=private_isg.add_corrective_action(target,p_payload->>'description',p_payload->>'assignee',
      (p_payload->>'due_on')::date,p_payload->>'external_ref',stamp);
  ELSE
    target:=(p_payload->>'nonconformity_id')::uuid;
    PERFORM 1 FROM private_isg.nonconformities WHERE nonconformity_id=target AND company_id=p_company AND owner_id=actor;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    result:=private_isg.record_verification(target,p_payload->>'outcome',actor,
      coalesce((p_payload->>'verified_on')::date,(stamp AT TIME ZONE 'Europe/Istanbul')::date),NULL,p_payload->>'note',stamp);
  END IF;

  result:=jsonb_build_object('schema_version',1,'action',p_action,'operation_id',p_operation,
    'row',private_isg.nonconformity_row(p_company,target),'outcome',result,'legacy_finding_written',false);
  INSERT INTO private_isg.nonconformity_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $$;

REVOKE ALL ON FUNCTION private_isg.open_nonconformity_record(uuid,uuid,text,text,text,text,text,date,date,text,timestamptz),
  private_isg.set_nonconformity_detail(uuid,text,text,text,text,text,numeric,numeric,numeric,integer,integer,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';

-- P09 client slice: the surface behind "Kontrol Listeleri".
-- Additive. No rollout row is added and none is opened: this rides on the
-- `nonconformity` switch the P09 core slice created.
--
-- The core slice built the run, the pinned template version, the item results
-- and the explicit conversion of a failing answer into a nonconformity. Two
-- things were missing rather than merely unreachable:
--
--   1. There was no way to author a template at all. `publish_checklist_version`
--      required a draft that nothing could create, and no template was seeded,
--      so the module could not start a single run.
--   2. `checklist_templates` had no owner. An expert's own list would have
--      landed in a table every account reads, and two experts could not even
--      use the same code.
--
-- Five things this slice makes structurally impossible:
--   1. Another account's template or run cannot be reached, and a code one
--      expert picks can never collide with another's: the stored code is
--      derived from the owner, and the title is what the expert named.
--   2. A failing answer never becomes a nonconformity on its own. Opening one
--      is a separate field in the payload, the core function demands it
--      explicitly, and every read reports `auto_nonconformity: false`.
--   3. A published version is never edited. Changing a list means a new
--      version, and a run pins the version it was filled with, so publishing
--      later cannot rewrite what was answered.
--   4. A run cannot be submitted with an unanswered question, and once
--      submitted no answer can change.
--   5. "Uygulanabilir değil" is only accepted where the template itself said it
--      is allowed.
--
-- The product ships NO ready-made checklist. A question list that arrives in
-- the box reads as a statement of what the law asks for, and no such catalogue
-- has been approved. The expert writes the list, and the screen says so.
SET LOCAL lock_timeout='5s';

-- Whose list this is. NULL is a product template; none is seeded, and no
-- function here can create one, so the column exists for a later approved
-- catalogue rather than for anything shipping today.
ALTER TABLE private_isg.checklist_templates
  ADD COLUMN owner_id uuid REFERENCES public.profiles(id),
  ADD COLUMN is_archived boolean NOT NULL DEFAULT false;
CREATE INDEX checklist_template_owner_idx ON private_isg.checklist_templates(owner_id,is_archived);

CREATE TABLE private_isg.checklist_receipts (
  actor_id uuid NOT NULL, mutation_id uuid NOT NULL, company_id uuid NOT NULL,
  operation_id uuid NOT NULL, request_hash bytea NOT NULL, response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(actor_id,mutation_id),
  FOREIGN KEY(company_id,actor_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
CREATE INDEX checklist_receipt_company_idx ON private_isg.checklist_receipts(company_id,actor_id);
ALTER TABLE private_isg.checklist_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.checklist_receipts FROM PUBLIC,anon,authenticated,service_role;

-- The stored code is derived from the owner and the name they typed, so the
-- global key can never collide across accounts and reveals nothing about
-- another account's lists.
CREATE FUNCTION private_isg.checklist_template_code(p_owner uuid,p_title text) RETURNS text
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT 'c'||left(md5(p_owner::text||':'||btrim(lower(p_title))),20)
$$;

-- Authoring. A draft is the only editable thing; a published version is not.
CREATE FUNCTION private_isg.draft_checklist_template(p_owner uuid,p_title text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE code text; entry private_isg.checklist_templates; next_version integer; existing integer;
BEGIN
  PERFORM private_isg.nonconformity_gate(true);
  IF p_owner IS NULL OR p_title IS NULL OR btrim(p_title)='' OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  code:=private_isg.checklist_template_code(p_owner,p_title);
  SELECT * INTO entry FROM private_isg.checklist_templates WHERE template_code=code FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO private_isg.checklist_templates(template_code,title,owner_id,created_at)
      VALUES(code,private_isg.text_value(p_title,200),p_owner,p_now);
  ELSIF entry.owner_id IS DISTINCT FROM p_owner THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED';
  END IF;
  -- One draft at a time: a second call returns the draft that is already open.
  SELECT version INTO existing FROM private_isg.checklist_template_versions
    WHERE template_code=code AND status='draft' FOR UPDATE;
  IF existing IS NOT NULL THEN
    RETURN jsonb_build_object('schema_version',1,'template_code',code,'version',existing,
      'status','draft','replayed',true); END IF;
  SELECT coalesce(max(version),0)+1 INTO next_version FROM private_isg.checklist_template_versions
    WHERE template_code=code;
  INSERT INTO private_isg.checklist_template_versions(template_code,version,status,created_at)
    VALUES(code,next_version,'draft',p_now);
  -- A new version starts from what is published, so a small change is a small
  -- edit rather than retyping the whole list.
  INSERT INTO private_isg.checklist_template_items(template_code,version,item_code,prompt,allows_not_applicable,position)
    SELECT i.template_code,next_version,i.item_code,i.prompt,i.allows_not_applicable,i.position
    FROM private_isg.checklist_template_items i
    JOIN private_isg.checklist_template_versions v
      ON v.template_code=i.template_code AND v.version=i.version AND v.status='published'
    WHERE i.template_code=code;
  RETURN jsonb_build_object('schema_version',1,'template_code',code,'version',next_version,
    'status','draft','replayed',false);
END $$;

CREATE FUNCTION private_isg.set_checklist_item(p_code text,p_version integer,p_item text,p_prompt text,
  p_allows_na boolean,p_position integer,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.checklist_template_versions;
BEGIN
  PERFORM private_isg.nonconformity_gate(true);
  IF p_code IS NULL OR p_version IS NULL OR p_item IS NULL OR p_prompt IS NULL OR p_position IS NULL OR
     p_allows_na IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.checklist_template_versions
    WHERE template_code=p_code AND version=p_version FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  -- Only a draft is editable. A published list is what runs were filled
  -- against, so it is never changed under them.
  IF entry.status<>'draft' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='TEMPLATE_PUBLISHED'; END IF;
  INSERT INTO private_isg.checklist_template_items(template_code,version,item_code,prompt,allows_not_applicable,position)
    VALUES(p_code,p_version,p_item,private_isg.text_value(p_prompt,500),p_allows_na,p_position)
  ON CONFLICT(template_code,version,item_code) DO UPDATE SET prompt=excluded.prompt,
    allows_not_applicable=excluded.allows_not_applicable,position=excluded.position;
  RETURN jsonb_build_object('schema_version',1,'template_code',p_code,'version',p_version,
    'item_code',p_item,'position',p_position);
END $$;

CREATE FUNCTION private_isg.remove_checklist_item(p_code text,p_version integer,p_item text) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.checklist_template_versions;
BEGIN
  PERFORM private_isg.nonconformity_gate(true);
  IF p_code IS NULL OR p_version IS NULL OR p_item IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.checklist_template_versions
    WHERE template_code=p_code AND version=p_version FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.status<>'draft' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='TEMPLATE_PUBLISHED'; END IF;
  DELETE FROM private_isg.checklist_template_items
    WHERE template_code=p_code AND version=p_version AND item_code=p_item;
  RETURN jsonb_build_object('schema_version',1,'template_code',p_code,'version',p_version,'item_code',p_item);
END $$;

CREATE FUNCTION private_isg.cancel_checklist_run(p_run uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE run private_isg.checklist_runs;
BEGIN
  PERFORM private_isg.nonconformity_gate(true);
  IF p_run IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO run FROM private_isg.checklist_runs WHERE run_id=p_run FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF run.state='cancelled' THEN
    RETURN jsonb_build_object('schema_version',1,'run_id',p_run,'state','cancelled','replayed',true); END IF;
  -- A submitted run is the record of what was checked; it is not withdrawn.
  IF run.state<>'open' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RUN_SUBMITTED'; END IF;
  UPDATE private_isg.checklist_runs SET state='cancelled' WHERE run_id=p_run;
  RETURN jsonb_build_object('schema_version',1,'run_id',p_run,'state','cancelled','replayed',false);
END $$;

CREATE FUNCTION private_isg.checklist_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM private_isg.nonconformity_gate(p_write);
END $$;

-- A NULL company is the whole account, and only for reads: every write names
-- the company it writes into. The core functions were written for a caller that
-- had already checked ownership; this is that caller.
CREATE FUNCTION private_isg.require_checklist_company(p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  IF NOT private_isg.p05_pilot_account_enabled(actor,p_write) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  IF p_company IS NOT NULL AND NOT private_isg.p05_pilot_can_read(actor,p_company) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  PERFORM private_isg.checklist_gate(p_write);
  IF p_write THEN
    IF p_company IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM public.user_subscriptions WHERE user_id=actor AND tier IN ('plus','pro') AND
      status IN ('active','trialing','grace_period') AND
      (current_period_ends_at IS NULL OR current_period_ends_at>clock_timestamp()) FOR SHARE;
    IF NOT FOUND OR private.user_plan_tier(actor) NOT IN ('plus','pro') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAID_PLAN_REQUIRED'; END IF;
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor AND NOT is_archived FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSIF p_company IS NOT NULL THEN
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSE
    IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=actor) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  RETURN actor;
END $$;

-- A template the actor may use: their own, or a product one. There are no
-- product ones today, and nothing here can create one.
CREATE FUNCTION private_isg.require_checklist_template(p_code text,p_actor uuid,p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.checklist_templates;
BEGIN
  SELECT * INTO entry FROM private_isg.checklist_templates WHERE template_code=p_code;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  -- Reading a product template is allowed; editing one is not, because it is
  -- not the expert's to change.
  IF p_write THEN
    IF entry.owner_id IS DISTINCT FROM p_actor THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSIF entry.owner_id IS NOT NULL AND entry.owner_id<>p_actor THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED';
  END IF;
END $$;

-- One run with what it was filled against and what it found. Nothing is stored:
-- the tallies are counted from the answers at read time.
CREATE FUNCTION private_isg.checklist_run_row(p_run uuid,p_items boolean) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE run private_isg.checklist_runs; template private_isg.checklist_templates;
  expected integer; answered integer; failing integer; conform integer; skipped integer; opened integer;
BEGIN
  SELECT * INTO run FROM private_isg.checklist_runs WHERE run_id=p_run;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO template FROM private_isg.checklist_templates WHERE template_code=run.template_code;
  SELECT count(*) INTO expected FROM private_isg.checklist_template_items
    WHERE template_code=run.template_code AND version=run.template_version;
  SELECT count(*),count(*) FILTER (WHERE result='nonconform'),
         count(*) FILTER (WHERE result='conform'),
         count(*) FILTER (WHERE result='not_applicable'),
         count(*) FILTER (WHERE nonconformity_id IS NOT NULL)
    INTO answered,failing,conform,skipped,opened
    FROM private_isg.checklist_run_items WHERE run_id=p_run;
  RETURN jsonb_build_object(
    'id',run.run_id,'company_id',run.company_id,'workplace_id',run.workplace_id,
    'template_code',run.template_code,'template_title',template.title,
    -- The version the run was filled against, pinned when it started.
    'template_version',run.template_version,
    'state',run.state,'started_on',run.started_on,'submitted_at',run.submitted_at,
    'expected',expected,'answered',answered,'remaining',greatest(expected-answered,0),
    'conform',conform,'nonconform',failing,'not_applicable',skipped,
    -- How many failing answers the expert chose to turn into a record. It is
    -- never all of them by default, because nothing converts on its own.
    'nonconformities_opened',opened,
    'auto_nonconformity',false,
    'items',CASE WHEN p_items THEN
      (SELECT coalesce(jsonb_agg(jsonb_build_object('item_code',t.item_code,'prompt',t.prompt,
          'position',t.position,'allows_not_applicable',t.allows_not_applicable,
          'result',r.result,'note',r.note,'nonconformity_id',r.nonconformity_id,
          'recorded_at',r.recorded_at) ORDER BY t.position),'[]'::jsonb)
       FROM private_isg.checklist_template_items t
       LEFT JOIN private_isg.checklist_run_items r ON r.run_id=p_run AND r.item_code=t.item_code
       WHERE t.template_code=run.template_code AND t.version=run.template_version) END,
    'compliance_verdict',NULL,'health_records_tracked',false);
END $$;

CREATE FUNCTION private_isg.read_checklists(p_company uuid,p_kind text,p_query text,p_state text,
  p_workplace uuid,p_template text,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; needle text; today date;
  page_limit integer; page_offset integer;
  tally_all jsonb; tally_companies jsonb; tally_rows jsonb; matching_rows integer;
BEGIN
  actor:=private_isg.require_checklist_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('catalog','templates','list','detail') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date;

  IF p_kind='catalog' THEN
    RETURN jsonb_build_object('schema_version',1,'kind','catalog',
      'workplaces',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,
          'needs_review',w.needs_review) ORDER BY w.name),'[]'::jsonb)
        FROM private_isg.workplaces w
        WHERE p_company IS NOT NULL AND w.company_id=p_company AND w.owner_id=actor AND NOT w.is_archived),
      -- The lists a run may be started from: published only, and only the
      -- expert's own or a product one.
      'templates',(SELECT coalesce(jsonb_agg(jsonb_build_object('template_code',t.template_code,
          'title',t.title,'version',v.version,'items',
          (SELECT count(*) FROM private_isg.checklist_template_items i
            WHERE i.template_code=t.template_code AND i.version=v.version),
          'is_product',t.owner_id IS NULL) ORDER BY t.title),'[]'::jsonb)
        FROM private_isg.checklist_templates t
        JOIN private_isg.checklist_template_versions v
          ON v.template_code=t.template_code AND v.status='published'
        WHERE NOT t.is_archived AND (t.owner_id IS NULL OR t.owner_id=actor)),
      -- Said plainly rather than implied by an empty list: the product does not
      -- ship a question set, because no approved one exists.
      'product_templates_offered',false,
      'auto_nonconformity',false,
      'health_records_tracked',false);
  END IF;

  IF p_kind='templates' THEN
    RETURN jsonb_build_object('schema_version',1,'kind','templates',
      'rows',(SELECT coalesce(jsonb_agg(jsonb_build_object('template_code',t.template_code,'title',t.title,
          'is_product',t.owner_id IS NULL,'is_archived',t.is_archived,
          'versions',(SELECT coalesce(jsonb_agg(jsonb_build_object('version',v.version,'status',v.status,
              'published_at',v.published_at,'approval_note',v.approval_note,
              'items',(SELECT coalesce(jsonb_agg(jsonb_build_object('item_code',i.item_code,'prompt',i.prompt,
                  'position',i.position,'allows_not_applicable',i.allows_not_applicable)
                  ORDER BY i.position),'[]'::jsonb)
                FROM private_isg.checklist_template_items i
                WHERE i.template_code=v.template_code AND i.version=v.version))
              ORDER BY v.version DESC),'[]'::jsonb)
            FROM private_isg.checklist_template_versions v WHERE v.template_code=t.template_code))
          ORDER BY t.title),'[]'::jsonb)
        FROM private_isg.checklist_templates t
        WHERE t.owner_id IS NULL OR t.owner_id=actor),
      -- An expert's approval of their own list is exactly that, and no more.
      'approval_is_self_declared',true,
      'product_templates_offered',false);
  END IF;

  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.checklist_runs r
      JOIN public.companies c ON c.id=r.company_id AND c.user_id=actor
      WHERE r.run_id=p_id AND (p_company IS NULL OR r.company_id=p_company);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'kind','detail','today',today,
      'row',private_isg.checklist_run_row(p_id,true));
  END IF;

  IF p_state IS NOT NULL AND p_state NOT IN ('open','submitted','cancelled') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  page_limit:=least(greatest(coalesce(p_limit,10),1),100);
  page_offset:=greatest(coalesce(p_offset,0),0);
  needle:=nullif(btrim(coalesce(p_query,'')),'');

  WITH scope AS (
    SELECT c.id,c.name FROM public.companies c WHERE c.user_id=actor AND NOT c.is_archived AND private_isg.p05_pilot_can_read(actor,c.id)
  ), page AS (
    SELECT r.run_id,r.company_id,s.name AS company_name,r.workplace_id,w.name AS workplace_name,
      r.template_code,t.title AS template_title,r.state AS entry_state,r.started_on,
      -- Open first, because an unfinished run is the one that needs a person.
      row_number() OVER (ORDER BY
        CASE r.state WHEN 'open' THEN 0 WHEN 'submitted' THEN 1 ELSE 2 END,
        r.started_on DESC,s.name,w.name,r.run_id) AS ordinal
    FROM private_isg.checklist_runs r
    JOIN scope s ON s.id=r.company_id
    JOIN private_isg.workplaces w ON w.company_id=r.company_id AND w.id=r.workplace_id
    JOIN private_isg.checklist_templates t ON t.template_code=r.template_code
    WHERE r.owner_id=actor
  ), scoped AS (
    SELECT * FROM page WHERE (p_company IS NULL OR company_id=p_company)
  ), filtered AS (
    SELECT * FROM scoped
    WHERE (p_workplace IS NULL OR workplace_id=p_workplace)
      AND (p_template IS NULL OR template_code=p_template)
      AND (p_state IS NULL OR entry_state=p_state)
      AND (needle IS NULL OR template_title ILIKE '%'||needle||'%'
           OR workplace_name ILIKE '%'||needle||'%' OR company_name ILIKE '%'||needle||'%')
  )
  SELECT
    (SELECT coalesce(jsonb_object_agg(state,total),'{}'::jsonb) FROM
      (SELECT entry_state AS state,count(*) AS total FROM page GROUP BY entry_state) a),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'total',total,'counts',states)
       ORDER BY name),'[]'::jsonb) FROM
      (SELECT company_id AS id,max(company_name) AS name,count(*) AS total,
        jsonb_object_agg(entry_state,state_total) AS states FROM
        (SELECT company_id,company_name,entry_state,count(*) AS state_total FROM page
          GROUP BY company_id,company_name,entry_state) b GROUP BY company_id) c),
    (SELECT count(*) FROM filtered),
    (SELECT coalesce(jsonb_agg(entry ORDER BY sort),'[]'::jsonb) FROM (
       SELECT picked.ordinal AS sort,
         private_isg.checklist_run_row(picked.run_id,false)
           ||jsonb_build_object('company_name',picked.company_name,
               'workplace_name',picked.workplace_name) AS entry
       FROM (SELECT * FROM filtered ORDER BY ordinal LIMIT page_limit OFFSET page_offset) picked) built)
  INTO tally_all,tally_companies,matching_rows,tally_rows;

  RETURN jsonb_build_object('schema_version',1,'kind','list','rows',tally_rows,'today',today,
    'counts',tally_all,'companies',tally_companies,
    'total',matching_rows,'returned',jsonb_array_length(tally_rows),
    'has_more',page_offset+jsonb_array_length(tally_rows)<matching_rows,
    'limit',page_limit,'offset',page_offset,
    -- A tally of checks that were run, never a statement that any workplace is
    -- compliant, and never a claim that a failing answer became a finding.
    'compliance_verdict',NULL,'auto_nonconformity',false,'health_records_tracked',false);
END $$;

-- Every write goes through the function that owns the rule. This is the
-- boundary: it proves who is asking, allowlists what may be sent, and keeps the
-- receipt so the same request twice is the same answer twice.
CREATE FUNCTION private_isg.mutate_checklists(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.checklist_receipts;
  result jsonb; answer jsonb; run uuid; entry private_isg.checklist_runs;
  stamp timestamptz:=clock_timestamp(); today date;
BEGIN
  actor:=private_isg.require_checklist_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>8192 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(stamp AT TIME ZONE 'Europe/Istanbul')::date;
  allowed:=CASE p_action
    WHEN 'draft_template' THEN ARRAY['title']
    WHEN 'set_item' THEN ARRAY['template_code','version','item_code','prompt','allows_not_applicable','position']
    WHEN 'remove_item' THEN ARRAY['template_code','version','item_code']
    -- No approver here: an expert approves their own list, and the boundary
    -- supplies who that is rather than letting the client name someone.
    WHEN 'publish_template' THEN ARRAY['template_code','version','approval_note']
    WHEN 'start_run' THEN ARRAY['workplace_id','template_code','started_on']
    -- `open_nonconformity` is its own field on purpose: a failing answer never
    -- becomes a record unless this says so.
    WHEN 'record_item' THEN ARRAY['run_id','item_code','result','note','open_nonconformity',
      'severity','due_on']
    WHEN 'submit_run' THEN ARRAY['run_id']
    WHEN 'cancel_run' THEN ARRAY['run_id']
    ELSE NULL END;
  IF allowed IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO offending FROM jsonb_object_keys(p_payload) AS keys(key)
    WHERE NOT (key=ANY(allowed)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;

  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-checklist:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.checklist_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN prior.response||jsonb_build_object('replayed',true);
  END IF;

  IF p_action='draft_template' THEN
    IF p_payload->>'title' IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    answer:=private_isg.draft_checklist_template(actor,p_payload->>'title',stamp);
  ELSIF p_action IN ('set_item','remove_item','publish_template') THEN
    IF p_payload->>'template_code' IS NULL OR p_payload->>'version' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    -- A product template is readable but never editable, and another account's
    -- is neither.
    PERFORM private_isg.require_checklist_template(p_payload->>'template_code',actor,true);
    IF p_action='set_item' THEN
      IF p_payload->>'item_code' IS NULL OR p_payload->>'prompt' IS NULL OR
         p_payload->>'position' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.set_checklist_item(p_payload->>'template_code',(p_payload->>'version')::integer,
        p_payload->>'item_code',p_payload->>'prompt',
        coalesce((p_payload->>'allows_not_applicable')::boolean,true),
        (p_payload->>'position')::integer,stamp);
    ELSIF p_action='remove_item' THEN
      IF p_payload->>'item_code' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.remove_checklist_item(p_payload->>'template_code',
        (p_payload->>'version')::integer,p_payload->>'item_code');
    ELSE
      IF p_payload->>'approval_note' IS NULL OR btrim(p_payload->>'approval_note')='' THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.publish_checklist_version(p_payload->>'template_code',
        (p_payload->>'version')::integer,actor,p_payload->>'approval_note',stamp);
    END IF;
  ELSIF p_action='start_run' THEN
    IF p_payload->>'workplace_id' IS NULL OR p_payload->>'template_code' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.workplaces WHERE company_id=p_company
      AND id=(p_payload->>'workplace_id')::uuid AND owner_id=actor AND NOT is_archived;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    PERFORM private_isg.require_checklist_template(p_payload->>'template_code',actor,false);
    answer:=private_isg.start_checklist_run(p_company,(p_payload->>'workplace_id')::uuid,
      p_payload->>'template_code',
      coalesce((p_payload->>'started_on')::date,today),stamp);
    run:=(answer->>'run_id')::uuid;
  ELSE
    run:=(p_payload->>'run_id')::uuid;
    SELECT * INTO entry FROM private_isg.checklist_runs
      WHERE run_id=run AND company_id=p_company AND owner_id=actor FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF p_action='record_item' THEN
      IF p_payload->>'item_code' IS NULL OR p_payload->>'result' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.record_run_item(run,p_payload->>'item_code',p_payload->>'result',
        nullif(btrim(coalesce(p_payload->>'note','')),''),NULL,
        coalesce((p_payload->>'open_nonconformity')::boolean,false),
        nullif(btrim(coalesce(p_payload->>'severity','')),''),
        (p_payload->>'due_on')::date,stamp);
    ELSIF p_action='submit_run' THEN
      answer:=private_isg.submit_checklist_run(run,stamp);
    ELSE
      answer:=private_isg.cancel_checklist_run(run,stamp);
    END IF;
  END IF;

  result:=jsonb_build_object('schema_version',1,'action',p_action,'answer',answer,
    'run_id',run,'row',CASE WHEN run IS NOT NULL THEN private_isg.checklist_run_row(run,true) END,
    'auto_nonconformity',false);
  INSERT INTO private_isg.checklist_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $$;

CREATE FUNCTION public.isg_checklists_read_v1(p_company uuid,p_kind text,p_query text,p_state text,
  p_workplace uuid,p_template text,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.read_checklists(p_company,p_kind,p_query,p_state,p_workplace,p_template,p_id,p_limit,p_offset)
$$;
CREATE FUNCTION public.isg_checklists_mutate_v1(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.mutate_checklists(p_company,p_action,p_operation,p_mutation,p_payload)
$$;

REVOKE ALL ON FUNCTION private_isg.checklist_template_code(uuid,text),
  private_isg.draft_checklist_template(uuid,text,timestamptz),
  private_isg.set_checklist_item(text,integer,text,text,boolean,integer,timestamptz),
  private_isg.remove_checklist_item(text,integer,text),
  private_isg.cancel_checklist_run(uuid,timestamptz),
  private_isg.checklist_gate(boolean),
  private_isg.require_checklist_company(uuid,boolean),
  private_isg.require_checklist_template(text,uuid,boolean),
  private_isg.checklist_run_row(uuid,boolean),
  private_isg.read_checklists(uuid,text,text,text,uuid,text,uuid,integer,integer),
  private_isg.mutate_checklists(uuid,text,uuid,uuid,jsonb),
  public.isg_checklists_read_v1(uuid,text,text,text,uuid,text,uuid,integer,integer),
  public.isg_checklists_mutate_v1(uuid,text,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.read_checklists(uuid,text,text,text,uuid,text,uuid,integer,integer),
  private_isg.mutate_checklists(uuid,text,uuid,uuid,jsonb),
  public.isg_checklists_read_v1(uuid,text,text,text,uuid,text,uuid,integer,integer),
  public.isg_checklists_mutate_v1(uuid,text,uuid,uuid,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
