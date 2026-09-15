-- The emergency plan's team editor had to be filled by hand, one name at a
-- time, even when the company already holds a support-staff appointment on
-- record (Atama ve Temsilciler / "Destek elemanı"). This slice makes that
-- roster visible to the plan editor as suggestions the expert picks from; it
-- adds no write path and changes no other module.
--
-- Two things stay true:
--   1. This is a suggestion list, not a link. Picking one only copies a name
--      into the team snapshot the expert is building; the snapshot itself is
--      unchanged (still full_name/role/contact, still frozen at publish
--      time). Nothing here makes the plan's team snapshot a live pointer to
--      an appointment: if the appointment ends tomorrow, an already-published
--      plan's team is untouched, exactly as before.
--   2. A closed Atama ve Temsilciler module produces an empty list here, not
--      an error. The emergency plan catalog must not fail because a
--      different module's switch is off; it simply has nothing to suggest.
--
-- One divergence from the live schema, in the same vein as earlier slices:
-- the live `private_isg.appointments` table carries an `is_deleted` column
-- this dev chain's own appointments migration never added. This file matches
-- the dev schema (no `is_deleted` filter); the pilot-release mirror of this
-- file adds `AND NOT a.is_deleted` to match what is actually live.
CREATE OR REPLACE FUNCTION private_isg.read_emergency_plans(p_company uuid,p_kind text,p_query text,p_state text,
  p_workplace uuid,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; needle text; today date; notice integer:=private_isg.emergency_notice_days();
  page_limit integer; page_offset integer; appointment_module_open boolean;
  tally_all jsonb; tally_companies jsonb; tally_rows jsonb; matching_rows integer;
BEGIN
  actor:=private_isg.require_emergency_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('catalog','list','detail') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(clock_timestamp() AT TIME ZONE 'UTC')::date;

  IF p_kind='catalog' THEN
    -- Read only, and never raised: a closed appointment module just means an
    -- empty suggestion list, not a failed emergency plan catalog.
    appointment_module_open:=coalesce((SELECT read_enabled FROM private_isg.rollout WHERE feature='modules'),false)
      AND coalesce((SELECT m.read_enabled FROM private_isg.module_registry m WHERE m.module='appointment'),false);
    RETURN jsonb_build_object('schema_version',1,'kind','catalog','notice_days',notice,
      'workplaces',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name,
          'needs_review',w.needs_review) ORDER BY w.name),'[]'::jsonb)
        FROM private_isg.workplaces w
        WHERE p_company IS NOT NULL AND w.company_id=p_company AND w.owner_id=actor AND NOT w.is_archived),
      'team_roles',(SELECT coalesce(jsonb_agg(jsonb_build_object('code',r.role_code,'ordinal',r.ordinal)
          ORDER BY r.ordinal),'[]'::jsonb) FROM private_isg.emergency_team_roles r),
      -- Who the company already lists as destek elemanı, so the expert can
      -- pick a name instead of typing it. Company-wide, not workplace-scoped:
      -- the request is "this company's support staff," not one building's.
      'support_staff',(SELECT CASE WHEN p_company IS NOT NULL AND appointment_module_open THEN
          coalesce(jsonb_agg(jsonb_build_object('appointment_id',a.appointment_id,
              'employee_id',a.employee_id,'full_name',e.full_name,
              'workplace_id',a.scope_workplace_id,'workplace_name',w2.name)
            ORDER BY e.full_name),'[]'::jsonb)
        ELSE '[]'::jsonb END
        FROM private_isg.appointments a
        JOIN private_isg.employees e ON e.id=a.employee_id AND e.company_id=a.company_id
        LEFT JOIN private_isg.workplaces w2 ON w2.id=a.scope_workplace_id
        WHERE a.company_id=p_company AND a.kind='support_staff'
          AND (a.ends_before IS NULL OR a.ends_before>=today)),
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
REVOKE ALL ON FUNCTION private_isg.read_emergency_plans(uuid,text,text,text,uuid,uuid,integer,integer)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.read_emergency_plans(uuid,text,text,text,uuid,uuid,integer,integer)
  TO authenticated;
NOTIFY pgrst,'reload schema';
