-- Wires the file-attach path the core function already had a column and a
-- validated parameter for, but which was deliberately blocked
-- (FILE_STORAGE_UNAVAILABLE) before file storage existed at all. It exists
-- now (20260915260000_isg_pilot_file_storage_core_and_library.sql, applied
-- just before this).
--
-- Based on the CONFIRMED LIVE bodies of these three functions (read via
-- pg_get_functiondef on the live database before writing this — the live
-- publish_emergency_plan turned out to be the "always reject" body from
-- 20260914204842_isg_pilot_operational_modules.sql, not the "validate clean
-- asset" one from 20260913230000_isg_module_core.sql that this migration's
-- own first draft was wrongly based on off the migrations folder alone, and
-- was discarded before ever being applied). All three keep their exact
-- signature — CREATE OR REPLACE, no rename, no new RPC version.
CREATE OR REPLACE FUNCTION private_isg.publish_emergency_plan(p_company uuid,p_workplace uuid,p_plan uuid,p_scope text,
  p_prepared_on date,p_valid_until date,p_team jsonb,p_asset uuid,p_review_note text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE owner uuid; plan uuid; next_version integer; review boolean; previous integer;
BEGIN
  owner:=private_isg.module_scope('emergency_plan',p_company,p_workplace,true);
  IF p_scope IS NULL OR p_prepared_on IS NULL OR NOT isfinite(p_prepared_on) OR p_now IS NULL OR
     p_team IS NULL OR jsonb_typeof(p_team)<>'array' OR jsonb_array_length(p_team) NOT BETWEEN 1 AND 200 OR
     (p_valid_until IS NOT NULL AND p_valid_until<=p_prepared_on) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  -- Only a clean, promoted asset may be attached — the same check the core
  -- always carried the shape for; only the caller could never reach it.
  IF p_asset IS NOT NULL THEN
    PERFORM 1 FROM private_isg.file_assets WHERE asset_id=p_asset AND scan_status='clean' FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  -- An unverified legal basis stays in review; it is never silently accepted.
  review:=p_review_note IS NULL;
  plan:=coalesce(p_plan,gen_random_uuid());
  SELECT coalesce(max(version),0) INTO previous FROM private_isg.emergency_plan_versions WHERE plan_id=plan;
  IF p_plan IS NOT NULL AND previous=0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  next_version:=previous+1;
  -- Renewing supersedes the pointer only. The previous row keeps its own scope,
  -- team snapshot, dates and file.
  UPDATE private_isg.emergency_plan_versions SET state='superseded' WHERE plan_id=plan AND state='active';
  INSERT INTO private_isg.emergency_plan_versions(plan_id,version,company_id,owner_id,workplace_id,scope,prepared_on,
      valid_until,team_snapshot,asset_id,needs_review,review_note,created_at)
    VALUES(plan,next_version,p_company,owner,p_workplace,private_isg.text_value(p_scope,300),p_prepared_on,
      p_valid_until,p_team,p_asset,review,p_review_note,p_now);
  RETURN jsonb_build_object('schema_version',1,'plan_id',plan,'version',next_version,'state','active',
    'needs_review',review,'previous_version',nullif(previous,0));
END $$;

-- emergency_plan_row gains a resolved download location for the active
-- version's own asset (when one is attached) — the plan is where the file
-- is found now, not a separate note about where the original supposedly is.
CREATE OR REPLACE FUNCTION private_isg.emergency_plan_row(p_plan uuid,p_today date,p_history boolean) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE active private_isg.emergency_plan_versions;
  notice integer:=private_isg.emergency_notice_days(); shown_state text; total integer;
BEGIN
  SELECT * INTO active FROM private_isg.emergency_plan_versions
    WHERE plan_id=p_plan AND state='active';
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT count(*) INTO total FROM private_isg.emergency_plan_versions WHERE plan_id=p_plan;
  shown_state:=private_isg.emergency_plan_status(active.valid_until,true,notice,p_today);
  RETURN jsonb_build_object(
    'id',active.plan_id,'company_id',active.company_id,'workplace_id',active.workplace_id,
    'version',active.version,'versions_total',total,
    'scope',active.scope,'prepared_on',active.prepared_on,'valid_until',active.valid_until,
    'created_at',active.created_at,
    'state',shown_state,'state_group',private_isg.emergency_plan_group(shown_state),
    'state_authority','computed_at_read','notice_days',notice,
    'needs_review',active.needs_review,'review_note',active.review_note,
    'period_source','expert','period_needs_review',true,
    'team',active.team_snapshot,'team_size',jsonb_array_length(active.team_snapshot),
    'asset_id',active.asset_id,
    'asset_download',(SELECT jsonb_build_object('bucket',bucket,'path',immutable_path)
      FROM private_isg.file_assets WHERE asset_id=active.asset_id),
    'versions',CASE WHEN p_history THEN
      (SELECT coalesce(jsonb_agg(jsonb_build_object('version',v.version,'state',v.state,
          'scope',v.scope,'prepared_on',v.prepared_on,'valid_until',v.valid_until,
          'needs_review',v.needs_review,'review_note',v.review_note,
          'team',v.team_snapshot,'team_size',jsonb_array_length(v.team_snapshot),
          'asset_id',v.asset_id,'created_at',v.created_at)
          ORDER BY v.version DESC),'[]'::jsonb)
       FROM private_isg.emergency_plan_versions v WHERE v.plan_id=p_plan) END,
    'compliance_verdict',NULL,'health_records_tracked',false);
END $$;

-- mutate_emergency_plans: publish_plan now accepts an `asset_id` payload key
-- (validated by publish_emergency_plan itself, unchanged just above) and
-- actually passes it through instead of the hardcoded NULL every prior call
-- sent, and validates the asset belongs to this same account's own filed
-- library entry before trusting it (an extra check beyond what the core
-- alone does, since the core only checks scan_status, not ownership scope).
CREATE OR REPLACE FUNCTION private_isg.mutate_emergency_plans(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.emergency_plan_receipts;
  result jsonb; answer jsonb; plan uuid; team jsonb; asset uuid;
  stamp timestamptz:=clock_timestamp(); today date;
BEGIN
  actor:=private_isg.require_emergency_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>16384 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(stamp AT TIME ZONE 'UTC')::date;
  allowed:=CASE p_action
    WHEN 'publish_plan' THEN ARRAY['plan_id','workplace_id','scope','prepared_on','valid_until',
      'team','review_note','asset_id']
    ELSE NULL END;
  IF allowed IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO offending FROM jsonb_object_keys(p_payload) AS keys(key)
    WHERE NOT (key=ANY(allowed)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;

  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-emergency:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.emergency_plan_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN prior.response||jsonb_build_object('replayed',true);
  END IF;

  IF p_payload->>'workplace_id' IS NULL OR p_payload->>'scope' IS NULL OR
     p_payload->>'prepared_on' IS NULL OR NOT p_payload ? 'team' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  PERFORM 1 FROM private_isg.workplaces WHERE company_id=p_company
    AND id=(p_payload->>'workplace_id')::uuid AND owner_id=actor AND NOT is_archived;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF p_payload->>'plan_id' IS NOT NULL THEN
    plan:=(p_payload->>'plan_id')::uuid;
    PERFORM 1 FROM private_isg.emergency_plan_versions
      WHERE plan_id=plan AND company_id=p_company AND owner_id=actor FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  IF (p_payload->>'prepared_on')::date>today THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PREPARED_IN_THE_FUTURE'; END IF;
  IF p_payload->>'asset_id' IS NOT NULL THEN
    asset:=(p_payload->>'asset_id')::uuid;
    PERFORM 1 FROM private_isg.file_library_entries WHERE asset_id=asset AND company_id=p_company AND owner_id=actor FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  team:=private_isg.emergency_team_snapshot(p_payload->'team');
  answer:=private_isg.publish_emergency_plan(p_company,(p_payload->>'workplace_id')::uuid,plan,
    p_payload->>'scope',(p_payload->>'prepared_on')::date,(p_payload->>'valid_until')::date,
    team,asset,nullif(btrim(coalesce(p_payload->>'review_note','')),''),stamp);
  plan:=(answer->>'plan_id')::uuid;

  result:=jsonb_build_object('schema_version',1,'action',p_action,'plan_id',plan,'answer',answer,
    'row',private_isg.emergency_plan_row(plan,today,true));
  INSERT INTO private_isg.emergency_plan_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $$;
