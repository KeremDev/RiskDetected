-- Read-only NOVA statistics. No record writes, quota changes or new table access.
SET LOCAL lock_timeout='3s';
CREATE FUNCTION private_isg.statistics_read(p_company uuid,p_months integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); today date:=(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date;
 first_day date; overview jsonb; companies jsonb; ids uuid[]; result jsonb; findings jsonb:=NULL; docs jsonb:=NULL; raw_docs jsonb;
 c uuid; states jsonb; available boolean;
BEGIN
 IF NOT private_isg.p05_pilot_account_enabled(actor,false) THEN RAISE EXCEPTION 'FEATURE_UNAVAILABLE'; END IF;
 IF p_months IS NULL OR p_months NOT IN (1,3,6,12) THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 IF p_company IS NOT NULL THEN PERFORM private_isg.require_company(p_company,false); END IF;
 first_day:=(date_trunc('month',today::timestamp)-make_interval(months=>p_months-1))::date;
 overview:=public.isg_pilot_overview_v1(NULL);
 SELECT coalesce(jsonb_agg(x ORDER BY x->>'name'),'[]'),coalesce(array_agg((x->>'id')::uuid),'{}') INTO companies,ids
 FROM jsonb_array_elements(overview->'companies') x WHERE NOT (x->>'is_archived')::boolean
 AND (p_company IS NULL OR (x->>'id')::uuid=p_company);
 IF p_company IS NOT NULL AND cardinality(ids)=0 THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 -- One company projection per event, then distinct event/person keys across companies.
 WITH training AS MATERIALIZED (
  SELECT r.id,r.company_id,coalesce(r.session_id,r.id) AS event_id,
   (r.starts_at AT TIME ZONE 'Europe/Istanbul')::date AS day
  FROM private_isg.pilot_training_records r LEFT JOIN private_isg.pilot_training_sessions s ON s.id=r.session_id
  WHERE r.owner_id=actor AND r.company_id=ANY(ids) AND r.state='completed'
   AND (r.session_id IS NULL OR (s.owner_id=actor AND s.deleted_at IS NULL))
   AND r.starts_at>=first_day::timestamp AT TIME ZONE 'Europe/Istanbul'
   AND r.starts_at<(today+1)::timestamp AT TIME ZONE 'Europe/Istanbul'
 ), events AS (SELECT event_id,min(day) AS day FROM training GROUP BY event_id), analysis AS MATERIALIZED (
  SELECT a.id,(coalesce(a.completed_at,a.created_at) AT TIME ZONE 'Europe/Istanbul')::date AS day
  FROM public.analyses a WHERE a.user_id=actor AND a.kind='photo' AND a.status='completed'
   AND (a.company_id=ANY(ids) OR (p_company IS NULL AND a.company_id IS NULL))
   AND coalesce(a.completed_at,a.created_at)>=first_day::timestamp AT TIME ZONE 'Europe/Istanbul'
   AND coalesce(a.completed_at,a.created_at)<(today+1)::timestamp AT TIME ZONE 'Europe/Istanbul'
 ), months AS (SELECT generate_series(first_day::timestamp,date_trunc('month',today::timestamp),interval '1 month')::date AS month)
 SELECT jsonb_build_object('schema_version',1,'owner_id',actor,'company_id',p_company,'months',p_months,
  'from_day',first_day,'today',today,'generated_at',clock_timestamp(),
  'companies',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',x->'id','name',x->'name','personnel',x->'personnel_count','workplaces',x->'workplace_count','hazard',x->'hazard_class') ORDER BY x->>'name'),'[]') FROM jsonb_array_elements(overview->'companies') x WHERE NOT (x->>'is_archived')::boolean),
  'company_count',cardinality(ids),'personnel',(SELECT coalesce(sum((x->>'personnel_count')::int),0) FROM jsonb_array_elements(companies) x),
  'workplaces',(SELECT coalesce(sum((x->>'workplace_count')::int),0) FROM jsonb_array_elements(companies) x),
  'analyses',(SELECT count(*) FROM analysis),'trainings',(SELECT count(DISTINCT event_id) FROM training),
  'trained_people',(SELECT count(DISTINCT p.employee_id) FROM training t JOIN private_isg.pilot_training_participants p ON p.training_id=t.id AND p.company_id=t.company_id),
  'training_enrollments',(SELECT count(DISTINCT (t.event_id,p.employee_id)) FROM training t JOIN private_isg.pilot_training_participants p ON p.training_id=t.id AND p.company_id=t.company_id),
  'series',(SELECT jsonb_agg(jsonb_build_object('month',m.month,'analyses',(SELECT count(*) FROM analysis a WHERE date_trunc('month',a.day::timestamp)::date=m.month),
   'trainings',(SELECT count(*) FROM events t WHERE date_trunc('month',t.day::timestamp)::date=m.month)) ORDER BY m.month) FROM months m)
 ) INTO result;
 -- Optional modules may not yet be installed on the narrow pilot. NULL means unavailable, never zero.
 IF to_regclass('private_isg.nonconformities') IS NOT NULL AND to_regprocedure('private_isg.require_nonconformity_company(uuid,boolean)') IS NOT NULL THEN
  EXECUTE 'SELECT coalesce(bool_or(read_enabled),false) FROM private_isg.rollout WHERE feature=''nonconformity''' INTO available;
  IF available THEN
   FOREACH c IN ARRAY ids LOOP EXECUTE 'SELECT private_isg.require_nonconformity_company($1,false)' USING c; END LOOP;
   EXECUTE $q$ SELECT jsonb_build_object(
    'open',count(*) FILTER(WHERE state IN ('open','assigned','in_progress','pending_verification','reopened')),
    'overdue',count(*) FILTER(WHERE state IN ('open','assigned','in_progress','pending_verification','reopened') AND due_on<$3),
    'pending',count(*) FILTER(WHERE state='pending_verification'),
    'opened',count(*) FILTER(WHERE state NOT IN ('draft','cancelled') AND opened_on BETWEEN $4 AND $3),
    'closed',count(*) FILTER(WHERE state='closed' AND closed_on BETWEEN $4 AND $3),
    'severity',jsonb_build_object('critical',count(*) FILTER(WHERE state IN ('open','assigned','in_progress','pending_verification','reopened') AND severity='critical'),
     'high',count(*) FILTER(WHERE state IN ('open','assigned','in_progress','pending_verification','reopened') AND severity='high'),
     'medium',count(*) FILTER(WHERE state IN ('open','assigned','in_progress','pending_verification','reopened') AND severity='medium'),
     'low',count(*) FILTER(WHERE state IN ('open','assigned','in_progress','pending_verification','reopened') AND severity='low')))
    FROM private_isg.nonconformities n WHERE owner_id=$1 AND company_id=ANY($2) AND coalesce(to_jsonb(n)->>'record_kind','nonconformity')='nonconformity' $q$
    INTO findings USING actor,ids,today,first_day;
  END IF;
 END IF;
 IF to_regprocedure('private_isg.read_document_portfolio(text,text,uuid,text[],integer,integer)') IS NOT NULL THEN
  BEGIN
   EXECUTE 'SELECT private_isg.read_document_portfolio(NULL,NULL,NULL,NULL,1,0)' INTO raw_docs;
   SELECT jsonb_build_object('valid',coalesce(sum((x->'counts'->>'valid')::int),0),'missing',coalesce(sum((x->'counts'->>'missing')::int),0),
    'due_soon',coalesce(sum((x->'counts'->>'due_soon')::int),0),'expired',coalesce(sum((x->'counts'->>'expired')::int),0))
   INTO docs FROM jsonb_array_elements(raw_docs->'companies') x WHERE (x->>'id')::uuid=ANY(ids);
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'FEATURE_UNAVAILABLE' THEN RAISE; END IF;
  END;
 END IF;
 RETURN result||jsonb_build_object('findings',findings,'documents',docs);
END $$;
REVOKE ALL ON FUNCTION private_isg.statistics_read(uuid,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.statistics_read(uuid,integer) TO authenticated;
CREATE FUNCTION public.isg_statistics_v1(p_company uuid DEFAULT NULL,p_months integer DEFAULT 6) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.statistics_read(p_company,p_months) $$;
REVOKE ALL ON FUNCTION public.isg_statistics_v1(uuid,integer) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.isg_statistics_v1(uuid,integer) TO authenticated;
