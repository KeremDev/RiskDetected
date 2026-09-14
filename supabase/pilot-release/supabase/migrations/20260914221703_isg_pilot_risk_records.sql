-- Narrow pilot: expert records; no uploaded files or published legal rules.
INSERT INTO private_isg.rollout(feature) VALUES('risk') ON CONFLICT DO NOTHING;
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
  file_asset_id uuid CHECK(file_asset_id IS NULL),
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
  asset_id uuid NOT NULL CHECK(asset_id IS NULL),
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
REVOKE ALL ON private_isg.risk_assessments,private_isg.risk_assessment_versions,private_isg.risk_source_links,private_isg.revision_impacts,private_isg.risk_file_variants FROM PUBLIC,anon,authenticated,service_role;

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
  IF p_kind='rescan' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FILE_STORAGE_UNAVAILABLE'; END IF;
  IF p_assessment IS NULL OR p_kind IS NULL OR p_now IS NULL OR p_expected_current IS NULL OR
     p_kind NOT IN ('full','partial','metadata','rescan') OR
     (p_kind='partial' AND (p_scope IS NULL OR jsonb_typeof(p_scope)<>'array' OR jsonb_array_length(p_scope) NOT BETWEEN 1 AND 50)) OR
     (p_kind NOT IN ('full','rescan') AND p_reason IS NULL) OR
     (p_kind<>'partial' AND p_scope IS NOT NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.risk_assessments WHERE assessment_id=p_assessment FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.current_version<>p_expected_current THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  today:=(p_now AT TIME ZONE 'Europe/Istanbul')::date;
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
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FILE_STORAGE_UNAVAILABLE';
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
BEGIN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FILE_STORAGE_UNAVAILABLE'; END $$;
CREATE FUNCTION private_isg.finalize_risk_version(p_assessment uuid,p_version integer,p_expected_current integer,
  p_verified_by uuid,p_rule_code text,p_period_years integer,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.risk_assessments; revision private_isg.risk_assessment_versions;
  years integer; source text; review boolean:=false; valid date;
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
  IF revision.state<>'draft' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_FINALIZED'; END IF;
  IF revision.kind='full' THEN
    IF p_rule_code IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RULE_NEEDS_REVIEW';
    ELSE
      IF p_period_years IS NULL OR p_period_years NOT BETWEEN 1 AND 20 THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      years:=p_period_years; source:='unapproved_fixture'; review:=true;
    END IF;
    -- The period runs from the real assessment date, not from today.
    valid:=(revision.assessment_on+make_interval(years=>years))::date;
  ELSE
    -- A rescan, a metadata correction or a scoped revision never resets the
    -- whole workplace period.
    IF p_rule_code IS NOT NULL OR p_period_years IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    valid:=entry.valid_until;
    SELECT r.period_years,r.period_source,r.period_needs_review INTO years,source,review FROM private_isg.risk_assessment_versions r WHERE r.assessment_id=p_assessment AND r.version=entry.current_version;
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
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path='' AS $$
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


-- P08 second slice: the client surface behind "Risk Değerlendirmesi".
-- Additive. No rollout row is added and none is opened: this rides on the
-- `risk` switch the first slice created.
--
-- The first P08 slice built the four revision kinds, the date rules, the
-- explicit transfer of analysis findings, the impact list, the drift flag and
-- the single-winner finalisation. What it never had was a client boundary, and
-- its domain functions carried no ownership check because nothing could reach
-- them — the same gap the equipment slice had.
--
-- Five things this slice makes structurally impossible:
--   1. Another owner's assessment cannot be reached. The checked entries verify
--      the company against the signed-in actor before delegating.
--   2. A validity date is never invented. A finalised version with no period
--      reads 'period_unknown' — not 'valid'. Not knowing when a document runs
--      out is a gap in the record, never a clean bill.
--   3. A period is never presented as a legal requirement unless a published
--      rule produced it. An expert's own number is stored as
--      'unapproved_fixture', forces the review flag, and the read says so on
--      every row.
--   4. The legal assessment date cannot be moved by a correction. Only a full
--      renewal carries a date; the allowlists and the domain function agree.
--   5. Nothing is copied from a photo analysis on its own. A source link is an
--      action the expert takes, and a source that later moves can only raise a
--      drift flag — the finalised document is never rewritten.

SET LOCAL lock_timeout='5s';

CREATE TABLE private_isg.risk_version_receipts (
  actor_id uuid NOT NULL, mutation_id uuid NOT NULL, company_id uuid NOT NULL,
  operation_id uuid NOT NULL, request_hash bytea NOT NULL, response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(actor_id,mutation_id),
  FOREIGN KEY(company_id,actor_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
REVOKE ALL ON private_isg.risk_version_receipts FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX risk_version_receipt_company_idx ON private_isg.risk_version_receipts(company_id,actor_id);
ALTER TABLE private_isg.risk_version_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.risk_assessments,private_isg.risk_assessment_versions,private_isg.risk_source_links,private_isg.revision_impacts,private_isg.risk_file_variants FROM PUBLIC,anon,authenticated,service_role;

-- How early the page starts warning that an assessment runs out. One number,
-- owned by the server and reported on every read, so the client never invents a
-- window. This is the product's own warning distance, not a legal period: the
-- period itself comes from the rule or from the expert, and is attributed.
CREATE FUNCTION private_isg.risk_notice_days() RETURNS integer
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$ SELECT 60 $$;

-- What the record says about one workplace today. Nothing is stored: the answer
-- is worked out from the finalised version's own dates at read time.
--
-- 'period_unknown' is the honest answer when a document was finalised but no
-- period was ever attached to it. It is deliberately NOT 'valid'.
CREATE FUNCTION private_isg.risk_assessment_status(p_current_version integer,p_has_final boolean,
  p_valid_until date,p_notice_days integer,p_today date) RETURNS text
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
BEGIN
  IF NOT p_has_final OR coalesce(p_current_version,0)=0 THEN RETURN 'never_assessed'; END IF;
  IF p_valid_until IS NULL THEN RETURN 'period_unknown'; END IF;
  IF p_valid_until<p_today THEN RETURN 'expired'; END IF;
  IF p_valid_until<=p_today+p_notice_days THEN RETURN 'due_soon'; END IF;
  RETURN 'valid';
END $$;

-- Four counters over five states, and every state belongs to exactly one group,
-- so a counter and the filter it carries can never disagree.
CREATE FUNCTION private_isg.risk_assessment_group(p_state text) RETURNS text
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT CASE p_state
    WHEN 'valid' THEN 'current'
    WHEN 'due_soon' THEN 'due_soon'
    WHEN 'expired' THEN 'expired'
    ELSE 'untracked' END
$$;

CREATE FUNCTION private_isg.risk_version_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM private_isg.risk_gate(p_write);
END $$;

-- A NULL company is the whole account, and only for reads: every write names
-- the company it writes into. The domain functions below were written for a
-- caller that had already checked ownership; this is that caller.
CREATE FUNCTION private_isg.require_risk_company(p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  PERFORM private_isg.risk_version_gate(p_write);
  IF NOT private_isg.p05_pilot_account_enabled(actor,p_write) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  IF p_company IS NOT NULL AND NOT private_isg.p05_pilot_can_read(actor,p_company) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
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

-- One workplace's assessment: the document that stands today, whether a draft
-- is open on top of it, and the whole version history when asked for.
CREATE FUNCTION private_isg.risk_assessment_row(p_assessment uuid,p_today date,p_history boolean) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.risk_assessments; current private_isg.risk_assessment_versions;
  draft private_isg.risk_assessment_versions; notice integer:=private_isg.risk_notice_days();
  -- Prefixed so it can never be mistaken for the version column of the same
  -- name in the queries below.
  shown_state text;
BEGIN
  SELECT * INTO entry FROM private_isg.risk_assessments WHERE assessment_id=p_assessment;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO current FROM private_isg.risk_assessment_versions
    WHERE assessment_id=p_assessment AND state='final' LIMIT 1;
  SELECT * INTO draft FROM private_isg.risk_assessment_versions
    WHERE assessment_id=p_assessment AND state='draft' LIMIT 1;
  shown_state:=private_isg.risk_assessment_status(entry.current_version,current.version IS NOT NULL,
    entry.valid_until,notice,p_today);
  RETURN jsonb_build_object(
    'id',entry.assessment_id,'company_id',entry.company_id,'workplace_id',entry.workplace_id,
    'current_version',entry.current_version,'base_assessment_on',entry.base_assessment_on,
    'valid_until',entry.valid_until,'created_at',entry.created_at,
    'state',shown_state,'state_group',private_isg.risk_assessment_group(shown_state),
    'state_authority','computed_at_read','notice_days',notice,
    -- The document that stands today, and how its period was arrived at.
    'current_kind',current.kind,'current_assessment_on',current.assessment_on,
    'current_revision_on',current.revision_on,'current_finalized_at',current.finalized_at,
    'period_years',current.period_years,'period_source',current.period_source,
    'period_needs_review',CASE WHEN current.version IS NULL THEN NULL
      ELSE coalesce(current.period_needs_review,false) END,
    'date_needs_review',coalesce(current.date_needs_review,false),
    'source_drift',coalesce(current.source_drift,false),'drift_note',current.drift_note,
    'current_file_asset_id',current.file_asset_id,
    -- A draft is work in progress, never the document. It is reported beside
    -- the state rather than inside it.
    'has_open_draft',draft.version IS NOT NULL,'draft_version',draft.version,'draft_kind',draft.kind,
    'draft_assessment_on',draft.assessment_on,'draft_reason',draft.reason,
    'source_link_count',(SELECT count(*) FROM private_isg.risk_source_links l
      WHERE l.assessment_id=p_assessment AND l.version=coalesce(draft.version,current.version)),
    'versions',CASE WHEN p_history THEN
      (SELECT coalesce(jsonb_agg(jsonb_build_object('version',v.version,'kind',v.kind,
          'previous_version',v.previous_version,'assessment_on',v.assessment_on,'revision_on',v.revision_on,
          'scope',v.scope,'reason',v.reason,'state',v.state,'finalized_at',v.finalized_at,
          'period_years',v.period_years,'period_source',v.period_source,
          'period_needs_review',v.period_needs_review,'date_needs_review',v.date_needs_review,
          'valid_until',v.valid_until,'source_drift',v.source_drift,'drift_note',v.drift_note,
          'file_asset_id',v.file_asset_id,
          'sources',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',l.link_id,'analysis_id',l.analysis_id,
              'finding_id',l.finding_id,'source_version',l.source_version,'selected_at',l.selected_at)
              ORDER BY l.selected_at),'[]'::jsonb)
            FROM private_isg.risk_source_links l WHERE l.assessment_id=v.assessment_id AND l.version=v.version),
          'impacts',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',i.impact_id,'target_kind',i.target_kind,
              'target_ref',i.target_ref,'action',i.action,'note',i.note) ORDER BY i.created_at),'[]'::jsonb)
            FROM private_isg.revision_impacts i WHERE i.assessment_id=v.assessment_id AND i.version=v.version))
          ORDER BY v.version DESC),'[]'::jsonb)
       FROM private_isg.risk_assessment_versions v WHERE v.assessment_id=p_assessment) END,
    -- The legacy photo analysis is a source, never a risk assessment of its own.
    'analysis_is_not_an_assessment',true,'legacy_analysis_written',false);
END $$;

-- The catalogue tells the client which workplaces exist, what a period may be
-- attributed to and how wide the warning window is, so nothing on screen is a
-- number the client made up.
CREATE FUNCTION private_isg.read_risk_versions(p_company uuid,p_kind text,p_query text,p_state text,
  p_workplace uuid,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; needle text; today date; notice integer:=private_isg.risk_notice_days();
  page_limit integer; page_offset integer;
  tally_all jsonb; tally_companies jsonb; tally_rows jsonb; matching_rows integer;
BEGIN
  actor:=private_isg.require_risk_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('catalog','list','detail') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date;

  IF p_kind='catalog' THEN
    RETURN jsonb_build_object('schema_version',1,'kind','catalog','notice_days',notice,
      'workplaces',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,
          'needs_review',w.needs_review) ORDER BY w.name),'[]'::jsonb)
        FROM private_isg.workplaces w
        WHERE p_company IS NOT NULL AND w.company_id=p_company AND w.owner_id=actor AND NOT w.is_archived),
      'kinds',jsonb_build_array('full','partial','metadata'),
      -- Which rules the product could attribute a period to. An empty list is
      -- the honest answer while no rule set has been approved, and the client
      -- then has only the expert's own number, marked as such.
      'rules','[]'::jsonb,
      'period_defaults_offered',false,
      'expert_period_source','unapproved_fixture',
      'expert_period_needs_review',true,
      'analysis_is_not_an_assessment',true,
      'health_records_tracked',false);
  END IF;

  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.risk_assessments a
      JOIN public.companies c ON c.id=a.company_id AND c.user_id=actor AND private_isg.p05_pilot_can_read(actor,c.id)
      WHERE a.assessment_id=p_id AND (p_company IS NULL OR a.company_id=p_company);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'kind','detail','today',today,
      'row',private_isg.risk_assessment_row(p_id,today,true));
  END IF;

  IF p_state IS NOT NULL AND p_state NOT IN ('never_assessed','period_unknown','expired','due_soon','valid',
    'current','untracked') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  page_limit:=least(greatest(coalesce(p_limit,10),1),100);
  page_offset:=greatest(coalesce(p_offset,0),0);
  needle:=nullif(btrim(coalesce(p_query,'')),'');

  WITH scope AS (
    SELECT c.id,c.name FROM public.companies c WHERE c.user_id=actor AND private_isg.p05_pilot_can_read(actor,c.id) AND NOT c.is_archived
  ), page AS (
    SELECT a.assessment_id,a.company_id,s.name AS company_name,a.workplace_id,w.name AS workplace_name,
      private_isg.risk_assessment_status(a.current_version,a.current_version>0,a.valid_until,notice,today) AS entry_state,
      a.valid_until,
      -- Worst first: what ran out, then what was never assessed, then what has
      -- no period, then what is due.
      row_number() OVER (ORDER BY
        CASE private_isg.risk_assessment_status(a.current_version,a.current_version>0,a.valid_until,notice,today)
          WHEN 'expired' THEN 0 WHEN 'never_assessed' THEN 1 WHEN 'period_unknown' THEN 2
          WHEN 'due_soon' THEN 3 ELSE 4 END,
        a.valid_until NULLS FIRST,s.name,w.name,a.assessment_id) AS ordinal
    FROM private_isg.risk_assessments a
    JOIN scope s ON s.id=a.company_id
    JOIN private_isg.workplaces w ON w.company_id=a.company_id AND w.id=a.workplace_id
    WHERE a.owner_id=actor AND private_isg.p05_pilot_can_read(actor,a.company_id) AND NOT w.is_archived
  ), scoped AS (
    SELECT * FROM page WHERE (p_company IS NULL OR company_id=p_company)
  ), filtered AS (
    SELECT * FROM scoped
    WHERE (p_workplace IS NULL OR workplace_id=p_workplace)
      AND (p_state IS NULL OR entry_state=p_state
        OR private_isg.risk_assessment_group(entry_state)=p_state)
      AND (needle IS NULL OR workplace_name ILIKE '%'||needle||'%' OR company_name ILIKE '%'||needle||'%')
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
         private_isg.risk_assessment_row(picked.assessment_id,today,false)
           ||jsonb_build_object('company_name',picked.company_name,
               'workplace_name',picked.workplace_name) AS entry
       FROM (SELECT * FROM filtered ORDER BY ordinal LIMIT page_limit OFFSET page_offset) picked) built)
  INTO tally_all,tally_companies,matching_rows,tally_rows;

  RETURN jsonb_build_object('schema_version',1,'kind','list','rows',tally_rows,'today',today,
    'counts',tally_all,'companies',tally_companies,
    'total',matching_rows,'returned',jsonb_array_length(tally_rows),
    'has_more',page_offset+jsonb_array_length(tally_rows)<matching_rows,
    'limit',page_limit,'offset',page_offset,'notice_days',notice,
    -- A tally of tracked assessments, never a statement that any workplace is
    -- compliant, and never a claim that an analysis is an assessment.
    'compliance_verdict',NULL,'analysis_is_not_an_assessment',true,'health_records_tracked',false);
END $$;

-- Every write goes through the domain function that owns the rule. This is the
-- boundary: it proves who is asking, allowlists what may be sent, and keeps the
-- receipt so the same request twice is the same answer twice.
CREATE FUNCTION private_isg.mutate_risk_versions(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.risk_version_receipts;
  result jsonb; answer jsonb; target uuid; entry private_isg.risk_assessments;
  stamp timestamptz:=clock_timestamp(); today date;
BEGIN
  actor:=private_isg.require_risk_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>8192 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(stamp AT TIME ZONE 'Europe/Istanbul')::date;
  IF p_action NOT IN ('open_assessment','draft_version','finalize_version','record_impact') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  allowed:=CASE p_action
    WHEN 'open_assessment' THEN ARRAY['workplace_id']
    -- No verified_by here: the verification is the signed-in expert's own, and
    -- the boundary supplies it rather than letting the client name someone.
    WHEN 'draft_version' THEN ARRAY['assessment_id','kind','assessment_on','revision_on','scope','reason',
      'file_asset_id','expected_current']
    WHEN 'attach_source' THEN ARRAY['assessment_id','version','analysis_id','finding_id','source_version',
      'copied_fields']
    WHEN 'record_impact' THEN ARRAY['assessment_id','version','target_kind','target_ref','action','note']
    WHEN 'finalize_version' THEN ARRAY['assessment_id','version','expected_current','rule_code','period_years']
    WHEN 'flag_drift' THEN ARRAY['assessment_id','version','analysis_id','current_source_version','note']
    ELSE NULL END;
  IF allowed IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO offending FROM jsonb_object_keys(p_payload) AS keys(key)
    WHERE NOT (key=ANY(allowed)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;

  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-risk:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.risk_version_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN prior.response||jsonb_build_object('replayed',true);
  END IF;

  IF p_action='open_assessment' THEN
    IF p_payload->>'workplace_id' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    -- The workplace has to be this company's and this actor's before the domain
    -- function, which was written for a caller that had already checked.
    PERFORM 1 FROM private_isg.workplaces WHERE company_id=p_company
      AND id=(p_payload->>'workplace_id')::uuid AND owner_id=actor AND NOT is_archived;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    answer:=private_isg.open_risk_assessment(p_company,(p_payload->>'workplace_id')::uuid,stamp);
    target:=(answer->>'assessment_id')::uuid;
  ELSE
    target:=(p_payload->>'assessment_id')::uuid;
    SELECT * INTO entry FROM private_isg.risk_assessments
      WHERE assessment_id=target AND company_id=p_company AND owner_id=actor FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;

    IF p_action='draft_version' THEN
      IF p_payload->>'kind' IS NULL OR p_payload->>'expected_current' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.draft_risk_version(target,p_payload->>'kind',
        (p_payload->>'assessment_on')::date,(p_payload->>'revision_on')::date,
        CASE WHEN p_payload ? 'scope' THEN p_payload->'scope' END,
        nullif(btrim(coalesce(p_payload->>'reason','')),''),
        (p_payload->>'file_asset_id')::uuid,(p_payload->>'expected_current')::integer,stamp);
    ELSIF p_action='attach_source' THEN
      IF p_payload->>'version' IS NULL OR p_payload->>'analysis_id' IS NULL OR
         p_payload->>'finding_id' IS NULL OR p_payload->>'source_version' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.attach_risk_source(target,(p_payload->>'version')::integer,
        (p_payload->>'analysis_id')::uuid,(p_payload->>'finding_id')::uuid,
        (p_payload->>'source_version')::bigint,
        coalesce(p_payload->'copied_fields','{}'::jsonb),stamp);
    ELSIF p_action='record_impact' THEN
      IF p_payload->>'version' IS NULL OR p_payload->>'target_kind' IS NULL OR
         p_payload->>'target_ref' IS NULL OR p_payload->>'action' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.record_revision_impact(target,(p_payload->>'version')::integer,
        p_payload->>'target_kind',p_payload->>'target_ref',p_payload->>'action',
        nullif(btrim(coalesce(p_payload->>'note','')),''),stamp);
    ELSIF p_action='finalize_version' THEN
      IF p_payload->>'version' IS NULL OR p_payload->>'expected_current' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      -- The expert who is signed in is the one verifying. The client cannot
      -- name a verifier, so no record can carry someone else's confirmation.
      answer:=private_isg.finalize_risk_version(target,(p_payload->>'version')::integer,
        (p_payload->>'expected_current')::integer,actor,
        nullif(btrim(coalesce(p_payload->>'rule_code','')),''),
        (p_payload->>'period_years')::integer,stamp);
    ELSE
      IF p_payload->>'version' IS NULL OR p_payload->>'analysis_id' IS NULL OR
         p_payload->>'current_source_version' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.flag_source_drift(target,(p_payload->>'version')::integer,
        (p_payload->>'analysis_id')::uuid,(p_payload->>'current_source_version')::bigint,
        nullif(btrim(coalesce(p_payload->>'note','')),''),stamp);
    END IF;
  END IF;

  result:=jsonb_build_object('schema_version',1,'action',p_action,'assessment_id',target,
    'answer',answer,'row',private_isg.risk_assessment_row(target,today,true));
  INSERT INTO private_isg.risk_version_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $$;

CREATE FUNCTION public.isg_risk_versions_read_v1(p_company uuid,p_kind text,p_query text,p_state text,
  p_workplace uuid,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.read_risk_versions(p_company,p_kind,p_query,p_state,p_workplace,p_id,p_limit,p_offset)
$$;
CREATE FUNCTION public.isg_risk_versions_mutate_v1(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.mutate_risk_versions(p_company,p_action,p_operation,p_mutation,p_payload)
$$;

REVOKE ALL ON FUNCTION private_isg.risk_notice_days(),
  private_isg.risk_assessment_status(integer,boolean,date,integer,date),
  private_isg.risk_assessment_group(text),
  private_isg.risk_version_gate(boolean),
  private_isg.require_risk_company(uuid,boolean),
  private_isg.risk_assessment_row(uuid,date,boolean),
  private_isg.read_risk_versions(uuid,text,text,text,uuid,uuid,integer,integer),
  private_isg.mutate_risk_versions(uuid,text,uuid,uuid,jsonb),
  public.isg_risk_versions_read_v1(uuid,text,text,text,uuid,uuid,integer,integer),
  public.isg_risk_versions_mutate_v1(uuid,text,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.read_risk_versions(uuid,text,text,text,uuid,uuid,integer,integer),
  private_isg.mutate_risk_versions(uuid,text,uuid,uuid,jsonb),
  public.isg_risk_versions_read_v1(uuid,text,text,text,uuid,uuid,integer,integer),
  public.isg_risk_versions_mutate_v1(uuid,text,uuid,uuid,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';

