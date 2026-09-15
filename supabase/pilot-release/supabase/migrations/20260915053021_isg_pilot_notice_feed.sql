-- The header bell. Two things were missing: the client had no way to ask what
-- is due, and the user had no way to say "I saw this" or "hide this".
--
-- Notices are COMPUTED AT READ TIME from the records themselves. Nothing here
-- stores a notice, its wording or its severity; only the reader's own marks
-- are stored. Five claims are structurally impossible:
--   1. A notice never says a push was sent, delivered or read. This file reads
--      no delivery table, and every envelope carries push_delivery_claimed
--      false. Marking a notice read marks THIS list, not a notification.
--   2. Dismissing hides the situation, not the record: the key carries the due
--      date, so when the date moves the notice comes back. The envelope says
--      dismiss_is_permanent false, and no record is ever written or deleted
--      here.
--   3. No date is invented. A record with no due date produces no dated
--      notice; it is simply absent.
--   4. Another owner's record is unreachable: every source joins the actor's
--      own companies and passes the pilot read check.
--   5. A closed module produces no notices, so the bell can never point at a
--      surface the account cannot open.
SET LOCAL lock_timeout='5s';

-- The reader's own marks. One row per (reader, situation).
CREATE TABLE IF NOT EXISTS private_isg.notice_marks (
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  notice_key text NOT NULL CHECK(btrim(notice_key)<>'' AND length(notice_key)<=120),
  read_at timestamptz,
  dismissed_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(owner_id,notice_key),
  CHECK(read_at IS NOT NULL OR dismissed_at IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS notice_mark_owner_idx ON private_isg.notice_marks(owner_id,updated_at DESC);
ALTER TABLE private_isg.notice_marks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.notice_marks FROM PUBLIC,anon,authenticated,service_role;

-- How early each kind starts calling a record due. Four modules already own
-- this number, so the bell asks them rather than keeping a second copy that
-- could silently disagree. The rest have no such function, and their windows
-- are this feature's own reading, not an approved rule. Evrak is absent on
-- purpose: it carries its own window on the obligation.
CREATE OR REPLACE FUNCTION private_isg.notice_window(p_kind text) RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT CASE p_kind
    WHEN 'risk_assessment' THEN private_isg.risk_notice_days()
    WHEN 'emergency_plan' THEN private_isg.emergency_notice_days()
    WHEN 'drill' THEN private_isg.drill_notice_days()
    WHEN 'equipment' THEN private_isg.equipment_notice_days()
    WHEN 'katip_contract' THEN 30
    WHEN 'appointment' THEN 30
    WHEN 'annual_work_item' THEN 14
    WHEN 'board' THEN 14
    WHEN 'board_decision' THEN 7
  END
$$;

-- Which switch governs a kind. Two switches fail differently everywhere else
-- in this schema; here a closed one simply removes the kind from the feed.
CREATE OR REPLACE FUNCTION private_isg.notice_kind_available(p_kind text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT CASE
    WHEN p_kind='risk_assessment'
      THEN coalesce((SELECT read_enabled FROM private_isg.rollout WHERE feature='risk'),false)
    WHEN p_kind='document'
      THEN coalesce((SELECT read_enabled FROM private_isg.rollout WHERE feature='document_tracking'),false)
    ELSE coalesce((SELECT read_enabled FROM private_isg.rollout WHERE feature='modules'),false)
     AND coalesce((SELECT m.read_enabled FROM private_isg.module_registry m WHERE m.module=CASE p_kind
       WHEN 'annual_work_item' THEN 'annual_work_plan'
       WHEN 'board_decision' THEN 'board'
       ELSE p_kind END),false)
  END
$$;

-- Every dated situation the actor owns, before any window or mark is applied.
-- The title is the record's own text; this function writes no prose.
CREATE OR REPLACE FUNCTION private_isg.notice_rows(p_actor uuid,p_company uuid)
RETURNS TABLE(kind text,destination text,company_id uuid,company_name text,record_id uuid,title text,
              due_on date,window_days integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
WITH scoped AS MATERIALIZED (
  SELECT c.id,c.name FROM public.companies c
  WHERE c.user_id=p_actor AND NOT c.is_archived
    AND (p_company IS NULL OR c.id=p_company)
    AND private_isg.p05_pilot_can_read(p_actor,c.id)),
raw AS (
  SELECT 'katip_contract'::text kind,'katipContracts'::text destination,c.id company_id,c.name company_name,
         t.contract_id record_id,t.counterparty title,(t.ends_before-1) due_on
    FROM private_isg.katip_contracts t JOIN scoped c ON c.id=t.company_id
   WHERE NOT t.is_deleted AND t.state='active' AND t.ends_before IS NOT NULL
  UNION ALL
  SELECT 'appointment','appointments',c.id,c.name,t.appointment_id,e.full_name,(t.ends_before-1)
    FROM private_isg.appointments t JOIN scoped c ON c.id=t.company_id
    JOIN private_isg.employees e ON e.id=t.employee_id
   WHERE NOT t.is_deleted AND t.ends_before IS NOT NULL
  UNION ALL
  SELECT 'emergency_plan','emergencyPlans',c.id,c.name,t.plan_id,w.name,t.valid_until
    FROM private_isg.emergency_plan_versions t JOIN scoped c ON c.id=t.company_id
    LEFT JOIN private_isg.workplaces w ON w.id=t.workplace_id
   WHERE NOT t.is_deleted AND t.state='active' AND t.valid_until IS NOT NULL
  UNION ALL
  SELECT 'drill','drills',c.id,c.name,t.drill_id,w.name,t.planned_on
    FROM private_isg.drill_records t JOIN scoped c ON c.id=t.company_id
    LEFT JOIN private_isg.workplaces w ON w.id=t.workplace_id
   WHERE NOT t.is_deleted AND t.state='planned' AND t.planned_on IS NOT NULL
  UNION ALL
  SELECT 'annual_work_item','annualWorkPlans',c.id,c.name,t.item_id,t.activity,t.planned_on
    FROM private_isg.annual_work_plan_items t
    JOIN private_isg.annual_work_plans p ON p.plan_id=t.plan_id
    JOIN scoped c ON c.id=p.company_id
   WHERE NOT t.is_deleted AND NOT p.is_deleted AND t.state='planned' AND t.planned_on IS NOT NULL
  UNION ALL
  SELECT 'board','boardMeetings',c.id,c.name,t.meeting_id,w.name,t.planned_on
    FROM private_isg.board_meetings t JOIN scoped c ON c.id=t.company_id
    LEFT JOIN private_isg.workplaces w ON w.id=t.workplace_id
   WHERE NOT t.is_deleted AND t.state='planned' AND t.planned_on IS NOT NULL
  UNION ALL
  SELECT 'board_decision','boardMeetings',c.id,c.name,t.decision_id,t.decision_no::text,t.due_on
    FROM private_isg.board_decisions t
    JOIN private_isg.board_meetings p ON p.meeting_id=t.meeting_id
    JOIN scoped c ON c.id=p.company_id
   WHERE NOT t.is_deleted AND NOT p.is_deleted AND p.state<>'cancelled'
     AND t.state='open' AND t.due_on IS NOT NULL
  UNION ALL
  SELECT 'risk_assessment','riskAssessments',c.id,c.name,t.assessment_id,w.name,t.valid_until
    FROM private_isg.risk_assessments t JOIN scoped c ON c.id=t.company_id
    LEFT JOIN private_isg.workplaces w ON w.id=t.workplace_id
   WHERE t.valid_until IS NOT NULL
  UNION ALL
  SELECT 'equipment','periodicChecks',c.id,c.name,t.equipment_id,t.serial_tag,i.next_due_on
    FROM private_isg.equipment_items t JOIN scoped c ON c.id=t.company_id
    JOIN LATERAL (SELECT x.next_due_on FROM private_isg.equipment_inspections x
                   WHERE x.equipment_id=t.equipment_id
                   ORDER BY x.performed_on DESC,x.inspection_id DESC LIMIT 1) i ON true
   WHERE NOT t.is_archived AND i.next_due_on IS NOT NULL)
SELECT r.kind,r.destination,r.company_id,r.company_name,r.record_id,
       coalesce(nullif(btrim(r.title),''),'—'),r.due_on,private_isg.notice_window(r.kind)
  FROM raw r WHERE private_isg.notice_kind_available(r.kind)
UNION ALL
-- Evrak carries its own window, and only the newest recorded copy counts.
SELECT 'document','documentChecklist',c.id,c.name,o.obligation_id,o.title,d.valid_until,o.notice_days
  FROM private_isg.document_obligations o JOIN scoped c ON c.id=o.company_id
  JOIN LATERAL (SELECT x.valid_until FROM private_isg.document_obligation_records x
                 WHERE x.obligation_id=o.obligation_id
                 ORDER BY x.issued_on DESC,x.record_id DESC LIMIT 1) d ON true
 WHERE NOT o.is_archived AND d.valid_until IS NOT NULL
   AND private_isg.notice_kind_available('document')
$$;

-- Every situation the actor owns, with the key the client marks it by. The key
-- carries the due date on purpose: a moved date is a new situation.
CREATE OR REPLACE FUNCTION private_isg.notice_keys(p_actor uuid)
RETURNS TABLE(notice_key text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT r.kind||':'||r.record_id::text||':'||coalesce(r.due_on::text,'none')
    FROM private_isg.notice_rows(p_actor,NULL) r
$$;

CREATE OR REPLACE FUNCTION private_isg.read_notice_feed(p_company uuid,p_scope text,p_limit integer)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();
        today date:=(clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::date;
        answer jsonb;
BEGIN
  IF actor IS NULL OR NOT private_isg.p05_pilot_account_enabled(actor,false)
    THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF p_scope IS NULL OR p_scope NOT IN ('active','unread','all')
    THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_limit IS NULL OR p_limit<1 OR p_limit>200
    THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_company IS NOT NULL AND NOT EXISTS(
      SELECT 1 FROM public.companies c WHERE c.id=p_company AND c.user_id=actor AND NOT c.is_archived
        AND private_isg.p05_pilot_can_read(actor,c.id))
    THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  WITH due AS (
    SELECT r.*,r.kind||':'||r.record_id::text||':'||coalesce(r.due_on::text,'none') AS notice_key,
           (r.due_on-today) AS days
      FROM private_isg.notice_rows(actor,p_company) r
     WHERE r.due_on IS NOT NULL AND r.window_days IS NOT NULL
       AND r.due_on<=today+r.window_days),
  marked AS (
    SELECT d.*,m.read_at,m.dismissed_at,
           CASE WHEN d.days<0 THEN 'overdue' ELSE 'soon' END AS severity
      FROM due d LEFT JOIN private_isg.notice_marks m
        ON m.owner_id=actor AND m.notice_key=d.notice_key),
  shown AS (
    SELECT * FROM marked
     WHERE CASE p_scope
             WHEN 'all' THEN true
             WHEN 'unread' THEN dismissed_at IS NULL AND read_at IS NULL
             ELSE dismissed_at IS NULL END)
  SELECT jsonb_build_object(
    'today',today,'generated_at',clock_timestamp(),'company_id',p_company,'scope',p_scope,
    -- What the bell shows, and what it may never be mistaken for.
    'unread',(SELECT count(*) FROM marked WHERE dismissed_at IS NULL AND read_at IS NULL),
    'overdue',(SELECT count(*) FROM marked WHERE dismissed_at IS NULL AND severity='overdue'),
    'total',(SELECT count(*) FROM marked WHERE dismissed_at IS NULL),
    'dismissed',(SELECT count(*) FROM marked WHERE dismissed_at IS NOT NULL),
    'has_more',(SELECT count(*) FROM shown)>p_limit,
    'push_delivery_claimed',false,'dismiss_is_permanent',false,'records_changed',false,
    'rows',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'notice_key',s.notice_key,'kind',s.kind,'destination',s.destination,
        'company_id',s.company_id,'company_name',s.company_name,'record_id',s.record_id,
        'title',s.title,'due_on',s.due_on,'days',s.days,'severity',s.severity,
        'unread',s.read_at IS NULL,'dismissed',s.dismissed_at IS NOT NULL)
      ORDER BY (s.severity='overdue') DESC,s.due_on,s.company_name,s.kind,s.record_id)
      FROM (SELECT * FROM shown ORDER BY (severity='overdue') DESC,due_on,company_name,kind,record_id
             LIMIT p_limit) s),'[]'::jsonb))
  INTO answer;
  RETURN answer;
END $$;

-- Marking is idempotent and writes nothing but the reader's own marks. A key
-- the actor's feed does not currently contain is refused, so the table can not
-- be used as free storage, and stale marks are pruned on every write.
CREATE OR REPLACE FUNCTION private_isg.mark_notices(p_action text,p_keys text[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); touched integer:=0;
        current_keys text[]; valid text[];
BEGIN
  IF actor IS NULL OR NOT private_isg.p05_pilot_account_enabled(actor,true)
    THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF p_action IS NULL OR p_action NOT IN ('read','dismiss','restore','read_all','dismiss_all')
    THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_action IN ('read','dismiss','restore') THEN
    IF p_keys IS NULL OR cardinality(p_keys)=0 OR cardinality(p_keys)>200
      THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  ELSIF p_keys IS NOT NULL THEN
    -- The bulk actions take no list; a payload here would be a second meaning.
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED';
  END IF;

  SELECT coalesce(array_agg(k.notice_key),'{}') INTO current_keys
    FROM private_isg.notice_keys(actor) k;
  IF p_keys IS NULL THEN valid:=current_keys;
  ELSE
    SELECT coalesce(array_agg(DISTINCT x),'{}') INTO valid
      FROM unnest(p_keys) x WHERE x=ANY(current_keys);
    IF cardinality(valid)<>cardinality(ARRAY(SELECT DISTINCT unnest(p_keys)))
      THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='NOTICE_NOT_FOUND'; END IF;
  END IF;

  IF p_action='restore' THEN
    -- Undoing a dismissal restores the notice; a row that carried nothing else
    -- is removed rather than left violating its own rule.
    UPDATE private_isg.notice_marks m SET dismissed_at=NULL,updated_at=now()
     WHERE m.owner_id=actor AND m.notice_key=ANY(valid)
       AND m.dismissed_at IS NOT NULL AND m.read_at IS NOT NULL;
    GET DIAGNOSTICS touched=ROW_COUNT;
    DELETE FROM private_isg.notice_marks m
     WHERE m.owner_id=actor AND m.notice_key=ANY(valid) AND m.read_at IS NULL;
  ELSE
    INSERT INTO private_isg.notice_marks AS t(owner_id,notice_key,read_at,dismissed_at)
    SELECT actor,k,now(),CASE WHEN p_action IN ('dismiss','dismiss_all') THEN now() END
      FROM unnest(valid) k
    ON CONFLICT(owner_id,notice_key) DO UPDATE
      SET read_at=coalesce(t.read_at,excluded.read_at),
          dismissed_at=coalesce(excluded.dismissed_at,t.dismissed_at),
          updated_at=now();
    GET DIAGNOSTICS touched=ROW_COUNT;
  END IF;

  -- A situation that no longer exists keeps no mark.
  DELETE FROM private_isg.notice_marks m
   WHERE m.owner_id=actor AND NOT (m.notice_key=ANY(current_keys));

  RETURN jsonb_build_object('action',p_action,'marked',touched,
    'generated_at',clock_timestamp(),
    'push_delivery_claimed',false,'dismiss_is_permanent',false,'records_changed',false);
END $$;

CREATE OR REPLACE FUNCTION public.isg_pilot_notice_feed_v1(
  p_company uuid DEFAULT NULL,p_scope text DEFAULT 'active',p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.read_notice_feed(p_company,p_scope,p_limit) $$;
CREATE OR REPLACE FUNCTION public.isg_pilot_notice_mark_v1(p_action text,p_keys text[] DEFAULT NULL)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.mark_notices(p_action,p_keys) $$;

REVOKE ALL ON FUNCTION private_isg.notice_window(text),private_isg.notice_kind_available(text),
  private_isg.notice_rows(uuid,uuid),private_isg.notice_keys(uuid),
  private_isg.read_notice_feed(uuid,text,integer),private_isg.mark_notices(text,text[]),
  public.isg_pilot_notice_feed_v1(uuid,text,integer),public.isg_pilot_notice_mark_v1(text,text[])
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.read_notice_feed(uuid,text,integer),
  private_isg.mark_notices(text,text[]),
  public.isg_pilot_notice_feed_v1(uuid,text,integer),public.isg_pilot_notice_mark_v1(text,text[])
  TO authenticated;
NOTIFY pgrst,'reload schema';
