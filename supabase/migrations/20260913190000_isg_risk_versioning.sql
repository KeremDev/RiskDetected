-- P08/D08 first slice: four revision kinds with their own date rules, explicit
-- expert transfer of AI findings, impact lists, source drift flags and a
-- single-winner finalisation. Additive; rollout OFF; no client grant.
-- The legacy photo analysis and its findings are read-only sources here; no
-- legacy row is written, mutated or auto-converted into a risk assessment.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE private_isg.rollout DROP CONSTRAINT rollout_feature_check;
ALTER TABLE private_isg.rollout ADD CONSTRAINT rollout_feature_check
  CHECK(feature IN ('personnel','event_dispatch','quota_ledger','file_core','rule_engine','training','risk'));
INSERT INTO private_isg.rollout(feature) VALUES('risk');

CREATE TABLE private_isg.risk_assessments (
  assessment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL, workplace_id uuid NOT NULL,
  current_version integer NOT NULL DEFAULT 0 CHECK(current_version BETWEEN 0 AND 100000),
  base_assessment_on date CHECK(base_assessment_on IS NULL OR isfinite(base_assessment_on)),
  valid_until date CHECK(valid_until IS NULL OR isfinite(valid_until)),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id,workplace_id),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE
);
CREATE TABLE private_isg.risk_assessment_versions (
  assessment_id uuid NOT NULL REFERENCES private_isg.risk_assessments(assessment_id) ON DELETE CASCADE,
  version integer NOT NULL CHECK(version BETWEEN 1 AND 100000),
  kind text NOT NULL CHECK(kind IN ('full','partial','metadata','rescan')),
  previous_version integer CHECK(previous_version IS NULL OR previous_version>=1),
  -- The legal date of the assessment. A file's upload day is never this date.
  assessment_on date NOT NULL CHECK(isfinite(assessment_on)),
  revision_on date CHECK(revision_on IS NULL OR isfinite(revision_on)),
  scope jsonb, reason text CHECK(reason IS NULL OR length(reason) BETWEEN 10 AND 2000),
  file_asset_id uuid REFERENCES private_isg.file_assets(asset_id),
  source_snapshot jsonb,
  state text NOT NULL DEFAULT 'draft' CHECK(state IN ('draft','final','superseded')),
  date_needs_review boolean NOT NULL DEFAULT false,
  period_years integer CHECK(period_years IS NULL OR period_years BETWEEN 1 AND 20),
  period_source text CHECK(period_source IS NULL OR period_source IN ('rule_version','unapproved_fixture')),
  period_needs_review boolean NOT NULL DEFAULT false,
  valid_until date CHECK(valid_until IS NULL OR isfinite(valid_until)),
  source_drift boolean NOT NULL DEFAULT false, drift_note text,
  verified_by uuid REFERENCES public.profiles(id), finalized_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(assessment_id,version),
  CHECK((state IN ('final','superseded'))=(finalized_at IS NOT NULL)),
  CHECK(state='draft' OR verified_by IS NOT NULL),
  CHECK((kind='full')=(previous_version IS NULL)),
  CHECK(kind<>'partial' OR scope IS NOT NULL),
  CHECK(kind IN ('full','rescan') OR reason IS NOT NULL),
  CHECK(revision_on IS NULL OR revision_on>=assessment_on),
  FOREIGN KEY(assessment_id,previous_version) REFERENCES private_isg.risk_assessment_versions(assessment_id,version)
);
-- A finding becomes part of a risk assessment only because the expert picked
-- it. The copied fields are snapshotted; the legacy analysis is never written.
CREATE TABLE private_isg.risk_source_links (
  link_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assessment_id uuid NOT NULL, version integer NOT NULL,
  analysis_id uuid NOT NULL, finding_id uuid NOT NULL,
  source_version bigint NOT NULL CHECK(source_version>=0),
  copied_fields jsonb NOT NULL, selected_at timestamptz NOT NULL,
  UNIQUE(assessment_id,version,analysis_id,finding_id),
  FOREIGN KEY(assessment_id,version) REFERENCES private_isg.risk_assessment_versions(assessment_id,version) ON DELETE CASCADE
);
CREATE TABLE private_isg.revision_impacts (
  impact_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assessment_id uuid NOT NULL, version integer NOT NULL,
  target_kind text NOT NULL CHECK(target_kind IN ('requirement','curriculum_review','risk_area')),
  target_ref text NOT NULL CHECK(btrim(target_ref)<>'' AND length(target_ref)<=200),
  action text NOT NULL CHECK(action IN ('review','reschedule','no_change')),
  note text CHECK(note IS NULL OR length(note)<=1000),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(assessment_id,version,target_kind,target_ref),
  FOREIGN KEY(assessment_id,version) REFERENCES private_isg.risk_assessment_versions(assessment_id,version) ON DELETE CASCADE
);
-- A better scan is a new file variant of the same assessment, not a renewal.
CREATE TABLE private_isg.risk_file_variants (
  variant_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assessment_id uuid NOT NULL, version integer NOT NULL,
  asset_id uuid NOT NULL REFERENCES private_isg.file_assets(asset_id),
  base_version integer NOT NULL, source_sha256 bytea NOT NULL CHECK(octet_length(source_sha256)=32),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(assessment_id,version), UNIQUE(assessment_id,asset_id),
  FOREIGN KEY(assessment_id,version) REFERENCES private_isg.risk_assessment_versions(assessment_id,version) ON DELETE CASCADE
);
CREATE INDEX risk_assessment_owner_idx ON private_isg.risk_assessments(company_id,owner_id);
CREATE INDEX risk_assessment_workplace_idx ON private_isg.risk_assessments(company_id,workplace_id);
CREATE INDEX risk_version_state_idx ON private_isg.risk_assessment_versions(assessment_id,state);
CREATE INDEX risk_version_asset_idx ON private_isg.risk_assessment_versions(file_asset_id);
CREATE INDEX risk_version_verifier_idx ON private_isg.risk_assessment_versions(verified_by);
CREATE INDEX risk_version_previous_idx ON private_isg.risk_assessment_versions(assessment_id,previous_version);
CREATE INDEX risk_source_analysis_idx ON private_isg.risk_source_links(analysis_id,finding_id);
CREATE INDEX risk_variant_asset_idx ON private_isg.risk_file_variants(asset_id);
ALTER TABLE private_isg.risk_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.risk_assessment_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.risk_source_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.revision_impacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.risk_file_variants ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.risk_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM private_isg.rollout WHERE feature='risk' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $$;
CREATE FUNCTION private_isg.open_risk_assessment(p_company uuid,p_workplace uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE workplace private_isg.workplaces; existing private_isg.risk_assessments; assessment uuid;
BEGIN
  PERFORM private_isg.risk_gate(true);
  IF p_company IS NULL OR p_workplace IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO workplace FROM private_isg.workplaces WHERE company_id=p_company AND id=p_workplace FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO existing FROM private_isg.risk_assessments WHERE company_id=p_company AND workplace_id=p_workplace;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'assessment_id',existing.assessment_id,
    'current_version',existing.current_version,'replayed',true); END IF;
  INSERT INTO private_isg.risk_assessments(company_id,owner_id,workplace_id,created_at,updated_at)
    VALUES(p_company,workplace.owner_id,p_workplace,p_now,p_now) RETURNING assessment_id INTO assessment;
  RETURN jsonb_build_object('schema_version',1,'assessment_id',assessment,'current_version',0,'replayed',false);
END $$;
-- Date rules live here: a future date is refused, a very old one is flagged for
-- review, and a revision can never move the base legal date backwards.
CREATE FUNCTION private_isg.draft_risk_version(p_assessment uuid,p_kind text,p_assessment_on date,p_revision_on date,
  p_scope jsonb,p_reason text,p_asset uuid,p_expected_current integer,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.risk_assessments; base private_isg.risk_assessment_versions;
  next_version integer; effective date; review boolean:=false; today date;
BEGIN
  PERFORM private_isg.risk_gate(true);
  IF p_assessment IS NULL OR p_kind IS NULL OR p_now IS NULL OR p_expected_current IS NULL OR
     p_kind NOT IN ('full','partial','metadata','rescan') OR
     (p_kind='partial' AND (p_scope IS NULL OR jsonb_typeof(p_scope)<>'array' OR jsonb_array_length(p_scope) NOT BETWEEN 1 AND 50)) OR
     (p_kind NOT IN ('full','rescan') AND p_reason IS NULL) OR
     (p_kind<>'partial' AND p_scope IS NOT NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.risk_assessments WHERE assessment_id=p_assessment FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.current_version<>p_expected_current THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  today:=(p_now AT TIME ZONE 'UTC')::date;
  IF p_kind='full' THEN
    IF p_assessment_on IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    effective:=p_assessment_on;
  ELSE
    IF entry.current_version=0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    SELECT * INTO base FROM private_isg.risk_assessment_versions
      WHERE assessment_id=p_assessment AND version=entry.current_version FOR SHARE;
    -- A rescan or a metadata correction keeps the original legal date.
    IF p_assessment_on IS NOT NULL AND p_assessment_on<>base.assessment_on THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSESSMENT_DATE_IMMUTABLE'; END IF;
    effective:=base.assessment_on;
  END IF;
  IF effective>today THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSESSMENT_DATE_IN_FUTURE'; END IF;
  IF effective<today-3650 THEN review:=true; END IF;
  IF p_revision_on IS NOT NULL AND (p_revision_on>today OR p_revision_on<effective) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_asset IS NOT NULL THEN
    PERFORM 1 FROM private_isg.file_assets WHERE asset_id=p_asset AND scan_status='clean' FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  PERFORM 1 FROM private_isg.risk_assessment_versions WHERE assessment_id=p_assessment AND state='draft' FOR UPDATE;
  IF FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DRAFT_ALREADY_OPEN'; END IF;
  SELECT coalesce(max(version),0)+1 INTO next_version FROM private_isg.risk_assessment_versions WHERE assessment_id=p_assessment;
  INSERT INTO private_isg.risk_assessment_versions(assessment_id,version,kind,previous_version,assessment_on,
      revision_on,scope,reason,file_asset_id,date_needs_review,created_at,updated_at)
    VALUES(p_assessment,next_version,p_kind,CASE WHEN p_kind='full' THEN NULL ELSE entry.current_version END,
      effective,p_revision_on,p_scope,p_reason,p_asset,review,p_now,p_now);
  RETURN jsonb_build_object('schema_version',1,'assessment_id',p_assessment,'version',next_version,'kind',p_kind,
    'assessment_on',effective,'state','draft','date_needs_review',review);
END $$;
-- Explicit expert selection. Nothing is copied automatically from an analysis.
CREATE FUNCTION private_isg.attach_risk_source(p_assessment uuid,p_version integer,p_analysis uuid,p_finding uuid,
  p_source_version bigint,p_fields jsonb,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.risk_assessment_versions; link uuid; existing uuid;
BEGIN
  PERFORM private_isg.risk_gate(true);
  IF p_assessment IS NULL OR p_version IS NULL OR p_analysis IS NULL OR p_finding IS NULL OR p_now IS NULL OR
     p_source_version IS NULL OR p_source_version<0 OR p_fields IS NULL OR jsonb_typeof(p_fields)<>'object' OR
     octet_length(p_fields::text)>4096 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.risk_assessment_versions
    WHERE assessment_id=p_assessment AND version=p_version FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state<>'draft' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_FINALIZED'; END IF;
  SELECT link_id INTO existing FROM private_isg.risk_source_links
    WHERE assessment_id=p_assessment AND version=p_version AND analysis_id=p_analysis AND finding_id=p_finding;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'link_id',existing,'replayed',true); END IF;
  INSERT INTO private_isg.risk_source_links(assessment_id,version,analysis_id,finding_id,source_version,copied_fields,selected_at)
    VALUES(p_assessment,p_version,p_analysis,p_finding,p_source_version,p_fields,p_now) RETURNING link_id INTO link;
  RETURN jsonb_build_object('schema_version',1,'link_id',link,'analysis_id',p_analysis,'finding_id',p_finding,
    'source_version',p_source_version,'legacy_analysis_written',false,'replayed',false);
END $$;
CREATE FUNCTION private_isg.record_revision_impact(p_assessment uuid,p_version integer,p_target_kind text,
  p_target_ref text,p_action text,p_note text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.risk_assessment_versions; impact uuid; existing uuid;
BEGIN
  PERFORM private_isg.risk_gate(true);
  IF p_assessment IS NULL OR p_version IS NULL OR p_now IS NULL OR p_target_kind IS NULL OR p_target_ref IS NULL OR
     p_action IS NULL OR p_target_kind NOT IN ('requirement','curriculum_review','risk_area') OR
     p_action NOT IN ('review','reschedule','no_change') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.risk_assessment_versions
    WHERE assessment_id=p_assessment AND version=p_version FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state<>'draft' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_FINALIZED'; END IF;
  IF entry.kind<>'partial' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT impact_id INTO existing FROM private_isg.revision_impacts WHERE assessment_id=p_assessment AND
    version=p_version AND target_kind=p_target_kind AND target_ref=p_target_ref;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'impact_id',existing,'replayed',true); END IF;
  INSERT INTO private_isg.revision_impacts(assessment_id,version,target_kind,target_ref,action,note,created_at)
    VALUES(p_assessment,p_version,p_target_kind,private_isg.text_value(p_target_ref,200),p_action,p_note,p_now)
    RETURNING impact_id INTO impact;
  RETURN jsonb_build_object('schema_version',1,'impact_id',impact,'action',p_action,'replayed',false);
END $$;
CREATE FUNCTION private_isg.attach_rescan_variant(p_assessment uuid,p_version integer,p_asset uuid,p_sha256 bytea,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.risk_assessment_versions; variant uuid;
BEGIN
  PERFORM private_isg.risk_gate(true);
  IF p_assessment IS NULL OR p_version IS NULL OR p_asset IS NULL OR p_now IS NULL OR p_sha256 IS NULL OR
     octet_length(p_sha256)<>32 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.risk_assessment_versions
    WHERE assessment_id=p_assessment AND version=p_version FOR UPDATE;
  IF NOT FOUND OR entry.kind<>'rescan' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF entry.state<>'draft' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_FINALIZED'; END IF;
  PERFORM 1 FROM private_isg.file_assets WHERE asset_id=p_asset AND scan_status='clean' FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  INSERT INTO private_isg.risk_file_variants(assessment_id,version,asset_id,base_version,source_sha256,created_at)
    VALUES(p_assessment,p_version,p_asset,entry.previous_version,p_sha256,p_now) RETURNING variant_id INTO variant;
  RETURN jsonb_build_object('schema_version',1,'variant_id',variant,'base_version',entry.previous_version,
    'renews_period',false);
END $$;
-- Only a full renewal opens a new period, and only with a real assessment date
-- plus an expert verification. Two devices finalising the same version: one
-- winner, the other gets a conflict.
CREATE FUNCTION private_isg.finalize_risk_version(p_assessment uuid,p_version integer,p_expected_current integer,
  p_verified_by uuid,p_rule_code text,p_period_years integer,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.risk_assessments; revision private_isg.risk_assessment_versions;
  rule private_isg.rule_versions; years integer; source text; review boolean:=false; valid date;
BEGIN
  PERFORM private_isg.risk_gate(true);
  IF p_assessment IS NULL OR p_version IS NULL OR p_expected_current IS NULL OR p_verified_by IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.risk_assessments WHERE assessment_id=p_assessment FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO revision FROM private_isg.risk_assessment_versions AS r
    WHERE r.assessment_id=p_assessment AND r.version=p_version FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF revision.state='final' THEN RETURN jsonb_build_object('schema_version',1,'assessment_id',p_assessment,
    'version',p_version,'state','final','valid_until',revision.valid_until,'replayed',true); END IF;
  IF entry.current_version<>p_expected_current THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  IF revision.kind='full' THEN
    IF p_rule_code IS NOT NULL THEN
      SELECT * INTO rule FROM private_isg.rule_versions WHERE rule_code=p_rule_code AND status='published' FOR SHARE;
      IF NOT FOUND OR rule.period_kind<>'years' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RULE_NEEDS_REVIEW'; END IF;
      years:=rule.period_length; source:='rule_version';
    ELSE
      IF p_period_years IS NULL OR p_period_years NOT BETWEEN 1 AND 20 THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      years:=p_period_years; source:='unapproved_fixture'; review:=true;
    END IF;
    -- The period runs from the real assessment date, not from today.
    valid:=private_isg.next_due_on(revision.assessment_on,'years',years);
  ELSE
    -- A rescan, a metadata correction or a scoped revision never resets the
    -- whole workplace period.
    IF p_rule_code IS NOT NULL OR p_period_years IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    valid:=entry.valid_until;
  END IF;
  UPDATE private_isg.risk_assessment_versions AS r SET state='superseded',updated_at=p_now
    WHERE r.assessment_id=p_assessment AND r.state='final';
  UPDATE private_isg.risk_assessment_versions AS r SET state='final',verified_by=p_verified_by,finalized_at=p_now,
    period_years=years,period_source=source,period_needs_review=review,valid_until=valid,updated_at=p_now
    WHERE r.assessment_id=p_assessment AND r.version=p_version;
  UPDATE private_isg.risk_assessments SET current_version=p_version,updated_at=p_now,
    base_assessment_on=CASE WHEN revision.kind='full' THEN revision.assessment_on ELSE base_assessment_on END,
    valid_until=valid WHERE assessment_id=p_assessment;
  RETURN jsonb_build_object('schema_version',1,'assessment_id',p_assessment,'version',p_version,'kind',revision.kind,
    'state','final','assessment_on',revision.assessment_on,'valid_until',valid,'period_years',years,
    'period_source',source,'period_needs_review',review,'replayed',false);
END $$;
-- The source analysis moving on never edits a finalised risk document; it can
-- only raise a drift flag for review.
CREATE FUNCTION private_isg.flag_source_drift(p_assessment uuid,p_version integer,p_analysis uuid,
  p_current_source_version bigint,p_note text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.risk_assessment_versions; linked bigint; drifted boolean; before jsonb;
BEGIN
  PERFORM private_isg.risk_gate(true);
  IF p_assessment IS NULL OR p_version IS NULL OR p_analysis IS NULL OR p_now IS NULL OR
     p_current_source_version IS NULL OR p_current_source_version<0 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.risk_assessment_versions
    WHERE assessment_id=p_assessment AND version=p_version FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT max(source_version) INTO linked FROM private_isg.risk_source_links
    WHERE assessment_id=p_assessment AND version=p_version AND analysis_id=p_analysis;
  IF linked IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  drifted:=p_current_source_version>linked;
  before:=jsonb_build_object('assessment_on',entry.assessment_on,'valid_until',entry.valid_until,'state',entry.state);
  IF drifted THEN
    UPDATE private_isg.risk_assessment_versions SET source_drift=true,drift_note=p_note,updated_at=p_now
      WHERE assessment_id=p_assessment AND version=p_version;
  END IF;
  RETURN jsonb_build_object('schema_version',1,'assessment_id',p_assessment,'version',p_version,
    'linked_source_version',linked,'current_source_version',p_current_source_version,'source_drift',drifted,
    'document_unchanged',before,'action','review_suggested');
END $$;
-- Any sender must prove it is holding the current version; a stale queued job
-- is stopped instead of delivering an outdated document.
CREATE FUNCTION private_isg.assert_current_risk_version(p_assessment uuid,p_version integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.risk_assessments;
BEGIN
  PERFORM private_isg.risk_gate(false);
  IF p_assessment IS NULL OR p_version IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.risk_assessments WHERE assessment_id=p_assessment;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.current_version<>p_version THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  RETURN jsonb_build_object('schema_version',1,'assessment_id',p_assessment,'current_version',entry.current_version,
    'valid_until',entry.valid_until,'dispatch_allowed',true);
END $$;
REVOKE ALL ON FUNCTION private_isg.risk_gate(boolean),
  private_isg.open_risk_assessment(uuid,uuid,timestamptz),
  private_isg.draft_risk_version(uuid,text,date,date,jsonb,text,uuid,integer,timestamptz),
  private_isg.attach_risk_source(uuid,integer,uuid,uuid,bigint,jsonb,timestamptz),
  private_isg.record_revision_impact(uuid,integer,text,text,text,text,timestamptz),
  private_isg.attach_rescan_variant(uuid,integer,uuid,bytea,timestamptz),
  private_isg.finalize_risk_version(uuid,integer,integer,uuid,text,integer,timestamptz),
  private_isg.flag_source_drift(uuid,integer,uuid,bigint,text,timestamptz),
  private_isg.assert_current_risk_version(uuid,integer)
  FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
