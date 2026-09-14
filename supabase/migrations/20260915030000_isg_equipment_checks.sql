-- P10 second client slice: the surface behind "Periyodik Kontroller".
-- Additive. No rollout row is added and none is opened: this module rides on
-- the switches P10 already created, so it needs BOTH the `modules` feature and
-- the `equipment` module switch before it answers at all.
--
-- The first P10 slice built the equipment inventory, the per-type inspection
-- period and the inspection record, with the plan's own rules already in them:
-- the period belongs to the equipment TYPE and is never one fixed year for
-- everything, a type with no rule produces NO due date, and a failed
-- inspection produces no due date either. What it never had was a client
-- boundary, and its domain functions carried no ownership check because
-- nothing could reach them.
--
-- Four things this slice makes structurally impossible:
--   1. A due date is never invented. When the type has no rule the row reads
--      'period_unknown' — not 'valid'. A missing period is a gap in the
--      record, never a statement that the equipment is good for another year.
--   2. A period is never presented as a legal requirement unless the expert
--      says where it came from. 'unapproved_fixture' forces needs_review, and
--      the read carries the source and that flag on every row.
--   3. Another owner's equipment cannot be reached. The checked entries verify
--      the company against the signed-in actor before delegating to the domain
--      functions, which were written for a caller that had already scoped them.
--   4. This is not a human health check. The suggestion catalogue is a fixed
--      CHECK in the schema with no health code in it, and no table here holds a
--      person.
BEGIN;
SET LOCAL lock_timeout='5s';

-- The plan lists "kontrolü yapan" among the fields a periodic check record
-- carries. It is the expert's own note of who performed it; the product never
-- treats it as proof of accreditation.
ALTER TABLE private_isg.equipment_inspections
  ADD COLUMN inspector text CHECK(inspector IS NULL OR length(inspector)<=200);
-- Where the equipment stands inside its workplace. The workplace is the scope;
-- this is the shelf, the line or the floor.
ALTER TABLE private_isg.equipment_items
  ADD COLUMN location_note text CHECK(location_note IS NULL OR length(location_note)<=200);

-- Names the client may offer, and nothing else. There is deliberately NO period
-- column here: the plan forbids handing every piece of equipment one fixed
-- period, so a suggested name never arrives with a suggested duration.
CREATE TABLE private_isg.equipment_type_suggestions (
  equipment_type text PRIMARY KEY CHECK(equipment_type IN ('lifting_equipment','crane','forklift',
    'pressure_vessel','compressor','boiler','lift','scaffold','ladder','electrical_installation',
    'earthing','fire_extinguisher','fire_detection','ventilation','power_tool','welding_set',
    'conveyor','press_machine','lathe','other_equipment')),
  ordinal integer NOT NULL CHECK(ordinal BETWEEN 1 AND 999),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(ordinal)
);
INSERT INTO private_isg.equipment_type_suggestions(equipment_type,ordinal) VALUES
  ('lifting_equipment',1),('crane',2),('forklift',3),('pressure_vessel',4),('compressor',5),
  ('boiler',6),('lift',7),('scaffold',8),('ladder',9),('electrical_installation',10),
  ('earthing',11),('fire_extinguisher',12),('fire_detection',13),('ventilation',14),
  ('power_tool',15),('welding_set',16),('conveyor',17),('press_machine',18),('lathe',19),
  ('other_equipment',20);

CREATE TABLE private_isg.equipment_check_receipts (
  actor_id uuid NOT NULL, mutation_id uuid NOT NULL, company_id uuid NOT NULL,
  operation_id uuid NOT NULL, request_hash bytea NOT NULL, response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(actor_id,mutation_id),
  FOREIGN KEY(company_id,actor_id) REFERENCES public.companies(id,user_id) ON DELETE CASCADE
);
CREATE INDEX equipment_check_receipt_company_idx ON private_isg.equipment_check_receipts(company_id,actor_id);
-- The page reads the latest report per item rather than sweeping the whole
-- inspection history. The company/type index the list also needs already
-- exists as equipment_type_idx from the P10 slice, so none is added here.
CREATE INDEX equipment_inspection_latest_idx
  ON private_isg.equipment_inspections(equipment_id,performed_on DESC,inspection_id);

ALTER TABLE private_isg.equipment_type_suggestions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.equipment_check_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;

-- How long before a due date the page starts warning. One number, owned by the
-- server and reported on every read, so the client never invents a window.
CREATE FUNCTION private_isg.equipment_notice_days() RETURNS integer
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$ SELECT 30 $$;

-- What the inventory says about one item today. Nothing is stored: the answer
-- is worked out from the last inspection and the type's period at read time,
-- so no row can carry yesterday's answer.
--
-- 'period_unknown' is the honest answer when an inspection exists but the type
-- has no rule. It is deliberately NOT 'valid': not knowing when something is
-- next due is a gap in the record, not a clean bill.
CREATE FUNCTION private_isg.equipment_check_status(p_next_due date,p_has_inspection boolean,
  p_last_result text,p_notice_days integer,p_today date) RETURNS text
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
BEGIN
  IF NOT p_has_inspection THEN RETURN 'never_inspected'; END IF;
  IF p_last_result='fail' THEN RETURN 'failed'; END IF;
  IF p_next_due IS NULL THEN RETURN 'period_unknown'; END IF;
  IF p_next_due<p_today THEN RETURN 'overdue'; END IF;
  IF p_next_due<=p_today+p_notice_days THEN RETURN 'due_soon'; END IF;
  RETURN 'valid';
END $$;

-- The counters the page shows. Five groups over six states, and every state
-- belongs to exactly one group, so a counter and the filter it carries can
-- never disagree about which rows they cover.
CREATE FUNCTION private_isg.equipment_check_group(p_state text) RETURNS text
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT CASE p_state
    WHEN 'valid' THEN 'current'
    WHEN 'due_soon' THEN 'due_soon'
    WHEN 'overdue' THEN 'overdue'
    WHEN 'failed' THEN 'failed'
    ELSE 'untracked' END
$$;

CREATE FUNCTION private_isg.equipment_check_gate(p_write boolean) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
  PERFORM private_isg.module_gate('equipment',p_write);
END $$;

-- A NULL company is the whole account, and only for reads: every write names
-- the company it writes into. The domain functions below were written for a
-- caller that had already checked ownership; this is that caller.
CREATE FUNCTION private_isg.require_equipment_company(p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor();
BEGIN
  PERFORM private_isg.equipment_check_gate(p_write);
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

-- One item with the period its type carries, the state that period produces
-- today and its inspection history.
CREATE FUNCTION private_isg.equipment_check_row(p_equipment uuid,p_today date,p_history boolean) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE item private_isg.equipment_items; latest private_isg.equipment_inspections;
  rule private_isg.equipment_inspection_rules; notice integer:=private_isg.equipment_notice_days();
  state text;
BEGIN
  SELECT * INTO item FROM private_isg.equipment_items WHERE equipment_id=p_equipment;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO latest FROM private_isg.equipment_inspections
    WHERE equipment_id=p_equipment ORDER BY performed_on DESC,inspection_id LIMIT 1;
  SELECT * INTO rule FROM private_isg.equipment_inspection_rules
    WHERE company_id=item.company_id AND equipment_type=item.equipment_type;
  state:=private_isg.equipment_check_status(latest.next_due_on,latest.inspection_id IS NOT NULL,
    latest.result,notice,p_today);
  RETURN jsonb_build_object(
    'id',item.equipment_id,'company_id',item.company_id,'workplace_id',item.workplace_id,
    'equipment_type',item.equipment_type,'serial_tag',item.serial_tag,
    'acquired_on',item.acquired_on,'location_note',item.location_note,
    'is_archived',item.is_archived,'created_at',item.created_at,
    'state',state,'state_group',private_isg.equipment_check_group(state),
    'state_authority','computed_at_read','notice_days',notice,
    -- The period and where it came from travel together. A period with no
    -- source the expert stands behind is flagged, never dressed up as a rule.
    'period_months',rule.period_months,'period_source',rule.period_source,
    'period_needs_review',CASE WHEN rule.equipment_type IS NULL THEN NULL ELSE rule.needs_review END,
    'period_exception_note',rule.exception_note,
    -- A rule set after a report was filed does not rewrite that report: the due
    -- date stored with it is the one that was worked out at the time. When the
    -- two disagree the row says which, instead of leaving a period on screen
    -- next to a state that seems to ignore it.
    'period_defined_after_report',rule.equipment_type IS NOT NULL AND latest.inspection_id IS NOT NULL
      AND latest.next_due_on IS NULL AND latest.result<>'fail',
    'last_performed_on',latest.performed_on,'last_result',latest.result,
    'last_inspector',latest.inspector,'last_external_ref',latest.external_ref,
    'next_due_on',latest.next_due_on,
    'evidence_asset_id',latest.evidence_asset_id,
    'inspections',CASE WHEN p_history THEN
      (SELECT coalesce(jsonb_agg(jsonb_build_object('id',i.inspection_id,'performed_on',i.performed_on,
          'result',i.result,'next_due_on',i.next_due_on,'period_months',i.period_months,
          'inspector',i.inspector,'external_ref',i.external_ref,'note',i.note,
          'evidence_asset_id',i.evidence_asset_id)
          ORDER BY i.performed_on DESC,i.inspection_id),'[]'::jsonb)
       FROM private_isg.equipment_inspections i WHERE i.equipment_id=p_equipment) END,
    -- A tally of equipment records. Never a statement that a workplace, a
    -- company or a person is compliant, and never a health record.
    'health_record',false);
END $$;

-- ---------------------------------------------------------------------------
-- Read. One aggregate answers the page, the tally, the per-company summary and
-- the per-type tally, so a count can never disagree with the list it counts.
-- ---------------------------------------------------------------------------
CREATE FUNCTION private_isg.read_equipment_checks(p_company uuid,p_kind text,p_query text,p_state text,
  p_workplace uuid,p_type text,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; needle text; today date; notice integer:=private_isg.equipment_notice_days();
  page_limit integer; page_offset integer;
  tally_all jsonb; tally_companies jsonb; tally_types jsonb; tally_rows jsonb; matching_rows integer;
BEGIN
  actor:=private_isg.require_equipment_company(p_company,false);
  IF p_kind IS NULL OR p_kind NOT IN ('catalog','list','detail') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(clock_timestamp() AT TIME ZONE 'UTC')::date;

  IF p_kind='catalog' THEN
    RETURN jsonb_build_object('schema_version',1,'kind','catalog','notice_days',notice,
      -- Names only. There is no period here, because handing every type one
      -- default duration is exactly what the plan refuses.
      'suggestions',(SELECT coalesce(jsonb_agg(jsonb_build_object('code',s.equipment_type,
          'ordinal',s.ordinal) ORDER BY s.ordinal),'[]'::jsonb)
        FROM private_isg.equipment_type_suggestions s),
      'period_defaults_offered',false,
      'rules',(SELECT coalesce(jsonb_agg(jsonb_build_object('equipment_type',r.equipment_type,
          'period_months',r.period_months,'period_source',r.period_source,
          'needs_review',r.needs_review,'exception_note',r.exception_note) ORDER BY r.equipment_type),'[]'::jsonb)
        FROM private_isg.equipment_inspection_rules r WHERE p_company IS NOT NULL AND r.company_id=p_company),
      'workplaces',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name)
          ORDER BY w.name),'[]'::jsonb)
        FROM private_isg.workplaces w
        WHERE p_company IS NOT NULL AND w.company_id=p_company AND w.owner_id=actor AND NOT w.is_archived),
      'health_records_tracked',false);
  END IF;

  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.equipment_items e
      JOIN public.companies c ON c.id=e.company_id AND c.user_id=actor
      WHERE e.equipment_id=p_id AND (p_company IS NULL OR e.company_id=p_company);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'kind','detail','today',today,
      'row',private_isg.equipment_check_row(p_id,today,true));
  END IF;

  IF p_state IS NOT NULL AND p_state NOT IN ('never_inspected','period_unknown','failed','overdue',
    'due_soon','valid','current','untracked') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  page_limit:=least(greatest(coalesce(p_limit,10),1),100);
  page_offset:=greatest(coalesce(p_offset,0),0);
  needle:=nullif(btrim(coalesce(p_query,'')),'');

  WITH scope AS (
    SELECT c.id,c.name FROM public.companies c WHERE c.user_id=actor AND NOT c.is_archived
  ), latest AS (
    SELECT DISTINCT ON (i.equipment_id) i.equipment_id,i.next_due_on,i.result,i.performed_on
    FROM private_isg.equipment_inspections i
    JOIN private_isg.equipment_items e ON e.equipment_id=i.equipment_id
    WHERE e.company_id IN (SELECT id FROM scope)
    ORDER BY i.equipment_id,i.performed_on DESC,i.inspection_id
  ), page AS (
    SELECT e.equipment_id,e.company_id,s.name AS company_name,e.equipment_type,e.serial_tag,
      e.workplace_id,
      private_isg.equipment_check_status(l.next_due_on,l.equipment_id IS NOT NULL,l.result,notice,today) AS entry_state,
      l.next_due_on,
      row_number() OVER (ORDER BY
        -- Worst first: what ran out, then what failed, then what is not
        -- followed at all, then what is due, then what is current.
        CASE private_isg.equipment_check_status(l.next_due_on,l.equipment_id IS NOT NULL,l.result,notice,today)
          WHEN 'overdue' THEN 0 WHEN 'failed' THEN 1 WHEN 'never_inspected' THEN 2
          WHEN 'period_unknown' THEN 3 WHEN 'due_soon' THEN 4 ELSE 5 END,
        l.next_due_on NULLS FIRST,s.name,e.serial_tag,e.equipment_id) AS ordinal
    FROM private_isg.equipment_items e
    JOIN scope s ON s.id=e.company_id
    LEFT JOIN latest l ON l.equipment_id=e.equipment_id
    WHERE e.owner_id=actor AND NOT e.is_archived
  ), scoped AS (
    SELECT * FROM page WHERE (p_company IS NULL OR company_id=p_company)
  ), filtered AS (
    SELECT * FROM scoped
    WHERE (p_workplace IS NULL OR workplace_id=p_workplace)
      AND (p_type IS NULL OR equipment_type=p_type)
      AND (p_state IS NULL OR entry_state=p_state
        OR private_isg.equipment_check_group(entry_state)=p_state)
      AND (needle IS NULL OR serial_tag ILIKE '%'||needle||'%'
           OR equipment_type ILIKE '%'||needle||'%' OR company_name ILIKE '%'||needle||'%')
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
    (SELECT coalesce(jsonb_object_agg(equipment_type,states),'{}'::jsonb) FROM
      (SELECT equipment_type,jsonb_object_agg(entry_state,state_total) AS states FROM
        (SELECT equipment_type,entry_state,count(*) AS state_total FROM scoped
          GROUP BY equipment_type,entry_state) d GROUP BY equipment_type) e),
    (SELECT count(*) FROM filtered),
    (SELECT coalesce(jsonb_agg(entry ORDER BY sort),'[]'::jsonb) FROM (
       SELECT picked.ordinal AS sort,
         private_isg.equipment_check_row(picked.equipment_id,today,false)
           ||jsonb_build_object('company_name',picked.company_name) AS entry
       FROM (SELECT * FROM filtered ORDER BY ordinal LIMIT page_limit OFFSET page_offset) picked) built)
  INTO tally_all,tally_companies,tally_types,matching_rows,tally_rows;

  RETURN jsonb_build_object('schema_version',1,'kind','list','rows',tally_rows,'today',today,
    'counts',tally_all,'companies',tally_companies,'type_counts',tally_types,
    'total',matching_rows,'returned',jsonb_array_length(tally_rows),
    'has_more',page_offset+jsonb_array_length(tally_rows)<matching_rows,
    'limit',page_limit,'offset',page_offset,'notice_days',notice,
    -- A tally of equipment records, never a compliance verdict, and never a
    -- health record about a person.
    'compliance_verdict',NULL,'health_records_tracked',false);
END $$;

-- ---------------------------------------------------------------------------
-- Write. Every action delegates to the P10 domain function that owns the rule,
-- so the due date, the asset check and the uniqueness rules stay in one place.
-- What this adds is the ownership check those functions never had.
-- ---------------------------------------------------------------------------
CREATE FUNCTION private_isg.mutate_equipment_checks(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.equipment_check_receipts;
  result jsonb; answer jsonb; target uuid; item private_isg.equipment_items;
  stamp timestamptz:=clock_timestamp(); today date;
BEGIN
  actor:=private_isg.require_equipment_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>4096 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(stamp AT TIME ZONE 'UTC')::date;
  allowed:=CASE p_action
    WHEN 'set_rule' THEN ARRAY['equipment_type','period_months','period_source','exception_note']
    WHEN 'register_equipment' THEN ARRAY['workplace_id','equipment_type','serial_tag','acquired_on','location_note']
    WHEN 'update_equipment' THEN ARRAY['equipment_id','workplace_id','serial_tag','acquired_on','location_note']
    WHEN 'archive_equipment' THEN ARRAY['equipment_id']
    WHEN 'record_inspection' THEN ARRAY['equipment_id','performed_on','result','inspector',
      'external_ref','note','evidence_asset_id']
    ELSE NULL END;
  IF allowed IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO offending FROM jsonb_object_keys(p_payload) AS keys(key)
    WHERE NOT (key=ANY(allowed)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;

  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-equipment:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.equipment_check_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN prior.response||jsonb_build_object('replayed',true);
  END IF;

  IF p_action='set_rule' THEN
    IF p_payload->>'equipment_type' IS NULL OR p_payload->>'period_months' IS NULL OR
       p_payload->>'period_source' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    answer:=private_isg.set_equipment_inspection_rule(p_company,p_payload->>'equipment_type',
      (p_payload->>'period_months')::integer,p_payload->>'period_source',
      nullif(btrim(coalesce(p_payload->>'exception_note','')),''),stamp);
    result:=jsonb_build_object('schema_version',1,'action',p_action,'rule',answer);
  ELSIF p_action='register_equipment' THEN
    IF p_payload->>'workplace_id' IS NULL OR p_payload->>'equipment_type' IS NULL OR
       p_payload->>'serial_tag' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    answer:=private_isg.register_equipment(p_company,(p_payload->>'workplace_id')::uuid,
      p_payload->>'equipment_type',p_payload->>'serial_tag',
      (p_payload->>'acquired_on')::date,stamp);
    target:=(answer->>'equipment_id')::uuid;
    -- The domain function owns the identity rules; the shelf note is this
    -- slice's own column and is written only for a row it actually created.
    IF NOT (answer->>'replayed')::boolean THEN
      UPDATE private_isg.equipment_items
        SET location_note=nullif(btrim(coalesce(p_payload->>'location_note','')),'')
        WHERE equipment_id=target;
    END IF;
    result:=jsonb_build_object('schema_version',1,'action',p_action,'equipment_id',target,
      'row',private_isg.equipment_check_row(target,today,true));
  ELSE
    target:=(p_payload->>'equipment_id')::uuid;
    SELECT * INTO item FROM private_isg.equipment_items
      WHERE equipment_id=target AND company_id=p_company AND owner_id=actor FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;

    IF p_action='update_equipment' THEN
      IF p_payload ? 'workplace_id' THEN
        PERFORM 1 FROM private_isg.workplaces WHERE id=(p_payload->>'workplace_id')::uuid
          AND company_id=p_company AND owner_id=actor AND NOT is_archived;
        IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      END IF;
      UPDATE private_isg.equipment_items SET
        workplace_id=coalesce((p_payload->>'workplace_id')::uuid,workplace_id),
        serial_tag=coalesce(private_isg.text_value(p_payload->>'serial_tag',100),serial_tag),
        acquired_on=CASE WHEN p_payload ? 'acquired_on' THEN (p_payload->>'acquired_on')::date ELSE acquired_on END,
        location_note=CASE WHEN p_payload ? 'location_note'
          THEN nullif(btrim(coalesce(p_payload->>'location_note','')),'') ELSE location_note END
        WHERE equipment_id=target;
    ELSIF p_action='archive_equipment' THEN
      -- Archiving takes the item off the list. The inspections it already
      -- carries are history and are not deleted.
      UPDATE private_isg.equipment_items SET is_archived=true WHERE equipment_id=target;
    ELSE
      IF p_payload->>'performed_on' IS NULL OR p_payload->>'result' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      -- A report cannot be dated after today: a future inspection has not
      -- happened yet, whatever the form says.
      IF (p_payload->>'performed_on')::date>today THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PERFORMED_IN_THE_FUTURE'; END IF;
      answer:=private_isg.record_equipment_inspection(target,(p_payload->>'performed_on')::date,
        p_payload->>'result',(p_payload->>'evidence_asset_id')::uuid,
        nullif(btrim(coalesce(p_payload->>'external_ref','')),''),
        nullif(btrim(coalesce(p_payload->>'note','')),''),stamp);
      IF NOT (answer->>'replayed')::boolean THEN
        UPDATE private_isg.equipment_inspections
          SET inspector=nullif(btrim(coalesce(p_payload->>'inspector','')),'')
          WHERE inspection_id=(answer->>'inspection_id')::uuid;
      END IF;
    END IF;
    result:=jsonb_build_object('schema_version',1,'action',p_action,'equipment_id',target,
      'row',private_isg.equipment_check_row(target,today,true));
  END IF;

  INSERT INTO private_isg.equipment_check_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $$;

CREATE FUNCTION public.isg_equipment_checks_read_v1(p_company uuid,p_kind text,p_query text,p_state text,
  p_workplace uuid,p_type text,p_id uuid,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.read_equipment_checks(p_company,p_kind,p_query,p_state,p_workplace,p_type,p_id,p_limit,p_offset)
$$;
CREATE FUNCTION public.isg_equipment_checks_mutate_v1(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.mutate_equipment_checks(p_company,p_action,p_operation,p_mutation,p_payload)
$$;

REVOKE ALL ON FUNCTION private_isg.equipment_notice_days(),
  private_isg.equipment_check_status(date,boolean,text,integer,date),
  private_isg.equipment_check_group(text),
  private_isg.equipment_check_gate(boolean),
  private_isg.require_equipment_company(uuid,boolean),
  private_isg.equipment_check_row(uuid,date,boolean),
  private_isg.read_equipment_checks(uuid,text,text,text,uuid,text,uuid,integer,integer),
  private_isg.mutate_equipment_checks(uuid,text,uuid,uuid,jsonb),
  public.isg_equipment_checks_read_v1(uuid,text,text,text,uuid,text,uuid,integer,integer),
  public.isg_equipment_checks_mutate_v1(uuid,text,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.read_equipment_checks(uuid,text,text,text,uuid,text,uuid,integer,integer),
  private_isg.mutate_equipment_checks(uuid,text,uuid,uuid,jsonb),
  public.isg_equipment_checks_read_v1(uuid,text,text,text,uuid,text,uuid,integer,integer),
  public.isg_equipment_checks_mutate_v1(uuid,text,uuid,uuid,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
