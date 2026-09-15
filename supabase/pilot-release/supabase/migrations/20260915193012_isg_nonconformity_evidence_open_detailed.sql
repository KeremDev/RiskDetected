-- Elle Uygunsuzluk's own screen (NovaManualNonconformityScreen) files through
-- action 'open_detailed', not 'open_manual' — it needs the description/
-- control_measure/risk_method keys only 'open_detailed' carries. The evidence
-- attach landed scoped to 'open_manual' only in the prior migration, which
-- would have made the client's evidence_asset_ids payload a silent
-- PAYLOAD_NOT_ALLOWED on the screen that actually sends it. Widens both the
-- allowlist and the write condition to include 'open_detailed'.

CREATE OR REPLACE FUNCTION private_isg.mutate_nonconformity(p_company uuid, p_action text, p_operation uuid, p_mutation uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.nonconformity_receipts;
  result jsonb; detail jsonb; resolved_severity text; resolved_kind text; target uuid;
  stamp timestamptz:=clock_timestamp();
BEGIN
  actor:=private_isg.require_nonconformity_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>8192 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  allowed:=CASE p_action
    WHEN 'open_manual' THEN ARRAY['workplace_id','title','severity','opened_on','due_on','assignee','evidence_asset_ids']
    WHEN 'open_from_finding' THEN ARRAY['workplace_id','title','risk_band','severity','finding_id','opened_on','due_on']
    -- An expert-opinion item arrives unscored. There is deliberately no
    -- 'risk_band' key here: nothing can be mapped from a score that does not exist.
    WHEN 'open_from_expert_item' THEN ARRAY['workplace_id','title','severity','record_kind','item_id',
      'opened_on','due_on','assignee','description']
    WHEN 'open_detailed' THEN ARRAY['workplace_id','title','severity','record_kind','opened_on','due_on','assignee',
      'description','control_measure','legislation_ref','responsible_contact','risk_method',
      'fk_probability','fk_frequency','fk_severity','m5_probability','m5_severity','evidence_asset_ids']
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
    -- Only clean, owned assets may be attached — the same rule every other
    -- module's asset_id enforces. A replay must not silently re-attach a
    -- different set than what was actually cleared the first time.
    IF (result->>'replayed')::boolean IS NOT TRUE AND p_action IN ('open_manual','open_detailed')
       AND p_payload ? 'evidence_asset_ids' AND jsonb_array_length(p_payload->'evidence_asset_ids')>0 THEN
      IF jsonb_array_length(p_payload->'evidence_asset_ids')>3 THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      IF EXISTS(SELECT 1 FROM jsonb_array_elements_text(p_payload->'evidence_asset_ids') a
          WHERE NOT EXISTS(SELECT 1 FROM private_isg.file_assets fa
            JOIN private_isg.file_library_entries fle ON fle.asset_id=fa.asset_id
            WHERE fa.asset_id=a::uuid AND fa.scan_status='clean'
              AND fle.company_id=p_company AND fle.owner_id=actor)) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      UPDATE private_isg.nonconformities SET evidence_asset_ids=
          (SELECT array_agg(a::uuid) FROM jsonb_array_elements_text(p_payload->'evidence_asset_ids') a)
        WHERE nonconformity_id=target;
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
END $function$;
