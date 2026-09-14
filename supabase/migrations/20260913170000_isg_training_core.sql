-- P07/D07 first slice: versioned training catalogue, workplace curriculum with
-- its own G4 version, plan/session/enrolment/attendance/assessment and an
-- immutable completion that can satisfy a P06 obligation.
-- Additive; rollout OFF; no client grant; NO legal content is seeded here.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE private_isg.rollout DROP CONSTRAINT rollout_feature_check;
ALTER TABLE private_isg.rollout ADD CONSTRAINT rollout_feature_check
  CHECK(feature IN ('personnel','event_dispatch','quota_ledger','file_core','rule_engine','training'));
INSERT INTO private_isg.rollout(feature) VALUES('training');

-- A special catalogue is its own namespace. Naming a special course
-- "Temel İSG" does not make it the official one.
CREATE TABLE private_isg.training_catalogs (
  catalog_code text PRIMARY KEY CHECK(catalog_code ~ '^[a-z][a-z0-9_]{2,60}$'),
  namespace text NOT NULL CHECK(namespace IN ('official','special')),
  title text NOT NULL CHECK(btrim(title)<>'' AND length(title)<=200),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE private_isg.training_catalog_versions (
  catalog_code text NOT NULL REFERENCES private_isg.training_catalogs(catalog_code) ON DELETE CASCADE,
  version integer NOT NULL CHECK(version BETWEEN 1 AND 1000),
  source_id uuid REFERENCES private_isg.legal_sources(source_id),
  status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','published','superseded')),
  -- The V5 figures are fixtures until the official text is reviewed, so a
  -- version says out loud whether its content was ever approved.
  content_approved boolean NOT NULL DEFAULT false,
  approved_by uuid REFERENCES public.profiles(id), approval_note text, published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(catalog_code,version),
  CHECK(status<>'published' OR (approved_by IS NOT NULL AND approval_note IS NOT NULL AND published_at IS NOT NULL))
);
CREATE UNIQUE INDEX training_single_published_idx ON private_isg.training_catalog_versions(catalog_code) WHERE status='published';
-- Official sub-topic groups are versioned with the catalogue. A UI short title
-- never replaces the official document label.
CREATE TABLE private_isg.training_topic_groups (
  catalog_code text NOT NULL, version integer NOT NULL,
  group_code text NOT NULL CHECK(group_code IN ('G1','G2','G3','G4')),
  official_label text NOT NULL CHECK(btrim(official_label)<>''),
  min_lessons integer NOT NULL CHECK(min_lessons BETWEEN 0 AND 200),
  PRIMARY KEY(catalog_code,version,group_code),
  FOREIGN KEY(catalog_code,version) REFERENCES private_isg.training_catalog_versions(catalog_code,version) ON DELETE CASCADE
);
CREATE TABLE private_isg.training_class_rules (
  catalog_code text NOT NULL, version integer NOT NULL,
  hazard_class text NOT NULL CHECK(hazard_class IN ('low','medium','high')),
  first_lessons integer NOT NULL CHECK(first_lessons BETWEEN 1 AND 200),
  refresh_lessons integer NOT NULL CHECK(refresh_lessons BETWEEN 1 AND 200),
  onboarding_lessons integer NOT NULL CHECK(onboarding_lessons BETWEEN 1 AND 200),
  refresh_period_years integer NOT NULL CHECK(refresh_period_years BETWEEN 1 AND 10),
  lesson_minutes integer NOT NULL CHECK(lesson_minutes BETWEEN 1 AND 240),
  break_minutes integer NOT NULL CHECK(break_minutes BETWEEN 0 AND 240),
  pass_score integer NOT NULL CHECK(pass_score BETWEEN 0 AND 100),
  max_attempts integer NOT NULL CHECK(max_attempts BETWEEN 1 AND 10),
  PRIMARY KEY(catalog_code,version,hazard_class),
  FOREIGN KEY(catalog_code,version) REFERENCES private_isg.training_catalog_versions(catalog_code,version) ON DELETE CASCADE
);
-- G4 is workplace specific and versioned on its own: a job or risk change
-- produces a new curriculum version, it never edits a signed past record.
CREATE TABLE private_isg.company_curriculum_versions (
  curriculum_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL, workplace_id uuid NOT NULL,
  catalog_code text NOT NULL, catalog_version integer NOT NULL,
  version integer NOT NULL CHECK(version>=1),
  hazard_class text NOT NULL CHECK(hazard_class IN ('low','medium','high')),
  g4_topics jsonb NOT NULL, g4_lessons integer NOT NULL CHECK(g4_lessons BETWEEN 0 AND 200),
  state text NOT NULL DEFAULT 'draft' CHECK(state IN ('draft','active','superseded')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id,workplace_id,catalog_code,version),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE,
  FOREIGN KEY(catalog_code,catalog_version) REFERENCES private_isg.training_catalog_versions(catalog_code,version)
);
CREATE UNIQUE INDEX curriculum_single_active_idx ON private_isg.company_curriculum_versions(company_id,workplace_id,catalog_code) WHERE state='active';
-- A plan is not a completion. Creating one trains nobody.
CREATE TABLE private_isg.training_plans (
  plan_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, workplace_id uuid NOT NULL,
  curriculum_id uuid NOT NULL REFERENCES private_isg.company_curriculum_versions(curriculum_id) ON DELETE CASCADE,
  requirement_id uuid REFERENCES private_isg.requirement_instances(requirement_id) ON DELETE SET NULL,
  kind text NOT NULL CHECK(kind IN ('first','refresh','onboarding','special')),
  planned_on date NOT NULL CHECK(isfinite(planned_on)),
  state text NOT NULL DEFAULT 'planned' CHECK(state IN ('planned','running','closed','cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE private_isg.training_sessions (
  session_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id uuid NOT NULL REFERENCES private_isg.training_plans(plan_id) ON DELETE CASCADE,
  method text NOT NULL CHECK(method IN ('classroom','online_sync','online_async','on_the_job')),
  starts_at timestamptz NOT NULL, ends_at timestamptz NOT NULL,
  -- Lesson time and break time are separate fields; a break is not instruction.
  lesson_minutes integer NOT NULL CHECK(lesson_minutes BETWEEN 1 AND 240),
  break_minutes integer NOT NULL CHECK(break_minutes BETWEEN 0 AND 240),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK(starts_at<ends_at)
);
CREATE TABLE private_isg.training_enrolments (
  enrolment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES private_isg.training_sessions(session_id) ON DELETE CASCADE,
  company_id uuid NOT NULL, employee_id uuid NOT NULL,
  state text NOT NULL DEFAULT 'enrolled' CHECK(state IN ('enrolled','completed','withdrawn')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(session_id,employee_id),
  FOREIGN KEY(company_id,employee_id) REFERENCES private_isg.employees(company_id,id) ON DELETE CASCADE
);
CREATE TABLE private_isg.attendance_intervals (
  interval_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  enrolment_id uuid NOT NULL REFERENCES private_isg.training_enrolments(enrolment_id) ON DELETE CASCADE,
  starts_at timestamptz NOT NULL, ends_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK(starts_at<ends_at), UNIQUE(enrolment_id,starts_at,ends_at)
);
CREATE TABLE private_isg.assessment_attempts (
  attempt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  enrolment_id uuid NOT NULL REFERENCES private_isg.training_enrolments(enrolment_id) ON DELETE CASCADE,
  attempt_no integer NOT NULL CHECK(attempt_no BETWEEN 1 AND 10),
  score integer NOT NULL CHECK(score BETWEEN 0 AND 100),
  passed boolean NOT NULL, attempted_at timestamptz NOT NULL,
  UNIQUE(enrolment_id,attempt_no)
);
-- Finalised completions are immutable: later catalogue or curriculum versions
-- never rewrite a past record.
CREATE TABLE private_isg.training_completions (
  completion_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  enrolment_id uuid NOT NULL UNIQUE REFERENCES private_isg.training_enrolments(enrolment_id) ON DELETE CASCADE,
  company_id uuid NOT NULL, employee_id uuid NOT NULL, workplace_id uuid NOT NULL,
  catalog_code text NOT NULL, catalog_version integer NOT NULL, curriculum_version integer NOT NULL,
  kind text NOT NULL, hazard_class text NOT NULL,
  credited_minutes integer NOT NULL CHECK(credited_minutes>=0),
  required_minutes integer NOT NULL CHECK(required_minutes>=0),
  score integer NOT NULL CHECK(score BETWEEN 0 AND 100), attempts_used integer NOT NULL CHECK(attempts_used>=1),
  completed_on date NOT NULL CHECK(isfinite(completed_on)),
  valid_until date CHECK(valid_until IS NULL OR isfinite(valid_until)),
  content_approved boolean NOT NULL,
  snapshot jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(company_id,employee_id) REFERENCES private_isg.employees(company_id,id) ON DELETE CASCADE
);
-- An external certificate is its own record with its own evidence. It is not a
-- completion of our catalogue and never becomes one.
CREATE TABLE private_isg.external_credentials (
  credential_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, employee_id uuid NOT NULL,
  issuer text NOT NULL CHECK(btrim(issuer)<>'' AND length(issuer)<=200),
  title text NOT NULL CHECK(btrim(title)<>'' AND length(title)<=200),
  issued_on date NOT NULL CHECK(isfinite(issued_on)),
  valid_until date CHECK(valid_until IS NULL OR isfinite(valid_until)),
  asset_id uuid REFERENCES private_isg.file_assets(asset_id),
  evidence_note text CHECK(evidence_note IS NULL OR length(evidence_note)<=1000),
  needs_review boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id,employee_id,issuer,title,issued_on),
  CHECK(valid_until IS NULL OR issued_on<valid_until),
  CHECK(needs_review OR asset_id IS NOT NULL),
  FOREIGN KEY(company_id,employee_id) REFERENCES private_isg.employees(company_id,id) ON DELETE CASCADE
);
CREATE INDEX curriculum_scope_idx ON private_isg.company_curriculum_versions(company_id,workplace_id);
CREATE INDEX curriculum_owner_idx ON private_isg.company_curriculum_versions(company_id,owner_id);
CREATE INDEX curriculum_catalog_idx ON private_isg.company_curriculum_versions(catalog_code,catalog_version);
CREATE INDEX plan_scope_idx ON private_isg.training_plans(company_id,workplace_id,state);
CREATE INDEX plan_curriculum_idx ON private_isg.training_plans(curriculum_id);
CREATE INDEX plan_requirement_idx ON private_isg.training_plans(requirement_id);
CREATE INDEX session_plan_idx ON private_isg.training_sessions(plan_id);
CREATE INDEX enrolment_employee_idx ON private_isg.training_enrolments(company_id,employee_id);
CREATE INDEX attendance_enrolment_idx ON private_isg.attendance_intervals(enrolment_id,starts_at);
CREATE INDEX completion_employee_idx ON private_isg.training_completions(company_id,employee_id);
CREATE INDEX completion_validity_idx ON private_isg.training_completions(company_id,valid_until);
CREATE INDEX credential_employee_idx ON private_isg.external_credentials(company_id,employee_id);
CREATE INDEX credential_asset_idx ON private_isg.external_credentials(asset_id);
CREATE INDEX catalog_version_source_idx ON private_isg.training_catalog_versions(source_id);
CREATE INDEX catalog_version_approver_idx ON private_isg.training_catalog_versions(approved_by);
ALTER TABLE private_isg.training_catalogs ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.training_catalog_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.training_topic_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.training_class_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.company_curriculum_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.training_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.training_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.training_enrolments ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.attendance_intervals ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.assessment_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.training_completions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.external_credentials ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.training_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM private_isg.rollout WHERE feature='training' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $$;
-- Credited time is the union of attendance, never the sum: the same minute
-- cannot be paid twice, not even inside one enrolment.
CREATE FUNCTION private_isg.attendance_minutes(p_enrolment uuid) RETURNS integer
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
  WITH bounds AS (
    SELECT starts_at,ends_at,max(ends_at) OVER (ORDER BY starts_at,ends_at
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS prior_end
    FROM private_isg.attendance_intervals WHERE enrolment_id=p_enrolment),
  islands AS (
    SELECT starts_at,ends_at,count(*) FILTER (WHERE prior_end IS NULL OR starts_at>prior_end)
      OVER (ORDER BY starts_at,ends_at) AS island FROM bounds),
  merged AS (SELECT min(starts_at) AS opens, max(ends_at) AS closes FROM islands GROUP BY island)
  SELECT coalesce(floor(sum(extract(epoch FROM closes-opens))/60),0)::integer FROM merged
$$;
CREATE FUNCTION private_isg.publish_catalog_version(p_code text,p_version integer,p_approver uuid,p_note text,
  p_content_approved boolean,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.training_catalog_versions; catalog private_isg.training_catalogs;
  source private_isg.legal_sources; previous integer;
BEGIN
  PERFORM private_isg.training_gate(true);
  IF p_code IS NULL OR p_version IS NULL OR p_approver IS NULL OR p_note IS NULL OR p_now IS NULL OR
     p_content_approved IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.training_catalog_versions WHERE catalog_code=p_code AND version=p_version FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.status='published' THEN RETURN jsonb_build_object('schema_version',1,'catalog_code',p_code,'version',p_version,'status','published','replayed',true); END IF;
  IF entry.status<>'draft' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO catalog FROM private_isg.training_catalogs WHERE catalog_code=p_code FOR SHARE;
  -- Official content needs a verified legal source; a special course does not
  -- borrow official equivalence by claiming one.
  IF catalog.namespace='official' THEN
    IF entry.source_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RULE_NEEDS_REVIEW'; END IF;
    SELECT * INTO source FROM private_isg.legal_sources WHERE source_id=entry.source_id FOR SHARE;
    IF source.needs_review THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RULE_NEEDS_REVIEW'; END IF;
  ELSIF p_content_approved THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';
  END IF;
  PERFORM 1 FROM private_isg.training_class_rules WHERE catalog_code=p_code AND version=p_version;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT version INTO previous FROM private_isg.training_catalog_versions WHERE catalog_code=p_code AND status='published' FOR UPDATE;
  IF previous IS NOT NULL THEN
    UPDATE private_isg.training_catalog_versions SET status='superseded' WHERE catalog_code=p_code AND version=previous; END IF;
  UPDATE private_isg.training_catalog_versions SET status='published',approved_by=p_approver,
    approval_note=private_isg.text_value(p_note,500),published_at=p_now,content_approved=p_content_approved
    WHERE catalog_code=p_code AND version=p_version;
  RETURN jsonb_build_object('schema_version',1,'catalog_code',p_code,'version',p_version,'status','published',
    'content_approved',p_content_approved,'superseded_version',previous,'replayed',false);
END $$;
CREATE FUNCTION private_isg.activate_curriculum(p_company uuid,p_workplace uuid,p_code text,p_hazard text,
  p_g4_topics jsonb,p_g4_lessons integer,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE workplace private_isg.workplaces; catalog private_isg.training_catalog_versions;
  minimum integer; next_version integer; curriculum uuid; previous uuid;
BEGIN
  PERFORM private_isg.training_gate(true);
  IF p_company IS NULL OR p_workplace IS NULL OR p_code IS NULL OR p_hazard IS NULL OR p_now IS NULL OR
     p_g4_lessons IS NULL OR p_g4_topics IS NULL OR jsonb_typeof(p_g4_topics)<>'array' OR
     jsonb_array_length(p_g4_topics) NOT BETWEEN 1 AND 100 OR p_hazard NOT IN ('low','medium','high') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO workplace FROM private_isg.workplaces WHERE company_id=p_company AND id=p_workplace FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO catalog FROM private_isg.training_catalog_versions WHERE catalog_code=p_code AND status='published' FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RULE_NEEDS_REVIEW'; END IF;
  SELECT min_lessons INTO minimum FROM private_isg.training_topic_groups
    WHERE catalog_code=p_code AND version=catalog.version AND group_code='G4';
  IF minimum IS NOT NULL AND p_g4_lessons<minimum THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT curriculum_id INTO previous FROM private_isg.company_curriculum_versions
    WHERE company_id=p_company AND workplace_id=p_workplace AND catalog_code=p_code AND state='active' FOR UPDATE;
  SELECT coalesce(max(version),0)+1 INTO next_version FROM private_isg.company_curriculum_versions
    WHERE company_id=p_company AND workplace_id=p_workplace AND catalog_code=p_code;
  IF previous IS NOT NULL THEN
    UPDATE private_isg.company_curriculum_versions SET state='superseded' WHERE curriculum_id=previous; END IF;
  INSERT INTO private_isg.company_curriculum_versions(company_id,owner_id,workplace_id,catalog_code,catalog_version,
      version,hazard_class,g4_topics,g4_lessons,state,created_at)
    VALUES(p_company,workplace.owner_id,p_workplace,p_code,catalog.version,next_version,p_hazard,p_g4_topics,
      p_g4_lessons,'active',p_now) RETURNING curriculum_id INTO curriculum;
  RETURN jsonb_build_object('schema_version',1,'curriculum_id',curriculum,'version',next_version,
    'catalog_version',catalog.version,'superseded_curriculum',previous);
END $$;
CREATE FUNCTION private_isg.open_training_plan(p_curriculum uuid,p_kind text,p_requirement uuid,p_on date,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE curriculum private_isg.company_curriculum_versions; plan uuid; requirement private_isg.requirement_instances;
BEGIN
  PERFORM private_isg.training_gate(true);
  IF p_curriculum IS NULL OR p_kind IS NULL OR p_on IS NULL OR NOT isfinite(p_on) OR p_now IS NULL OR
     p_kind NOT IN ('first','refresh','onboarding','special') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO curriculum FROM private_isg.company_curriculum_versions WHERE curriculum_id=p_curriculum FOR SHARE;
  IF NOT FOUND OR curriculum.state<>'active' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF p_requirement IS NOT NULL THEN
    SELECT * INTO requirement FROM private_isg.requirement_instances WHERE requirement_id=p_requirement FOR SHARE;
    IF NOT FOUND OR requirement.company_id<>curriculum.company_id OR requirement.workplace_id<>curriculum.workplace_id OR
       requirement.action_kind<>'training' OR requirement.status<>'open' THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  INSERT INTO private_isg.training_plans(company_id,workplace_id,curriculum_id,requirement_id,kind,planned_on,created_at,updated_at)
    VALUES(curriculum.company_id,curriculum.workplace_id,p_curriculum,p_requirement,p_kind,p_on,p_now,p_now)
    RETURNING plan_id INTO plan;
  -- A plan schedules work. It completes nothing and satisfies no obligation.
  RETURN jsonb_build_object('schema_version',1,'plan_id',plan,'state','planned','kind',p_kind,
    'requirement_id',p_requirement,'completes_nothing',true);
END $$;
CREATE FUNCTION private_isg.schedule_training_session(p_plan uuid,p_method text,p_starts timestamptz,p_ends timestamptz,
  p_lesson_minutes integer,p_break_minutes integer,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE plan private_isg.training_plans; session uuid;
BEGIN
  PERFORM private_isg.training_gate(true);
  IF p_plan IS NULL OR p_method IS NULL OR p_starts IS NULL OR p_ends IS NULL OR p_starts>=p_ends OR p_now IS NULL OR
     p_method NOT IN ('classroom','online_sync','online_async','on_the_job') OR
     p_lesson_minutes IS NULL OR p_break_minutes IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO plan FROM private_isg.training_plans WHERE plan_id=p_plan FOR UPDATE;
  IF NOT FOUND OR plan.state NOT IN ('planned','running') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  INSERT INTO private_isg.training_sessions(plan_id,method,starts_at,ends_at,lesson_minutes,break_minutes,created_at)
    VALUES(p_plan,p_method,p_starts,p_ends,p_lesson_minutes,p_break_minutes,p_now) RETURNING session_id INTO session;
  UPDATE private_isg.training_plans SET state='running',updated_at=p_now WHERE plan_id=p_plan AND state='planned';
  RETURN jsonb_build_object('schema_version',1,'session_id',session,'plan_id',p_plan,'method',p_method);
END $$;
CREATE FUNCTION private_isg.enrol_employee(p_session uuid,p_employee uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE plan private_isg.training_plans; existing uuid; enrolment uuid;
BEGIN
  PERFORM private_isg.training_gate(true);
  IF p_session IS NULL OR p_employee IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT p.* INTO plan FROM private_isg.training_plans p JOIN private_isg.training_sessions s ON s.plan_id=p.plan_id
    WHERE s.session_id=p_session FOR SHARE OF p;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  PERFORM 1 FROM private_isg.employees WHERE company_id=plan.company_id AND id=p_employee AND NOT is_archived FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT enrolment_id INTO existing FROM private_isg.training_enrolments WHERE session_id=p_session AND employee_id=p_employee;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'enrolment_id',existing,'replayed',true); END IF;
  IF plan.state NOT IN ('planned','running') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  INSERT INTO private_isg.training_enrolments(session_id,company_id,employee_id,created_at)
    VALUES(p_session,plan.company_id,p_employee,p_now) RETURNING enrolment_id INTO enrolment;
  RETURN jsonb_build_object('schema_version',1,'enrolment_id',enrolment,'replayed',false);
END $$;
CREATE FUNCTION private_isg.record_attendance(p_enrolment uuid,p_starts timestamptz,p_ends timestamptz,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.training_enrolments; session private_isg.training_sessions; slot uuid;
BEGIN
  PERFORM private_isg.training_gate(true);
  IF p_enrolment IS NULL OR p_starts IS NULL OR p_ends IS NULL OR p_starts>=p_ends OR p_now IS NULL OR
     NOT isfinite(p_now) OR p_ends>p_now THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.training_enrolments WHERE enrolment_id=p_enrolment FOR UPDATE;
  IF NOT FOUND OR entry.state<>'enrolled' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO session FROM private_isg.training_sessions WHERE session_id=entry.session_id FOR SHARE;
  IF p_starts<session.starts_at OR p_ends>session.ends_at THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  -- Enrolments differ across courses. Serialize by person, not enrolment, so
  -- concurrent overlap checks cannot both observe an empty attendance history.
  PERFORM 1 FROM private_isg.employees WHERE company_id=entry.company_id AND id=entry.employee_id FOR UPDATE;
  -- The same minute cannot be credited to two courses for one person.
  PERFORM 1 FROM private_isg.attendance_intervals a
    JOIN private_isg.training_enrolments e ON e.enrolment_id=a.enrolment_id
    WHERE e.company_id=entry.company_id AND e.employee_id=entry.employee_id AND e.enrolment_id<>p_enrolment
      AND a.starts_at<p_ends AND p_starts<a.ends_at;
  IF FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ATTENDANCE_OVERLAP'; END IF;
  SELECT a.interval_id INTO slot FROM private_isg.attendance_intervals a
    WHERE a.enrolment_id=p_enrolment AND a.starts_at=p_starts AND a.ends_at=p_ends;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'interval_id',slot,
    'credited_minutes',private_isg.attendance_minutes(p_enrolment),'replayed',true); END IF;
  INSERT INTO private_isg.attendance_intervals(enrolment_id,starts_at,ends_at,created_at)
    VALUES(p_enrolment,p_starts,p_ends,p_now) RETURNING attendance_intervals.interval_id INTO slot;
  RETURN jsonb_build_object('schema_version',1,'interval_id',slot,
    'credited_minutes',private_isg.attendance_minutes(p_enrolment),'replayed',false);
END $$;
CREATE FUNCTION private_isg.record_assessment_attempt(p_enrolment uuid,p_score integer,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.training_enrolments; rules private_isg.training_class_rules; used integer; attempt uuid; passed boolean;
BEGIN
  PERFORM private_isg.training_gate(true);
  IF p_enrolment IS NULL OR p_score IS NULL OR p_score NOT BETWEEN 0 AND 100 OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.training_enrolments WHERE enrolment_id=p_enrolment FOR UPDATE;
  IF NOT FOUND OR entry.state<>'enrolled' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT r.* INTO rules FROM private_isg.training_class_rules r
    JOIN private_isg.company_curriculum_versions c ON c.catalog_code=r.catalog_code AND c.catalog_version=r.version AND c.hazard_class=r.hazard_class
    JOIN private_isg.training_plans p ON p.curriculum_id=c.curriculum_id
    JOIN private_isg.training_sessions s ON s.plan_id=p.plan_id WHERE s.session_id=entry.session_id;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT count(*) INTO used FROM private_isg.assessment_attempts WHERE enrolment_id=p_enrolment;
  IF used>=rules.max_attempts THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ATTEMPT_LIMIT_REACHED'; END IF;
  passed:=p_score>=rules.pass_score;
  INSERT INTO private_isg.assessment_attempts(enrolment_id,attempt_no,score,passed,attempted_at)
    VALUES(p_enrolment,used+1,p_score,passed,p_now) RETURNING attempt_id INTO attempt;
  RETURN jsonb_build_object('schema_version',1,'attempt_id',attempt,'attempt_no',used+1,'score',p_score,
    'passed',passed,'pass_score',rules.pass_score,'attempts_left',rules.max_attempts-used-1);
END $$;
-- Attendance and a passing attempt together finalise a completion; the snapshot
-- is written once and never edited by a later catalogue version.
CREATE FUNCTION private_isg.complete_training(p_enrolment uuid,p_on date,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.training_enrolments; plan private_isg.training_plans;
  curriculum private_isg.company_curriculum_versions; rules private_isg.training_class_rules;
  catalog private_isg.training_catalog_versions; attempt private_isg.assessment_attempts;
  credited integer; required integer; lessons integer; completion uuid; valid date; existing private_isg.training_completions;
BEGIN
  PERFORM private_isg.training_gate(true);
  IF p_enrolment IS NULL OR p_on IS NULL OR NOT isfinite(p_on) OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.training_enrolments WHERE enrolment_id=p_enrolment FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO existing FROM private_isg.training_completions WHERE enrolment_id=p_enrolment;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'completion_id',existing.completion_id,
    'completed_on',existing.completed_on,'valid_until',existing.valid_until,'replayed',true); END IF;
  SELECT p.* INTO plan FROM private_isg.training_plans p JOIN private_isg.training_sessions s ON s.plan_id=p.plan_id
    WHERE s.session_id=entry.session_id FOR UPDATE OF p;
  SELECT * INTO curriculum FROM private_isg.company_curriculum_versions WHERE curriculum_id=plan.curriculum_id FOR SHARE;
  SELECT * INTO catalog FROM private_isg.training_catalog_versions
    WHERE catalog_code=curriculum.catalog_code AND version=curriculum.catalog_version FOR SHARE;
  SELECT * INTO rules FROM private_isg.training_class_rules
    WHERE catalog_code=curriculum.catalog_code AND version=curriculum.catalog_version AND hazard_class=curriculum.hazard_class;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  lessons:=CASE plan.kind WHEN 'first' THEN rules.first_lessons WHEN 'refresh' THEN rules.refresh_lessons
    WHEN 'onboarding' THEN rules.onboarding_lessons ELSE curriculum.g4_lessons END;
  -- Break time is excluded: only lesson minutes are required instruction.
  required:=lessons*rules.lesson_minutes;
  credited:=private_isg.attendance_minutes(p_enrolment);
  IF credited<required THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ATTENDANCE_INSUFFICIENT'; END IF;
  SELECT * INTO attempt FROM private_isg.assessment_attempts WHERE enrolment_id=p_enrolment AND passed
    ORDER BY attempt_no LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSESSMENT_NOT_PASSED'; END IF;
  IF NOT isfinite(p_now) OR p_on>(p_now AT TIME ZONE 'Europe/Istanbul')::date OR
     p_on<(SELECT (max(ends_at) AT TIME ZONE 'Europe/Istanbul')::date
       FROM private_isg.attendance_intervals WHERE enrolment_id=p_enrolment) OR
     p_on<(attempt.attempted_at AT TIME ZONE 'Europe/Istanbul')::date THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  valid:=CASE WHEN plan.kind='special' THEN NULL
    ELSE private_isg.next_due_on(p_on,'years',rules.refresh_period_years) END;
  INSERT INTO private_isg.training_completions(enrolment_id,company_id,employee_id,workplace_id,catalog_code,
      catalog_version,curriculum_version,kind,hazard_class,credited_minutes,required_minutes,score,attempts_used,
      completed_on,valid_until,content_approved,snapshot,created_at)
    VALUES(p_enrolment,entry.company_id,entry.employee_id,plan.workplace_id,curriculum.catalog_code,
      curriculum.catalog_version,curriculum.version,plan.kind,curriculum.hazard_class,credited,required,
      attempt.score,(SELECT count(*) FROM private_isg.assessment_attempts WHERE enrolment_id=p_enrolment),
      p_on,valid,catalog.content_approved,
      jsonb_build_object('schema_version',1,'catalog_code',curriculum.catalog_code,'catalog_version',curriculum.catalog_version,
        'curriculum_version',curriculum.version,'g4_topics',curriculum.g4_topics,'g4_lessons',curriculum.g4_lessons,
        'hazard_class',curriculum.hazard_class,'kind',plan.kind,'lesson_minutes',rules.lesson_minutes,
        'break_minutes',rules.break_minutes,'required_lessons',lessons,'pass_score',rules.pass_score,
        'content_approved',catalog.content_approved),p_now)
    RETURNING completion_id INTO completion;
  UPDATE private_isg.training_enrolments SET state='completed' WHERE enrolment_id=p_enrolment;
  RETURN jsonb_build_object('schema_version',1,'completion_id',completion,'credited_minutes',credited,
    'required_minutes',required,'score',attempt.score,'completed_on',p_on,'valid_until',valid,
    'content_approved',catalog.content_approved,'requirement_id',plan.requirement_id,'replayed',false);
END $$;
-- The obligation closes only when every enrolled person of the plan completed.
CREATE FUNCTION private_isg.settle_training_requirement(p_plan uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE plan private_isg.training_plans; enrolled integer; completed integer;
BEGIN
  PERFORM private_isg.training_gate(true);
  IF p_plan IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO plan FROM private_isg.training_plans WHERE plan_id=p_plan FOR UPDATE;
  IF NOT FOUND OR plan.requirement_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT count(*),count(*) FILTER (WHERE e.state='completed') INTO enrolled,completed
    FROM private_isg.training_enrolments e JOIN private_isg.training_sessions s ON s.session_id=e.session_id
    WHERE s.plan_id=p_plan;
  IF enrolled=0 OR completed<enrolled THEN
    RETURN jsonb_build_object('schema_version',1,'plan_id',p_plan,'enrolled',enrolled,'completed',completed,
      'requirement_satisfied',false,'reason','TRAINING_INCOMPLETE'); END IF;
  PERFORM private_isg.close_requirement(plan.requirement_id,'satisfied',NULL,p_now);
  UPDATE private_isg.training_plans SET state='closed',updated_at=p_now WHERE plan_id=p_plan;
  RETURN jsonb_build_object('schema_version',1,'plan_id',p_plan,'enrolled',enrolled,'completed',completed,
    'requirement_satisfied',true,'requirement_id',plan.requirement_id);
END $$;
CREATE FUNCTION private_isg.record_external_credential(p_company uuid,p_employee uuid,p_issuer text,p_title text,
  p_issued_on date,p_valid_until date,p_asset uuid,p_evidence text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE credential uuid; existing uuid; review boolean; asset_owner uuid; scan text;
BEGIN
  PERFORM private_isg.training_gate(true);
  IF p_company IS NULL OR p_employee IS NULL OR p_issuer IS NULL OR p_title IS NULL OR p_issued_on IS NULL OR
     NOT isfinite(p_issued_on) OR p_now IS NULL OR (p_valid_until IS NOT NULL AND p_issued_on>=p_valid_until) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  PERFORM 1 FROM private_isg.employees WHERE company_id=p_company AND id=p_employee FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF p_asset IS NOT NULL THEN
    -- Only a promoted, scanned-clean original counts as the document evidence.
    SELECT owner_id,scan_status INTO asset_owner,scan FROM private_isg.file_assets WHERE asset_id=p_asset FOR SHARE;
    IF asset_owner IS NULL OR scan IS DISTINCT FROM 'clean' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  review:=p_asset IS NULL OR p_evidence IS NULL;
  SELECT credential_id INTO existing FROM private_isg.external_credentials
    WHERE company_id=p_company AND employee_id=p_employee AND issuer=private_isg.text_value(p_issuer,200)
      AND title=private_isg.text_value(p_title,200) AND issued_on=p_issued_on;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'credential_id',existing,'replayed',true); END IF;
  INSERT INTO private_isg.external_credentials(company_id,employee_id,issuer,title,issued_on,valid_until,asset_id,
      evidence_note,needs_review,created_at)
    VALUES(p_company,p_employee,private_isg.text_value(p_issuer,200),private_isg.text_value(p_title,200),
      p_issued_on,p_valid_until,p_asset,p_evidence,review,p_now) RETURNING credential_id INTO credential;
  -- An external certificate is evidence of somebody else's course. It is not a
  -- completion of this catalogue and never becomes one.
  RETURN jsonb_build_object('schema_version',1,'credential_id',credential,'needs_review',review,
    'is_training_completion',false,'replayed',false);
END $$;
REVOKE ALL ON FUNCTION private_isg.training_gate(boolean),private_isg.attendance_minutes(uuid),
  private_isg.publish_catalog_version(text,integer,uuid,text,boolean,timestamptz),
  private_isg.activate_curriculum(uuid,uuid,text,text,jsonb,integer,timestamptz),
  private_isg.open_training_plan(uuid,text,uuid,date,timestamptz),
  private_isg.schedule_training_session(uuid,text,timestamptz,timestamptz,integer,integer,timestamptz),
  private_isg.enrol_employee(uuid,uuid,timestamptz),
  private_isg.record_attendance(uuid,timestamptz,timestamptz,timestamptz),
  private_isg.record_assessment_attempt(uuid,integer,timestamptz),
  private_isg.complete_training(uuid,date,timestamptz),
  private_isg.settle_training_requirement(uuid,timestamptz),
  private_isg.record_external_credential(uuid,uuid,text,text,date,date,uuid,text,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
