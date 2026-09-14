-- P10 client slice: the surface behind "İSG-KATİP Sözleşmeleri".
-- Additive. No rollout row is added and none is opened: this rides on the
-- `modules` feature and the `katip_contract` module switch P10 already created.
--
-- The P10 second core built the contract row and put the product's hardest
-- promise into the schema itself: `official_integration` can only ever be
-- false. Three things were missing rather than merely unreachable:
--
--   1. No client boundary, and no ownership check. `module_scope` proves the
--      workplace belongs to the company, never that the company belongs to the
--      caller.
--   2. Nothing could archive a contract, and nothing could set or correct its
--      end date after it was written. `state IN ('active','archived')` sat in
--      the schema with no function to move it.
--   3. The plan lists the declared service time and a reminder among this
--      module's fields, and there was no column for either.
--
-- Five things this slice makes structurally impossible:
--   1. Another owner's contract or workplace cannot be reached.
--   2. The product never acts on the official system. `official_integration`
--      is a false-only column, it is on no allowlist, no field anywhere takes
--      a credential, and every read states that nothing was filed there.
--   3. The product never says how much service time is required. What is
--      stored is what the contract itself declares, and the read says the
--      required amount is unknown rather than implying the declared one is
--      enough.
--   4. An open ended contract is its own state, not a missing end date. The
--      schema derives it, so no read can present the two as the same thing.
--   5. An archived contract is closed: its dates are not edited afterwards.
BEGIN;
SET LOCAL lock_timeout='5s';

-- What the contract itself says the expert will spend, and the expert's own
-- note about it. A declaration, never a measurement and never a requirement.
ALTER TABLE private_isg.katip_contracts
  ADD COLUMN declared_monthly_minutes integer
    CHECK(declared_monthly_minutes IS NULL OR declared_monthly_minutes BETWEEN 1 AND 100000),
  ADD COLUMN declared_note text CHECK(declared_note IS NULL OR length(declared_note)<=500),
  -- Where the signed contract is kept. The tracker holds a reference, never
  -- the document.
  ADD COLUMN contract_location text CHECK(contract_location IS NULL OR length(contract_location)<=300);

CREATE TABLE private_isg.katip_receipts (
  actor_id uuid NOT NULL, mutation_id uuid NOT NULL, company_id uuid NOT NULL,
  operation_id uuid NOT NULL, request_hash bytea NOT NULL, response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(actor_id,mutation_id),
  FOREIGN KEY(company_id,actor_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
CREATE INDEX katip_receipt_company_idx ON private_isg.katip_receipts(company_id,actor_id);
ALTER TABLE private_isg.katip_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

-- How early the page starts warning that a fixed term contract runs out. The
-- product's own warning distance, reported on every read.
CREATE FUNCTION private_isg.katip_notice_days() RETURNS integer
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$ SELECT 30 $$;

-- Where a contract stands today. Nothing is stored: the answer comes from its
-- own dates and its archived flag at read time.
CREATE FUNCTION private_isg.katip_contract_status(p_state text,p_starts_on date,p_ends_before date,
  p_notice_days integer,p_today date) RETURNS text
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
BEGIN
  IF p_state='archived' THEN RETURN 'archived'; END IF;
  IF p_starts_on>p_today THEN RETURN 'upcoming'; END IF;
  -- An open ended contract has no end to run out of, so it never expires.
  IF p_ends_before IS NULL THEN RETURN 'active'; END IF;
  IF p_ends_before<=p_today THEN RETURN 'expired'; END IF;
  IF p_ends_before<=p_today+p_notice_days THEN RETURN 'expiring'; END IF;
  RETURN 'active';
END $$;

-- Four counters over five states, every state in exactly one group.
CREATE FUNCTION private_isg.katip_contract_group(p_state text) RETURNS text
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT CASE p_state
    WHEN 'expired' THEN 'expired'
    WHEN 'expiring' THEN 'expiring'
    WHEN 'archived' THEN 'archived'
    ELSE 'current' END
$$;

CREATE FUNCTION private_isg.katip_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM private_isg.module_gate('katip_contract',p_write);
END $$;

CREATE FUNCTION private_isg.require_katip_company(p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  PERFORM private_isg.katip_gate(p_write);
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

-- The missing end date. Setting it again corrects it; an archived contract is
-- closed and its dates are left alone.
CREATE FUNCTION private_isg.end_katip_contract(p_contract uuid,p_ends_before date,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.katip_contracts;
BEGIN
  PERFORM private_isg.module_gate('katip_contract',true);
  IF p_contract IS NULL OR p_ends_before IS NULL OR NOT isfinite(p_ends_before) OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.katip_contracts WHERE contract_id=p_contract FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state='archived' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CONTRACT_ARCHIVED'; END IF;
  IF entry.ends_before IS NOT DISTINCT FROM p_ends_before THEN
    RETURN jsonb_build_object('schema_version',1,'contract_id',p_contract,
      'ends_before',p_ends_before,'term_state','fixed_term','replayed',true); END IF;
  IF p_ends_before<=entry.starts_on THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ENDS_BEFORE_START'; END IF;
  UPDATE private_isg.katip_contracts SET ends_before=p_ends_before,updated_at=p_now
    WHERE contract_id=p_contract;
  RETURN jsonb_build_object('schema_version',1,'contract_id',p_contract,'starts_on',entry.starts_on,
    'ends_before',p_ends_before,'term_state','fixed_term','official_submission_made',false,'replayed',false);
END $$;

-- The missing state transition.
CREATE FUNCTION private_isg.archive_katip_contract(p_contract uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.katip_contracts;
BEGIN
  PERFORM private_isg.module_gate('katip_contract',true);
  IF p_contract IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.katip_contracts WHERE contract_id=p_contract FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state='archived' THEN
    RETURN jsonb_build_object('schema_version',1,'contract_id',p_contract,'state','archived','replayed',true); END IF;
  UPDATE private_isg.katip_contracts SET state='archived',updated_at=p_now WHERE contract_id=p_contract;
  -- Archiving is a change in this application's record. Nothing was filed
  -- anywhere else, and the answer says so.
  RETURN jsonb_build_object('schema_version',1,'contract_id',p_contract,'state','archived',
    'official_submission_made',false,'replayed',false);
END $$;

-- One contract as the board sees it.
CREATE FUNCTION private_isg.katip_contract_row(p_contract uuid,p_today date) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.katip_contracts; place private_isg.workplaces;
  notice integer:=private_isg.katip_notice_days(); shown_state text;
BEGIN
  SELECT * INTO entry FROM private_isg.katip_contracts WHERE contract_id=p_contract;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO place FROM private_isg.workplaces
    WHERE company_id=entry.company_id AND id=entry.workplace_id;
  shown_state:=private_isg.katip_contract_status(entry.state,entry.starts_on,entry.ends_before,notice,p_today);
  RETURN jsonb_build_object(
    'id',entry.contract_id,'company_id',entry.company_id,
    'workplace_id',entry.workplace_id,'workplace_name',place.name,
    'counterparty',entry.counterparty,'expert_contact',entry.expert_contact,'scope',entry.scope,
    'starts_on',entry.starts_on,'ends_before',entry.ends_before,
    -- Derived by the schema: an open ended contract is its own thing, never a
    -- fixed term one whose end date nobody entered.
    'term_state',entry.term_state,
    'state',shown_state,'record_state',entry.state,
    'state_group',private_isg.katip_contract_group(shown_state),
    'state_authority','computed_at_read','notice_days',notice,
    -- What the contract declares, and nothing about whether it is enough.
    'declared_monthly_minutes',entry.declared_monthly_minutes,
    'declared_note',entry.declared_note,
    'required_service_time_known',false,
    'contract_location',entry.contract_location,'contract_stored',false,
    -- The column can only ever be false, and this repeats it on every read.
    'official_integration',entry.official_integration,
    'official_submission_made',false,'official_status_checked',false,
    'compliance_verdict',NULL,'health_records_tracked',false);
END $$;

CREATE FUNCTION private_isg.read_katip_contracts(p_company uuid,p_kind text,p_query text,p_state text,
  p_workplace uuid,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; needle text; today date; notice integer:=private_isg.katip_notice_days();
  page_limit integer; page_offset integer;
  tally_all jsonb; tally_companies jsonb; tally_rows jsonb; matching_rows integer;
BEGIN
  actor:=private_isg.require_katip_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('catalog','list','detail') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(clock_timestamp() AT TIME ZONE 'UTC')::date;

  IF p_kind='catalog' THEN
    RETURN jsonb_build_object('schema_version',1,'kind','catalog','notice_days',notice,
      'workplaces',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name)
          ORDER BY w.name),'[]'::jsonb)
        FROM private_isg.workplaces w
        WHERE p_company IS NOT NULL AND w.company_id=p_company AND w.owner_id=actor AND NOT w.is_archived),
      'term_states',jsonb_build_array('open_ended','fixed_term'),
      -- Said plainly, at the top of everything this module offers.
      'official_integration',false,
      'official_status_checked',false,
      'credential_collection',false,
      'required_service_time_known',false,
      'contract_storage_available',false,
      'health_records_tracked',false);
  END IF;

  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.katip_contracts k
      JOIN public.companies c ON c.id=k.company_id AND c.user_id=actor
      WHERE k.contract_id=p_id AND (p_company IS NULL OR k.company_id=p_company);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'kind','detail','today',today,
      'row',private_isg.katip_contract_row(p_id,today));
  END IF;

  IF p_state IS NOT NULL AND p_state NOT IN ('upcoming','active','expiring','expired','archived','current') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  page_limit:=least(greatest(coalesce(p_limit,10),1),100);
  page_offset:=greatest(coalesce(p_offset,0),0);
  needle:=nullif(btrim(coalesce(p_query,'')),'');

  WITH scope AS (
    SELECT c.id,c.name FROM public.companies c WHERE c.user_id=actor AND NOT c.is_archived
  ), page AS (
    SELECT k.contract_id,k.company_id,s.name AS company_name,k.workplace_id,w.name AS workplace_name,
      k.counterparty,k.scope AS contract_scope,k.ends_before,
      private_isg.katip_contract_status(k.state,k.starts_on,k.ends_before,notice,today) AS entry_state,
      -- What ran out first, then what is about to.
      row_number() OVER (ORDER BY
        CASE private_isg.katip_contract_status(k.state,k.starts_on,k.ends_before,notice,today)
          WHEN 'expired' THEN 0 WHEN 'expiring' THEN 1 WHEN 'upcoming' THEN 2
          WHEN 'active' THEN 3 ELSE 4 END,
        k.ends_before NULLS LAST,s.name,w.name,k.counterparty,k.contract_id) AS ordinal
    FROM private_isg.katip_contracts k
    JOIN scope s ON s.id=k.company_id
    JOIN private_isg.workplaces w ON w.company_id=k.company_id AND w.id=k.workplace_id
    WHERE k.owner_id=actor AND NOT w.is_archived
  ), scoped AS (
    SELECT * FROM page WHERE (p_company IS NULL OR company_id=p_company)
  ), filtered AS (
    SELECT * FROM scoped
    WHERE (p_workplace IS NULL OR workplace_id=p_workplace)
      AND (p_state IS NULL OR entry_state=p_state
        OR private_isg.katip_contract_group(entry_state)=p_state)
      AND (needle IS NULL OR counterparty ILIKE '%'||needle||'%'
           OR contract_scope ILIKE '%'||needle||'%'
           OR workplace_name ILIKE '%'||needle||'%' OR company_name ILIKE '%'||needle||'%')
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
         private_isg.katip_contract_row(picked.contract_id,today)
           ||jsonb_build_object('company_name',picked.company_name) AS entry
       FROM (SELECT * FROM filtered ORDER BY ordinal LIMIT page_limit OFFSET page_offset) picked) built)
  INTO tally_all,tally_companies,matching_rows,tally_rows;

  RETURN jsonb_build_object('schema_version',1,'kind','list','rows',tally_rows,'today',today,
    'counts',tally_all,'companies',tally_companies,
    'total',matching_rows,'returned',jsonb_array_length(tally_rows),
    'has_more',page_offset+jsonb_array_length(tally_rows)<matching_rows,
    'limit',page_limit,'offset',page_offset,'notice_days',notice,
    -- A tally of contracts this application holds, never a statement about the
    -- official system or about whether the service time is sufficient.
    'compliance_verdict',NULL,'official_integration',false,
    'official_status_checked',false,'required_service_time_known',false,
    'health_records_tracked',false);
END $$;

CREATE FUNCTION private_isg.mutate_katip_contracts(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.katip_receipts;
  result jsonb; answer jsonb; contract uuid; entry private_isg.katip_contracts;
  stamp timestamptz:=clock_timestamp(); today date;
BEGIN
  actor:=private_isg.require_katip_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>4096 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(stamp AT TIME ZONE 'UTC')::date;
  allowed:=CASE p_action
    -- Nothing here takes a credential, a session, or anything that could be
    -- sent to the official system, and nothing may raise the integration flag.
    WHEN 'record_contract' THEN ARRAY['workplace_id','counterparty','expert_contact','scope',
      'starts_on','ends_before','declared_monthly_minutes','declared_note','contract_location']
    WHEN 'end_contract' THEN ARRAY['contract_id','ends_before']
    WHEN 'archive_contract' THEN ARRAY['contract_id']
    ELSE NULL END;
  IF allowed IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO offending FROM jsonb_object_keys(p_payload) AS keys(key)
    WHERE NOT (key=ANY(allowed)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;

  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-katip:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.katip_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN prior.response||jsonb_build_object('replayed',true);
  END IF;

  IF p_action='record_contract' THEN
    IF p_payload->>'workplace_id' IS NULL OR p_payload->>'counterparty' IS NULL OR
       p_payload->>'expert_contact' IS NULL OR p_payload->>'scope' IS NULL OR
       p_payload->>'starts_on' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.workplaces WHERE company_id=p_company
      AND id=(p_payload->>'workplace_id')::uuid AND owner_id=actor AND NOT is_archived;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    answer:=private_isg.record_katip_contract(p_company,(p_payload->>'workplace_id')::uuid,
      p_payload->>'counterparty',p_payload->>'expert_contact',p_payload->>'scope',
      (p_payload->>'starts_on')::date,(p_payload->>'ends_before')::date,NULL,stamp);
    contract:=(answer->>'contract_id')::uuid;
    IF NOT coalesce((answer->>'replayed')::boolean,false) THEN
      UPDATE private_isg.katip_contracts SET
        declared_monthly_minutes=(p_payload->>'declared_monthly_minutes')::integer,
        declared_note=nullif(btrim(coalesce(p_payload->>'declared_note','')),''),
        contract_location=nullif(btrim(coalesce(p_payload->>'contract_location','')),'')
        WHERE contract_id=contract;
    END IF;
  ELSE
    contract:=(p_payload->>'contract_id')::uuid;
    SELECT * INTO entry FROM private_isg.katip_contracts
      WHERE contract_id=contract AND company_id=p_company AND owner_id=actor FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF p_action='end_contract' THEN
      IF p_payload->>'ends_before' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.end_katip_contract(contract,(p_payload->>'ends_before')::date,stamp);
    ELSE
      answer:=private_isg.archive_katip_contract(contract,stamp);
    END IF;
  END IF;

  result:=jsonb_build_object('schema_version',1,'action',p_action,'contract_id',contract,'answer',answer,
    'row',private_isg.katip_contract_row(contract,today),
    -- Repeated on the envelope of every write, not only on the read.
    'official_submission_made',false);
  INSERT INTO private_isg.katip_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $$;

CREATE FUNCTION public.isg_katip_read_v1(p_company uuid,p_kind text,p_query text,p_state text,
  p_workplace uuid,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.read_katip_contracts(p_company,p_kind,p_query,p_state,p_workplace,p_id,p_limit,p_offset)
$$;
CREATE FUNCTION public.isg_katip_mutate_v1(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.mutate_katip_contracts(p_company,p_action,p_operation,p_mutation,p_payload)
$$;

REVOKE ALL ON FUNCTION private_isg.katip_notice_days(),
  private_isg.katip_contract_status(text,date,date,integer,date),
  private_isg.katip_contract_group(text),
  private_isg.katip_gate(boolean),
  private_isg.require_katip_company(uuid,boolean),
  private_isg.end_katip_contract(uuid,date,timestamptz),
  private_isg.archive_katip_contract(uuid,timestamptz),
  private_isg.katip_contract_row(uuid,date),
  private_isg.read_katip_contracts(uuid,text,text,text,uuid,uuid,integer,integer),
  private_isg.mutate_katip_contracts(uuid,text,uuid,uuid,jsonb),
  public.isg_katip_read_v1(uuid,text,text,text,uuid,uuid,integer,integer),
  public.isg_katip_mutate_v1(uuid,text,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.read_katip_contracts(uuid,text,text,text,uuid,uuid,integer,integer),
  private_isg.mutate_katip_contracts(uuid,text,uuid,uuid,jsonb),
  public.isg_katip_read_v1(uuid,text,text,text,uuid,uuid,integer,integer),
  public.isg_katip_mutate_v1(uuid,text,uuid,uuid,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
