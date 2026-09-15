-- "Acil durum planında geçerlilik süresini tehlike sınıfına göre otomatik
-- getir" — same legal periods as risk assessment (6331 m.11/12: az
-- tehlikeli 6, tehlikeli 4, çok tehlikeli 2 yıl), so the client can suggest
-- the same number for a plan's own validity. No new mapping function: reuses
-- private_isg.risk_period_years_for_hazard_class already shipped for Risk
-- Analizi. Additive only — the catalog gains hazard_class and
-- suggested_period_years per workplace; nothing about how a plan is stored
-- changes.

CREATE OR REPLACE FUNCTION private_isg.read_emergency_plans(p_company uuid, p_kind text, p_query text, p_state text, p_workplace uuid, p_id uuid, p_limit integer, p_offset integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; needle text; today date; notice integer:=private_isg.emergency_notice_days();
  page_limit integer; page_offset integer;
  tally_all jsonb; tally_companies jsonb; tally_rows jsonb; matching_rows integer;
BEGIN
  actor:=private_isg.require_emergency_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('catalog','list','detail') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date;

  IF p_kind='catalog' THEN
    RETURN jsonb_build_object('schema_version',1,'kind','catalog','notice_days',notice,
      'workplaces',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,
          'needs_review',w.needs_review,'hazard_class',w.hazard_class,
          'suggested_period_years',private_isg.risk_period_years_for_hazard_class(w.hazard_class)) ORDER BY w.name),'[]'::jsonb)
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
    PERFORM 1 FROM private_isg.live_emergency_plan_versions v
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
    SELECT c.id,c.name FROM public.companies c WHERE c.user_id=actor AND NOT c.is_archived AND private_isg.p05_pilot_can_read(actor,c.id)
  ), page AS (
    SELECT v.plan_id,v.company_id,s.name AS company_name,v.workplace_id,w.name AS workplace_name,
      v.scope AS plan_scope,
      private_isg.emergency_plan_status(v.valid_until,true,notice,today) AS entry_state,
      v.valid_until,v.needs_review,
      row_number() OVER (ORDER BY
        CASE private_isg.emergency_plan_status(v.valid_until,true,notice,today)
          WHEN 'expired' THEN 0 WHEN 'period_unknown' THEN 1 WHEN 'due_soon' THEN 2 ELSE 3 END,
        v.valid_until NULLS FIRST,s.name,w.name,v.plan_id) AS ordinal
    FROM private_isg.live_emergency_plan_versions v
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
END $function$;
