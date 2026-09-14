-- P10 client slice: the surface behind "KKD Zimmetleri".
-- Additive. No rollout row is added and none is opened: this rides on the
-- `modules` feature and the `ppe` module switch P10 already created.
--
-- The P10 core built the handover, the return and the two rules that matter:
-- nothing comes back before it went out, and no more comes back than went out.
-- Three things were missing rather than merely unreachable:
--
--   1. No client boundary, and no ownership check. `record_ppe_handover`
--      proves the employee belongs to the company, never that the company
--      belongs to the caller; `record_ppe_return` took a handover id and
--      trusted it entirely.
--   2. Nothing could take back a mistaken return. A return entered by accident
--      would misreport what a person is still holding, for good.
--   3. `signed_copy` demands a stored file, and there is no client path to
--      one, so the flag could only ever have been refused. What an expert
--      actually has is a signed form in a folder somewhere, and there was
--      nowhere to say where.
--
-- Five things this slice makes structurally impossible:
--   1. Another owner's handover or employee cannot be reached, and a return
--      cannot be filed against a handover outside the caller's company.
--   2. More cannot come back than went out, and nothing comes back before it
--      went out. Both rules stay in the core function; the boundary only
--      reaches it after proving who is asking.
--   3. The product never claims to hold a signed form. `signed_copy` is on no
--      allowlist, so it can only ever be false, and every read says the file
--      is not stored here — what is kept is the expert's own note of where it
--      is.
--   4. What a person is still holding is counted at read time from the returns
--      themselves, never stored. Removing a mistaken return corrects it at
--      once, with no field to fix by hand.
--   5. A handover dated tomorrow is refused: nothing was handed over on a day
--      that has not happened.
BEGIN;
SET LOCAL lock_timeout='5s';

-- Where the signed form is kept. The tracker holds a reference, never the
-- file, exactly as the document tracker does.
ALTER TABLE private_isg.ppe_handovers
  ADD COLUMN signed_copy_location text
    CHECK(signed_copy_location IS NULL OR length(signed_copy_location)<=300);

CREATE TABLE private_isg.ppe_receipts (
  actor_id uuid NOT NULL, mutation_id uuid NOT NULL, company_id uuid NOT NULL,
  operation_id uuid NOT NULL, request_hash bytea NOT NULL, response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(actor_id,mutation_id),
  FOREIGN KEY(company_id,actor_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
CREATE INDEX ppe_receipt_company_idx ON private_isg.ppe_receipts(company_id,actor_id);
ALTER TABLE private_isg.ppe_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

-- What a handover says about itself. Three states, and each is its own
-- counter: there is no group layer here because nothing would be grouped.
CREATE FUNCTION private_isg.ppe_handover_status(p_handed numeric,p_returned numeric) RETURNS text
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
BEGIN
  IF coalesce(p_returned,0)<=0 THEN RETURN 'outstanding'; END IF;
  IF p_returned>=p_handed THEN RETURN 'closed'; END IF;
  RETURN 'partial';
END $$;

CREATE FUNCTION private_isg.ppe_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM private_isg.module_gate('ppe',p_write);
END $$;

CREATE FUNCTION private_isg.require_ppe_company(p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  PERFORM private_isg.ppe_gate(p_write);
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

-- The missing correction. A return entered by mistake is taken back; what the
-- person is still holding is recounted at the next read, because it was never
-- stored in the first place.
CREATE FUNCTION private_isg.remove_ppe_return(p_handover uuid,p_return uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.ppe_handovers; removed integer; returned numeric;
BEGIN
  PERFORM private_isg.module_gate('ppe',true);
  IF p_handover IS NULL OR p_return IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.ppe_handovers WHERE handover_id=p_handover FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  DELETE FROM private_isg.ppe_returns WHERE return_id=p_return AND handover_id=p_handover;
  GET DIAGNOSTICS removed=ROW_COUNT;
  IF removed=0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT coalesce(sum(quantity),0) INTO returned FROM private_isg.ppe_returns WHERE handover_id=p_handover;
  RETURN jsonb_build_object('schema_version',1,'handover_id',p_handover,'return_id',p_return,
    'returned_total',returned,'handed_quantity',entry.quantity,'outstanding',entry.quantity-returned);
END $$;

-- One handover with what came back against it. Nothing is stored: the
-- outstanding amount is counted from the returns at read time.
CREATE FUNCTION private_isg.ppe_handover_row(p_handover uuid,p_history boolean) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.ppe_handovers; person private_isg.employees;
  returned numeric; lost numeric; shown_state text;
BEGIN
  SELECT * INTO entry FROM private_isg.ppe_handovers WHERE handover_id=p_handover;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO person FROM private_isg.employees
    WHERE company_id=entry.company_id AND id=entry.employee_id;
  SELECT coalesce(sum(quantity),0),coalesce(sum(quantity) FILTER (WHERE condition='lost'),0)
    INTO returned,lost FROM private_isg.ppe_returns WHERE handover_id=p_handover;
  shown_state:=private_isg.ppe_handover_status(entry.quantity,returned);
  RETURN jsonb_build_object(
    'id',entry.handover_id,'company_id',entry.company_id,'employee_id',entry.employee_id,
    'employee_name',person.full_name,'employee_archived',coalesce(person.is_archived,false),
    'item',entry.item,'quantity',entry.quantity,'unit',entry.unit,'handed_on',entry.handed_on,
    'external_ref',entry.external_ref,'created_at',entry.created_at,
    'state',shown_state,'state_authority','computed_at_read',
    'returned_quantity',returned,'outstanding',entry.quantity-returned,'lost_quantity',lost,
    -- The product holds no file, so this can only ever be false. What is kept
    -- is the expert's own note of where the signed form is.
    'signed_copy',entry.signed_copy,'signed_copy_stored',false,
    'signed_copy_location',entry.signed_copy_location,
    'returns',CASE WHEN p_history THEN
      (SELECT coalesce(jsonb_agg(jsonb_build_object('id',r.return_id,'quantity',r.quantity,
          'returned_on',r.returned_on,'condition',r.condition,'note',r.note,'created_at',r.created_at)
          ORDER BY r.returned_on DESC,r.created_at DESC),'[]'::jsonb)
       FROM private_isg.ppe_returns r WHERE r.handover_id=p_handover) END,
    'compliance_verdict',NULL,'health_records_tracked',false);
END $$;

CREATE FUNCTION private_isg.read_ppe_handovers(p_company uuid,p_kind text,p_query text,p_state text,
  p_employee uuid,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; needle text; today date;
  page_limit integer; page_offset integer;
  tally_all jsonb; tally_companies jsonb; tally_rows jsonb; matching_rows integer;
BEGIN
  actor:=private_isg.require_ppe_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('catalog','list','detail') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(clock_timestamp() AT TIME ZONE 'UTC')::date;

  IF p_kind='catalog' THEN
    RETURN jsonb_build_object('schema_version',1,'kind','catalog',
      'employees',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',e.id,'full_name',e.full_name)
          ORDER BY e.full_name),'[]'::jsonb)
        FROM private_isg.employees e
        WHERE p_company IS NOT NULL AND e.company_id=p_company AND NOT e.is_archived),
      'units',jsonb_build_array('piece','pair','set','metre','litre'),
      'conditions',jsonb_build_array('reusable','worn','damaged','lost'),
      -- No equipment catalogue ships: naming a fixed list of protective
      -- equipment would read as a statement of what the law requires, and no
      -- such list has been approved. The expert names the item.
      'item_catalogue_offered',false,
      -- The product holds no signed form, on any handover.
      'signed_copy_storage_available',false,
      'health_records_tracked',false);
  END IF;

  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.ppe_handovers h
      JOIN public.companies c ON c.id=h.company_id AND c.user_id=actor
      WHERE h.handover_id=p_id AND (p_company IS NULL OR h.company_id=p_company);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'kind','detail','today',today,
      'row',private_isg.ppe_handover_row(p_id,true));
  END IF;

  IF p_state IS NOT NULL AND p_state NOT IN ('outstanding','partial','closed') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  page_limit:=least(greatest(coalesce(p_limit,10),1),100);
  page_offset:=greatest(coalesce(p_offset,0),0);
  needle:=nullif(btrim(coalesce(p_query,'')),'');

  WITH scope AS (
    SELECT c.id,c.name FROM public.companies c WHERE c.user_id=actor AND NOT c.is_archived
  ), page AS (
    SELECT h.handover_id,h.company_id,s.name AS company_name,h.employee_id,e.full_name AS employee_name,
      h.item,h.handed_on,
      private_isg.ppe_handover_status(h.quantity,
        (SELECT coalesce(sum(r.quantity),0) FROM private_isg.ppe_returns r
          WHERE r.handover_id=h.handover_id)) AS entry_state,
      -- What is still out first: that is the question the page answers.
      row_number() OVER (ORDER BY
        CASE private_isg.ppe_handover_status(h.quantity,
          (SELECT coalesce(sum(r.quantity),0) FROM private_isg.ppe_returns r
            WHERE r.handover_id=h.handover_id))
          WHEN 'outstanding' THEN 0 WHEN 'partial' THEN 1 ELSE 2 END,
        h.handed_on DESC,s.name,e.full_name,h.handover_id) AS ordinal
    FROM private_isg.ppe_handovers h
    JOIN scope s ON s.id=h.company_id
    JOIN private_isg.employees e ON e.company_id=h.company_id AND e.id=h.employee_id
  ), scoped AS (
    SELECT * FROM page WHERE (p_company IS NULL OR company_id=p_company)
  ), filtered AS (
    SELECT * FROM scoped
    WHERE (p_employee IS NULL OR employee_id=p_employee)
      AND (p_state IS NULL OR entry_state=p_state)
      AND (needle IS NULL OR item ILIKE '%'||needle||'%'
           OR employee_name ILIKE '%'||needle||'%' OR company_name ILIKE '%'||needle||'%')
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
         private_isg.ppe_handover_row(picked.handover_id,false)
           ||jsonb_build_object('company_name',picked.company_name) AS entry
       FROM (SELECT * FROM filtered ORDER BY ordinal LIMIT page_limit OFFSET page_offset) picked) built)
  INTO tally_all,tally_companies,matching_rows,tally_rows;

  RETURN jsonb_build_object('schema_version',1,'kind','list','rows',tally_rows,'today',today,
    'counts',tally_all,'companies',tally_companies,
    'total',matching_rows,'returned',jsonb_array_length(tally_rows),
    'has_more',page_offset+jsonb_array_length(tally_rows)<matching_rows,
    'limit',page_limit,'offset',page_offset,
    -- A tally of what is still out, never a statement that anyone is
    -- adequately protected.
    'compliance_verdict',NULL,'signed_copy_storage_available',false,
    'health_records_tracked',false);
END $$;

CREATE FUNCTION private_isg.mutate_ppe_handovers(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.ppe_receipts;
  result jsonb; answer jsonb; handover uuid; entry private_isg.ppe_handovers;
  stamp timestamptz:=clock_timestamp(); today date;
BEGIN
  actor:=private_isg.require_ppe_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>4096 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(stamp AT TIME ZONE 'UTC')::date;
  allowed:=CASE p_action
    -- No `signed_copy` and no asset: the product holds no file, so the flag
    -- could only ever be refused. What may be recorded is where the signed
    -- form is kept.
    WHEN 'record_handover' THEN ARRAY['employee_id','item','quantity','unit','handed_on',
      'external_ref','signed_copy_location']
    WHEN 'record_return' THEN ARRAY['handover_id','quantity','returned_on','condition','note']
    WHEN 'remove_return' THEN ARRAY['handover_id','return_id']
    ELSE NULL END;
  IF allowed IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO offending FROM jsonb_object_keys(p_payload) AS keys(key)
    WHERE NOT (key=ANY(allowed)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;

  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-ppe:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.ppe_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN prior.response||jsonb_build_object('replayed',true);
  END IF;

  IF p_action='record_handover' THEN
    IF p_payload->>'employee_id' IS NULL OR p_payload->>'item' IS NULL OR
       p_payload->>'quantity' IS NULL OR p_payload->>'unit' IS NULL OR
       p_payload->>'handed_on' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    -- Nothing was handed over on a day that has not happened.
    IF (p_payload->>'handed_on')::date>today THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='HANDED_IN_THE_FUTURE'; END IF;
    answer:=private_isg.record_ppe_handover(p_company,(p_payload->>'employee_id')::uuid,
      p_payload->>'item',(p_payload->>'quantity')::numeric,p_payload->>'unit',
      (p_payload->>'handed_on')::date,NULL,false,
      nullif(btrim(coalesce(p_payload->>'external_ref','')),''),stamp);
    handover:=(answer->>'handover_id')::uuid;
    IF NOT coalesce((answer->>'replayed')::boolean,false) THEN
      UPDATE private_isg.ppe_handovers
        SET signed_copy_location=nullif(btrim(coalesce(p_payload->>'signed_copy_location','')),'')
        WHERE handover_id=handover;
    END IF;
  ELSE
    handover:=(p_payload->>'handover_id')::uuid;
    -- The handover has to be this company's before the core function, which
    -- was written for a caller that had already checked.
    SELECT * INTO entry FROM private_isg.ppe_handovers
      WHERE handover_id=handover AND company_id=p_company FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF p_action='record_return' THEN
      IF p_payload->>'quantity' IS NULL OR p_payload->>'returned_on' IS NULL OR
         p_payload->>'condition' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      IF (p_payload->>'returned_on')::date>today THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RETURNED_IN_THE_FUTURE'; END IF;
      answer:=private_isg.record_ppe_return(handover,(p_payload->>'quantity')::numeric,
        (p_payload->>'returned_on')::date,p_payload->>'condition',
        nullif(btrim(coalesce(p_payload->>'note','')),''),stamp);
    ELSE
      IF p_payload->>'return_id' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.remove_ppe_return(handover,(p_payload->>'return_id')::uuid);
    END IF;
  END IF;

  result:=jsonb_build_object('schema_version',1,'action',p_action,'handover_id',handover,'answer',answer,
    'row',private_isg.ppe_handover_row(handover,true));
  INSERT INTO private_isg.ppe_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $$;

CREATE FUNCTION public.isg_ppe_read_v1(p_company uuid,p_kind text,p_query text,p_state text,
  p_employee uuid,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.read_ppe_handovers(p_company,p_kind,p_query,p_state,p_employee,p_id,p_limit,p_offset)
$$;
CREATE FUNCTION public.isg_ppe_mutate_v1(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.mutate_ppe_handovers(p_company,p_action,p_operation,p_mutation,p_payload)
$$;

REVOKE ALL ON FUNCTION private_isg.ppe_handover_status(numeric,numeric),
  private_isg.ppe_gate(boolean),
  private_isg.require_ppe_company(uuid,boolean),
  private_isg.remove_ppe_return(uuid,uuid),
  private_isg.ppe_handover_row(uuid,boolean),
  private_isg.read_ppe_handovers(uuid,text,text,text,uuid,uuid,integer,integer),
  private_isg.mutate_ppe_handovers(uuid,text,uuid,uuid,jsonb),
  public.isg_ppe_read_v1(uuid,text,text,text,uuid,uuid,integer,integer),
  public.isg_ppe_mutate_v1(uuid,text,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.read_ppe_handovers(uuid,text,text,text,uuid,uuid,integer,integer),
  private_isg.mutate_ppe_handovers(uuid,text,uuid,uuid,jsonb),
  public.isg_ppe_read_v1(uuid,text,text,text,uuid,uuid,integer,integer),
  public.isg_ppe_mutate_v1(uuid,text,uuid,uuid,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
