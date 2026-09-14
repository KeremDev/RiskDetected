-- P09 second slice: the fields an expert actually fills in by hand — hazard
-- description, control measure, legislation reference, the responsible person
-- and a risk score — plus the record kind that separates an improvement
-- suggestion from a nonconformity.
-- Additive. The rollout row is NOT opened here. public.findings and
-- public.analyses stay unwritten: an expert-opinion item is referenced by
-- source_ref exactly the way a scored finding already is.
BEGIN;
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
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;
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
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
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
      coalesce((p_payload->>'opened_on')::date,(stamp AT TIME ZONE 'UTC')::date),
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
      coalesce((p_payload->>'verified_on')::date,(stamp AT TIME ZONE 'UTC')::date),NULL,p_payload->>'note',stamp);
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
COMMIT;
