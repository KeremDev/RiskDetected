-- "Senin İçin": every card counts exactly the records of the list it opens.
--
-- The first home feed counted by its own rules, so a card could say "5" and
-- open a list of 4. This aligns each count with the list the card opens:
--   * analyses: the analyses list shows every finished photo analysis of the
--     account by the moment it was made (an organization: the member's own
--     ready analyses in companies it can see), so the feed counts those;
--   * trainings: the training register lists sessions by the day they were
--     held, so the feed counts sessions and their attendees by that day, with
--     the register's own visibility rule;
--   * checks: the checks list also holds the actor's own runs without a
--     company, so the feed counts them too;
--   * nonconformities: the list rows gain created_at and created_by_user_id,
--     so the client can narrow the list to "recorded in these days" and "mine"
--     the way the feed counts. Existing readers ignore the two new keys.
--
-- Only function bodies change. Grants, the organization allowlist and the
-- card contract stay as 20260924183727_isg_home_feed.sql left them.
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION private_isg.home_feed(p_local jsonb, p_client jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  actor uuid := private_isg.active_actor();
  workspace uuid := private_isg.expert_workspace();
  member private_isg.workspace_memberships;
  now_ timestamptz := clock_timestamp();
  today date;
  day0 timestamptz;
  w7 timestamptz;
  w14 timestamptz;
  w30 timestamptz;
  role_ text := 'personal';
  contract integer := 1;
  routes text[];
  can_write boolean := false;
  ids uuid[] := '{}';
  names jsonb := '{}';
  -- Module availability. A disabled module never produces a card.
  modules_on boolean;
  nc_on boolean;
  risk_on boolean;
  tracking_on boolean;
  training_on boolean;
  personnel_on boolean;
  equipment_on boolean;
  ppe_on boolean;
  permit_on boolean;
  emergency_on boolean;
  drill_on boolean;
  -- Module write access. A card that creates or finishes a record also needs
  -- the module open for writing, not only the account.
  nc_write boolean;
  risk_write boolean;
  personnel_write boolean;
  equipment_write boolean;
  emergency_write boolean;
  drill_write boolean;
  -- Signals.
  account_days integer;
  personnel integer := 0;
  workplaces integer := 0;
  an_total integer := 0; an_7 integer := 0; an_prev7 integer := 0; an_30 integer := 0; an_today integer := 0;
  an_last timestamptz; photo_total integer := 0;
  tr_total integer := 0; tr_7 integer := 0; tr_30 integer := 0; tr_last timestamptz; tr_any boolean := false;
  pp_7 integer := 0; pp_prev7 integer := 0; pp_30 integer := 0;
  nc_total integer := 0; nc_7 integer := 0; nc_prev7 integer := 0; nc_last timestamptz;
  nc_drafts integer := 0; nc_overdue integer := 0;
  risk_final integer := 0; risk_drafts integer := 0;
  cl_submitted integer := 0; cl_open integer := 0; cl_any boolean := false;
  drills_due integer := 0;
  eq_any boolean := false; ep_any boolean := false; ppe_any boolean := false; doc_count integer := 0;
  rec_7 integer := 0; rec_prev7 integer := 0; rec_30 integer := 0; days_30 integer := 0;
  modules_7 integer := 0; modules_30 integer := 0;
  lifetime integer := 0;
  dl jsonb;
  dl_expired integer := 0; dl_soon integer := 0;
  used text[] := '{}';
  states jsonb := '{}';
  segment text;
  cands jsonb := '[]';
  item jsonb;
  local_kind text;
  local_ref text;
  local_company uuid;
  local_at timestamptz;
  local_seen text[] := '{}';
  local_route text;
  company_draft boolean := false;
  rec record;
  discover_order integer := 0;
  shown date;
  sort_value numeric;
  top jsonb;
  more jsonb;
  more_total integer;
BEGIN
  IF actor IS NULL OR NOT private_isg.p05_pilot_account_enabled(actor, false) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'FEATURE_UNAVAILABLE';
  END IF;
  p_local := coalesce(p_local, '[]'::jsonb);
  p_client := coalesce(p_client, '{}'::jsonb);
  IF jsonb_typeof(p_local) IS DISTINCT FROM 'array' OR jsonb_array_length(p_local) > 20
     OR octet_length(p_local::text) > 8192
     OR jsonb_typeof(p_client) IS DISTINCT FROM 'object' OR octet_length(p_client::text) > 4096
     OR (p_client ? 'contract' AND (jsonb_typeof(p_client->'contract') IS DISTINCT FROM 'number'
         OR (p_client->>'contract') !~ '^[1-9][0-9]{0,3}$'))
     OR (p_client ? 'routes' AND (jsonb_typeof(p_client->'routes') IS DISTINCT FROM 'array'
         OR jsonb_array_length(p_client->'routes') > 60
         OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_client->'routes') r
                     WHERE jsonb_typeof(r) IS DISTINCT FROM 'string' OR r #>> '{}' !~ '^[a-z_]{2,40}$'))) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'VALIDATION_ERROR';
  END IF;
  contract := coalesce((p_client->>'contract')::integer, 1);
  IF p_client ? 'routes' THEN
    SELECT coalesce(array_agg(r #>> '{}'), '{}') INTO routes FROM jsonb_array_elements(p_client->'routes') r;
  END IF;

  -- Rolling windows in Istanbul days: "last 7 days" is today and the six days
  -- before it, "previous 7 days" the week before that. Timestamps count only
  -- up to now: a record stamped later today is not work done yet.
  today := (now_ AT TIME ZONE 'Europe/Istanbul')::date;
  day0 := today::timestamp AT TIME ZONE 'Europe/Istanbul';
  w7 := (today - 6)::timestamp AT TIME ZONE 'Europe/Istanbul';
  w14 := (today - 13)::timestamp AT TIME ZONE 'Europe/Istanbul';
  w30 := (today - 29)::timestamp AT TIME ZONE 'Europe/Istanbul';

  IF workspace IS NULL THEN
    SELECT coalesce(array_agg(c.id ORDER BY c.id), '{}'), coalesce(jsonb_object_agg(c.id, c.name), '{}')
      INTO ids, names
      FROM public.companies c
     WHERE c.user_id = actor AND NOT c.is_archived
       AND private_isg.p05_pilot_can_read(actor, c.id);
  ELSE
    member := private_isg.workspace_require_member(workspace, ARRAY['owner', 'admin', 'expert'], false);
    role_ := CASE WHEN member.role = 'expert' THEN 'expert' ELSE 'manager' END;
    SELECT coalesce(array_agg(c.id ORDER BY c.id), '{}'), coalesce(jsonb_object_agg(c.id, c.name), '{}')
      INTO ids, names
      FROM public.companies c
     WHERE c.workspace_id = workspace AND NOT c.is_archived
       AND private_isg.expert_company_visible(c.user_id, c.id, actor);
  END IF;
  -- Cards that create or finish a record need write access in this session.
  BEGIN
    can_write := private_isg.p05_pilot_account_enabled(actor, true);
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    can_write := false;
  END;

  modules_on := coalesce((SELECT bool_or(r.read_enabled) FROM private_isg.rollout r WHERE r.feature = 'modules'), false);
  nc_on := coalesce((SELECT bool_or(r.read_enabled) FROM private_isg.rollout r WHERE r.feature = 'nonconformity'), false);
  risk_on := coalesce((SELECT bool_or(r.read_enabled) FROM private_isg.rollout r WHERE r.feature = 'risk'), false);
  tracking_on := coalesce((SELECT bool_or(r.read_enabled) FROM private_isg.rollout r WHERE r.feature = 'document_tracking'), false);
  personnel_on := coalesce((SELECT bool_or(r.read_enabled) FROM private_isg.rollout r WHERE r.feature = 'personnel'), false);
  training_on := coalesce((SELECT bool_or(e.enabled) FROM private_isg.education_controls e WHERE e.key = 'catalog_v1'), false);
  equipment_on := modules_on AND coalesce((SELECT bool_or(m.read_enabled) FROM private_isg.module_registry m WHERE m.module = 'equipment'), false);
  ppe_on := modules_on AND coalesce((SELECT bool_or(m.read_enabled) FROM private_isg.module_registry m WHERE m.module = 'ppe'), false);
  permit_on := modules_on AND coalesce((SELECT bool_or(m.read_enabled) FROM private_isg.module_registry m WHERE m.module = 'work_permit'), false);
  emergency_on := modules_on AND coalesce((SELECT bool_or(m.read_enabled) FROM private_isg.module_registry m WHERE m.module = 'emergency_plan'), false);
  drill_on := modules_on AND coalesce((SELECT bool_or(m.read_enabled) FROM private_isg.module_registry m WHERE m.module = 'drill'), false);
  nc_write := can_write AND nc_on AND coalesce((SELECT bool_or(r.write_enabled) FROM private_isg.rollout r WHERE r.feature = 'nonconformity'), false);
  risk_write := can_write AND risk_on AND coalesce((SELECT bool_or(r.write_enabled) FROM private_isg.rollout r WHERE r.feature = 'risk'), false);
  personnel_write := can_write AND personnel_on AND coalesce((SELECT bool_or(r.write_enabled) FROM private_isg.rollout r WHERE r.feature = 'personnel'), false);
  -- Registry modules follow private_isg.module_gate: the shared 'modules'
  -- rollout and the module's own row must both allow writing.
  equipment_write := can_write AND equipment_on
    AND coalesce((SELECT bool_or(r.write_enabled) FROM private_isg.rollout r WHERE r.feature = 'modules'), false)
    AND coalesce((SELECT bool_or(m.write_enabled) FROM private_isg.module_registry m WHERE m.module = 'equipment'), false);
  emergency_write := can_write AND emergency_on
    AND coalesce((SELECT bool_or(r.write_enabled) FROM private_isg.rollout r WHERE r.feature = 'modules'), false)
    AND coalesce((SELECT bool_or(m.write_enabled) FROM private_isg.module_registry m WHERE m.module = 'emergency_plan'), false);
  drill_write := can_write AND drill_on
    AND coalesce((SELECT bool_or(r.write_enabled) FROM private_isg.rollout r WHERE r.feature = 'modules'), false)
    AND coalesce((SELECT bool_or(m.write_enabled) FROM private_isg.module_registry m WHERE m.module = 'drill'), false);

  SELECT today - (p.created_at AT TIME ZONE 'Europe/Istanbul')::date INTO account_days
    FROM public.profiles p WHERE p.id = actor;

  SELECT count(*) INTO personnel FROM private_isg.employees e
   WHERE e.company_id = ANY(ids) AND NOT e.is_archived;
  SELECT count(*) INTO workplaces FROM private_isg.workplaces w
   WHERE w.company_id = ANY(ids) AND NOT w.is_archived;

  -- Analyses the actor made, exactly as the analyses list shows them, by the
  -- moment they were made: every finished photo analysis of the account
  -- (with or without a company), or in an organization the member's own ready
  -- analyses in companies it can see.
  IF workspace IS NULL THEN
    SELECT count(*), count(*) FILTER (WHERE x.t >= w7), count(*) FILTER (WHERE x.t >= w14 AND x.t < w7),
           count(*) FILTER (WHERE x.t >= w30), count(*) FILTER (WHERE x.t >= day0), max(x.t), count(*)
      INTO an_total, an_7, an_prev7, an_30, an_today, an_last, photo_total
      FROM (SELECT a.created_at AS t FROM public.analyses a
             WHERE a.user_id = actor AND a.kind = 'photo' AND a.status = 'completed') x
     WHERE x.t <= now_;
  ELSE
    SELECT count(*), count(*) FILTER (WHERE x.t >= w7), count(*) FILTER (WHERE x.t >= w14 AND x.t < w7),
           count(*) FILTER (WHERE x.t >= w30), count(*) FILTER (WHERE x.t >= day0), max(x.t),
           count(*) FILTER (WHERE x.kind = 'photo')
      INTO an_total, an_7, an_prev7, an_30, an_today, an_last, photo_total
      FROM (SELECT a.created_at AS t, a.kind FROM private_isg.workspace_analyses a
              JOIN public.companies c ON c.id = a.company_id
             WHERE a.workspace_id = workspace AND a.status = 'ready' AND a.created_by_user_id = actor
               AND private_isg.expert_company_visible(c.user_id, c.id, actor)) x
     WHERE x.t <= now_;
  END IF;

  -- Trainings exactly as the training register lists them: sessions the actor
  -- can see whose every company is readable, by the day they were held, and
  -- in an organization only the member's own. A session counts once; people
  -- are the distinct attendees of its completed company records.
  WITH ses AS MATERIALIZED (
    SELECT s.id, s.held_on FROM private_isg.pilot_training_sessions s
     WHERE s.deleted_at IS NULL AND s.held_on <= today
       -- The visibility rule's own first test, written so an index can apply it.
       AND CASE WHEN workspace IS NULL THEN s.owner_id = actor
                ELSE s.workspace_id = workspace AND s.created_by_user_id = actor END
       AND private_isg.expert_session_visible(s.owner_id, s.id, actor)
       AND EXISTS (SELECT 1 FROM private_isg.pilot_training_records r WHERE r.session_id = s.id)
       AND NOT EXISTS (SELECT 1 FROM private_isg.pilot_training_records r
                        WHERE r.session_id = s.id AND NOT private_isg.p05_pilot_can_read(actor, r.company_id))
  ), tr AS MATERIALIZED (
    SELECT ses.id AS ev, ses.held_on AS d, r.id, r.company_id FROM ses
      JOIN private_isg.pilot_training_records r ON r.session_id = ses.id AND r.state = 'completed'
  ), people AS MATERIALIZED (
    SELECT tr.d, p.employee_id FROM tr
      JOIN private_isg.pilot_training_participants p ON p.training_id = tr.id AND p.company_id = tr.company_id
     WHERE p.attended AND tr.d >= today - 29
  )
  SELECT (SELECT count(DISTINCT ev) FROM tr), (SELECT count(DISTINCT ev) FROM tr WHERE d >= today - 6),
         (SELECT count(DISTINCT ev) FROM tr WHERE d >= today - 29),
         (SELECT max(d)::timestamp AT TIME ZONE 'Europe/Istanbul' FROM tr),
         (SELECT count(DISTINCT employee_id) FROM people WHERE d >= today - 6),
         (SELECT count(DISTINCT employee_id) FROM people WHERE d >= today - 13 AND d < today - 6),
         (SELECT count(DISTINCT employee_id) FROM people)
    INTO tr_total, tr_7, tr_30, tr_last, pp_7, pp_prev7, pp_30;
  tr_any := EXISTS (SELECT 1 FROM private_isg.pilot_training_records r
                     WHERE r.company_id = ANY(ids) AND (workspace IS NULL OR r.created_by_user_id = actor));

  IF nc_on THEN
    SELECT count(*) FILTER (WHERE x.mine AND x.state NOT IN ('draft', 'cancelled') AND x.created_at <= now_),
           count(*) FILTER (WHERE x.mine AND x.state NOT IN ('draft', 'cancelled') AND x.created_at >= w7 AND x.created_at <= now_),
           count(*) FILTER (WHERE x.mine AND x.state NOT IN ('draft', 'cancelled') AND x.created_at >= w14 AND x.created_at < w7),
           max(x.created_at) FILTER (WHERE x.mine AND x.state NOT IN ('draft', 'cancelled') AND x.created_at <= now_),
           count(*) FILTER (WHERE x.mine AND x.state = 'draft'),
           count(*) FILTER (WHERE x.state IN ('open', 'assigned', 'in_progress', 'pending_verification', 'reopened') AND x.due_on < today)
      INTO nc_total, nc_7, nc_prev7, nc_last, nc_drafts, nc_overdue
      FROM (SELECT n.state, n.created_at, n.due_on, (workspace IS NULL OR n.created_by_user_id = actor) AS mine
              FROM private_isg.nonconformities n
             WHERE n.company_id = ANY(ids) AND coalesce(n.record_kind, 'nonconformity') = 'nonconformity') x;
  END IF;

  IF risk_on THEN
    SELECT count(DISTINCT v.assessment_id) FILTER (WHERE v.state IN ('final', 'superseded')),
           count(*) FILTER (WHERE v.state = 'draft')
      INTO risk_final, risk_drafts
      FROM private_isg.risk_assessments a
      JOIN private_isg.risk_assessment_versions v ON v.assessment_id = a.assessment_id
     WHERE a.company_id = ANY(ids) AND (workspace IS NULL OR v.created_by_user_id = actor);
  END IF;

  -- Checks as the checks list holds them: runs in the companies in scope and
  -- the actor's own runs without a company; in an organization, the member's own.
  SELECT count(*) FILTER (WHERE c.state = 'submitted'), count(*) FILTER (WHERE c.state = 'open'), count(*) > 0
    INTO cl_submitted, cl_open, cl_any
    FROM private_isg.checklist_runs c
   WHERE c.state <> 'cancelled' AND (workspace IS NULL OR c.created_by_user_id = actor)
     AND ((c.company_id = ANY(ids) AND private_isg.expert_company_visible(c.owner_id, c.company_id, actor))
          OR (c.company_id IS NULL AND c.owner_id = actor AND c.workspace_id IS NOT DISTINCT FROM workspace));
  IF drill_on THEN
    SELECT count(*) INTO drills_due FROM private_isg.drill_records d
     WHERE d.company_id = ANY(ids) AND NOT d.is_deleted AND d.state = 'planned' AND d.planned_on < today;
  END IF;
  eq_any := EXISTS (SELECT 1 FROM private_isg.equipment_items e
                     WHERE e.company_id = ANY(ids) AND (workspace IS NULL OR e.created_by_user_id = actor));
  ep_any := EXISTS (SELECT 1 FROM private_isg.emergency_plan_versions v
                     WHERE v.company_id = ANY(ids) AND NOT v.is_deleted AND (workspace IS NULL OR v.created_by_user_id = actor));
  ppe_any := EXISTS (SELECT 1 FROM private_isg.ppe_handovers h
                      WHERE h.company_id = ANY(ids) AND NOT h.is_deleted AND (workspace IS NULL OR h.created_by_user_id = actor));
  SELECT count(*) INTO doc_count FROM private_isg.document_obligation_records d
   WHERE d.company_id = ANY(ids) AND d.recorded_at <= now_ AND (workspace IS NULL OR d.recorded_by = actor);

  -- Everything the actor recorded in the last 30 days, one row per record.
  -- Drafts and cancelled rows are not work done. A personnel import can add
  -- hundreds of rows at once, so people count towards active days and module
  -- variety but not towards the number of records.
  WITH ev AS (
    SELECT 'analysis'::text AS m, a.created_at AS t, 1 AS w FROM public.analyses a
     WHERE workspace IS NULL AND a.user_id = actor AND a.kind = 'photo' AND a.status = 'completed' AND a.created_at >= w30
    UNION ALL
    SELECT 'analysis', a.created_at, 1 FROM private_isg.workspace_analyses a
      JOIN public.companies c ON c.id = a.company_id
     WHERE workspace IS NOT NULL AND a.workspace_id = workspace AND a.status = 'ready'
       AND a.created_by_user_id = actor AND a.created_at >= w30
       AND private_isg.expert_company_visible(c.user_id, c.id, actor)
    UNION ALL
    SELECT 'training', min(r.created_at), 1 FROM private_isg.pilot_training_records r
     WHERE r.company_id = ANY(ids) AND r.state <> 'cancelled' AND r.created_at >= w30
       AND (workspace IS NULL OR r.created_by_user_id = actor)
       AND (r.session_id IS NULL OR EXISTS (SELECT 1 FROM private_isg.pilot_training_sessions s
                                             WHERE s.id = r.session_id AND s.deleted_at IS NULL))
     GROUP BY coalesce(r.session_id, r.id)
    UNION ALL
    SELECT 'nonconformity', n.created_at, 1 FROM private_isg.nonconformities n
     WHERE nc_on AND n.company_id = ANY(ids) AND n.state NOT IN ('draft', 'cancelled') AND n.created_at >= w30
       AND (workspace IS NULL OR n.created_by_user_id = actor)
    UNION ALL
    SELECT 'risk', v.finalized_at, 1 FROM private_isg.risk_assessment_versions v
      JOIN private_isg.risk_assessments a ON a.assessment_id = v.assessment_id
     WHERE risk_on AND a.company_id = ANY(ids) AND v.finalized_at >= w30
       AND (workspace IS NULL OR v.created_by_user_id = actor)
    UNION ALL
    SELECT 'checklist', c.submitted_at, 1 FROM private_isg.checklist_runs c
     WHERE c.state = 'submitted' AND c.submitted_at >= w30 AND (workspace IS NULL OR c.created_by_user_id = actor)
       AND ((c.company_id = ANY(ids) AND private_isg.expert_company_visible(c.owner_id, c.company_id, actor))
            OR (c.company_id IS NULL AND c.owner_id = actor AND c.workspace_id IS NOT DISTINCT FROM workspace))
    UNION ALL
    SELECT 'equipment', e.created_at, 1 FROM private_isg.equipment_items e
     WHERE e.company_id = ANY(ids) AND e.created_at >= w30 AND (workspace IS NULL OR e.created_by_user_id = actor)
    UNION ALL
    SELECT 'equipment', i.created_at, 1 FROM private_isg.equipment_inspections i
      JOIN private_isg.equipment_items e ON e.equipment_id = i.equipment_id
     WHERE e.company_id = ANY(ids) AND i.created_at >= w30 AND (workspace IS NULL OR i.created_by_user_id = actor)
    UNION ALL
    SELECT 'emergency_plan', v.created_at, 1 FROM private_isg.emergency_plan_versions v
     WHERE v.company_id = ANY(ids) AND NOT v.is_deleted AND v.created_at >= w30
       AND (workspace IS NULL OR v.created_by_user_id = actor)
    UNION ALL
    SELECT 'drill', d.updated_at, 1 FROM private_isg.drill_records d
     WHERE d.company_id = ANY(ids) AND NOT d.is_deleted AND d.state = 'performed' AND d.updated_at >= w30
       AND (workspace IS NULL OR d.created_by_user_id = actor)
    UNION ALL
    SELECT 'ppe', h.created_at, 1 FROM private_isg.ppe_handovers h
     WHERE h.company_id = ANY(ids) AND NOT h.is_deleted AND h.created_at >= w30
       AND (workspace IS NULL OR h.created_by_user_id = actor)
    UNION ALL
    SELECT 'personnel', e.registered_at, 0 FROM private_isg.employees e
     WHERE e.company_id = ANY(ids) AND e.registered_at >= w30 AND (workspace IS NULL OR e.created_by_user_id = actor)
    UNION ALL
    SELECT 'document', d.recorded_at, 1 FROM private_isg.document_obligation_records d
     WHERE d.company_id = ANY(ids) AND d.recorded_at >= w30 AND (workspace IS NULL OR d.recorded_by = actor)
    UNION ALL
    SELECT 'company', c.created_at, 1 FROM public.companies c
     WHERE workspace IS NULL AND c.id = ANY(ids) AND c.created_at >= w30
  )
  SELECT coalesce(sum(w) FILTER (WHERE t >= w7), 0), coalesce(sum(w) FILTER (WHERE t >= w14 AND t < w7), 0),
         coalesce(sum(w), 0), count(DISTINCT (t AT TIME ZONE 'Europe/Istanbul')::date),
         count(DISTINCT m) FILTER (WHERE t >= w7), count(DISTINCT m)
    INTO rec_7, rec_prev7, rec_30, days_30, modules_7, modules_30
    FROM ev WHERE t <= now_;

  -- The same dated rows and the same classification as the deadline board and
  -- Evrak Takibi: "soon" is each record's own notice window.
  WITH r AS MATERIALIZED (
    SELECT f.kind, f.company_id, f.company_name, f.record_id, f.title, f.due_on,
           CASE WHEN f.due_on < today THEN 'expired'
                WHEN f.due_on <= today + coalesce(f.window_days, 30) THEN 'soon' END AS status
      FROM private_isg.pilot_followup_rows(actor, NULL) f
     WHERE f.due_on IS NOT NULL
  )
  SELECT jsonb_build_object(
    'expired', count(*) FILTER (WHERE status = 'expired'),
    'soon', count(*) FILTER (WHERE status = 'soon'),
    'first_expired', (SELECT jsonb_build_object('kind', x.kind, 'record_id', x.record_id, 'company_id', x.company_id,
        'company_name', x.company_name, 'title', x.title, 'due_on', x.due_on)
      FROM r x WHERE x.status = 'expired' ORDER BY x.due_on, x.company_name, x.kind, x.record_id LIMIT 1),
    'first_soon', (SELECT jsonb_build_object('kind', x.kind, 'record_id', x.record_id, 'company_id', x.company_id,
        'company_name', x.company_name, 'title', x.title, 'due_on', x.due_on)
      FROM r x WHERE x.status = 'soon' ORDER BY x.due_on, x.company_name, x.kind, x.record_id LIMIT 1))
    INTO dl FROM r;
  dl_expired := (dl->>'expired')::integer;
  dl_soon := (dl->>'soon')::integer;

  SELECT coalesce(array_agg(u.feature ORDER BY u.feature), '{}') INTO used
    FROM private_isg.feature_usage u WHERE u.owner_id = actor;
  SELECT coalesce(jsonb_object_agg(s.card_id, jsonb_build_object('dismissed_until', s.dismissed_until, 'shown_on', s.shown_on)), '{}')
    INTO states FROM private_isg.home_card_states s
   WHERE s.owner_id = actor AND s.scope_key = private_isg.home_card_scope(s.card_id, workspace);

  -- The group follows real use. A company is a suggestion of its own, not a
  -- condition: analyses without a company are supported and count.
  lifetime := an_total + tr_total + nc_total + risk_final + cl_submitted + doc_count
    + CASE WHEN eq_any THEN 1 ELSE 0 END + CASE WHEN ep_any THEN 1 ELSE 0 END + CASE WHEN ppe_any THEN 1 ELSE 0 END;
  segment := CASE
    WHEN lifetime < 5 THEN 'new'
    WHEN rec_30 >= 20 AND modules_30 >= 3 AND days_30 >= 6 THEN 'active'
    ELSE 'growing' END;

  -- 1. Situations past their date. They take the main card whenever present.
  IF dl_expired > 0 THEN
    cands := cands || private_isg.home_card('critical.expired', 'critical.expired', 'critical', 'danger', 5, dl_expired,
      jsonb_build_object('count', dl_expired, 'kind', dl#>>'{first_expired,kind}', 'title', dl#>>'{first_expired,title}',
        'company_name', dl#>>'{first_expired,company_name}', 'due_on', dl#>>'{first_expired,due_on}'),
      CASE WHEN dl_expired = 1 THEN jsonb_build_object('route', 'followup_record', 'kind', dl#>>'{first_expired,kind}',
             'id', dl#>>'{first_expired,record_id}', 'company_id', dl#>>'{first_expired,company_id}', 'status', 'expired')
           ELSE jsonb_build_object('route', 'followup', 'status', 'expired') END);
  END IF;
  IF nc_on AND nc_overdue > 0 THEN
    SELECT n.nonconformity_id, n.company_id, n.title, n.due_on INTO rec
      FROM private_isg.nonconformities n
     WHERE n.company_id = ANY(ids) AND coalesce(n.record_kind, 'nonconformity') = 'nonconformity'
       AND n.state IN ('open', 'assigned', 'in_progress', 'pending_verification', 'reopened') AND n.due_on < today
     ORDER BY n.due_on, n.nonconformity_id LIMIT 1;
    cands := cands || private_isg.home_card('critical.nonconformity_overdue', 'critical.nonconformity_overdue', 'critical', 'danger', 6, nc_overdue,
      jsonb_build_object('count', nc_overdue, 'title', rec.title, 'company_name', names->>rec.company_id::text, 'due_on', rec.due_on),
      CASE WHEN nc_overdue = 1 THEN jsonb_build_object('route', 'nonconformity', 'id', rec.nonconformity_id, 'company_id', rec.company_id)
           ELSE jsonb_build_object('route', 'nonconformities', 'status', 'overdue') END);
  END IF;

  -- 2. Unfinished work, most recent first. Each source offers its three latest
  -- items and one card for the rest, which opens the module list.
  FOR item IN SELECT value FROM jsonb_array_elements(p_local) LOOP
    local_kind := item->>'kind';
    local_ref := item->>'ref';
    IF jsonb_typeof(item) IS DISTINCT FROM 'object'
       OR local_kind IS NULL OR local_kind NOT IN ('company_create', 'training_draft', 'emergency_plan_draft', 'risk_wizard', 'emergency_wizard')
       OR local_ref IS NULL OR local_ref !~ '^[A-Za-z0-9_-]{1,64}$'
       OR (item ? 'company_id' AND jsonb_typeof(item->'company_id') <> 'null'
           AND coalesce(item->>'company_id', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
       OR coalesce(item->>'updated_at', '') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}' THEN
      CONTINUE;
    END IF;
    BEGIN
      local_at := least((item->>'updated_at')::timestamptz, now_);
    EXCEPTION WHEN others THEN
      CONTINUE;
    END;
    local_company := nullif(item->>'company_id', '')::uuid;
    local_route := CASE local_kind
      WHEN 'company_create' THEN CASE WHEN workspace IS NULL AND can_write THEN 'company_create' END
      WHEN 'training_draft' THEN CASE WHEN training_on AND can_write THEN 'training_create' END
      WHEN 'emergency_plan_draft' THEN CASE WHEN emergency_write THEN 'emergency_plan_create' END
      WHEN 'risk_wizard' THEN CASE WHEN risk_on THEN 'risk_wizard' END
      WHEN 'emergency_wizard' THEN CASE WHEN emergency_on THEN 'emergency_wizard' END END;
    -- Drafts older than 30 days, repeated entries, drafts for a company the
    -- session can no longer see and drafts this session cannot finish are not
    -- offered.
    IF local_route IS NULL OR local_at < now_ - interval '30 days' OR (local_kind || ':' || local_ref) = ANY(local_seen)
       OR (local_company IS NOT NULL AND NOT local_company = ANY(ids)) THEN
      CONTINUE;
    END IF;
    local_seen := local_seen || (local_kind || ':' || local_ref);
    company_draft := company_draft OR local_kind = 'company_create';
    cands := cands || private_isg.home_card('continue.' || local_kind || ':' || local_ref, 'continue.' || local_kind,
      'continue', 'brand', 10, extract(epoch FROM local_at),
      jsonb_build_object('company_name', names->>local_company::text, 'updated_at', local_at),
      jsonb_build_object('route', local_route, 'ref', local_ref, 'company_id', local_company));
  END LOOP;

  IF nc_write AND nc_drafts > 0 THEN
    FOR rec IN SELECT n.nonconformity_id, n.company_id, n.title, n.updated_at
                 FROM private_isg.nonconformities n
                WHERE n.company_id = ANY(ids) AND n.state = 'draft'
                  AND coalesce(n.record_kind, 'nonconformity') = 'nonconformity'
                  AND (workspace IS NULL OR n.created_by_user_id = actor)
                ORDER BY n.updated_at DESC, n.nonconformity_id LIMIT 3 LOOP
      cands := cands || private_isg.home_card('continue.nonconformity_draft:' || rec.nonconformity_id, 'continue.nonconformity_draft',
        'continue', 'brand', 10, extract(epoch FROM rec.updated_at),
        jsonb_build_object('title', rec.title, 'company_name', names->>rec.company_id::text, 'updated_at', rec.updated_at),
        jsonb_build_object('route', 'nonconformity', 'id', rec.nonconformity_id, 'company_id', rec.company_id));
    END LOOP;
    IF nc_drafts > 3 THEN
      cands := cands || private_isg.home_card('continue.nonconformity_drafts', 'continue.nonconformity_drafts', 'continue', 'brand',
        11, nc_drafts - 3, jsonb_build_object('count', nc_drafts - 3, 'total', nc_drafts),
        jsonb_build_object('route', 'nonconformities', 'status', 'draft', 'mine', workspace IS NOT NULL));
    END IF;
  END IF;

  IF risk_write AND risk_drafts > 0 THEN
    FOR rec IN SELECT a.assessment_id, a.company_id, w.name AS workplace_name, v.updated_at
                 FROM private_isg.risk_assessment_versions v
                 JOIN private_isg.risk_assessments a ON a.assessment_id = v.assessment_id
                 LEFT JOIN private_isg.workplaces w ON w.id = a.workplace_id
                WHERE a.company_id = ANY(ids) AND v.state = 'draft'
                  AND (workspace IS NULL OR v.created_by_user_id = actor)
                ORDER BY v.updated_at DESC, a.assessment_id LIMIT 3 LOOP
      cands := cands || private_isg.home_card('continue.risk_draft:' || rec.assessment_id, 'continue.risk_draft',
        'continue', 'brand', 10, extract(epoch FROM rec.updated_at),
        jsonb_build_object('title', rec.workplace_name, 'company_name', names->>rec.company_id::text, 'updated_at', rec.updated_at),
        jsonb_build_object('route', 'risk_assessment', 'id', rec.assessment_id, 'company_id', rec.company_id));
    END LOOP;
    IF risk_drafts > 3 THEN
      cands := cands || private_isg.home_card('continue.risk_drafts', 'continue.risk_drafts', 'continue', 'brand',
        11, risk_drafts - 3, jsonb_build_object('count', risk_drafts - 3, 'total', risk_drafts),
        jsonb_build_object('route', 'risk_assessments', 'status', 'draft', 'mine', workspace IS NOT NULL));
    END IF;
  END IF;

  IF can_write AND cl_open > 0 THEN
    FOR rec IN SELECT c.run_id, c.company_id, coalesce(nullif(btrim(c.area_label), ''), nullif(btrim(c.equipment_label), '')) AS title,
                      coalesce(c.updated_at, c.created_at) AS changed_at
                 FROM private_isg.checklist_runs c
                WHERE c.state = 'open' AND (workspace IS NULL OR c.created_by_user_id = actor)
                  AND ((c.company_id = ANY(ids) AND private_isg.expert_company_visible(c.owner_id, c.company_id, actor))
                       OR (c.company_id IS NULL AND c.owner_id = actor AND c.workspace_id IS NOT DISTINCT FROM workspace))
                ORDER BY coalesce(c.updated_at, c.created_at) DESC, c.run_id LIMIT 3 LOOP
      cands := cands || private_isg.home_card('continue.checklist_open:' || rec.run_id, 'continue.checklist_open',
        'continue', 'brand', 10, extract(epoch FROM rec.changed_at),
        jsonb_build_object('title', rec.title, 'company_name', names->>rec.company_id::text, 'updated_at', rec.changed_at),
        jsonb_build_object('route', 'checklist_run', 'id', rec.run_id, 'company_id', rec.company_id));
    END LOOP;
    IF cl_open > 3 THEN
      cands := cands || private_isg.home_card('continue.checklists_open', 'continue.checklists_open', 'continue', 'brand',
        11, cl_open - 3, jsonb_build_object('count', cl_open - 3, 'total', cl_open),
        jsonb_build_object('route', 'checklists', 'status', 'open', 'mine', workspace IS NOT NULL));
    END IF;
  END IF;

  -- A drill planned for a day that has passed still waits for its result.
  IF drill_write AND drills_due > 0 THEN
    FOR rec IN SELECT d.drill_id, d.company_id, d.planned_on
                 FROM private_isg.drill_records d
                WHERE d.company_id = ANY(ids) AND NOT d.is_deleted AND d.state = 'planned' AND d.planned_on < today
                ORDER BY d.planned_on DESC, d.drill_id LIMIT 3 LOOP
      cands := cands || private_isg.home_card('continue.drill_result:' || rec.drill_id, 'continue.drill_result',
        'continue', 'brand', 10, extract(epoch FROM rec.planned_on::timestamp),
        jsonb_build_object('company_name', names->>rec.company_id::text, 'due_on', rec.planned_on),
        jsonb_build_object('route', 'drill', 'id', rec.drill_id, 'company_id', rec.company_id));
    END LOOP;
    IF drills_due > 3 THEN
      cands := cands || private_isg.home_card('continue.drill_results', 'continue.drill_results', 'continue', 'brand',
        11, drills_due - 3, jsonb_build_object('count', drills_due - 3, 'total', drills_due),
        jsonb_build_object('route', 'drills', 'status', 'result_due'));
    END IF;
  END IF;

  -- 3. Records coming due. The count is the board's "Yaklaşan" count and the
  -- card opens that same list; it is raised only when the nearest date is
  -- within seven days.
  IF dl_soon > 0 AND (dl#>>'{first_soon,due_on}')::date <= today + 6 THEN
    cands := cands || private_isg.home_card('critical.soon', 'critical.soon', 'critical', 'warning', 15, dl_soon,
      jsonb_build_object('count', dl_soon, 'kind', dl#>>'{first_soon,kind}', 'title', dl#>>'{first_soon,title}',
        'company_name', dl#>>'{first_soon,company_name}', 'due_on', dl#>>'{first_soon,due_on}'),
      CASE WHEN dl_soon = 1 THEN jsonb_build_object('route', 'followup_record', 'kind', dl#>>'{first_soon,kind}',
             'id', dl#>>'{first_soon,record_id}', 'company_id', dl#>>'{first_soon,company_id}', 'status', 'soon')
           ELSE jsonb_build_object('route', 'followup', 'status', 'soon') END);
  END IF;

  -- 4. First steps. A new account is guided before anything else is offered.
  IF workspace IS NULL AND can_write AND cardinality(ids) = 0 AND NOT company_draft THEN
    cands := cands || private_isg.home_card('motivation.first_company', 'motivation.first_company', 'motivation', 'brand',
      CASE WHEN segment = 'new' THEN 25 ELSE 45 END, 3, '{}', jsonb_build_object('route', 'company_create'));
  END IF;
  IF personnel_write AND cardinality(ids) > 0 AND personnel = 0 THEN
    cands := cands || private_isg.home_card('motivation.first_personnel', 'motivation.first_personnel', 'motivation', 'brand',
      CASE WHEN segment = 'new' THEN 26 ELSE 46 END, 2, '{}', jsonb_build_object('route', 'personnel'));
  END IF;
  IF segment = 'new' AND can_write AND photo_total = 0 AND (workspace IS NULL OR cardinality(ids) > 0) THEN
    cands := cands || private_isg.home_card('motivation.first_analysis', 'motivation.first_analysis', 'motivation', 'brand',
      27, 1, '{}', jsonb_build_object('route', 'photo_analysis'));
  END IF;

  -- 5. Progress. Only real, positive numbers; a comparison appears only when
  -- it is an increase over the previous 7 days. Every card opens a list of
  -- exactly the records it counts: the same date range (Istanbul days) and, in
  -- an organization, only the member's own records ("mine"). There is no list
  -- for "records of every kind", so no card counts them.
  IF an_total = 1 AND an_last >= w7 THEN
    IF workspace IS NULL THEN
      SELECT a.id INTO rec FROM public.analyses a
       WHERE a.user_id = actor AND a.kind = 'photo' AND a.status = 'completed' AND a.created_at <= now_
       LIMIT 1;
    ELSE
      SELECT a.id INTO rec FROM private_isg.workspace_analyses a
        JOIN public.companies c ON c.id = a.company_id
       WHERE a.workspace_id = workspace AND a.status = 'ready' AND a.created_by_user_id = actor
         AND a.created_at <= now_ AND private_isg.expert_company_visible(c.user_id, c.id, actor)
       LIMIT 1;
    END IF;
    cands := cands || private_isg.home_card('performance.first_analysis', 'performance.first_analysis', 'performance', 'success',
      30, 100, '{}', jsonb_build_object('route', 'analysis', 'id', rec.id));
  ELSIF an_7 > 0 AND segment <> 'new' THEN
    cands := cands || private_isg.home_card('performance.analyses_7d', 'performance.analyses_7d', 'performance', 'success',
      30, an_7 * 3, jsonb_build_object('count', an_7, 'delta', CASE WHEN an_prev7 > 0 AND an_7 > an_prev7 THEN an_7 - an_prev7 END),
      jsonb_build_object('route', 'analyses', 'status', 'completed', 'from', today - 6, 'to', today, 'mine', workspace IS NOT NULL));
  END IF;
  IF training_on AND pp_7 > 0 AND segment <> 'new' THEN
    cands := cands || private_isg.home_card('performance.trained_people_7d', 'performance.trained_people_7d', 'performance', 'success',
      30, pp_7, jsonb_build_object('count', pp_7, 'sessions', tr_7, 'delta', CASE WHEN pp_prev7 > 0 AND pp_7 > pp_prev7 THEN pp_7 - pp_prev7 END),
      jsonb_build_object('route', 'trainings', 'status', 'completed', 'from', today - 6, 'to', today, 'mine', workspace IS NOT NULL));
  END IF;
  IF nc_on AND nc_7 > 0 AND segment <> 'new' THEN
    cands := cands || private_isg.home_card('performance.nonconformities_7d', 'performance.nonconformities_7d', 'performance', 'success',
      30, nc_7 * 3, jsonb_build_object('count', nc_7, 'delta', CASE WHEN nc_prev7 > 0 AND nc_7 > nc_prev7 THEN nc_7 - nc_prev7 END),
      jsonb_build_object('route', 'nonconformities', 'status', 'recorded', 'from', today - 6, 'to', today, 'mine', workspace IS NOT NULL));
  END IF;
  -- A quiet week still has a month to show.
  IF an_7 = 0 AND pp_7 = 0 AND nc_7 = 0 AND segment <> 'new' THEN
    IF an_30 >= 2 THEN
      cands := cands || private_isg.home_card('performance.analyses_30d', 'performance.analyses_30d', 'performance', 'success',
        31, an_30, jsonb_build_object('count', an_30),
        jsonb_build_object('route', 'analyses', 'status', 'completed', 'from', today - 29, 'to', today, 'mine', workspace IS NOT NULL));
    ELSIF training_on AND pp_30 >= 5 THEN
      cands := cands || private_isg.home_card('performance.trained_people_30d', 'performance.trained_people_30d', 'performance', 'success',
        31, pp_30, jsonb_build_object('count', pp_30, 'sessions', tr_30),
        jsonb_build_object('route', 'trainings', 'status', 'completed', 'from', today - 29, 'to', today, 'mine', workspace IS NOT NULL));
    END IF;
  END IF;

  -- 6. Features the actor has not used. The one the client showed today stays
  -- for the rest of the day; the next day the one shown longest ago (or never)
  -- comes first.
  FOR rec IN SELECT d.key, d.route FROM (VALUES
      ('photo_analysis', 'photo_analysis', segment <> 'new' AND can_write AND photo_total = 0 AND (workspace IS NULL OR cardinality(ids) > 0)),
      ('risk_wizard', 'risk_wizard', risk_on AND NOT 'risk_wizard' = ANY(used)),
      ('nonconformity', 'nonconformity_create', nc_write AND cardinality(ids) > 0 AND nc_total = 0 AND nc_drafts = 0),
      ('training', 'training_create', training_on AND can_write AND cardinality(ids) > 0 AND NOT tr_any),
      ('equipment', 'equipment', equipment_write AND cardinality(ids) > 0 AND NOT eq_any),
      ('emergency_wizard', 'emergency_wizard', emergency_on AND NOT ep_any AND NOT 'emergency_wizard' = ANY(used)),
      ('checklist', 'checklists', can_write AND cardinality(ids) > 0 AND NOT cl_any),
      ('work_permit_forms', 'work_permit_forms', permit_on AND NOT 'work_permit_forms' = ANY(used)),
      ('ppe_form', 'ppe_form', ppe_on AND NOT ppe_any AND NOT 'ppe_form' = ANY(used)),
      ('statistics', 'statistics', (an_total >= 3 OR rec_30 >= 10) AND NOT 'statistics' = ANY(used)),
      ('followup', 'followup', tracking_on AND dl_expired + dl_soon > 0 AND NOT 'followup' = ANY(used))
    ) AS d(key, route, eligible) WHERE d.eligible LOOP
    discover_order := discover_order + 1;
    shown := (states#>>ARRAY['discover.' || rec.key, 'shown_on'])::date;
    sort_value := CASE WHEN shown = today THEN 3000000
                       WHEN shown IS NULL THEN 2000000 - discover_order
                       ELSE 1000000 + (today - shown) * 100 - discover_order END;
    cands := cands || private_isg.home_card('discover.' || rec.key, 'discover.' || rec.key, 'discover', 'feature',
      40, sort_value, '{}', jsonb_build_object('route', rec.route));
  END LOOP;

  -- 7. Gentle fallbacks, so the section is never empty.
  IF can_write AND an_total > 0 AND an_today = 0 THEN
    cands := cands || private_isg.home_card('motivation.today_analysis', 'motivation.today_analysis', 'motivation', 'brand',
      60, 1, '{}', jsonb_build_object('route', 'photo_analysis'));
  END IF;
  IF an_total > 0 OR rec_30 > 0 THEN
    cands := cands || private_isg.home_card('motivation.statistics', 'motivation.statistics', 'motivation', 'brand',
      61, 1, '{}', jsonb_build_object('route', 'statistics'));
  END IF;
  IF can_write AND (workspace IS NULL OR cardinality(ids) > 0) THEN
    cands := cands || private_isg.home_card('motivation.photo_analysis', 'motivation.photo_analysis', 'motivation', 'brand',
      90, 0, '{}', jsonb_build_object('route', 'photo_analysis'));
  END IF;

  -- Rank: priority, then the card's own order. Dismissed cards wait out their
  -- cooldown, and a client only gets cards of its contract that it can open.
  -- The section takes three cards: at most two of a kind and one suggestion.
  -- "Tümü" lists every remaining critical, unfinished and progress card, plus
  -- the next three suggestions and the next two first steps, up to 30.
  WITH c AS (
    SELECT x, (x->>'priority')::integer AS p, (x->>'sort')::numeric AS s, x->>'kind' AS k, x->>'id' AS id
      FROM jsonb_array_elements(cands) x
     WHERE (x->>'kind' = 'critical'
            OR coalesce((states#>>ARRAY[x->>'id', 'dismissed_until'])::timestamptz <= now_, true))
       -- A card added after contract 1 carries "since"; older clients never get it.
       AND coalesce((x->>'since')::integer, 1) <= contract
       AND (routes IS NULL OR x#>>'{target,route}' = ANY(routes))
  ), ranked AS (
    SELECT c.*, row_number() OVER (ORDER BY p, s DESC, id) AS n,
           row_number() OVER (PARTITION BY k ORDER BY p, s DESC, id) AS kn
      FROM c
  ), picked AS (
    SELECT * FROM ranked WHERE kn <= CASE WHEN k = 'discover' THEN 1 ELSE 2 END ORDER BY n LIMIT 3
  ), rest AS (
    SELECT * FROM ranked
     WHERE id NOT IN (SELECT id FROM picked)
       AND (k NOT IN ('discover', 'motivation')
            OR (k = 'discover' AND kn <= 3 + (SELECT count(*) FROM picked WHERE picked.k = 'discover'))
            OR (k = 'motivation' AND kn <= 2 + (SELECT count(*) FROM picked WHERE picked.k = 'motivation')))
  )
  SELECT coalesce((SELECT jsonb_agg(x - 'sort' - 'priority' - 'since' ORDER BY n) FROM picked), '[]'),
         coalesce((SELECT jsonb_agg(r.x - 'sort' - 'priority' - 'since' ORDER BY r.n) FROM (SELECT * FROM rest ORDER BY n LIMIT 30) r), '[]'),
         (SELECT count(*) FROM rest)
    INTO top, more, more_total;

  RETURN jsonb_build_object(
    'schema_version', 1, 'contract', 1, 'generated_at', now_, 'today', today, 'role', role_, 'segment', segment,
    'signals', jsonb_build_object(
      'account_days', account_days, 'companies', cardinality(ids), 'workplaces', workplaces, 'personnel', personnel,
      'can_write', can_write,
      'analyses', jsonb_build_object('total', an_total, 'photo', photo_total, 'last7', an_7, 'prev7', an_prev7,
        'last30', an_30, 'today', an_today, 'last_at', an_last),
      'trainings', CASE WHEN training_on THEN jsonb_build_object('total', tr_total, 'last7', tr_7, 'last30', tr_30, 'last_at', tr_last,
        'people_last7', pp_7, 'people_prev7', pp_prev7, 'people_last30', pp_30) END,
      'nonconformities', CASE WHEN nc_on THEN jsonb_build_object('total', nc_total, 'last7', nc_7, 'prev7', nc_prev7,
        'drafts', nc_drafts, 'overdue', nc_overdue, 'last_at', nc_last) END,
      'risk_assessments', CASE WHEN risk_on THEN jsonb_build_object('final', risk_final, 'drafts', risk_drafts) END,
      'checklists', jsonb_build_object('submitted', cl_submitted, 'open', cl_open),
      'drills_due', CASE WHEN drill_on THEN drills_due END,
      'records', jsonb_build_object('last7', rec_7, 'prev7', rec_prev7, 'last30', rec_30,
        'active_days30', days_30, 'modules7', modules_7, 'modules30', modules_30, 'lifetime', lifetime),
      'deadlines', jsonb_build_object('expired', dl_expired, 'soon', dl_soon),
      'features_used', to_jsonb(used)),
    'cards', top, 'more', more, 'more_total', more_total, 'has_more', more_total > jsonb_array_length(more));
END $$;

CREATE OR REPLACE FUNCTION private_isg.read_nonconformities(p_company uuid, p_kind text, p_query text, p_state text, p_after uuid, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      FROM private_isg.workplaces w WHERE w.company_id=p_company AND private_isg.expert_company_visible(w.owner_id,w.company_id,actor) AND NOT w.is_archived;
    RETURN jsonb_build_object('schema_version',1,'kind','workplaces','rows',rows);
  END IF;
  IF p_state IS NOT NULL AND p_state NOT IN ('draft','open','assigned','in_progress','pending_verification',
      'closed','reopened','cancelled') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  needle:=nullif(btrim(coalesce(p_query,'')),'');
  -- 'row' is a keyword-shaped alias; name it something the parser cannot claim.
  SELECT coalesce(jsonb_agg(entry ORDER BY (entry->>'opened_on') DESC,(entry->>'id')),'[]'::jsonb) INTO rows FROM (
    SELECT jsonb_build_object('id',n.nonconformity_id,'workplace_id',n.workplace_id,'title',n.title,
      'severity',n.severity,'state',n.state,'version',n.version,'opened_on',n.opened_on,'due_on',n.due_on,
      'record_kind',n.record_kind,'risk_band',d.risk_band,
      'source_kind',n.source_kind,'source_ref',n.source_ref,
      'created_at',n.created_at,'created_by_user_id',n.created_by_user_id) AS entry
    FROM private_isg.nonconformities n
    LEFT JOIN private_isg.nonconformity_details d ON d.nonconformity_id=n.nonconformity_id
    WHERE n.company_id=p_company AND private_isg.expert_company_visible(n.owner_id,n.company_id,actor)
      AND (p_state IS NULL OR n.state=p_state)
      AND (needle IS NULL OR n.title ILIKE '%'||needle||'%')
      AND (p_after IS NULL OR n.nonconformity_id<>p_after)
    ORDER BY n.opened_on DESC,n.nonconformity_id LIMIT 200) page;
  RETURN jsonb_build_object('schema_version',1,'kind','list','rows',rows,'legacy_findings_written',false);
END $function$;

NOTIFY pgrst, 'reload schema';
