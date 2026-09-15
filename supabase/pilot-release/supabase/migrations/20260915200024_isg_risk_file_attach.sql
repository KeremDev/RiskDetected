-- Risk Analizi's own "PILOT DIVERGENCE": draft_risk_version has carried a
-- real file_asset_id column since the assessment tables were first built
-- (already exposed on read — risk_assessment_row's current_file_asset_id and
-- each version's file_asset_id), but the write path unconditionally refused
-- any asset with FILE_STORAGE_UNAVAILABLE, from before file storage existed.
-- 'risk_assessment' is already an allowed file_library_categories value.
-- Wires it the same way the other four modules' asset attach did this
-- session: the clean-and-owned check now lives in mutate_risk_versions
-- (which already has actor/company in scope), and draft_risk_version simply
-- accepts the asset id once validated.

CREATE OR REPLACE FUNCTION private_isg.draft_risk_version(p_assessment uuid, p_kind text, p_assessment_on date, p_revision_on date, p_scope jsonb, p_reason text, p_asset uuid, p_expected_current integer, p_now timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
  PERFORM 1 FROM private_isg.risk_assessment_versions WHERE assessment_id=p_assessment AND state='draft' FOR UPDATE;
  IF FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DRAFT_ALREADY_OPEN'; END IF;
  SELECT coalesce(max(version),0)+1 INTO next_version FROM private_isg.risk_assessment_versions WHERE assessment_id=p_assessment;
  INSERT INTO private_isg.risk_assessment_versions(assessment_id,version,kind,previous_version,assessment_on,
      revision_on,scope,reason,file_asset_id,date_needs_review,created_at,updated_at)
    VALUES(p_assessment,next_version,p_kind,CASE WHEN p_kind='full' THEN NULL ELSE entry.current_version END,
      effective,p_revision_on,p_scope,p_reason,p_asset,review,p_now,p_now);
  RETURN jsonb_build_object('schema_version',1,'assessment_id',p_assessment,'version',next_version,'kind',p_kind,
    'assessment_on',effective,'state','draft','date_needs_review',review);
END $function$;

CREATE OR REPLACE FUNCTION private_isg.mutate_risk_versions(p_company uuid, p_action text, p_operation uuid, p_mutation uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      -- Only clean, owned assets may be attached — the same rule every other
      -- module's asset_id enforces.
      IF p_payload->>'file_asset_id' IS NOT NULL THEN
        PERFORM 1 FROM private_isg.file_assets fa JOIN private_isg.file_library_entries fle ON fle.asset_id=fa.asset_id
          WHERE fa.asset_id=(p_payload->>'file_asset_id')::uuid AND fa.scan_status='clean'
            AND fle.company_id=p_company AND fle.owner_id=actor;
        IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      END IF;
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
END $function$;
