-- P17/D16 first slice: a versioned score policy, an explainable contribution
-- per process, a provisional answer whenever something is unknown, and a
-- portfolio that weighs every company equally.
-- Additive; rollout OFF; no client grant. The score is never an official
-- compliance certificate, the candidate weights are never approved here, and
-- no published snapshot is ever rewritten by a later policy.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE private_isg.rollout DROP CONSTRAINT rollout_feature_check;
ALTER TABLE private_isg.rollout ADD CONSTRAINT rollout_feature_check
  CHECK(feature IN ('personnel','event_dispatch','quota_ledger','file_core','rule_engine','training','risk',
    'nonconformity','modules','documents','imports','notifications','personal_notes','billing_lifecycle',
    'campaigns','observability','score'));
INSERT INTO private_isg.rollout(feature) VALUES('score');

CREATE TABLE private_isg.score_policy_versions (
  policy_version_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  revision integer NOT NULL UNIQUE CHECK(revision BETWEEN 1 AND 100000),
  status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','published','superseded')),
  rounding_scale integer NOT NULL DEFAULT 2 CHECK(rounding_scale BETWEEN 0 AND 4),
  weight_source text NOT NULL DEFAULT 'unapproved_fixture' CHECK(weight_source IN ('unapproved_fixture','approved_catalog')),
  weights_approved boolean NOT NULL DEFAULT false CHECK(NOT weights_approved),
  -- A score reports; it never certifies. There is no flag to claim otherwise.
  is_official_compliance_certificate boolean NOT NULL DEFAULT false CHECK(NOT is_official_compliance_certificate),
  approved_by uuid, approval_note text CHECK(approval_note IS NULL OR length(approval_note) BETWEEN 3 AND 500),
  published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK(status<>'published' OR (approved_by IS NOT NULL AND approval_note IS NOT NULL AND published_at IS NOT NULL)),
  CHECK(weight_source<>'unapproved_fixture' OR NOT weights_approved)
);
-- Each process carries its own contribution cap, so a company with a thousand
-- employees cannot grow one module's weight without limit.
CREATE TABLE private_isg.score_processes (
  policy_version_id uuid NOT NULL REFERENCES private_isg.score_policy_versions(policy_version_id) ON DELETE CASCADE,
  process_key text NOT NULL CHECK(process_key IN ('risk_assessment','training','health_surveillance_followup',
    'nonconformity','emergency_readiness','records_and_documents')),
  weight numeric(6,3) NOT NULL CHECK(weight>0 AND weight<=100),
  contribution_cap numeric(6,3) NOT NULL CHECK(contribution_cap>0),
  cap_approved boolean NOT NULL DEFAULT false CHECK(NOT cap_approved),
  PRIMARY KEY(policy_version_id,process_key),
  CHECK(contribution_cap<=weight)
);
-- What this company's situation is for one process. Unknown is its own state
-- and never collapses into "not required".
CREATE TABLE private_isg.score_subject_states (
  company_id uuid NOT NULL,
  process_key text NOT NULL,
  applicability text NOT NULL CHECK(applicability IN ('required','not_required','needs_review','voluntary')),
  completed_units bigint CHECK(completed_units IS NULL OR completed_units>=0),
  required_units bigint CHECK(required_units IS NULL OR required_units>=0),
  justification_note text CHECK(justification_note IS NULL OR length(justification_note) BETWEEN 3 AND 500),
  verified_by uuid, verified_on date CHECK(verified_on IS NULL OR isfinite(verified_on)),
  source_context text NOT NULL CHECK(length(source_context) BETWEEN 3 AND 200),
  recorded_at timestamptz NOT NULL,
  PRIMARY KEY(company_id,process_key),
  -- Leaving a process out of the main score needs a verified reason.
  CHECK(applicability<>'not_required' OR (justification_note IS NOT NULL AND verified_by IS NOT NULL AND verified_on IS NOT NULL)),
  CHECK(applicability<>'required' OR (completed_units IS NOT NULL AND required_units IS NOT NULL)),
  CHECK(completed_units IS NULL OR required_units IS NULL OR completed_units<=required_units)
);
CREATE TABLE private_isg.score_snapshots (
  snapshot_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  policy_version_id uuid NOT NULL REFERENCES private_isg.score_policy_versions(policy_version_id),
  computed_for date NOT NULL CHECK(isfinite(computed_for)),
  main_score numeric(5,2) CHECK(main_score IS NULL OR (main_score>=0 AND main_score<=100)),
  earned_points numeric(9,3) NOT NULL CHECK(earned_points>=0),
  total_weight numeric(9,3) NOT NULL CHECK(total_weight>=0),
  has_any_data boolean NOT NULL,
  provisional boolean NOT NULL,
  needs_review_count integer NOT NULL CHECK(needs_review_count>=0),
  voluntary_count integer NOT NULL CHECK(voluntary_count>=0),
  critical_count integer NOT NULL DEFAULT 0 CHECK(critical_count>=0),
  source_context jsonb NOT NULL,
  superseded_by uuid REFERENCES private_isg.score_snapshots(snapshot_id),
  is_official_certificate boolean NOT NULL DEFAULT false CHECK(NOT is_official_certificate),
  computed_at timestamptz NOT NULL,
  UNIQUE(company_id,policy_version_id,computed_for),
  -- With no data there is no hundred to show, and an unknown scope keeps the
  -- answer provisional instead of quietly rounding it up.
  CHECK(has_any_data OR main_score IS NULL),
  CHECK(total_weight>0 OR main_score IS NULL),
  CHECK(needs_review_count=0 OR provisional)
);
CREATE INDEX score_snapshot_company_idx ON private_isg.score_snapshots(company_id,computed_for DESC);
CREATE INDEX score_snapshot_policy_idx ON private_isg.score_snapshots(policy_version_id);
CREATE INDEX score_snapshot_superseded_idx ON private_isg.score_snapshots(superseded_by);
-- One row per process, so any number on screen can be traced back to a rule.
CREATE TABLE private_isg.score_contributions (
  contribution_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  snapshot_id uuid NOT NULL REFERENCES private_isg.score_snapshots(snapshot_id) ON DELETE CASCADE,
  process_key text NOT NULL,
  applicability text NOT NULL,
  weight numeric(6,3) NOT NULL,
  contribution_cap numeric(6,3) NOT NULL,
  completed_units bigint, required_units bigint,
  raw_ratio numeric(6,5) CHECK(raw_ratio IS NULL OR (raw_ratio>=0 AND raw_ratio<=1)),
  capped_points numeric(9,3) NOT NULL CHECK(capped_points>=0),
  cap_applied boolean NOT NULL,
  counted_in_total_weight boolean NOT NULL,
  exclusion_reason text CHECK(exclusion_reason IS NULL OR exclusion_reason IN ('verified_not_required','voluntary')),
  UNIQUE(snapshot_id,process_key),
  CHECK(capped_points<=contribution_cap),
  CHECK(counted_in_total_weight OR exclusion_reason IS NOT NULL),
  -- A voluntary record is neutral: it adds nothing and it takes nothing away.
  CHECK(exclusion_reason IS DISTINCT FROM 'voluntary' OR capped_points=0)
);
CREATE INDEX score_contribution_process_idx ON private_isg.score_contributions(process_key);
-- A critical warning is a fact of its own; a high total can never hide it.
CREATE TABLE private_isg.score_critical_findings (
  finding_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  snapshot_id uuid NOT NULL REFERENCES private_isg.score_snapshots(snapshot_id) ON DELETE CASCADE,
  code text NOT NULL CHECK(code ~ '^[A-Z][A-Z0-9_]{2,49}$'),
  process_key text NOT NULL,
  note text NOT NULL CHECK(length(note) BETWEEN 3 AND 500),
  hidden_by_total_score boolean NOT NULL DEFAULT false CHECK(NOT hidden_by_total_score),
  raised_at timestamptz NOT NULL,
  UNIQUE(snapshot_id,code)
);
-- Hand verified golden fixtures. The oracle is a number a person computed, not
-- a second call into the same production function.
CREATE TABLE private_isg.score_oracle_fixtures (
  fixture_key text PRIMARY KEY CHECK(fixture_key ~ '^[a-z][a-z0-9_]{2,49}$'),
  expected_main_score numeric(5,2),
  expected_provisional boolean NOT NULL,
  expected_total_weight numeric(9,3) NOT NULL,
  expected_earned_points numeric(9,3) NOT NULL,
  hand_computed boolean NOT NULL DEFAULT true CHECK(hand_computed),
  computed_by_production_function boolean NOT NULL DEFAULT false CHECK(NOT computed_by_production_function),
  verified_by uuid NOT NULL, verified_on date NOT NULL CHECK(isfinite(verified_on)),
  note text NOT NULL CHECK(length(note) BETWEEN 3 AND 500)
);
-- A weight change is simulated against real snapshots before anyone publishes.
CREATE TABLE private_isg.score_simulations (
  simulation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_policy_version_id uuid NOT NULL REFERENCES private_isg.score_policy_versions(policy_version_id),
  to_policy_version_id uuid NOT NULL REFERENCES private_isg.score_policy_versions(policy_version_id),
  companies_compared integer NOT NULL CHECK(companies_compared>=0),
  max_absolute_delta numeric(6,2),
  history_rewritten boolean NOT NULL DEFAULT false CHECK(NOT history_rewritten),
  detail jsonb NOT NULL,
  simulated_at timestamptz NOT NULL,
  CHECK(from_policy_version_id<>to_policy_version_id)
);
CREATE INDEX score_simulation_from_idx ON private_isg.score_simulations(from_policy_version_id);
CREATE INDEX score_simulation_to_idx ON private_isg.score_simulations(to_policy_version_id);
-- Every company counts once. Headcount is reported, never used as a weight.
CREATE TABLE private_isg.portfolio_projections (
  projection_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  policy_version_id uuid NOT NULL REFERENCES private_isg.score_policy_versions(policy_version_id),
  computed_for date NOT NULL CHECK(isfinite(computed_for)),
  weighting text NOT NULL DEFAULT 'equal_per_company' CHECK(weighting='equal_per_company'),
  companies_total integer NOT NULL CHECK(companies_total>=0),
  companies_scored integer NOT NULL CHECK(companies_scored>=0),
  companies_provisional integer NOT NULL CHECK(companies_provisional>=0),
  average_main_score numeric(5,2) CHECK(average_main_score IS NULL OR (average_main_score>=0 AND average_main_score<=100)),
  headcount_used_as_weight boolean NOT NULL DEFAULT false CHECK(NOT headcount_used_as_weight),
  computed_at timestamptz NOT NULL,
  UNIQUE(owner_id,policy_version_id,computed_for),
  CHECK(companies_scored<=companies_total),
  CHECK(companies_scored>0 OR average_main_score IS NULL)
);
CREATE INDEX portfolio_projection_policy_idx ON private_isg.portfolio_projections(policy_version_id);
CREATE TABLE private_isg.portfolio_entries (
  entry_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  projection_id uuid NOT NULL REFERENCES private_isg.portfolio_projections(projection_id) ON DELETE CASCADE,
  company_id uuid NOT NULL,
  snapshot_id uuid REFERENCES private_isg.score_snapshots(snapshot_id),
  main_score numeric(5,2),
  provisional boolean NOT NULL,
  employee_count bigint CHECK(employee_count IS NULL OR employee_count>=0),
  portfolio_weight numeric(6,5) NOT NULL DEFAULT 1 CHECK(portfolio_weight=1),
  UNIQUE(projection_id,company_id)
);
CREATE INDEX portfolio_entry_company_idx ON private_isg.portfolio_entries(company_id);
CREATE INDEX portfolio_entry_snapshot_idx ON private_isg.portfolio_entries(snapshot_id);

ALTER TABLE private_isg.score_policy_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.score_processes ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.score_subject_states ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.score_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.score_contributions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.score_critical_findings ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.score_oracle_fixtures ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.score_simulations ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.portfolio_projections ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.portfolio_entries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.score_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM private_isg.rollout WHERE feature='score' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $$;
-- Publication is a recorded human decision. The candidate weights stay
-- unapproved, so every snapshot they produce is a provisional report.
CREATE FUNCTION private_isg.publish_score_policy(p_policy uuid,p_approver uuid,p_note text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.score_policy_versions; process_count integer; weight_sum numeric;
BEGIN
  PERFORM private_isg.score_gate(true);
  IF p_policy IS NULL OR p_approver IS NULL OR p_note IS NULL OR p_now IS NULL OR
     length(p_note) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.score_policy_versions WHERE policy_version_id=p_policy FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.status='published' THEN
    RETURN jsonb_build_object('schema_version',1,'policy_version_id',p_policy,'status','published','replayed',true); END IF;
  IF entry.status<>'draft' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT count(*),coalesce(sum(weight),0) INTO process_count,weight_sum
    FROM private_isg.score_processes WHERE policy_version_id=p_policy;
  IF process_count=0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='POLICY_INCOMPLETE'; END IF;
  UPDATE private_isg.score_policy_versions SET status='published',approved_by=p_approver,approval_note=p_note,
    published_at=p_now WHERE policy_version_id=p_policy;
  RETURN jsonb_build_object('schema_version',1,'policy_version_id',p_policy,'status','published','replayed',false,
    'process_count',process_count,'weight_sum',weight_sum,'weights_approved',false,
    'is_official_compliance_certificate',false);
END $$;
CREATE FUNCTION private_isg.declare_subject_state(p_company uuid,p_process text,p_applicability text,
  p_completed bigint,p_required bigint,p_justification text,p_verified_by uuid,p_verified_on date,
  p_context text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM private_isg.score_gate(true);
  IF p_company IS NULL OR p_process IS NULL OR p_applicability IS NULL OR p_context IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  INSERT INTO private_isg.score_subject_states(company_id,process_key,applicability,completed_units,required_units,
      justification_note,verified_by,verified_on,source_context,recorded_at)
    VALUES(p_company,p_process,p_applicability,p_completed,p_required,p_justification,p_verified_by,p_verified_on,
      p_context,p_now)
    ON CONFLICT(company_id,process_key) DO UPDATE SET applicability=EXCLUDED.applicability,
      completed_units=EXCLUDED.completed_units,required_units=EXCLUDED.required_units,
      justification_note=EXCLUDED.justification_note,verified_by=EXCLUDED.verified_by,
      verified_on=EXCLUDED.verified_on,source_context=EXCLUDED.source_context,recorded_at=EXCLUDED.recorded_at;
  RETURN jsonb_build_object('schema_version',1,'company_id',p_company,'process_key',p_process,
    'applicability',p_applicability,'counts_in_main_score',p_applicability IN ('required','needs_review'));
END $$;
-- The one calculation, with no writes at all. The snapshot and the simulation
-- both go through it, so a simulated number and a stored number cannot drift.
CREATE FUNCTION private_isg.score_preview(p_company uuid,p_policy uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE proc record; subject private_isg.score_subject_states; ratio numeric; points numeric;
  running_earned numeric:=0; running_weight numeric:=0; review_count integer:=0; volunteer_count integer:=0;
  any_data boolean; lines jsonb:='[]'::jsonb; resolved text; excluded text; cap_hit boolean; scale integer; total numeric;
BEGIN
  SELECT rounding_scale INTO scale FROM private_isg.score_policy_versions WHERE policy_version_id=p_policy;
  IF scale IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT EXISTS(SELECT 1 FROM private_isg.score_subject_states WHERE company_id=p_company) INTO any_data;
  FOR proc IN SELECT * FROM private_isg.score_processes WHERE policy_version_id=p_policy ORDER BY process_key LOOP
    SELECT * INTO subject FROM private_isg.score_subject_states
      WHERE company_id=p_company AND process_key=proc.process_key;
    -- No record is not a "no": an unmeasured process is unknown, not exempt.
    resolved:=coalesce(subject.applicability,'needs_review');
    ratio:=NULL; points:=0; excluded:=NULL; cap_hit:=false;
    IF resolved='required' THEN
      ratio:=CASE WHEN subject.required_units=0 THEN 1
        ELSE round(subject.completed_units::numeric/subject.required_units::numeric,5) END;
      points:=ratio*proc.weight;
      IF points>proc.contribution_cap THEN points:=proc.contribution_cap; cap_hit:=true; END IF;
      running_weight:=running_weight+proc.weight;
    ELSIF resolved='needs_review' THEN
      review_count:=review_count+1;
      running_weight:=running_weight+proc.weight;
    ELSIF resolved='not_required' THEN
      excluded:='verified_not_required';
    ELSE
      volunteer_count:=volunteer_count+1; excluded:='voluntary';
    END IF;
    running_earned:=running_earned+points;
    lines:=lines||jsonb_build_object('process_key',proc.process_key,'applicability',resolved,
      'weight',proc.weight,'contribution_cap',proc.contribution_cap,'completed_units',subject.completed_units,
      'required_units',subject.required_units,'raw_ratio',ratio,'capped_points',points,'cap_applied',cap_hit,
      'counted_in_total_weight',excluded IS NULL,'exclusion_reason',excluded);
  END LOOP;
  -- No data means no number. A hundred is never shown for an empty company.
  total:=CASE WHEN any_data AND running_weight>0 THEN round(100*running_earned/running_weight,scale) ELSE NULL END;
  RETURN jsonb_build_object('schema_version',1,'main_score',total,'earned_points',running_earned,
    'total_weight',running_weight,'has_any_data',any_data,'provisional',review_count>0 OR total IS NULL,
    'needs_review_count',review_count,'voluntary_count',volunteer_count,'contributions',lines,
    'is_official_certificate',false);
END $$;
CREATE FUNCTION private_isg.compute_score_snapshot(p_company uuid,p_policy uuid,p_for date,p_context jsonb,
  p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.score_policy_versions; preview jsonb; snap uuid; prior uuid; line jsonb;
BEGIN
  PERFORM private_isg.score_gate(true);
  IF p_company IS NULL OR p_policy IS NULL OR p_for IS NULL OR p_now IS NULL OR p_context IS NULL OR
     jsonb_typeof(p_context)<>'object' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.score_policy_versions WHERE policy_version_id=p_policy;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.status<>'published' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='POLICY_NOT_PUBLISHED'; END IF;
  SELECT snapshot_id INTO prior FROM private_isg.score_snapshots
    WHERE company_id=p_company AND policy_version_id=p_policy AND computed_for=p_for;
  IF prior IS NOT NULL THEN
    RETURN jsonb_build_object('schema_version',1,'snapshot_id',prior,'replayed',true); END IF;
  preview:=private_isg.score_preview(p_company,p_policy);
  INSERT INTO private_isg.score_snapshots(company_id,policy_version_id,computed_for,main_score,earned_points,
      total_weight,has_any_data,provisional,needs_review_count,voluntary_count,source_context,computed_at)
    VALUES(p_company,p_policy,p_for,(preview->>'main_score')::numeric,(preview->>'earned_points')::numeric,
      (preview->>'total_weight')::numeric,(preview->>'has_any_data')::boolean,(preview->>'provisional')::boolean,
      (preview->>'needs_review_count')::integer,(preview->>'voluntary_count')::integer,
      p_context||jsonb_build_object('policy_revision',entry.revision,'weights_approved',false),p_now)
    RETURNING snapshot_id INTO snap;
  FOR line IN SELECT * FROM jsonb_array_elements(preview->'contributions') LOOP
    INSERT INTO private_isg.score_contributions(snapshot_id,process_key,applicability,weight,contribution_cap,
        completed_units,required_units,raw_ratio,capped_points,cap_applied,counted_in_total_weight,exclusion_reason)
      VALUES(snap,line->>'process_key',line->>'applicability',(line->>'weight')::numeric,
        (line->>'contribution_cap')::numeric,(line->>'completed_units')::bigint,(line->>'required_units')::bigint,
        (line->>'raw_ratio')::numeric,(line->>'capped_points')::numeric,(line->>'cap_applied')::boolean,
        (line->>'counted_in_total_weight')::boolean,line->>'exclusion_reason');
  END LOOP;
  RETURN jsonb_build_object('schema_version',1,'snapshot_id',snap,'replayed',false,
    'main_score',preview->'main_score','provisional',preview->'provisional',
    'total_weight',preview->'total_weight','earned_points',preview->'earned_points',
    'needs_review_count',preview->'needs_review_count','voluntary_count',preview->'voluntary_count',
    'has_any_data',preview->'has_any_data','policy_revision',entry.revision,
    'weights_approved',false,'is_official_certificate',false);
END $$;
CREATE FUNCTION private_isg.explain_score(p_snapshot uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.score_snapshots; lines jsonb; warnings jsonb;
BEGIN
  PERFORM private_isg.score_gate(false);
  SELECT * INTO entry FROM private_isg.score_snapshots WHERE snapshot_id=p_snapshot;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY c.process_key),'[]'::jsonb) INTO lines
    FROM private_isg.score_contributions c WHERE c.snapshot_id=p_snapshot;
  -- A critical warning is reported next to the number, never folded into it.
  SELECT coalesce(jsonb_agg(jsonb_build_object('code',f.code,'process_key',f.process_key) ORDER BY f.code),'[]'::jsonb)
    INTO warnings FROM private_isg.score_critical_findings f WHERE f.snapshot_id=p_snapshot;
  RETURN jsonb_build_object('schema_version',1,'snapshot_id',p_snapshot,'main_score',entry.main_score,
    'provisional',entry.provisional,'contributions',lines,'critical_findings',warnings,
    'critical_findings_hidden',false,'is_official_certificate',false);
END $$;
CREATE FUNCTION private_isg.raise_score_critical_finding(p_snapshot uuid,p_code text,p_process text,p_note text,
  p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE created uuid; total integer;
BEGIN
  PERFORM private_isg.score_gate(true);
  IF p_snapshot IS NULL OR p_code IS NULL OR p_process IS NULL OR p_note IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  INSERT INTO private_isg.score_critical_findings(snapshot_id,code,process_key,note,raised_at)
    VALUES(p_snapshot,p_code,p_process,p_note,p_now) RETURNING finding_id INTO created;
  SELECT count(*) INTO total FROM private_isg.score_critical_findings WHERE snapshot_id=p_snapshot;
  UPDATE private_isg.score_snapshots SET critical_count=total WHERE snapshot_id=p_snapshot;
  RETURN jsonb_build_object('schema_version',1,'finding_id',created,'critical_count',total,
    'hidden_by_total_score',false);
END $$;
-- The fixture holds a number a person worked out by hand. Comparing the
-- production function with itself would prove nothing.
CREATE FUNCTION private_isg.verify_against_oracle(p_fixture text,p_snapshot uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE fixture private_isg.score_oracle_fixtures; entry private_isg.score_snapshots; matched boolean;
BEGIN
  PERFORM private_isg.score_gate(false);
  SELECT * INTO fixture FROM private_isg.score_oracle_fixtures WHERE fixture_key=p_fixture;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO entry FROM private_isg.score_snapshots WHERE snapshot_id=p_snapshot;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  matched:=entry.main_score IS NOT DISTINCT FROM fixture.expected_main_score
    AND entry.provisional=fixture.expected_provisional
    AND entry.total_weight=fixture.expected_total_weight
    AND entry.earned_points=fixture.expected_earned_points;
  RETURN jsonb_build_object('schema_version',1,'fixture_key',p_fixture,'matched',matched,
    'expected_main_score',fixture.expected_main_score,'actual_main_score',entry.main_score,
    'expected_total_weight',fixture.expected_total_weight,'actual_total_weight',entry.total_weight,
    'expected_earned_points',fixture.expected_earned_points,'actual_earned_points',entry.earned_points,
    'hand_computed',fixture.hand_computed,'computed_by_production_function',false);
END $$;
-- A weight change is measured against the companies that already have a
-- snapshot, and it writes no snapshot and rewrites no history.
CREATE FUNCTION private_isg.simulate_policy_change(p_from uuid,p_to uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry record; before_value numeric; after_value numeric; compared integer:=0; worst numeric:=NULL;
  lines jsonb:='[]'::jsonb; created uuid;
BEGIN
  PERFORM private_isg.score_gate(true);
  IF p_from IS NULL OR p_to IS NULL OR p_now IS NULL OR p_from=p_to THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  FOR entry IN SELECT DISTINCT company_id FROM private_isg.score_snapshots
      WHERE policy_version_id=p_from ORDER BY company_id LOOP
    before_value:=(private_isg.score_preview(entry.company_id,p_from)->>'main_score')::numeric;
    after_value:=(private_isg.score_preview(entry.company_id,p_to)->>'main_score')::numeric;
    compared:=compared+1;
    IF before_value IS NOT NULL AND after_value IS NOT NULL THEN
      worst:=greatest(coalesce(worst,0),abs(after_value-before_value)); END IF;
    lines:=lines||jsonb_build_object('company_id',entry.company_id,'before',before_value,'after',after_value);
  END LOOP;
  INSERT INTO private_isg.score_simulations(from_policy_version_id,to_policy_version_id,companies_compared,
      max_absolute_delta,detail,simulated_at)
    VALUES(p_from,p_to,compared,worst,jsonb_build_object('rows',lines),p_now) RETURNING simulation_id INTO created;
  RETURN jsonb_build_object('schema_version',1,'simulation_id',created,'companies_compared',compared,
    'max_absolute_delta',worst,'history_rewritten',false,'snapshots_written',0);
END $$;
-- Every company counts once. A thousand employee company does not take over
-- the portfolio; the headcount is reported beside the number, not inside it.
CREATE FUNCTION private_isg.build_portfolio_projection(p_owner uuid,p_policy uuid,p_for date,p_companies jsonb,
  p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry jsonb; snap private_isg.score_snapshots; created uuid; prior uuid;
  total_count integer:=0; scored integer:=0; review_count integer:=0; score_sum numeric:=0; average numeric;
BEGIN
  PERFORM private_isg.score_gate(true);
  IF p_owner IS NULL OR p_policy IS NULL OR p_for IS NULL OR p_now IS NULL OR p_companies IS NULL OR
     jsonb_typeof(p_companies)<>'array' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT projection_id INTO prior FROM private_isg.portfolio_projections
    WHERE owner_id=p_owner AND policy_version_id=p_policy AND computed_for=p_for;
  IF prior IS NOT NULL THEN
    RETURN jsonb_build_object('schema_version',1,'projection_id',prior,'replayed',true); END IF;
  INSERT INTO private_isg.portfolio_projections(owner_id,policy_version_id,computed_for,companies_total,
      companies_scored,companies_provisional,average_main_score,computed_at)
    VALUES(p_owner,p_policy,p_for,0,0,0,NULL,p_now) RETURNING projection_id INTO created;
  FOR entry IN SELECT * FROM jsonb_array_elements(p_companies) LOOP
    total_count:=total_count+1;
    SELECT * INTO snap FROM private_isg.score_snapshots
      WHERE company_id=(entry->>'company_id')::uuid AND policy_version_id=p_policy AND computed_for=p_for;
    IF snap.snapshot_id IS NOT NULL AND snap.main_score IS NOT NULL THEN
      scored:=scored+1; score_sum:=score_sum+snap.main_score; END IF;
    IF coalesce(snap.provisional,true) THEN review_count:=review_count+1; END IF;
    INSERT INTO private_isg.portfolio_entries(projection_id,company_id,snapshot_id,main_score,provisional,
        employee_count)
      VALUES(created,(entry->>'company_id')::uuid,snap.snapshot_id,snap.main_score,coalesce(snap.provisional,true),
        (entry->>'employee_count')::bigint);
  END LOOP;
  average:=CASE WHEN scored>0 THEN round(score_sum/scored,2) ELSE NULL END;
  UPDATE private_isg.portfolio_projections SET companies_total=total_count,companies_scored=scored,
    companies_provisional=review_count,average_main_score=average WHERE projection_id=created;
  RETURN jsonb_build_object('schema_version',1,'projection_id',created,'replayed',false,
    'companies_total',total_count,'companies_scored',scored,'companies_provisional',review_count,
    'average_main_score',average,'weighting','equal_per_company','headcount_used_as_weight',false);
END $$;
REVOKE ALL ON FUNCTION private_isg.score_gate(boolean),
  private_isg.publish_score_policy(uuid,uuid,text,timestamptz),
  private_isg.declare_subject_state(uuid,text,text,bigint,bigint,text,uuid,date,text,timestamptz),
  private_isg.score_preview(uuid,uuid),
  private_isg.compute_score_snapshot(uuid,uuid,date,jsonb,timestamptz),
  private_isg.explain_score(uuid),
  private_isg.raise_score_critical_finding(uuid,text,text,text,timestamptz),
  private_isg.verify_against_oracle(text,uuid),
  private_isg.simulate_policy_change(uuid,uuid,timestamptz),
  private_isg.build_portfolio_projection(uuid,uuid,date,jsonb,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
