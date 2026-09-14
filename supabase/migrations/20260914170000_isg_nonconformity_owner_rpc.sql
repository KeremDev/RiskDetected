-- P09 client boundary: the owner checked entry, the mutation receipt and the two
-- public wrappers the NOVA nonconformity screens call.
-- Additive. The rollout row is NOT opened here: switching a feature on stays a
-- separate, human decision, exactly as it is for personnel.
-- public.findings and public.analyses are never written; a finding is referenced
-- by source_ref and keeps living where it already lives.
BEGIN;
SET LOCAL lock_timeout='5s';

-- Same shape as personnel_receipts: one row per actor and mutation, so a retry
-- with the same key returns the first answer instead of opening a second record.
CREATE TABLE private_isg.nonconformity_receipts (
  actor_id uuid NOT NULL, mutation_id uuid NOT NULL, company_id uuid NOT NULL,
  operation_id uuid NOT NULL, request_hash bytea NOT NULL, response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(actor_id,mutation_id),
  FOREIGN KEY(company_id,actor_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
-- The foreign key is composite, so the covering index has to be composite too.
CREATE INDEX nonconformity_receipt_company_idx ON private_isg.nonconformity_receipts(company_id,actor_id);
ALTER TABLE private_isg.nonconformity_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

-- The legacy risk band and the nonconformity severity share four names. The
-- fifth legacy value is 'unknown', and it has no honest target here: an
-- unreadable band must reach a person, not quietly become the lowest severity.
CREATE FUNCTION private_isg.severity_for_risk_band(p_band text) RETURNS text
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
BEGIN
  IF p_band IS NULL OR p_band='unknown' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SEVERITY_UNKNOWN'; END IF;
  IF p_band NOT IN ('low','medium','high','critical') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  RETURN p_band;
END $$;

-- Session, subscription and company ownership, checked on this feature's switch.
CREATE FUNCTION private_isg.require_nonconformity_company(p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  PERFORM 1 FROM private_isg.rollout WHERE feature='nonconformity' AND read_enabled AND (NOT p_write OR write_enabled) FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
  IF p_write THEN
    PERFORM 1 FROM public.user_subscriptions WHERE user_id=actor AND tier IN ('plus','pro') AND
      status IN ('active','trialing','grace_period') AND
      (current_period_ends_at IS NULL OR current_period_ends_at>clock_timestamp()) FOR SHARE;
    IF NOT FOUND OR private.user_plan_tier(actor) NOT IN ('plus','pro') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAID_PLAN_REQUIRED'; END IF;
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor AND NOT is_archived FOR UPDATE;
  ELSE
    PERFORM 1 FROM public.companies WHERE id=p_company AND user_id=actor FOR SHARE;
  END IF;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  RETURN actor;
END $$;

CREATE FUNCTION private_isg.nonconformity_row(p_company uuid,p_nonconformity uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.nonconformities;
BEGIN
  SELECT * INTO entry FROM private_isg.nonconformities
    WHERE nonconformity_id=p_nonconformity AND company_id=p_company;
  IF NOT FOUND THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('id',entry.nonconformity_id,'workplace_id',entry.workplace_id,
    'source_kind',entry.source_kind,'source_ref',entry.source_ref,'title',entry.title,
    'severity',entry.severity,'state',entry.state,'version',entry.version,
    'opened_on',entry.opened_on,'due_on',entry.due_on,'closed_on',entry.closed_on,
    'assignee_contact',entry.assignee_contact,
    'actions',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',a.action_id,'description',a.description,
        'assignee',a.assignee_contact,'due_on',a.due_on,'state',a.state) ORDER BY a.created_at),'[]'::jsonb)
      FROM private_isg.nonconformity_actions a WHERE a.nonconformity_id=entry.nonconformity_id),
    'verifications',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',v.verification_id,'outcome',v.outcome,
        'verified_on',v.verified_on) ORDER BY v.verified_on),'[]'::jsonb)
      FROM private_isg.verification_records v WHERE v.nonconformity_id=entry.nonconformity_id),
    'legacy_finding_written',false);
END $$;

CREATE FUNCTION private_isg.read_nonconformities(p_company uuid,p_kind text,p_query text,p_state text,
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
      'source_kind',n.source_kind,'source_ref',n.source_ref) AS entry
    FROM private_isg.nonconformities n
    WHERE n.company_id=p_company AND n.owner_id=actor
      AND (p_state IS NULL OR n.state=p_state)
      AND (needle IS NULL OR n.title ILIKE '%'||needle||'%')
      AND (p_after IS NULL OR n.nonconformity_id<>p_after)
    ORDER BY n.opened_on DESC,n.nonconformity_id LIMIT 200) page;
  RETURN jsonb_build_object('schema_version',1,'kind','list','rows',rows,'legacy_findings_written',false);
END $$;

-- The two checked entries are the client RPC boundary and therefore DEFINER, the
-- same as the personnel pair: they run their own session, subscription and owner
-- checks first and call the private helpers afterwards.
-- One entry point for every write. The payload keys are allowlisted per action,
-- so a client cannot smuggle a field the server never agreed to read.
CREATE FUNCTION private_isg.mutate_nonconformity(p_company uuid,p_action text,p_operation uuid,p_mutation uuid,
  p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.nonconformity_receipts;
  result jsonb; resolved_severity text; target uuid; stamp timestamptz:=clock_timestamp();
BEGIN
  actor:=private_isg.require_nonconformity_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>4096 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  allowed:=CASE p_action
    WHEN 'open_manual' THEN ARRAY['workplace_id','title','severity','opened_on','due_on','assignee']
    WHEN 'open_from_finding' THEN ARRAY['workplace_id','title','risk_band','severity','finding_id','opened_on','due_on']
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

  IF p_action IN ('open_manual','open_from_finding') THEN
    -- An explicitly chosen severity wins; otherwise the legacy band maps across,
    -- and an unreadable band refuses instead of guessing the lowest one.
    resolved_severity:=CASE WHEN p_payload ? 'severity' THEN p_payload->>'severity'
      ELSE private_isg.severity_for_risk_band(p_payload->>'risk_band') END;
    result:=private_isg.open_nonconformity(p_company,(p_payload->>'workplace_id')::uuid,
      CASE WHEN p_action='open_manual' THEN 'manual' ELSE 'legacy_finding' END,
      CASE WHEN p_action='open_manual' THEN NULL ELSE p_payload->>'finding_id' END,
      p_payload->>'title',resolved_severity,
      coalesce((p_payload->>'opened_on')::date,(stamp AT TIME ZONE 'UTC')::date),
      (p_payload->>'due_on')::date,stamp);
    target:=(result->>'nonconformity_id')::uuid;
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

-- Exposed wrappers stay INVOKER; only the two checked entry points get a grant.
CREATE FUNCTION public.isg_nonconformity_read_v1(p_company uuid,p_kind text,p_query text,p_state text,
  p_after uuid,p_id uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.read_nonconformities(p_company,p_kind,p_query,p_state,p_after,p_id)
$$;
CREATE FUNCTION public.isg_nonconformity_mutate_v1(p_company uuid,p_action text,p_operation uuid,p_mutation uuid,
  p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.mutate_nonconformity(p_company,p_action,p_operation,p_mutation,p_payload)
$$;
REVOKE ALL ON FUNCTION private_isg.severity_for_risk_band(text),
  private_isg.require_nonconformity_company(uuid,boolean),
  private_isg.nonconformity_row(uuid,uuid),
  private_isg.read_nonconformities(uuid,text,text,text,uuid,uuid),
  private_isg.mutate_nonconformity(uuid,text,uuid,uuid,jsonb),
  public.isg_nonconformity_read_v1(uuid,text,text,text,uuid,uuid),
  public.isg_nonconformity_mutate_v1(uuid,text,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.read_nonconformities(uuid,text,text,text,uuid,uuid),
  private_isg.mutate_nonconformity(uuid,text,uuid,uuid,jsonb),
  public.isg_nonconformity_read_v1(uuid,text,text,text,uuid,uuid),
  public.isg_nonconformity_mutate_v1(uuid,text,uuid,uuid,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
