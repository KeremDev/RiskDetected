-- P06/D06 first slice: legal source registry, versioned rules with a bounded
-- applicability expression, a publishing gate that needs human approval, dated
-- requirement periods on real calendar math and schedule invalidation.
-- Additive; rollout OFF; no client grant; legacy findings/notifications untouched.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE private_isg.rollout DROP CONSTRAINT rollout_feature_check;
ALTER TABLE private_isg.rollout ADD CONSTRAINT rollout_feature_check
  CHECK(feature IN ('personnel','event_dispatch','quota_ledger','file_core','rule_engine'));
INSERT INTO private_isg.rollout(feature) VALUES('rule_engine');

-- A URL is not verification. Clearing review needs a retrieved document
-- checksum, a named reviewer and a written evidence note.
CREATE TABLE private_isg.legal_sources (
  source_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  jurisdiction text NOT NULL CHECK(jurisdiction ~ '^[A-Z]{2}$'),
  citation text NOT NULL CHECK(btrim(citation)<>'' AND length(citation)<=300),
  -- PostgreSQL caps a regex repetition count at 255, so the length is its own check.
  url text NOT NULL CHECK(url ~ '^https://[^[:space:]]+$' AND length(url) BETWEEN 12 AND 500),
  document_sha256 bytea NOT NULL CHECK(octet_length(document_sha256)=32),
  retrieved_at timestamptz NOT NULL,
  effective_from date NOT NULL CHECK(isfinite(effective_from)),
  effective_to date CHECK(effective_to IS NULL OR isfinite(effective_to)),
  verified_by uuid REFERENCES public.profiles(id), verified_at timestamptz,
  evidence_note text CHECK(evidence_note IS NULL OR length(evidence_note) BETWEEN 10 AND 2000),
  needs_review boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(url,document_sha256),
  CHECK((verified_by IS NULL)=(verified_at IS NULL)),
  CHECK(needs_review OR (verified_by IS NOT NULL AND evidence_note IS NOT NULL)),
  CHECK(effective_to IS NULL OR effective_from<effective_to)
);
CREATE TABLE private_isg.rule_versions (
  rule_code text NOT NULL CHECK(rule_code ~ '^[a-z][a-z0-9_]{2,40}\.[a-z][a-z0-9_]{2,40}$'),
  version integer NOT NULL CHECK(version BETWEEN 1 AND 1000),
  source_id uuid NOT NULL REFERENCES private_isg.legal_sources(source_id),
  jurisdiction text NOT NULL CHECK(jurisdiction ~ '^[A-Z]{2}$'),
  applicability jsonb NOT NULL,
  action_kind text NOT NULL CHECK(action_kind IN ('training','inspection','drill','plan_review','document_renewal')),
  -- Calendar months and years only. A yearly obligation is not 365 days.
  period_kind text NOT NULL CHECK(period_kind IN ('once','months','years')),
  period_length integer CHECK(period_length IS NULL OR period_length BETWEEN 1 AND 120),
  status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','simulated','published','superseded')),
  approved_by uuid REFERENCES public.profiles(id), approval_note text, published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(rule_code,version),
  CHECK((period_kind='once')=(period_length IS NULL)),
  CHECK(status<>'published' OR (approved_by IS NOT NULL AND approval_note IS NOT NULL AND published_at IS NOT NULL))
);
CREATE UNIQUE INDEX rule_single_published_idx ON private_isg.rule_versions(rule_code) WHERE status='published';
CREATE TABLE private_isg.rule_simulations (
  simulation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_code text NOT NULL, version integer NOT NULL,
  sample_size integer NOT NULL CHECK(sample_size>0),
  outcome jsonb NOT NULL, simulated_at timestamptz NOT NULL,
  UNIQUE(rule_code,version),
  FOREIGN KEY(rule_code,version) REFERENCES private_isg.rule_versions(rule_code,version) ON DELETE CASCADE
);
CREATE TABLE private_isg.applicability_decisions (
  decision_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, owner_id uuid NOT NULL, workplace_id uuid NOT NULL,
  rule_code text NOT NULL, rule_version integer NOT NULL,
  context_version bigint NOT NULL,
  decided_on date NOT NULL CHECK(isfinite(decided_on)),
  state text NOT NULL CHECK(state IN ('required','not_required','needs_review')),
  reason text NOT NULL CHECK(reason ~ '^[A-Z][A-Z_]{2,49}$'),
  missing_facts text[] NOT NULL DEFAULT '{}',
  facts jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id,workplace_id,rule_code,rule_version,context_version,decided_on),
  FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE,
  FOREIGN KEY(company_id,workplace_id) REFERENCES private_isg.workplaces(company_id,id) ON DELETE CASCADE,
  FOREIGN KEY(rule_code,rule_version) REFERENCES private_isg.rule_versions(rule_code,version)
);
-- One obligation per rule action and period; a retry can not open a second one.
CREATE TABLE private_isg.requirement_instances (
  requirement_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL, workplace_id uuid NOT NULL,
  decision_id uuid NOT NULL REFERENCES private_isg.applicability_decisions(decision_id) ON DELETE CASCADE,
  rule_code text NOT NULL, rule_version integer NOT NULL, action_kind text NOT NULL,
  period_key text NOT NULL CHECK(period_key ~ '^(once|[0-9]{4}-[0-9]{2}-[0-9]{2})$'),
  status text NOT NULL DEFAULT 'open' CHECK(status IN ('open','satisfied','cancelled','superseded')),
  closed_reason text CHECK(closed_reason IS NULL OR closed_reason ~ '^[A-Z][A-Z_]{2,49}$'),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id,workplace_id,rule_code,action_kind,period_key),
  CHECK((status IN ('cancelled','superseded'))=(closed_reason IS NOT NULL))
);
CREATE TABLE private_isg.requirement_schedules (
  schedule_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  requirement_id uuid NOT NULL REFERENCES private_isg.requirement_instances(requirement_id) ON DELETE CASCADE,
  version integer NOT NULL CHECK(version>=1),
  due_on date NOT NULL CHECK(isfinite(due_on)),
  timezone text NOT NULL,
  state text NOT NULL DEFAULT 'active' CHECK(state IN ('active','invalidated','completed')),
  invalidated_reason text CHECK(invalidated_reason IS NULL OR invalidated_reason ~ '^[A-Z][A-Z_]{2,49}$'),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(requirement_id,version),
  CHECK((state='invalidated')=(invalidated_reason IS NOT NULL))
);
CREATE UNIQUE INDEX schedule_single_active_idx ON private_isg.requirement_schedules(requirement_id) WHERE state='active';
CREATE TABLE private_isg.rule_reconciliations (
  ran_on date PRIMARY KEY CHECK(isfinite(ran_on)),
  report jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX rule_version_source_idx ON private_isg.rule_versions(source_id);
CREATE INDEX decision_scope_idx ON private_isg.applicability_decisions(company_id,workplace_id,rule_code);
CREATE INDEX decision_owner_idx ON private_isg.applicability_decisions(company_id,owner_id);
CREATE INDEX decision_rule_idx ON private_isg.applicability_decisions(rule_code,rule_version);
CREATE INDEX requirement_scope_idx ON private_isg.requirement_instances(company_id,workplace_id,status);
CREATE INDEX requirement_decision_idx ON private_isg.requirement_instances(decision_id);
CREATE INDEX schedule_due_idx ON private_isg.requirement_schedules(state,due_on);
CREATE INDEX legal_source_verifier_idx ON private_isg.legal_sources(verified_by);
CREATE INDEX rule_version_approver_idx ON private_isg.rule_versions(approved_by);
ALTER TABLE private_isg.legal_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.rule_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.rule_simulations ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.applicability_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.requirement_instances ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.requirement_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.rule_reconciliations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.rule_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM 1 FROM private_isg.rollout WHERE feature='rule_engine' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $$;
-- Deliberately tiny grammar: {"all"|"any":[clause,...]} with one level of
-- clauses over four allowlisted facts. No free text, no arithmetic, no eval.
CREATE FUNCTION private_isg.validate_rule_expression(p_expression jsonb) RETURNS void
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE combinator text; clause jsonb; operator text; clauses jsonb;
BEGIN
  IF p_expression IS NULL OR jsonb_typeof(p_expression)<>'object' OR
     (SELECT count(*) FROM jsonb_object_keys(p_expression))<>1 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO combinator FROM jsonb_object_keys(p_expression) key;
  IF combinator NOT IN ('all','any') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  clauses:=p_expression->combinator;
  IF jsonb_typeof(clauses)<>'array' OR jsonb_array_length(clauses) NOT BETWEEN 1 AND 8 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  FOR clause IN SELECT * FROM jsonb_array_elements(clauses) LOOP
    IF jsonb_typeof(clause)<>'object' OR (SELECT count(*) FROM jsonb_object_keys(clause))<>2 OR
       jsonb_typeof(clause->'fact')<>'string' OR
       (clause->>'fact') NOT IN ('hazard_class','industry_code','jurisdiction','employee_count') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    SELECT key INTO operator FROM jsonb_object_keys(clause) key WHERE key<>'fact';
    IF operator NOT IN ('in','not_in','eq','gte','lte') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    IF operator IN ('in','not_in') THEN
      IF jsonb_typeof(clause->operator)<>'array' OR jsonb_array_length(clause->operator) NOT BETWEEN 1 AND 16 OR
         EXISTS(SELECT 1 FROM jsonb_array_elements(clause->operator) v WHERE jsonb_typeof(v)<>'string') THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    ELSIF operator='eq' THEN
      IF jsonb_typeof(clause->'eq')<>'string' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    ELSE
      IF jsonb_typeof(clause->operator)<>'number' OR (clause->>operator) !~ '^[0-9]{1,9}$' OR
         (clause->>'fact')<>'employee_count' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    END IF;
  END LOOP;
END $$;
-- A missing fact is review, never a silent "not required".
CREATE FUNCTION private_isg.evaluate_applicability(p_expression jsonb,p_facts jsonb) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE combinator text; clause jsonb; operator text; fact text; value jsonb;
  truth boolean; missing text[]:='{}'; any_true boolean:=false; any_false boolean:=false; unknown boolean:=false;
BEGIN
  PERFORM private_isg.validate_rule_expression(p_expression);
  IF p_facts IS NULL OR jsonb_typeof(p_facts)<>'object' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO combinator FROM jsonb_object_keys(p_expression) key;
  FOR clause IN SELECT * FROM jsonb_array_elements(p_expression->combinator) LOOP
    fact:=clause->>'fact';
    SELECT key INTO operator FROM jsonb_object_keys(clause) key WHERE key<>'fact';
    value:=p_facts->fact;
    IF value IS NULL OR jsonb_typeof(value)='null' THEN
      missing:=missing||fact; unknown:=true; CONTINUE; END IF;
    IF operator IN ('gte','lte') THEN
      IF jsonb_typeof(value)<>'number' THEN missing:=missing||fact; unknown:=true; CONTINUE; END IF;
      truth:=CASE operator WHEN 'gte' THEN (value::text)::numeric>=(clause->>operator)::numeric
                           ELSE (value::text)::numeric<=(clause->>operator)::numeric END;
    ELSE
      IF jsonb_typeof(value)<>'string' THEN missing:=missing||fact; unknown:=true; CONTINUE; END IF;
      truth:=CASE operator
        WHEN 'eq' THEN (value#>>'{}')=(clause->>'eq')
        WHEN 'in' THEN clause->'in' @> jsonb_build_array(value#>>'{}')
        ELSE NOT (clause->'not_in' @> jsonb_build_array(value#>>'{}')) END;
    END IF;
    IF truth THEN any_true:=true; ELSE any_false:=true; END IF;
  END LOOP;
  IF combinator='all' THEN
    IF any_false THEN RETURN jsonb_build_object('state','not_required','reason','CLAUSE_NOT_MATCHED','missing_facts',missing); END IF;
    IF unknown THEN RETURN jsonb_build_object('state','needs_review','reason','FACT_UNKNOWN','missing_facts',missing); END IF;
    RETURN jsonb_build_object('state','required','reason','ALL_CLAUSES_MATCHED','missing_facts',missing);
  END IF;
  IF any_true THEN RETURN jsonb_build_object('state','required','reason','CLAUSE_MATCHED','missing_facts',missing); END IF;
  IF unknown THEN RETURN jsonb_build_object('state','needs_review','reason','FACT_UNKNOWN','missing_facts',missing); END IF;
  RETURN jsonb_build_object('state','not_required','reason','NO_CLAUSE_MATCHED','missing_facts',missing);
END $$;
-- Real calendar arithmetic: a year is a calendar year, and 31 January plus one
-- month is the last day of February, not the 3rd of March.
CREATE FUNCTION private_isg.next_due_on(p_from date,p_kind text,p_length integer) RETURNS date
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
BEGIN
  IF p_from IS NULL OR NOT isfinite(p_from) OR p_kind IS NULL OR p_kind NOT IN ('once','months','years') OR
     (p_kind='once')<>(p_length IS NULL) OR (p_length IS NOT NULL AND p_length NOT BETWEEN 1 AND 120) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_kind='once' THEN RETURN p_from; END IF;
  RETURN (p_from+CASE p_kind WHEN 'months' THEN make_interval(months=>p_length) ELSE make_interval(years=>p_length) END)::date;
END $$;
CREATE FUNCTION private_isg.register_legal_source(p_jurisdiction text,p_citation text,p_url text,p_sha256 bytea,
  p_retrieved_at timestamptz,p_from date,p_to date,p_verified_by uuid,p_evidence text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE source uuid; review boolean;
BEGIN
  PERFORM private_isg.rule_gate(true);
  IF p_jurisdiction IS NULL OR p_citation IS NULL OR p_url IS NULL OR p_sha256 IS NULL OR octet_length(p_sha256)<>32 OR
     p_retrieved_at IS NULL OR p_from IS NULL OR p_now IS NULL OR p_retrieved_at>p_now THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  -- Evidence without a named reviewer, or a reviewer without evidence, stays in review.
  review:=p_verified_by IS NULL OR p_evidence IS NULL;
  SELECT source_id INTO source FROM private_isg.legal_sources WHERE url=p_url AND document_sha256=p_sha256;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'source_id',source,'replayed',true); END IF;
  INSERT INTO private_isg.legal_sources(jurisdiction,citation,url,document_sha256,retrieved_at,effective_from,
      effective_to,verified_by,verified_at,evidence_note,needs_review,created_at)
    VALUES(p_jurisdiction,private_isg.text_value(p_citation,300),p_url,p_sha256,p_retrieved_at,p_from,p_to,
      CASE WHEN review THEN NULL ELSE p_verified_by END,CASE WHEN review THEN NULL ELSE p_now END,
      p_evidence,review,p_now) RETURNING source_id INTO source;
  RETURN jsonb_build_object('schema_version',1,'source_id',source,'needs_review',review,'replayed',false);
END $$;
CREATE FUNCTION private_isg.add_rule_version(p_code text,p_source uuid,p_expression jsonb,p_action text,
  p_period_kind text,p_period_length integer,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE source private_isg.legal_sources; next_version integer;
BEGIN
  PERFORM private_isg.rule_gate(true);
  IF p_code IS NULL OR p_source IS NULL OR p_now IS NULL OR p_action IS NULL OR p_period_kind IS NULL OR
     p_action NOT IN ('training','inspection','drill','plan_review','document_renewal') OR
     p_period_kind NOT IN ('once','months','years') OR (p_period_kind='once')<>(p_period_length IS NULL) OR
     (p_period_length IS NOT NULL AND p_period_length NOT BETWEEN 1 AND 120) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  PERFORM private_isg.validate_rule_expression(p_expression);
  SELECT * INTO source FROM private_isg.legal_sources WHERE source_id=p_source FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT coalesce(max(version),0)+1 INTO next_version FROM private_isg.rule_versions WHERE rule_code=p_code;
  INSERT INTO private_isg.rule_versions(rule_code,version,source_id,jurisdiction,applicability,action_kind,
      period_kind,period_length,created_at)
    VALUES(p_code,next_version,p_source,source.jurisdiction,p_expression,p_action,p_period_kind,p_period_length,p_now);
  RETURN jsonb_build_object('schema_version',1,'rule_code',p_code,'version',next_version,'status','draft',
    'jurisdiction',source.jurisdiction);
END $$;
CREATE FUNCTION private_isg.simulate_rule_version(p_code text,p_version integer,p_samples jsonb,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE rule private_isg.rule_versions; sample jsonb; verdict jsonb; required integer:=0; refused integer:=0; review integer:=0;
BEGIN
  PERFORM private_isg.rule_gate(true);
  IF p_code IS NULL OR p_version IS NULL OR p_now IS NULL OR p_samples IS NULL OR jsonb_typeof(p_samples)<>'array' OR
     jsonb_array_length(p_samples) NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO rule FROM private_isg.rule_versions WHERE rule_code=p_code AND version=p_version FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF rule.status NOT IN ('draft','simulated') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  FOR sample IN SELECT * FROM jsonb_array_elements(p_samples) LOOP
    verdict:=private_isg.evaluate_applicability(rule.applicability,sample);
    IF verdict->>'state'='required' THEN required:=required+1;
    ELSIF verdict->>'state'='not_required' THEN refused:=refused+1; ELSE review:=review+1; END IF;
  END LOOP;
  INSERT INTO private_isg.rule_simulations(rule_code,version,sample_size,outcome,simulated_at)
    VALUES(p_code,p_version,jsonb_array_length(p_samples),
      jsonb_build_object('required',required,'not_required',refused,'needs_review',review),p_now)
  ON CONFLICT(rule_code,version) DO UPDATE SET sample_size=excluded.sample_size,outcome=excluded.outcome,simulated_at=excluded.simulated_at;
  UPDATE private_isg.rule_versions SET status='simulated' WHERE rule_code=p_code AND version=p_version;
  RETURN jsonb_build_object('schema_version',1,'rule_code',p_code,'version',p_version,'status','simulated',
    'required',required,'not_required',refused,'needs_review',review);
END $$;
-- Publishing needs a verified source, a simulation and a named human approval.
CREATE FUNCTION private_isg.publish_rule_version(p_code text,p_version integer,p_approver uuid,p_note text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE rule private_isg.rule_versions; source private_isg.legal_sources; previous integer;
BEGIN
  PERFORM private_isg.rule_gate(true);
  IF p_code IS NULL OR p_version IS NULL OR p_approver IS NULL OR p_now IS NULL OR p_note IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO rule FROM private_isg.rule_versions WHERE rule_code=p_code AND version=p_version FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF rule.status='published' THEN RETURN jsonb_build_object('schema_version',1,'rule_code',p_code,'version',p_version,'status','published','replayed',true); END IF;
  IF rule.status<>'simulated' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RULE_NEEDS_REVIEW'; END IF;
  SELECT * INTO source FROM private_isg.legal_sources WHERE source_id=rule.source_id FOR SHARE;
  IF source.needs_review THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RULE_NEEDS_REVIEW'; END IF;
  PERFORM 1 FROM private_isg.rule_simulations WHERE rule_code=p_code AND version=p_version FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RULE_NEEDS_REVIEW'; END IF;
  SELECT version INTO previous FROM private_isg.rule_versions WHERE rule_code=p_code AND status='published' FOR UPDATE;
  IF previous IS NOT NULL THEN
    UPDATE private_isg.rule_versions SET status='superseded' WHERE rule_code=p_code AND version=previous; END IF;
  UPDATE private_isg.rule_versions SET status='published',approved_by=p_approver,
    approval_note=private_isg.text_value(p_note,500),published_at=p_now WHERE rule_code=p_code AND version=p_version;
  RETURN jsonb_build_object('schema_version',1,'rule_code',p_code,'version',p_version,'status','published',
    'superseded_version',previous,'replayed',false);
END $$;
CREATE FUNCTION private_isg.decide_applicability(p_company uuid,p_workplace uuid,p_code text,p_on date,p_facts jsonb,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE rule private_isg.rule_versions; workplace private_isg.workplaces; verdict jsonb; decision uuid; existing uuid;
BEGIN
  PERFORM private_isg.rule_gate(true);
  IF p_company IS NULL OR p_workplace IS NULL OR p_code IS NULL OR p_on IS NULL OR NOT isfinite(p_on) OR
     p_facts IS NULL OR jsonb_typeof(p_facts)<>'object' OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO workplace FROM private_isg.workplaces WHERE company_id=p_company AND id=p_workplace FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO rule FROM private_isg.rule_versions WHERE rule_code=p_code AND status='published' FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RULE_NEEDS_REVIEW'; END IF;
  -- A Turkish rule is never applied to another jurisdiction by default.
  IF p_facts->>'jurisdiction' IS NULL THEN
    verdict:=jsonb_build_object('state','needs_review','reason','JURISDICTION_UNKNOWN','missing_facts',ARRAY['jurisdiction']);
  ELSIF p_facts->>'jurisdiction'<>rule.jurisdiction THEN
    verdict:=jsonb_build_object('state','not_required','reason','JURISDICTION_MISMATCH','missing_facts','{}'::text[]);
  ELSE verdict:=private_isg.evaluate_applicability(rule.applicability,p_facts); END IF;
  SELECT decision_id INTO existing FROM private_isg.applicability_decisions
    WHERE company_id=p_company AND workplace_id=p_workplace AND rule_code=p_code AND rule_version=rule.version
      AND context_version=workplace.context_version AND decided_on=p_on;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'decision_id',existing,'state',verdict->>'state',
    'reason',verdict->>'reason','rule_version',rule.version,'replayed',true); END IF;
  INSERT INTO private_isg.applicability_decisions(company_id,owner_id,workplace_id,rule_code,rule_version,
      context_version,decided_on,state,reason,missing_facts,facts,created_at)
    VALUES(p_company,workplace.owner_id,p_workplace,p_code,rule.version,workplace.context_version,p_on,
      verdict->>'state',verdict->>'reason',
      ARRAY(SELECT jsonb_array_elements_text(coalesce(verdict->'missing_facts','[]'::jsonb))),p_facts,p_now)
    RETURNING decision_id INTO decision;
  RETURN jsonb_build_object('schema_version',1,'decision_id',decision,'state',verdict->>'state',
    'reason',verdict->>'reason','rule_version',rule.version,'context_version',workplace.context_version,
    'missing_facts',verdict->'missing_facts','replayed',false);
END $$;
-- Only a 'required' decision opens an obligation, and only one per period.
CREATE FUNCTION private_isg.open_requirement(p_decision uuid,p_period_start date,p_timezone text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE decision private_isg.applicability_decisions; rule private_isg.rule_versions;
  requirement uuid; existing private_isg.requirement_instances; period text; due date;
BEGIN
  PERFORM private_isg.rule_gate(true);
  IF p_decision IS NULL OR p_period_start IS NULL OR NOT isfinite(p_period_start) OR p_timezone IS NULL OR p_now IS NULL OR
     NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name=p_timezone) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO decision FROM private_isg.applicability_decisions WHERE decision_id=p_decision FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF decision.state<>'required' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RULE_NEEDS_REVIEW'; END IF;
  SELECT * INTO rule FROM private_isg.rule_versions WHERE rule_code=decision.rule_code AND version=decision.rule_version FOR SHARE;
  period:=CASE WHEN rule.period_kind='once' THEN 'once' ELSE to_char(p_period_start,'YYYY-MM-DD') END;
  due:=private_isg.next_due_on(p_period_start,rule.period_kind,rule.period_length);
  SELECT * INTO existing FROM private_isg.requirement_instances WHERE company_id=decision.company_id AND
    workplace_id=decision.workplace_id AND rule_code=decision.rule_code AND action_kind=rule.action_kind AND period_key=period FOR UPDATE;
  IF FOUND THEN
    RETURN jsonb_build_object('schema_version',1,'requirement_id',existing.requirement_id,'period_key',period,
      'status',existing.status,'due_on',(SELECT due_on FROM private_isg.requirement_schedules
        WHERE requirement_id=existing.requirement_id AND state='active'),'replayed',true);
  END IF;
  INSERT INTO private_isg.requirement_instances(company_id,workplace_id,decision_id,rule_code,rule_version,
      action_kind,period_key,created_at,updated_at)
    VALUES(decision.company_id,decision.workplace_id,p_decision,decision.rule_code,decision.rule_version,
      rule.action_kind,period,p_now,p_now) RETURNING requirement_id INTO requirement;
  INSERT INTO private_isg.requirement_schedules(requirement_id,version,due_on,timezone,created_at,updated_at)
    VALUES(requirement,1,due,p_timezone,p_now,p_now);
  RETURN jsonb_build_object('schema_version',1,'requirement_id',requirement,'period_key',period,'status','open',
    'due_on',due,'schedule_version',1,'replayed',false);
END $$;
-- A superseded rule or a changed context invalidates the old schedule and
-- writes a new version; it never silently edits the previous due date.
CREATE FUNCTION private_isg.reschedule_requirement(p_requirement uuid,p_due date,p_timezone text,p_reason text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE active private_isg.requirement_schedules; next_version integer;
BEGIN
  PERFORM private_isg.rule_gate(true);
  IF p_requirement IS NULL OR p_due IS NULL OR NOT isfinite(p_due) OR p_timezone IS NULL OR p_now IS NULL OR
     p_reason IS NULL OR p_reason !~ '^[A-Z][A-Z_]{2,49}$' OR
     NOT EXISTS(SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name=p_timezone) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO active FROM private_isg.requirement_schedules WHERE requirement_id=p_requirement AND state='active' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF active.due_on=p_due AND active.timezone=p_timezone THEN
    RETURN jsonb_build_object('schema_version',1,'requirement_id',p_requirement,'schedule_version',active.version,
      'due_on',active.due_on,'replayed',true); END IF;
  UPDATE private_isg.requirement_schedules SET state='invalidated',invalidated_reason=p_reason,updated_at=p_now
    WHERE schedule_id=active.schedule_id;
  next_version:=active.version+1;
  INSERT INTO private_isg.requirement_schedules(requirement_id,version,due_on,timezone,created_at,updated_at)
    VALUES(p_requirement,next_version,p_due,p_timezone,p_now,p_now);
  RETURN jsonb_build_object('schema_version',1,'requirement_id',p_requirement,'schedule_version',next_version,
    'due_on',p_due,'invalidated_reason',p_reason,'replayed',false);
END $$;
CREATE FUNCTION private_isg.close_requirement(p_requirement uuid,p_status text,p_reason text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.requirement_instances;
BEGIN
  PERFORM private_isg.rule_gate(true);
  IF p_requirement IS NULL OR p_now IS NULL OR p_status IS NULL OR p_status NOT IN ('satisfied','cancelled','superseded') OR
     (p_status='satisfied')<>(p_reason IS NULL) OR
     (p_reason IS NOT NULL AND p_reason !~ '^[A-Z][A-Z_]{2,49}$') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.requirement_instances WHERE requirement_id=p_requirement FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.status=p_status THEN RETURN jsonb_build_object('schema_version',1,'requirement_id',p_requirement,'status',p_status,'replayed',true); END IF;
  IF entry.status<>'open' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  UPDATE private_isg.requirement_instances SET status=p_status,closed_reason=p_reason,updated_at=p_now WHERE requirement_id=p_requirement;
  UPDATE private_isg.requirement_schedules SET state=CASE WHEN p_status='satisfied' THEN 'completed' ELSE 'invalidated' END,
    invalidated_reason=CASE WHEN p_status='satisfied' THEN NULL ELSE p_reason END,updated_at=p_now
    WHERE requirement_id=p_requirement AND state='active';
  RETURN jsonb_build_object('schema_version',1,'requirement_id',p_requirement,'status',p_status,'replayed',false);
END $$;
CREATE FUNCTION private_isg.reconcile_rules(p_on date,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE report jsonb;
BEGIN
  PERFORM private_isg.rule_gate(true);
  IF p_on IS NULL OR NOT isfinite(p_on) OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT jsonb_build_object('schema_version',1,'ran_on',p_on,
    'published_rules',(SELECT count(*) FROM private_isg.rule_versions WHERE status='published'),
    'sources_in_review',(SELECT count(*) FROM private_isg.legal_sources WHERE needs_review),
    'decisions',(SELECT count(*) FROM private_isg.applicability_decisions),
    'decisions_in_review',(SELECT count(*) FROM private_isg.applicability_decisions WHERE state='needs_review'),
    'open_requirements',(SELECT count(*) FROM private_isg.requirement_instances WHERE status='open'),
    'overdue_requirements',(SELECT count(*) FROM private_isg.requirement_instances r
        JOIN private_isg.requirement_schedules s ON s.requirement_id=r.requirement_id AND s.state='active'
        WHERE r.status='open' AND s.due_on<p_on),
    'required_without_requirement',(SELECT count(*) FROM private_isg.applicability_decisions d
        WHERE d.state='required' AND NOT EXISTS(SELECT 1 FROM private_isg.requirement_instances r WHERE r.decision_id=d.decision_id)),
    'requirements_on_superseded_rules',(SELECT count(*) FROM private_isg.requirement_instances r
        JOIN private_isg.rule_versions v ON v.rule_code=r.rule_code AND v.version=r.rule_version
        WHERE r.status='open' AND v.status='superseded'),
    'requirements_without_active_schedule',(SELECT count(*) FROM private_isg.requirement_instances r
        WHERE r.status='open' AND NOT EXISTS(SELECT 1 FROM private_isg.requirement_schedules s
          WHERE s.requirement_id=r.requirement_id AND s.state='active'))) INTO report;
  INSERT INTO private_isg.rule_reconciliations(ran_on,report,created_at) VALUES(p_on,report,p_now)
    ON CONFLICT(ran_on) DO UPDATE SET report=excluded.report,created_at=excluded.created_at;
  RETURN report;
END $$;
REVOKE ALL ON FUNCTION private_isg.rule_gate(boolean),private_isg.validate_rule_expression(jsonb),
  private_isg.evaluate_applicability(jsonb,jsonb),private_isg.next_due_on(date,text,integer),
  private_isg.register_legal_source(text,text,text,bytea,timestamptz,date,date,uuid,text,timestamptz),
  private_isg.add_rule_version(text,uuid,jsonb,text,text,integer,timestamptz),
  private_isg.simulate_rule_version(text,integer,jsonb,timestamptz),
  private_isg.publish_rule_version(text,integer,uuid,text,timestamptz),
  private_isg.decide_applicability(uuid,uuid,text,date,jsonb,timestamptz),
  private_isg.open_requirement(uuid,date,text,timestamptz),
  private_isg.reschedule_requirement(uuid,date,text,text,timestamptz),
  private_isg.close_requirement(uuid,text,text,timestamptz),
  private_isg.reconcile_rules(date,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
