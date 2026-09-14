-- P09 client slice: the surface behind "Kontrol Listeleri".
-- Additive. No rollout row is added and none is opened: this rides on the
-- `nonconformity` switch the P09 core slice created.
--
-- The core slice built the run, the pinned template version, the item results
-- and the explicit conversion of a failing answer into a nonconformity. Two
-- things were missing rather than merely unreachable:
--
--   1. There was no way to author a template at all. `publish_checklist_version`
--      required a draft that nothing could create, and no template was seeded,
--      so the module could not start a single run.
--   2. `checklist_templates` had no owner. An expert's own list would have
--      landed in a table every account reads, and two experts could not even
--      use the same code.
--
-- Five things this slice makes structurally impossible:
--   1. Another account's template or run cannot be reached, and a code one
--      expert picks can never collide with another's: the stored code is
--      derived from the owner, and the title is what the expert named.
--   2. A failing answer never becomes a nonconformity on its own. Opening one
--      is a separate field in the payload, the core function demands it
--      explicitly, and every read reports `auto_nonconformity: false`.
--   3. A published version is never edited. Changing a list means a new
--      version, and a run pins the version it was filled with, so publishing
--      later cannot rewrite what was answered.
--   4. A run cannot be submitted with an unanswered question, and once
--      submitted no answer can change.
--   5. "Uygulanabilir değil" is only accepted where the template itself said it
--      is allowed.
--
-- The product ships NO ready-made checklist. A question list that arrives in
-- the box reads as a statement of what the law asks for, and no such catalogue
-- has been approved. The expert writes the list, and the screen says so.
BEGIN;
SET LOCAL lock_timeout='5s';

-- Whose list this is. NULL is a product template; none is seeded, and no
-- function here can create one, so the column exists for a later approved
-- catalogue rather than for anything shipping today.
ALTER TABLE private_isg.checklist_templates
  ADD COLUMN owner_id uuid REFERENCES public.profiles(id),
  ADD COLUMN is_archived boolean NOT NULL DEFAULT false;
CREATE INDEX checklist_template_owner_idx ON private_isg.checklist_templates(owner_id,is_archived);

CREATE TABLE private_isg.checklist_receipts (
  actor_id uuid NOT NULL, mutation_id uuid NOT NULL, company_id uuid NOT NULL,
  operation_id uuid NOT NULL, request_hash bytea NOT NULL, response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(actor_id,mutation_id),
  FOREIGN KEY(company_id,actor_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
CREATE INDEX checklist_receipt_company_idx ON private_isg.checklist_receipts(company_id,actor_id);
ALTER TABLE private_isg.checklist_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

-- The stored code is derived from the owner and the name they typed, so the
-- global key can never collide across accounts and reveals nothing about
-- another account's lists.
CREATE FUNCTION private_isg.checklist_template_code(p_owner uuid,p_title text) RETURNS text
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT 'c'||left(md5(p_owner::text||':'||btrim(lower(p_title))),20)
$$;

-- Authoring. A draft is the only editable thing; a published version is not.
CREATE FUNCTION private_isg.draft_checklist_template(p_owner uuid,p_title text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE code text; entry private_isg.checklist_templates; next_version integer; existing integer;
BEGIN
  PERFORM private_isg.nonconformity_gate(true);
  IF p_owner IS NULL OR p_title IS NULL OR btrim(p_title)='' OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  code:=private_isg.checklist_template_code(p_owner,p_title);
  SELECT * INTO entry FROM private_isg.checklist_templates WHERE template_code=code FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO private_isg.checklist_templates(template_code,title,owner_id,created_at)
      VALUES(code,private_isg.text_value(p_title,200),p_owner,p_now);
  ELSIF entry.owner_id IS DISTINCT FROM p_owner THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED';
  END IF;
  -- One draft at a time: a second call returns the draft that is already open.
  SELECT version INTO existing FROM private_isg.checklist_template_versions
    WHERE template_code=code AND status='draft' FOR UPDATE;
  IF existing IS NOT NULL THEN
    RETURN jsonb_build_object('schema_version',1,'template_code',code,'version',existing,
      'status','draft','replayed',true); END IF;
  SELECT coalesce(max(version),0)+1 INTO next_version FROM private_isg.checklist_template_versions
    WHERE template_code=code;
  INSERT INTO private_isg.checklist_template_versions(template_code,version,status,created_at)
    VALUES(code,next_version,'draft',p_now);
  -- A new version starts from what is published, so a small change is a small
  -- edit rather than retyping the whole list.
  INSERT INTO private_isg.checklist_template_items(template_code,version,item_code,prompt,allows_not_applicable,position)
    SELECT i.template_code,next_version,i.item_code,i.prompt,i.allows_not_applicable,i.position
    FROM private_isg.checklist_template_items i
    JOIN private_isg.checklist_template_versions v
      ON v.template_code=i.template_code AND v.version=i.version AND v.status='published'
    WHERE i.template_code=code;
  RETURN jsonb_build_object('schema_version',1,'template_code',code,'version',next_version,
    'status','draft','replayed',false);
END $$;

CREATE FUNCTION private_isg.set_checklist_item(p_code text,p_version integer,p_item text,p_prompt text,
  p_allows_na boolean,p_position integer,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.checklist_template_versions;
BEGIN
  PERFORM private_isg.nonconformity_gate(true);
  IF p_code IS NULL OR p_version IS NULL OR p_item IS NULL OR p_prompt IS NULL OR p_position IS NULL OR
     p_allows_na IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.checklist_template_versions
    WHERE template_code=p_code AND version=p_version FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  -- Only a draft is editable. A published list is what runs were filled
  -- against, so it is never changed under them.
  IF entry.status<>'draft' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='TEMPLATE_PUBLISHED'; END IF;
  INSERT INTO private_isg.checklist_template_items(template_code,version,item_code,prompt,allows_not_applicable,position)
    VALUES(p_code,p_version,p_item,private_isg.text_value(p_prompt,500),p_allows_na,p_position)
  ON CONFLICT(template_code,version,item_code) DO UPDATE SET prompt=excluded.prompt,
    allows_not_applicable=excluded.allows_not_applicable,position=excluded.position;
  RETURN jsonb_build_object('schema_version',1,'template_code',p_code,'version',p_version,
    'item_code',p_item,'position',p_position);
END $$;

CREATE FUNCTION private_isg.remove_checklist_item(p_code text,p_version integer,p_item text) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.checklist_template_versions;
BEGIN
  PERFORM private_isg.nonconformity_gate(true);
  IF p_code IS NULL OR p_version IS NULL OR p_item IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.checklist_template_versions
    WHERE template_code=p_code AND version=p_version FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF entry.status<>'draft' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='TEMPLATE_PUBLISHED'; END IF;
  DELETE FROM private_isg.checklist_template_items
    WHERE template_code=p_code AND version=p_version AND item_code=p_item;
  RETURN jsonb_build_object('schema_version',1,'template_code',p_code,'version',p_version,'item_code',p_item);
END $$;

CREATE FUNCTION private_isg.cancel_checklist_run(p_run uuid,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE run private_isg.checklist_runs;
BEGIN
  PERFORM private_isg.nonconformity_gate(true);
  IF p_run IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO run FROM private_isg.checklist_runs WHERE run_id=p_run FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF run.state='cancelled' THEN
    RETURN jsonb_build_object('schema_version',1,'run_id',p_run,'state','cancelled','replayed',true); END IF;
  -- A submitted run is the record of what was checked; it is not withdrawn.
  IF run.state<>'open' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RUN_SUBMITTED'; END IF;
  UPDATE private_isg.checklist_runs SET state='cancelled' WHERE run_id=p_run;
  RETURN jsonb_build_object('schema_version',1,'run_id',p_run,'state','cancelled','replayed',false);
END $$;

CREATE FUNCTION private_isg.checklist_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM private_isg.nonconformity_gate(p_write);
END $$;

-- A NULL company is the whole account, and only for reads: every write names
-- the company it writes into. The core functions were written for a caller that
-- had already checked ownership; this is that caller.
CREATE FUNCTION private_isg.require_checklist_company(p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  PERFORM private_isg.checklist_gate(p_write);
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

-- A template the actor may use: their own, or a product one. There are no
-- product ones today, and nothing here can create one.
CREATE FUNCTION private_isg.require_checklist_template(p_code text,p_actor uuid,p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE entry private_isg.checklist_templates;
BEGIN
  SELECT * INTO entry FROM private_isg.checklist_templates WHERE template_code=p_code;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  -- Reading a product template is allowed; editing one is not, because it is
  -- not the expert's to change.
  IF p_write THEN
    IF entry.owner_id IS DISTINCT FROM p_actor THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  ELSIF entry.owner_id IS NOT NULL AND entry.owner_id<>p_actor THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED';
  END IF;
END $$;

-- One run with what it was filled against and what it found. Nothing is stored:
-- the tallies are counted from the answers at read time.
CREATE FUNCTION private_isg.checklist_run_row(p_run uuid,p_items boolean) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE run private_isg.checklist_runs; template private_isg.checklist_templates;
  expected integer; answered integer; failing integer; conform integer; skipped integer; opened integer;
BEGIN
  SELECT * INTO run FROM private_isg.checklist_runs WHERE run_id=p_run;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO template FROM private_isg.checklist_templates WHERE template_code=run.template_code;
  SELECT count(*) INTO expected FROM private_isg.checklist_template_items
    WHERE template_code=run.template_code AND version=run.template_version;
  SELECT count(*),count(*) FILTER (WHERE result='nonconform'),
         count(*) FILTER (WHERE result='conform'),
         count(*) FILTER (WHERE result='not_applicable'),
         count(*) FILTER (WHERE nonconformity_id IS NOT NULL)
    INTO answered,failing,conform,skipped,opened
    FROM private_isg.checklist_run_items WHERE run_id=p_run;
  RETURN jsonb_build_object(
    'id',run.run_id,'company_id',run.company_id,'workplace_id',run.workplace_id,
    'template_code',run.template_code,'template_title',template.title,
    -- The version the run was filled against, pinned when it started.
    'template_version',run.template_version,
    'state',run.state,'started_on',run.started_on,'submitted_at',run.submitted_at,
    'expected',expected,'answered',answered,'remaining',greatest(expected-answered,0),
    'conform',conform,'nonconform',failing,'not_applicable',skipped,
    -- How many failing answers the expert chose to turn into a record. It is
    -- never all of them by default, because nothing converts on its own.
    'nonconformities_opened',opened,
    'auto_nonconformity',false,
    'items',CASE WHEN p_items THEN
      (SELECT coalesce(jsonb_agg(jsonb_build_object('item_code',t.item_code,'prompt',t.prompt,
          'position',t.position,'allows_not_applicable',t.allows_not_applicable,
          'result',r.result,'note',r.note,'nonconformity_id',r.nonconformity_id,
          'recorded_at',r.recorded_at) ORDER BY t.position),'[]'::jsonb)
       FROM private_isg.checklist_template_items t
       LEFT JOIN private_isg.checklist_run_items r ON r.run_id=p_run AND r.item_code=t.item_code
       WHERE t.template_code=run.template_code AND t.version=run.template_version) END,
    'compliance_verdict',NULL,'health_records_tracked',false);
END $$;

CREATE FUNCTION private_isg.read_checklists(p_company uuid,p_kind text,p_query text,p_state text,
  p_workplace uuid,p_template text,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; needle text; today date;
  page_limit integer; page_offset integer;
  tally_all jsonb; tally_companies jsonb; tally_rows jsonb; matching_rows integer;
BEGIN
  actor:=private_isg.require_checklist_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('catalog','templates','list','detail') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(clock_timestamp() AT TIME ZONE 'UTC')::date;

  IF p_kind='catalog' THEN
    RETURN jsonb_build_object('schema_version',1,'kind','catalog',
      'workplaces',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,
          'needs_review',w.needs_review) ORDER BY w.name),'[]'::jsonb)
        FROM private_isg.workplaces w
        WHERE p_company IS NOT NULL AND w.company_id=p_company AND w.owner_id=actor AND NOT w.is_archived),
      -- The lists a run may be started from: published only, and only the
      -- expert's own or a product one.
      'templates',(SELECT coalesce(jsonb_agg(jsonb_build_object('template_code',t.template_code,
          'title',t.title,'version',v.version,'items',
          (SELECT count(*) FROM private_isg.checklist_template_items i
            WHERE i.template_code=t.template_code AND i.version=v.version),
          'is_product',t.owner_id IS NULL) ORDER BY t.title),'[]'::jsonb)
        FROM private_isg.checklist_templates t
        JOIN private_isg.checklist_template_versions v
          ON v.template_code=t.template_code AND v.status='published'
        WHERE NOT t.is_archived AND (t.owner_id IS NULL OR t.owner_id=actor)),
      -- Said plainly rather than implied by an empty list: the product does not
      -- ship a question set, because no approved one exists.
      'product_templates_offered',false,
      'auto_nonconformity',false,
      'health_records_tracked',false);
  END IF;

  IF p_kind='templates' THEN
    RETURN jsonb_build_object('schema_version',1,'kind','templates',
      'rows',(SELECT coalesce(jsonb_agg(jsonb_build_object('template_code',t.template_code,'title',t.title,
          'is_product',t.owner_id IS NULL,'is_archived',t.is_archived,
          'versions',(SELECT coalesce(jsonb_agg(jsonb_build_object('version',v.version,'status',v.status,
              'published_at',v.published_at,'approval_note',v.approval_note,
              'items',(SELECT coalesce(jsonb_agg(jsonb_build_object('item_code',i.item_code,'prompt',i.prompt,
                  'position',i.position,'allows_not_applicable',i.allows_not_applicable)
                  ORDER BY i.position),'[]'::jsonb)
                FROM private_isg.checklist_template_items i
                WHERE i.template_code=v.template_code AND i.version=v.version))
              ORDER BY v.version DESC),'[]'::jsonb)
            FROM private_isg.checklist_template_versions v WHERE v.template_code=t.template_code))
          ORDER BY t.title),'[]'::jsonb)
        FROM private_isg.checklist_templates t
        WHERE t.owner_id IS NULL OR t.owner_id=actor),
      -- An expert's approval of their own list is exactly that, and no more.
      'approval_is_self_declared',true,
      'product_templates_offered',false);
  END IF;

  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.checklist_runs r
      JOIN public.companies c ON c.id=r.company_id AND c.user_id=actor
      WHERE r.run_id=p_id AND (p_company IS NULL OR r.company_id=p_company);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'kind','detail','today',today,
      'row',private_isg.checklist_run_row(p_id,true));
  END IF;

  IF p_state IS NOT NULL AND p_state NOT IN ('open','submitted','cancelled') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  page_limit:=least(greatest(coalesce(p_limit,10),1),100);
  page_offset:=greatest(coalesce(p_offset,0),0);
  needle:=nullif(btrim(coalesce(p_query,'')),'');

  WITH scope AS (
    SELECT c.id,c.name FROM public.companies c WHERE c.user_id=actor AND NOT c.is_archived
  ), page AS (
    SELECT r.run_id,r.company_id,s.name AS company_name,r.workplace_id,w.name AS workplace_name,
      r.template_code,t.title AS template_title,r.state AS entry_state,r.started_on,
      -- Open first, because an unfinished run is the one that needs a person.
      row_number() OVER (ORDER BY
        CASE r.state WHEN 'open' THEN 0 WHEN 'submitted' THEN 1 ELSE 2 END,
        r.started_on DESC,s.name,w.name,r.run_id) AS ordinal
    FROM private_isg.checklist_runs r
    JOIN scope s ON s.id=r.company_id
    JOIN private_isg.workplaces w ON w.company_id=r.company_id AND w.id=r.workplace_id
    JOIN private_isg.checklist_templates t ON t.template_code=r.template_code
    WHERE r.owner_id=actor
  ), scoped AS (
    SELECT * FROM page WHERE (p_company IS NULL OR company_id=p_company)
  ), filtered AS (
    SELECT * FROM scoped
    WHERE (p_workplace IS NULL OR workplace_id=p_workplace)
      AND (p_template IS NULL OR template_code=p_template)
      AND (p_state IS NULL OR entry_state=p_state)
      AND (needle IS NULL OR template_title ILIKE '%'||needle||'%'
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
         private_isg.checklist_run_row(picked.run_id,false)
           ||jsonb_build_object('company_name',picked.company_name,
               'workplace_name',picked.workplace_name) AS entry
       FROM (SELECT * FROM filtered ORDER BY ordinal LIMIT page_limit OFFSET page_offset) picked) built)
  INTO tally_all,tally_companies,matching_rows,tally_rows;

  RETURN jsonb_build_object('schema_version',1,'kind','list','rows',tally_rows,'today',today,
    'counts',tally_all,'companies',tally_companies,
    'total',matching_rows,'returned',jsonb_array_length(tally_rows),
    'has_more',page_offset+jsonb_array_length(tally_rows)<matching_rows,
    'limit',page_limit,'offset',page_offset,
    -- A tally of checks that were run, never a statement that any workplace is
    -- compliant, and never a claim that a failing answer became a finding.
    'compliance_verdict',NULL,'auto_nonconformity',false,'health_records_tracked',false);
END $$;

-- Every write goes through the function that owns the rule. This is the
-- boundary: it proves who is asking, allowlists what may be sent, and keeps the
-- receipt so the same request twice is the same answer twice.
CREATE FUNCTION private_isg.mutate_checklists(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.checklist_receipts;
  result jsonb; answer jsonb; run uuid; entry private_isg.checklist_runs;
  stamp timestamptz:=clock_timestamp(); today date;
BEGIN
  actor:=private_isg.require_checklist_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>8192 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(stamp AT TIME ZONE 'UTC')::date;
  allowed:=CASE p_action
    WHEN 'draft_template' THEN ARRAY['title']
    WHEN 'set_item' THEN ARRAY['template_code','version','item_code','prompt','allows_not_applicable','position']
    WHEN 'remove_item' THEN ARRAY['template_code','version','item_code']
    -- No approver here: an expert approves their own list, and the boundary
    -- supplies who that is rather than letting the client name someone.
    WHEN 'publish_template' THEN ARRAY['template_code','version','approval_note']
    WHEN 'start_run' THEN ARRAY['workplace_id','template_code','started_on']
    -- `open_nonconformity` is its own field on purpose: a failing answer never
    -- becomes a record unless this says so.
    WHEN 'record_item' THEN ARRAY['run_id','item_code','result','note','open_nonconformity',
      'severity','due_on']
    WHEN 'submit_run' THEN ARRAY['run_id']
    WHEN 'cancel_run' THEN ARRAY['run_id']
    ELSE NULL END;
  IF allowed IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO offending FROM jsonb_object_keys(p_payload) AS keys(key)
    WHERE NOT (key=ANY(allowed)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;

  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-checklist:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.checklist_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN prior.response||jsonb_build_object('replayed',true);
  END IF;

  IF p_action='draft_template' THEN
    IF p_payload->>'title' IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    answer:=private_isg.draft_checklist_template(actor,p_payload->>'title',stamp);
  ELSIF p_action IN ('set_item','remove_item','publish_template') THEN
    IF p_payload->>'template_code' IS NULL OR p_payload->>'version' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    -- A product template is readable but never editable, and another account's
    -- is neither.
    PERFORM private_isg.require_checklist_template(p_payload->>'template_code',actor,true);
    IF p_action='set_item' THEN
      IF p_payload->>'item_code' IS NULL OR p_payload->>'prompt' IS NULL OR
         p_payload->>'position' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.set_checklist_item(p_payload->>'template_code',(p_payload->>'version')::integer,
        p_payload->>'item_code',p_payload->>'prompt',
        coalesce((p_payload->>'allows_not_applicable')::boolean,true),
        (p_payload->>'position')::integer,stamp);
    ELSIF p_action='remove_item' THEN
      IF p_payload->>'item_code' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.remove_checklist_item(p_payload->>'template_code',
        (p_payload->>'version')::integer,p_payload->>'item_code');
    ELSE
      IF p_payload->>'approval_note' IS NULL OR btrim(p_payload->>'approval_note')='' THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.publish_checklist_version(p_payload->>'template_code',
        (p_payload->>'version')::integer,actor,p_payload->>'approval_note',stamp);
    END IF;
  ELSIF p_action='start_run' THEN
    IF p_payload->>'workplace_id' IS NULL OR p_payload->>'template_code' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.workplaces WHERE company_id=p_company
      AND id=(p_payload->>'workplace_id')::uuid AND owner_id=actor AND NOT is_archived;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    PERFORM private_isg.require_checklist_template(p_payload->>'template_code',actor,false);
    answer:=private_isg.start_checklist_run(p_company,(p_payload->>'workplace_id')::uuid,
      p_payload->>'template_code',
      coalesce((p_payload->>'started_on')::date,today),stamp);
    run:=(answer->>'run_id')::uuid;
  ELSE
    run:=(p_payload->>'run_id')::uuid;
    SELECT * INTO entry FROM private_isg.checklist_runs
      WHERE run_id=run AND company_id=p_company AND owner_id=actor FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF p_action='record_item' THEN
      IF p_payload->>'item_code' IS NULL OR p_payload->>'result' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      answer:=private_isg.record_run_item(run,p_payload->>'item_code',p_payload->>'result',
        nullif(btrim(coalesce(p_payload->>'note','')),''),NULL,
        coalesce((p_payload->>'open_nonconformity')::boolean,false),
        nullif(btrim(coalesce(p_payload->>'severity','')),''),
        (p_payload->>'due_on')::date,stamp);
    ELSIF p_action='submit_run' THEN
      answer:=private_isg.submit_checklist_run(run,stamp);
    ELSE
      answer:=private_isg.cancel_checklist_run(run,stamp);
    END IF;
  END IF;

  result:=jsonb_build_object('schema_version',1,'action',p_action,'answer',answer,
    'run_id',run,'row',CASE WHEN run IS NOT NULL THEN private_isg.checklist_run_row(run,true) END,
    'auto_nonconformity',false);
  INSERT INTO private_isg.checklist_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $$;

CREATE FUNCTION public.isg_checklists_read_v1(p_company uuid,p_kind text,p_query text,p_state text,
  p_workplace uuid,p_template text,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.read_checklists(p_company,p_kind,p_query,p_state,p_workplace,p_template,p_id,p_limit,p_offset)
$$;
CREATE FUNCTION public.isg_checklists_mutate_v1(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.mutate_checklists(p_company,p_action,p_operation,p_mutation,p_payload)
$$;

REVOKE ALL ON FUNCTION private_isg.checklist_template_code(uuid,text),
  private_isg.draft_checklist_template(uuid,text,timestamptz),
  private_isg.set_checklist_item(text,integer,text,text,boolean,integer,timestamptz),
  private_isg.remove_checklist_item(text,integer,text),
  private_isg.cancel_checklist_run(uuid,timestamptz),
  private_isg.checklist_gate(boolean),
  private_isg.require_checklist_company(uuid,boolean),
  private_isg.require_checklist_template(text,uuid,boolean),
  private_isg.checklist_run_row(uuid,boolean),
  private_isg.read_checklists(uuid,text,text,text,uuid,text,uuid,integer,integer),
  private_isg.mutate_checklists(uuid,text,uuid,uuid,jsonb),
  public.isg_checklists_read_v1(uuid,text,text,text,uuid,text,uuid,integer,integer),
  public.isg_checklists_mutate_v1(uuid,text,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.read_checklists(uuid,text,text,text,uuid,text,uuid,integer,integer),
  private_isg.mutate_checklists(uuid,text,uuid,uuid,jsonb),
  public.isg_checklists_read_v1(uuid,text,text,text,uuid,text,uuid,integer,integer),
  public.isg_checklists_mutate_v1(uuid,text,uuid,uuid,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
