-- P10 client slice: the surface behind "Acil Durum Planları".
-- Additive. No rollout row is added and none is opened: this rides on the
-- `modules` feature and the `emergency_plan` module switch P10 already created.
--
-- The P10 core slice built the versioned plan whose renewal supersedes only the
-- pointer, so a previous version keeps its own scope, team snapshot, dates and
-- file. What it never had was a client boundary, and `publish_emergency_plan`
-- carried no ownership check: `module_scope` proves the workplace belongs to the
-- company, never that the company belongs to the caller.
--
-- Five things this slice makes structurally impossible:
--   1. Another owner's plan cannot be reached, and a renewal cannot be aimed at
--      a plan that is not this company's.
--   2. A renewal never rewrites what came before. The read returns every
--      version with its own team, dates and scope, so the history is visible
--      rather than asserted.
--   3. A validity date is never presented as a legal period. No approved
--      renewal catalogue exists, so the date is the expert's and the read says
--      so on every row. A plan with no date reads 'period_unknown', never
--      'valid'.
--   4. An unverified legal basis stays in review. `needs_review` is set by the
--      core function from the absence of a written basis; there is no payload
--      field that can clear it, and no action can edit a published version.
--   5. A team snapshot cannot be arbitrary JSON. Every entry is checked here
--      for a name and a role from a fixed set, so what is frozen into a plan is
--      a team rather than whatever the client happened to send.
BEGIN;
SET LOCAL lock_timeout='5s';

CREATE TABLE private_isg.emergency_plan_receipts (
  actor_id uuid NOT NULL, mutation_id uuid NOT NULL, company_id uuid NOT NULL,
  operation_id uuid NOT NULL, request_hash bytea NOT NULL, response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(actor_id,mutation_id),
  FOREIGN KEY(company_id,actor_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
CREATE INDEX emergency_plan_receipt_company_idx ON private_isg.emergency_plan_receipts(company_id,actor_id);
ALTER TABLE private_isg.emergency_plan_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

-- How early the page starts warning that a plan runs out. The product's own
-- warning distance, reported on every read, never a legal period.
CREATE FUNCTION private_isg.emergency_notice_days() RETURNS integer
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$ SELECT 30 $$;

-- The roles a team entry may carry. A fixed set in the schema, so a snapshot
-- cannot be filled with whatever the client invents.
CREATE TABLE private_isg.emergency_team_roles (
  role_code text PRIMARY KEY CHECK(role_code IN ('coordinator','fire','first_aid','evacuation','other')),
  ordinal integer NOT NULL CHECK(ordinal BETWEEN 1 AND 99),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(ordinal)
);
INSERT INTO private_isg.emergency_team_roles(role_code,ordinal) VALUES
  ('coordinator',1),('fire',2),('first_aid',3),('evacuation',4),('other',5);
ALTER TABLE private_isg.emergency_team_roles ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

-- What a plan says about itself today. Nothing is stored: the answer is worked
-- out from the active version's own dates at read time.
--
-- 'period_unknown' is the honest answer when a plan is published with no end
-- date. It is deliberately NOT 'valid': not knowing when a plan runs out is a
-- gap in the record, never a statement that it still stands.
CREATE FUNCTION private_isg.emergency_plan_status(p_valid_until date,p_has_version boolean,
  p_notice_days integer,p_today date) RETURNS text
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
BEGIN
  IF NOT p_has_version THEN RETURN 'never_published'; END IF;
  IF p_valid_until IS NULL THEN RETURN 'period_unknown'; END IF;
  IF p_valid_until<p_today THEN RETURN 'expired'; END IF;
  IF p_valid_until<=p_today+p_notice_days THEN RETURN 'due_soon'; END IF;
  RETURN 'valid';
END $$;

-- Four counters over five states, every state in exactly one group.
CREATE FUNCTION private_isg.emergency_plan_group(p_state text) RETURNS text
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT CASE p_state
    WHEN 'valid' THEN 'current'
    WHEN 'due_soon' THEN 'due_soon'
    WHEN 'expired' THEN 'expired'
    ELSE 'untracked' END
$$;

CREATE FUNCTION private_isg.emergency_plan_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM private_isg.module_gate('emergency_plan',p_write);
END $$;

-- A NULL company is the whole account, and only for reads: every write names
-- the company it writes into. `publish_emergency_plan` was written for a caller
-- that had already checked ownership; this is that caller.
CREATE FUNCTION private_isg.require_emergency_company(p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  PERFORM private_isg.emergency_plan_gate(p_write);
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

-- What may be frozen into a plan as its team. The core function only checks
-- that it is an array; this checks that every entry is a person with a role.
CREATE FUNCTION private_isg.emergency_team_snapshot(p_team jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE entry jsonb; cleaned jsonb:='[]'::jsonb; name text; role text; contact text; offending text;
BEGIN
  IF p_team IS NULL OR jsonb_typeof(p_team)<>'array' OR
     jsonb_array_length(p_team) NOT BETWEEN 1 AND 200 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  FOR entry IN SELECT * FROM jsonb_array_elements(p_team) LOOP
    IF jsonb_typeof(entry)<>'object' THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    -- Only these three keys, so nothing else rides into the snapshot.
    SELECT key INTO offending FROM jsonb_object_keys(entry) AS keys(key)
      WHERE key NOT IN ('full_name','role','contact') ORDER BY key LIMIT 1;
    IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;
    name:=nullif(btrim(coalesce(entry->>'full_name','')),'');
    role:=nullif(btrim(coalesce(entry->>'role','')),'');
    contact:=nullif(btrim(coalesce(entry->>'contact','')),'');
    IF name IS NULL OR length(name)>200 OR role IS NULL OR
       (contact IS NOT NULL AND length(contact)>120) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.emergency_team_roles WHERE role_code=role;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='TEAM_ROLE_UNKNOWN'; END IF;
    cleaned:=cleaned||jsonb_build_array(jsonb_strip_nulls(
      jsonb_build_object('full_name',name,'role',role,'contact',contact)));
  END LOOP;
  RETURN cleaned;
END $$;

-- One plan: the version that stands today, and every version behind it with its
-- own team, dates and scope.
CREATE FUNCTION private_isg.emergency_plan_row(p_plan uuid,p_today date,p_history boolean) RETURNS jsonb
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
    -- The basis the expert wrote down, and the flag its absence forces.
    'needs_review',active.needs_review,'review_note',active.review_note,
    -- The date is the expert's: no approved renewal catalogue exists.
    'period_source','expert','period_needs_review',true,
    'team',active.team_snapshot,'team_size',jsonb_array_length(active.team_snapshot),
    'asset_id',active.asset_id,
    'versions',CASE WHEN p_history THEN
      (SELECT coalesce(jsonb_agg(jsonb_build_object('version',v.version,'state',v.state,
          'scope',v.scope,'prepared_on',v.prepared_on,'valid_until',v.valid_until,
          'needs_review',v.needs_review,'review_note',v.review_note,
          -- Each version keeps its own team. Renewing never rewrites an older one.
          'team',v.team_snapshot,'team_size',jsonb_array_length(v.team_snapshot),
          'asset_id',v.asset_id,'created_at',v.created_at)
          ORDER BY v.version DESC),'[]'::jsonb)
       FROM private_isg.emergency_plan_versions v WHERE v.plan_id=p_plan) END,
    'compliance_verdict',NULL,'health_records_tracked',false);
END $$;

CREATE FUNCTION private_isg.read_emergency_plans(p_company uuid,p_kind text,p_query text,p_state text,
  p_workplace uuid,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; needle text; today date; notice integer:=private_isg.emergency_notice_days();
  page_limit integer; page_offset integer;
  tally_all jsonb; tally_companies jsonb; tally_rows jsonb; matching_rows integer;
BEGIN
  actor:=private_isg.require_emergency_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('catalog','list','detail') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(clock_timestamp() AT TIME ZONE 'UTC')::date;

  IF p_kind='catalog' THEN
    RETURN jsonb_build_object('schema_version',1,'kind','catalog','notice_days',notice,
      'workplaces',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,
          'needs_review',w.needs_review) ORDER BY w.name),'[]'::jsonb)
        FROM private_isg.workplaces w
        WHERE p_company IS NOT NULL AND w.company_id=p_company AND w.owner_id=actor AND NOT w.is_archived),
      'team_roles',(SELECT coalesce(jsonb_agg(jsonb_build_object('code',r.role_code,'ordinal',r.ordinal)
          ORDER BY r.ordinal),'[]'::jsonb) FROM private_isg.emergency_team_roles r),
      -- The product proposes no renewal period, because no approved catalogue
      -- exists. Whatever date the expert writes is stored as the expert's.
      'period_defaults_offered',false,
      'expert_period_source','expert',
      'review_cleared_by_note',true,
      'health_records_tracked',false);
  END IF;

  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.emergency_plan_versions v
      JOIN public.companies c ON c.id=v.company_id AND c.user_id=actor
      WHERE v.plan_id=p_id AND (p_company IS NULL OR v.company_id=p_company);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'kind','detail','today',today,
      'row',private_isg.emergency_plan_row(p_id,today,true));
  END IF;

  IF p_state IS NOT NULL AND p_state NOT IN ('never_published','period_unknown','expired','due_soon','valid',
    'current','untracked') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  page_limit:=least(greatest(coalesce(p_limit,10),1),100);
  page_offset:=greatest(coalesce(p_offset,0),0);
  needle:=nullif(btrim(coalesce(p_query,'')),'');

  WITH scope AS (
    SELECT c.id,c.name FROM public.companies c WHERE c.user_id=actor AND NOT c.is_archived
  ), page AS (
    SELECT v.plan_id,v.company_id,s.name AS company_name,v.workplace_id,w.name AS workplace_name,
      v.scope AS plan_scope,
      private_isg.emergency_plan_status(v.valid_until,true,notice,today) AS entry_state,
      v.valid_until,v.needs_review,
      -- Worst first: what ran out, then what has no end date, then what is due.
      row_number() OVER (ORDER BY
        CASE private_isg.emergency_plan_status(v.valid_until,true,notice,today)
          WHEN 'expired' THEN 0 WHEN 'period_unknown' THEN 1 WHEN 'due_soon' THEN 2 ELSE 3 END,
        v.valid_until NULLS FIRST,s.name,w.name,v.plan_id) AS ordinal
    FROM private_isg.emergency_plan_versions v
    JOIN scope s ON s.id=v.company_id
    JOIN private_isg.workplaces w ON w.company_id=v.company_id AND w.id=v.workplace_id
    WHERE v.owner_id=actor AND v.state='active' AND NOT w.is_archived
  ), scoped AS (
    SELECT * FROM page WHERE (p_company IS NULL OR company_id=p_company)
  ), filtered AS (
    SELECT * FROM scoped
    WHERE (p_workplace IS NULL OR workplace_id=p_workplace)
      AND (p_state IS NULL OR entry_state=p_state
        OR private_isg.emergency_plan_group(entry_state)=p_state)
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
         private_isg.emergency_plan_row(picked.plan_id,today,false)
           ||jsonb_build_object('company_name',picked.company_name,
               'workplace_name',picked.workplace_name) AS entry
       FROM (SELECT * FROM filtered ORDER BY ordinal LIMIT page_limit OFFSET page_offset) picked) built)
  INTO tally_all,tally_companies,matching_rows,tally_rows;

  RETURN jsonb_build_object('schema_version',1,'kind','list','rows',tally_rows,'today',today,
    'counts',tally_all,'companies',tally_companies,
    'total',matching_rows,'returned',jsonb_array_length(tally_rows),
    'has_more',page_offset+jsonb_array_length(tally_rows)<matching_rows,
    'limit',page_limit,'offset',page_offset,'notice_days',notice,
    'compliance_verdict',NULL,'health_records_tracked',false);
END $$;

-- Publishing is the only write. There is no edit: correcting a plan means
-- publishing the next version, and the one before it keeps everything it had.
CREATE FUNCTION private_isg.mutate_emergency_plans(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.emergency_plan_receipts;
  result jsonb; answer jsonb; plan uuid; team jsonb;
  stamp timestamptz:=clock_timestamp(); today date;
BEGIN
  actor:=private_isg.require_emergency_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>16384 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(stamp AT TIME ZONE 'UTC')::date;
  allowed:=CASE p_action
    -- No `needs_review` here: the flag follows from whether a basis was
    -- written, and nothing may set it directly.
    WHEN 'publish_plan' THEN ARRAY['plan_id','workplace_id','scope','prepared_on','valid_until',
      'team','review_note']
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
  -- A renewal must be aimed at a plan this company already holds.
  IF p_payload->>'plan_id' IS NOT NULL THEN
    plan:=(p_payload->>'plan_id')::uuid;
    PERFORM 1 FROM private_isg.emergency_plan_versions
      WHERE plan_id=plan AND company_id=p_company AND owner_id=actor FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  -- A prepared date in the future would be a plan that does not exist yet.
  IF (p_payload->>'prepared_on')::date>today THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PREPARED_IN_THE_FUTURE'; END IF;
  team:=private_isg.emergency_team_snapshot(p_payload->'team');
  answer:=private_isg.publish_emergency_plan(p_company,(p_payload->>'workplace_id')::uuid,plan,
    p_payload->>'scope',(p_payload->>'prepared_on')::date,(p_payload->>'valid_until')::date,
    team,NULL,nullif(btrim(coalesce(p_payload->>'review_note','')),''),stamp);
  plan:=(answer->>'plan_id')::uuid;

  result:=jsonb_build_object('schema_version',1,'action',p_action,'plan_id',plan,'answer',answer,
    'row',private_isg.emergency_plan_row(plan,today,true));
  INSERT INTO private_isg.emergency_plan_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $$;

CREATE FUNCTION public.isg_emergency_plans_read_v1(p_company uuid,p_kind text,p_query text,p_state text,
  p_workplace uuid,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.read_emergency_plans(p_company,p_kind,p_query,p_state,p_workplace,p_id,p_limit,p_offset)
$$;
CREATE FUNCTION public.isg_emergency_plans_mutate_v1(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.mutate_emergency_plans(p_company,p_action,p_operation,p_mutation,p_payload)
$$;

REVOKE ALL ON FUNCTION private_isg.emergency_notice_days(),
  private_isg.emergency_plan_status(date,boolean,integer,date),
  private_isg.emergency_plan_group(text),
  private_isg.emergency_plan_gate(boolean),
  private_isg.require_emergency_company(uuid,boolean),
  private_isg.emergency_team_snapshot(jsonb),
  private_isg.emergency_plan_row(uuid,date,boolean),
  private_isg.read_emergency_plans(uuid,text,text,text,uuid,uuid,integer,integer),
  private_isg.mutate_emergency_plans(uuid,text,uuid,uuid,jsonb),
  public.isg_emergency_plans_read_v1(uuid,text,text,text,uuid,uuid,integer,integer),
  public.isg_emergency_plans_mutate_v1(uuid,text,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.read_emergency_plans(uuid,text,text,text,uuid,uuid,integer,integer),
  private_isg.mutate_emergency_plans(uuid,text,uuid,uuid,jsonb),
  public.isg_emergency_plans_read_v1(uuid,text,text,text,uuid,uuid,integer,integer),
  public.isg_emergency_plans_mutate_v1(uuid,text,uuid,uuid,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
