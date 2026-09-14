ALTER TABLE private_isg.risk_assessment_versions DROP CONSTRAINT risk_assessment_versions_check1;
ALTER TABLE private_isg.risk_assessment_versions ADD CONSTRAINT risk_assessment_versions_check1 CHECK(state IN ('draft','cancelled') OR verified_by IS NOT NULL);
ALTER TABLE private_isg.risk_assessment_versions DROP CONSTRAINT risk_assessment_versions_state_check;
ALTER TABLE private_isg.risk_assessment_versions ADD CONSTRAINT risk_assessment_versions_state_check CHECK(state IN('draft','final','superseded','cancelled'));
ALTER TABLE private_isg.risk_assessment_versions ADD COLUMN edit_revision integer NOT NULL DEFAULT 0 CHECK(edit_revision>=0), ADD COLUMN cancellation_note text;
CREATE TABLE private_isg.risk_draft_history (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), assessment_id uuid NOT NULL, version integer NOT NULL,
 actor_id uuid NOT NULL REFERENCES auth.users(id), action text NOT NULL CHECK(action IN('edit_draft','cancel_draft')),
 before_snapshot jsonb NOT NULL, changed_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(assessment_id,version) REFERENCES private_isg.risk_assessment_versions(assessment_id,version)
);
ALTER TABLE private_isg.risk_draft_history ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.risk_draft_history FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private_isg.manage_risk_draft(p_company uuid,p_action text,p_operation uuid,p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.require_risk_company(p_company,true); a private_isg.risk_assessments; v private_isg.risk_assessment_versions;
 hash_ bytea; prior private_isg.risk_version_receipts; result jsonb; day_ date; revised date; scope_ jsonb; reason_ text; today date:=(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date;
BEGIN
 IF p_operation IS NULL OR p_mutation IS NULL OR p_action NOT IN('edit_draft','cancel_draft') OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object' OR octet_length(p_payload::text)>8192 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN('assessment_id','version','expected_current','expected_edit_revision','assessment_on','revision_on','scope','reason','cancellation_note')) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
 hash_:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
 PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-risk:'||p_mutation::text,0));
 SELECT * INTO prior FROM private_isg.risk_version_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
 IF FOUND THEN IF prior.request_hash IS DISTINCT FROM hash_ THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF; RETURN prior.response; END IF;
 SELECT * INTO a FROM private_isg.risk_assessments WHERE assessment_id=(p_payload->>'assessment_id')::uuid AND company_id=p_company AND owner_id=actor FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 SELECT * INTO v FROM private_isg.risk_assessment_versions WHERE assessment_id=a.assessment_id AND version=(p_payload->>'version')::integer FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 IF v.state<>'draft' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_FINALIZED'; END IF;
 IF a.current_version IS DISTINCT FROM (p_payload->>'expected_current')::integer OR v.edit_revision IS DISTINCT FROM (p_payload->>'expected_edit_revision')::integer THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
 IF p_action='cancel_draft' THEN
  reason_:=btrim(p_payload->>'cancellation_note');
  IF reason_ IS NULL OR length(reason_) NOT BETWEEN 10 AND 2000 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  UPDATE private_isg.risk_assessment_versions SET state='cancelled',cancellation_note=reason_,edit_revision=edit_revision+1,updated_at=clock_timestamp() WHERE assessment_id=v.assessment_id AND version=v.version;
 ELSE
  day_:=CASE WHEN v.kind='full' THEN (p_payload->>'assessment_on')::date ELSE v.assessment_on END;
  IF day_ IS NULL OR NOT isfinite(day_) OR day_>today THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSESSMENT_DATE_IN_FUTURE'; END IF;
  IF v.kind<>'full' AND p_payload->>'assessment_on' IS NOT NULL AND (p_payload->>'assessment_on')::date<>v.assessment_on THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSESSMENT_DATE_IMMUTABLE'; END IF;
  revised:=(p_payload->>'revision_on')::date; scope_:=p_payload->'scope'; reason_:=nullif(btrim(p_payload->>'reason'),'');
  IF revised IS NOT NULL AND (NOT isfinite(revised) OR revised<day_ OR revised>today) OR (v.kind='partial' AND (jsonb_typeof(scope_) IS DISTINCT FROM 'array' OR jsonb_array_length(scope_) NOT BETWEEN 1 AND 50)) OR (v.kind<>'partial' AND scope_ IS NOT NULL AND scope_<>'null'::jsonb) OR (v.kind<>'full' AND (reason_ IS NULL OR length(reason_)<10)) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  UPDATE private_isg.risk_assessment_versions SET assessment_on=day_,revision_on=revised,scope=CASE WHEN v.kind='partial' THEN scope_ END,reason=reason_,date_needs_review=day_<today-3650,edit_revision=edit_revision+1,updated_at=clock_timestamp() WHERE assessment_id=v.assessment_id AND version=v.version;
 END IF;
 INSERT INTO private_isg.risk_draft_history(assessment_id,version,actor_id,action,before_snapshot) VALUES(v.assessment_id,v.version,actor,p_action,to_jsonb(v));
 result:=jsonb_build_object('schema_version',1,'assessment_id',a.assessment_id,'row',private_isg.risk_assessment_row(a.assessment_id,today,true));
 INSERT INTO private_isg.risk_version_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response) VALUES(actor,p_mutation,p_company,p_operation,hash_,result);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION private_isg.manage_risk_draft(uuid,text,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.manage_risk_draft(uuid,text,uuid,uuid,jsonb) TO authenticated;
CREATE OR REPLACE FUNCTION public.isg_risk_versions_mutate_v1(p_company uuid,p_action text,p_operation uuid,p_mutation uuid,p_payload jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
 SELECT CASE WHEN p_action IN('edit_draft','cancel_draft') THEN private_isg.manage_risk_draft(p_company,p_action,p_operation,p_mutation,p_payload) ELSE private_isg.mutate_risk_versions(p_company,p_action,p_operation,p_mutation,p_payload) END
$$;
CREATE OR REPLACE FUNCTION private_isg.risk_assessment_row(p_assessment uuid,p_today date,p_history boolean) RETURNS jsonb
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
      (SELECT coalesce(jsonb_agg(jsonb_build_object('version',v.version,'edit_revision',v.edit_revision,'cancellation_note',v.cancellation_note,'kind',v.kind,
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
CREATE OR REPLACE FUNCTION private_isg.mutate_risk_versions(p_company uuid,p_action text,p_operation uuid,
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
    WHEN 'finalize_version' THEN ARRAY['expected_edit_revision','assessment_id','version','expected_current','rule_code','period_years']
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
      IF coalesce((p_payload->>'expected_edit_revision')::integer,0) IS DISTINCT FROM (SELECT edit_revision FROM private_isg.risk_assessment_versions WHERE assessment_id=target AND version=(p_payload->>'version')::integer) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
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


NOTIFY pgrst,'reload schema';
