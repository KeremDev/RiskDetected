-- P10 client slice: the surface behind "Tatbikatlar".
-- Additive. No rollout row is added and none is opened: this rides on the
-- `modules` feature and the `drill` module switch P10 already created.
--
-- The P10 core built the drill record and kept planning apart from performing.
-- Three things were missing rather than merely unreachable:
--
--   1. No client boundary, and `plan_drill` / `record_drill_result` carried no
--      ownership check — `module_scope` proves the workplace belongs to the
--      company, never that the company belongs to the caller, and recording a
--      result took a drill id and trusted it.
--   2. Nothing could cancel a drill. The state and its mandatory reason were in
--      the schema with no function to write them.
--   3. Participants were stored as employee ids alone. Renaming or archiving a
--      person later would have changed what a performed drill said about who
--      was there.
--
-- Five things this slice makes structurally impossible:
--   1. Another owner's drill or plan cannot be reached, and a drill cannot
--      rehearse a plan belonging to a different workplace.
--   2. Planning is not performing. A planned date that has passed reads
--      'overdue', never 'performed', and every read reports `performed` from
--      the record rather than from a date.
--   3. A performed drill is closed: no second result, and no cancellation
--      after the fact.
--   4. Who took part is frozen at the moment it is recorded. Changing the
--      personnel register afterwards never edits a performed drill.
--   5. A drill is pinned to the plan version it rehearsed. The client cannot
--      name a version at all: the boundary resolves the one in force, and
--      publishing a newer plan later never re-points it.
BEGIN;
SET LOCAL lock_timeout='5s';

-- Who was there, as they were named at the time. The core stores ids; this
-- keeps the answer a performed drill gave when it was given.
ALTER TABLE private_isg.drill_records
  ADD COLUMN participant_snapshot jsonb,
  ADD CONSTRAINT drill_snapshot_shape_check
    CHECK(participant_snapshot IS NULL OR jsonb_typeof(participant_snapshot)='array');

CREATE TABLE private_isg.drill_receipts (
  actor_id uuid NOT NULL, mutation_id uuid NOT NULL, company_id uuid NOT NULL,
  operation_id uuid NOT NULL, request_hash bytea NOT NULL, response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(actor_id,mutation_id),
  FOREIGN KEY(company_id,actor_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
CREATE INDEX drill_receipt_company_idx ON private_isg.drill_receipts(company_id,actor_id);
ALTER TABLE private_isg.drill_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

-- How early the page starts warning that a planned drill is coming up. The
-- product's own warning distance, reported on every read.
CREATE FUNCTION private_isg.drill_notice_days() RETURNS integer
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$ SELECT 14 $$;

-- What a drill says about itself today. Nothing is stored beyond the record's
-- own state; overdue and due soon are worked out from the planned date.
--
-- A planned date that has passed reads 'overdue'. It is deliberately never
-- 'performed': a date going by is not a drill being held.
CREATE FUNCTION private_isg.drill_status(p_state text,p_planned_on date,p_notice_days integer,
  p_today date) RETURNS text
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
BEGIN
  IF p_state='performed' THEN RETURN 'performed'; END IF;
  IF p_state='cancelled' THEN RETURN 'cancelled'; END IF;
  IF p_planned_on<p_today THEN RETURN 'overdue'; END IF;
  IF p_planned_on<=p_today+p_notice_days THEN RETURN 'due_soon'; END IF;
  RETURN 'scheduled';
END $$;

-- Four counters over five states, every state in exactly one group.
CREATE FUNCTION private_isg.drill_group(p_state text) RETURNS text
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT CASE p_state
    WHEN 'overdue' THEN 'overdue'
    WHEN 'due_soon' THEN 'due_soon'
    WHEN 'scheduled' THEN 'scheduled'
    ELSE 'closed' END
$$;

CREATE FUNCTION private_isg.drill_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM private_isg.module_gate('drill',p_write);
END $$;

CREATE FUNCTION private_isg.require_drill_company(p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  PERFORM private_isg.drill_gate(p_write);
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

-- The missing state transition. A drill that was held is a record of what
-- happened; it is not withdrawn.
CREATE FUNCTION private_isg.cancel_drill(p_drill uuid,p_reason text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.drill_records;
BEGIN
  PERFORM private_isg.module_gate('drill',true);
  IF p_drill IS NULL OR p_now IS NULL OR p_reason IS NULL OR btrim(p_reason)='' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.drill_records WHERE drill_id=p_drill FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.state='cancelled' THEN
    RETURN jsonb_build_object('schema_version',1,'drill_id',p_drill,'state','cancelled','replayed',true); END IF;
  IF entry.state<>'planned' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DRILL_PERFORMED'; END IF;
  UPDATE private_isg.drill_records SET state='cancelled',
    cancelled_reason=private_isg.text_value(p_reason,500),updated_at=p_now WHERE drill_id=p_drill;
  RETURN jsonb_build_object('schema_version',1,'drill_id',p_drill,'state','cancelled','replayed',false);
END $$;

-- One drill: what it rehearsed, when, and who was there as they were named at
-- the time.
CREATE FUNCTION private_isg.drill_row(p_drill uuid,p_today date) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.drill_records; plan private_isg.emergency_plan_versions;
  notice integer:=private_isg.drill_notice_days(); shown_state text;
BEGIN
  SELECT * INTO entry FROM private_isg.drill_records WHERE drill_id=p_drill;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO plan FROM private_isg.emergency_plan_versions
    WHERE plan_id=entry.plan_id AND version=entry.plan_version;
  shown_state:=private_isg.drill_status(entry.state,entry.planned_on,notice,p_today);
  RETURN jsonb_build_object(
    'id',entry.drill_id,'company_id',entry.company_id,'workplace_id',entry.workplace_id,
    'plan_id',entry.plan_id,'plan_version',entry.plan_version,'plan_scope',plan.scope,
    -- Whether the plan has moved on since. The drill still rehearsed the
    -- version it names, and is never re-pointed.
    'plan_version_superseded',plan.state<>'active',
    'planned_on',entry.planned_on,'performed_on',entry.performed_on,
    'state',shown_state,'record_state',entry.state,
    'state_group',private_isg.drill_group(shown_state),
    'state_authority','computed_at_read','notice_days',notice,
    -- Read from the record, never inferred from a date going by.
    'performed',entry.state='performed',
    'observation',entry.observation,'improvement',entry.improvement,
    'cancelled_reason',entry.cancelled_reason,
    'participants',coalesce(entry.participant_snapshot,'[]'::jsonb),
    'participant_count',coalesce(jsonb_array_length(entry.participant_snapshot),0),
    -- The names are the ones recorded at the time, not the register's today.
    'participants_snapshotted',entry.participant_snapshot IS NOT NULL,
    'created_at',entry.created_at,
    'compliance_verdict',NULL,'health_records_tracked',false);
END $$;

CREATE FUNCTION private_isg.read_drills(p_company uuid,p_kind text,p_query text,p_state text,
  p_workplace uuid,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; needle text; today date; notice integer:=private_isg.drill_notice_days();
  page_limit integer; page_offset integer;
  tally_all jsonb; tally_companies jsonb; tally_rows jsonb; matching_rows integer;
BEGIN
  actor:=private_isg.require_drill_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('catalog','list','detail') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(clock_timestamp() AT TIME ZONE 'UTC')::date;

  IF p_kind='catalog' THEN
    RETURN jsonb_build_object('schema_version',1,'kind','catalog','notice_days',notice,
      -- Only plans that are in force can be rehearsed, and only this actor's.
      -- A drill without a plan is not offered, because the record has nowhere
      -- to point.
      'plans',(SELECT coalesce(jsonb_agg(jsonb_build_object('plan_id',v.plan_id,'version',v.version,
          'scope',v.scope,'workplace_id',v.workplace_id,'workplace_name',w.name,
          'valid_until',v.valid_until) ORDER BY w.name,v.scope),'[]'::jsonb)
        FROM private_isg.emergency_plan_versions v
        JOIN private_isg.workplaces w ON w.company_id=v.company_id AND w.id=v.workplace_id
        WHERE p_company IS NOT NULL AND v.company_id=p_company AND v.owner_id=actor
          AND v.state='active' AND NOT w.is_archived),
      'employees',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',e.id,'full_name',e.full_name)
          ORDER BY e.full_name),'[]'::jsonb)
        FROM private_isg.employees e
        WHERE p_company IS NOT NULL AND e.company_id=p_company AND NOT e.is_archived),
      -- The product proposes no drill period: no approved catalogue exists.
      'period_defaults_offered',false,
      'participants_are_snapshotted',true,
      'health_records_tracked',false);
  END IF;

  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.drill_records d
      JOIN public.companies c ON c.id=d.company_id AND c.user_id=actor
      WHERE d.drill_id=p_id AND (p_company IS NULL OR d.company_id=p_company);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'kind','detail','today',today,
      'row',private_isg.drill_row(p_id,today));
  END IF;

  IF p_state IS NOT NULL AND p_state NOT IN ('overdue','due_soon','scheduled','performed','cancelled',
    'closed') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  page_limit:=least(greatest(coalesce(p_limit,10),1),100);
  page_offset:=greatest(coalesce(p_offset,0),0);
  needle:=nullif(btrim(coalesce(p_query,'')),'');

  WITH scope AS (
    SELECT c.id,c.name FROM public.companies c WHERE c.user_id=actor AND NOT c.is_archived
  ), page AS (
    SELECT d.drill_id,d.company_id,s.name AS company_name,d.workplace_id,w.name AS workplace_name,
      v.scope AS plan_scope,
      private_isg.drill_status(d.state,d.planned_on,notice,today) AS entry_state,
      d.planned_on,
      -- Worst first: what was missed, then what is coming up.
      row_number() OVER (ORDER BY
        CASE private_isg.drill_status(d.state,d.planned_on,notice,today)
          WHEN 'overdue' THEN 0 WHEN 'due_soon' THEN 1 WHEN 'scheduled' THEN 2 ELSE 3 END,
        d.planned_on,s.name,w.name,d.drill_id) AS ordinal
    FROM private_isg.drill_records d
    JOIN scope s ON s.id=d.company_id
    JOIN private_isg.workplaces w ON w.company_id=d.company_id AND w.id=d.workplace_id
    JOIN private_isg.emergency_plan_versions v
      ON v.plan_id=d.plan_id AND v.version=d.plan_version
    WHERE v.owner_id=actor AND NOT w.is_archived
  ), scoped AS (
    SELECT * FROM page WHERE (p_company IS NULL OR company_id=p_company)
  ), filtered AS (
    SELECT * FROM scoped
    WHERE (p_workplace IS NULL OR workplace_id=p_workplace)
      AND (p_state IS NULL OR entry_state=p_state
        OR private_isg.drill_group(entry_state)=p_state)
      AND (needle IS NULL OR plan_scope ILIKE '%'||needle||'%'
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
         private_isg.drill_row(picked.drill_id,today)
           ||jsonb_build_object('company_name',picked.company_name,
               'workplace_name',picked.workplace_name) AS entry
       FROM (SELECT * FROM filtered ORDER BY ordinal LIMIT page_limit OFFSET page_offset) picked) built)
  INTO tally_all,tally_companies,matching_rows,tally_rows;

  RETURN jsonb_build_object('schema_version',1,'kind','list','rows',tally_rows,'today',today,
    'counts',tally_all,'companies',tally_companies,
    'total',matching_rows,'returned',jsonb_array_length(tally_rows),
    'has_more',page_offset+jsonb_array_length(tally_rows)<matching_rows,
    'limit',page_limit,'offset',page_offset,'notice_days',notice,
    -- A tally of drills, never a statement that a workplace is prepared.
    'compliance_verdict',NULL,'health_records_tracked',false);
END $$;

CREATE FUNCTION private_isg.mutate_drills(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.drill_receipts;
  result jsonb; answer jsonb; drill uuid; entry private_isg.drill_records;
  plan private_isg.emergency_plan_versions; snapshot jsonb;
  stamp timestamptz:=clock_timestamp(); today date;
BEGIN
  actor:=private_isg.require_drill_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>16384 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(stamp AT TIME ZONE 'UTC')::date;
  allowed:=CASE p_action
    -- No plan_version: the boundary pins the version in force, so a drill can
    -- never be aimed at a version the expert did not see.
    WHEN 'plan_drill' THEN ARRAY['plan_id','planned_on']
    WHEN 'record_result' THEN ARRAY['drill_id','performed_on','participants','observation','improvement']
    WHEN 'cancel_drill' THEN ARRAY['drill_id','reason']
    ELSE NULL END;
  IF allowed IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO offending FROM jsonb_object_keys(p_payload) AS keys(key)
    WHERE NOT (key=ANY(allowed)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;

  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-drill:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.drill_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN prior.response||jsonb_build_object('replayed',true);
  END IF;

  IF p_action='plan_drill' THEN
    IF p_payload->>'plan_id' IS NULL OR p_payload->>'planned_on' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    -- The plan must be this actor's, in force, and its workplace is the
    -- drill's: a drill cannot rehearse another workplace's plan.
    SELECT * INTO plan FROM private_isg.emergency_plan_versions
      WHERE plan_id=(p_payload->>'plan_id')::uuid AND company_id=p_company
        AND owner_id=actor AND state='active' FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    answer:=private_isg.plan_drill(p_company,plan.workplace_id,plan.plan_id,plan.version,
      (p_payload->>'planned_on')::date,stamp);
    drill:=(answer->>'drill_id')::uuid;
  ELSE
    drill:=(p_payload->>'drill_id')::uuid;
    SELECT * INTO entry FROM private_isg.drill_records
      WHERE drill_id=drill AND company_id=p_company FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    -- The company is the caller's, but the plan behind the drill must be too.
    PERFORM 1 FROM private_isg.emergency_plan_versions
      WHERE plan_id=entry.plan_id AND version=entry.plan_version AND owner_id=actor;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;

    IF p_action='record_result' THEN
      IF p_payload->>'performed_on' IS NULL OR NOT p_payload ? 'participants' THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      -- A drill held tomorrow has not been held.
      IF (p_payload->>'performed_on')::date>today THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PERFORMED_IN_THE_FUTURE'; END IF;
      answer:=private_isg.record_drill_result(drill,(p_payload->>'performed_on')::date,
        p_payload->'participants',
        nullif(btrim(coalesce(p_payload->>'observation','')),''),
        nullif(btrim(coalesce(p_payload->>'improvement','')),''),stamp);
      -- Freeze who that was, as they are named now. The register may change
      -- afterwards; this record does not.
      IF NOT coalesce((answer->>'replayed')::boolean,false) THEN
        SELECT coalesce(jsonb_agg(jsonb_build_object('id',e.id,'full_name',e.full_name)
            ORDER BY e.full_name),'[]'::jsonb) INTO snapshot
          FROM private_isg.employees e
          WHERE e.company_id=p_company
            AND e.id::text IN (SELECT value FROM jsonb_array_elements_text(p_payload->'participants') AS t(value));
        UPDATE private_isg.drill_records SET participant_snapshot=snapshot WHERE drill_id=drill;
      END IF;
    ELSE
      IF p_payload->>'reason' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.cancel_drill(drill,p_payload->>'reason',stamp);
    END IF;
  END IF;

  result:=jsonb_build_object('schema_version',1,'action',p_action,'drill_id',drill,'answer',answer,
    'row',private_isg.drill_row(drill,today));
  INSERT INTO private_isg.drill_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $$;

CREATE FUNCTION public.isg_drills_read_v1(p_company uuid,p_kind text,p_query text,p_state text,
  p_workplace uuid,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.read_drills(p_company,p_kind,p_query,p_state,p_workplace,p_id,p_limit,p_offset)
$$;
CREATE FUNCTION public.isg_drills_mutate_v1(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.mutate_drills(p_company,p_action,p_operation,p_mutation,p_payload)
$$;

REVOKE ALL ON FUNCTION private_isg.drill_notice_days(),
  private_isg.drill_status(text,date,integer,date),
  private_isg.drill_group(text),
  private_isg.drill_gate(boolean),
  private_isg.require_drill_company(uuid,boolean),
  private_isg.cancel_drill(uuid,text,timestamptz),
  private_isg.drill_row(uuid,date),
  private_isg.read_drills(uuid,text,text,text,uuid,uuid,integer,integer),
  private_isg.mutate_drills(uuid,text,uuid,uuid,jsonb),
  public.isg_drills_read_v1(uuid,text,text,text,uuid,uuid,integer,integer),
  public.isg_drills_mutate_v1(uuid,text,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.read_drills(uuid,text,text,text,uuid,uuid,integer,integer),
  private_isg.mutate_drills(uuid,text,uuid,uuid,jsonb),
  public.isg_drills_read_v1(uuid,text,text,text,uuid,uuid,integer,integer),
  public.isg_drills_mutate_v1(uuid,text,uuid,uuid,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
