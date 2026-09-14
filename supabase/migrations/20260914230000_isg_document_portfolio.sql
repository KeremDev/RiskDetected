-- P11 second slice: the portfolio read behind Evrak Takibi.
-- Additive. The rollout row is NOT opened here.
--
-- The whole account is answered by one aggregate, not by one read per company:
-- the plan forbids an N+1 sweep over thirty companies every time the page opens.
-- The counts, the per-company summary and the page of rows all come from the
-- same CTE, so the tally can never disagree with the list it is counting.
-- Nothing new is stored: the status is still worked out from the dates here,
-- and no file is attached anywhere.
BEGIN;
SET LOCAL lock_timeout='5s';

CREATE FUNCTION private_isg.read_document_portfolio(p_query text,p_status text,p_company uuid,
  p_kinds text[],p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); today date; needle text;
  page_limit integer; page_offset integer;
  -- Prefixed so a local can never be mistaken for a column of the same name:
  -- the aggregates below alias total, state and states.
  tally_all jsonb; tally_companies jsonb; tally_kinds jsonb; tally_rows jsonb; matching_rows integer;
BEGIN
  PERFORM private_isg.document_tracking_gate(false);
  IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=actor) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF p_status IS NOT NULL AND p_status NOT IN ('missing','due_soon','expired','valid') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  -- The page size is the client's, inside a bound the server owns.
  page_limit:=least(greatest(coalesce(p_limit,10),1),100);
  page_offset:=greatest(coalesce(p_offset,0),0);
  today:=(clock_timestamp() AT TIME ZONE 'UTC')::date;
  needle:=nullif(btrim(coalesce(p_query,'')),'');

  -- One statement: the tally, the per-company summary and the page all read the
  -- same CTE, so the count can never disagree with the list it is counting.
  WITH scope AS (
    SELECT c.id,c.name FROM public.companies c WHERE c.user_id=actor AND NOT c.is_archived
  ), latest AS (
    SELECT DISTINCT ON (r.obligation_id) r.obligation_id,r.valid_until,r.issued_on
    FROM private_isg.document_obligation_records r
    JOIN private_isg.document_obligations o ON o.obligation_id=r.obligation_id
    WHERE o.company_id IN (SELECT id FROM scope)
    ORDER BY r.obligation_id,r.issued_on DESC,r.recorded_at DESC
  ), page AS (
    SELECT o.obligation_id,o.company_id,s.name AS company_name,o.title,o.kind_code,
      private_isg.document_obligation_status(l.valid_until,l.obligation_id IS NOT NULL,o.notice_days,today) AS state,
      l.valid_until,
      -- Worst first: what ran out, then what was never filed, then what is due.
      row_number() OVER (ORDER BY
        CASE private_isg.document_obligation_status(l.valid_until,l.obligation_id IS NOT NULL,o.notice_days,today)
          WHEN 'expired' THEN 0 WHEN 'missing' THEN 1 WHEN 'due_soon' THEN 2 ELSE 3 END,
        l.valid_until NULLS LAST,s.name,o.title,o.obligation_id) AS ordinal
    FROM private_isg.document_obligations o
    JOIN scope s ON s.id=o.company_id
    LEFT JOIN latest l ON l.obligation_id=o.obligation_id
    WHERE o.owner_id=actor AND NOT o.is_archived
  ), scoped AS (
    -- The company page asks one heading at a time, so a per-kind tally that
    -- follows only the company filter lets it read every heading in one call.
    SELECT * FROM page WHERE (p_company IS NULL OR company_id=p_company)
  ), filtered AS (
    SELECT * FROM page
    WHERE (p_status IS NULL OR state=p_status)
      AND (p_company IS NULL OR company_id=p_company)
      AND (p_kinds IS NULL OR kind_code=ANY(p_kinds))
      AND (needle IS NULL OR title ILIKE '%'||needle||'%' OR kind_code ILIKE '%'||needle||'%'
           OR company_name ILIKE '%'||needle||'%')
  )
  SELECT
    -- The headline counts the whole account, before any filter, so selecting a
    -- chip never makes the account look smaller than it is.
    (SELECT coalesce(jsonb_object_agg(state,total),'{}'::jsonb)
       FROM (SELECT state,count(*) AS total FROM page GROUP BY state) tally),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('id',company_id,'name',company_name,
        'total',total,'counts',states) ORDER BY company_name),'[]'::jsonb)
       FROM (SELECT company_id,company_name,count(*) AS total,
               jsonb_object_agg(state,state_total) AS states
             FROM (SELECT company_id,company_name,state,count(*) AS state_total
                   FROM page GROUP BY company_id,company_name,state) per_state
             GROUP BY company_id,company_name) grouped),
    (SELECT coalesce(jsonb_object_agg(kind_code,states),'{}'::jsonb)
       FROM (SELECT kind_code,jsonb_object_agg(state,state_total) AS states
             FROM (SELECT kind_code,state,count(*) AS state_total
                   FROM scoped GROUP BY kind_code,state) per_kind
             GROUP BY kind_code) by_kind),
    (SELECT count(*) FROM filtered),
    (SELECT coalesce(jsonb_agg(entry ORDER BY sort),'[]'::jsonb) FROM (
       SELECT picked.ordinal AS sort,
         private_isg.document_obligation_row(picked.company_id,picked.obligation_id,today)
           ||jsonb_build_object('company_id',picked.company_id,'company_name',picked.company_name) AS entry
       FROM (SELECT * FROM filtered ORDER BY ordinal LIMIT page_limit OFFSET page_offset) picked) built)
  INTO tally_all,tally_companies,tally_kinds,matching_rows,tally_rows;

  RETURN jsonb_build_object('schema_version',1,'kind','portfolio','today',today,
    'counts',tally_all,'companies',tally_companies,'kind_counts',tally_kinds,'rows',tally_rows,
    'total',matching_rows,'returned',jsonb_array_length(tally_rows),
    'has_more',page_offset+jsonb_array_length(tally_rows)<matching_rows,
    -- A tally of tracked documents, never a statement that any company or any
    -- person is compliant, and never a claim that a file is held here.
    'compliance_verdict',NULL,'file_storage_available',false);
END $$;

CREATE FUNCTION public.isg_document_portfolio_v1(p_query text,p_status text,p_company uuid,
  p_kinds text[],p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.read_document_portfolio(p_query,p_status,p_company,p_kinds,p_limit,p_offset)
$$;
REVOKE ALL ON FUNCTION private_isg.read_document_portfolio(text,text,uuid,text[],integer,integer),
  public.isg_document_portfolio_v1(text,text,uuid,text[],integer,integer)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.read_document_portfolio(text,text,uuid,text[],integer,integer),
  public.isg_document_portfolio_v1(text,text,uuid,text[],integer,integer) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
