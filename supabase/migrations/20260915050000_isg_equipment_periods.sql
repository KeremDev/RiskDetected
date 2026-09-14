-- P10 third slice: default inspection periods, an editable next date and the
-- expert's own İSG-KATİP declaration. Additive. No switch is added or opened.
--
-- The previous slice shipped no default period for any type, on the grounds
-- that §10.2 has no approved rule catalogue yet. The owner has decided the
-- module must come with periods defined, so this adds them — and makes the
-- attribution carry the whole weight of that decision rather than hiding it:
--
--   1. A default is never the expert's own determination. It lands as
--      period_source='regulation_default' and the schema FORCES needs_review on
--      it, exactly as it already does for an unapproved fixture. Every screen
--      that prints a period prints its source beside it.
--   2. The expert cannot set that source themselves. set_equipment_inspection_rule
--      accepts only manufacturer, rule_version and unapproved_fixture, so
--      'regulation_default' can only ever mean "this is the product's default,
--      nobody has confirmed it for this company yet". Editing it means choosing
--      a source the expert stands behind, which clears the flag.
--   3. The default is one general period, not a per-sector determination, and
--      the basis note on every row says so.
--
-- The next date stays the server's answer by default and becomes the expert's
-- when they change it: due_source records which, so a date nobody derived can
-- never be presented as one the period produced.
--
-- The İSG-KATİP mark is the expert's own declaration and nothing else. It
-- carries the same structural guarantee the KATİP contract table already has:
-- a column that can only ever be false, so no row can claim this product
-- verified anything in the official system.
BEGIN;
SET LOCAL lock_timeout='5s';

-- The general period the product starts a type at. Separate from the name
-- catalogue, because a name is a name and a period is a claim that needs its
-- own basis written next to it.
CREATE TABLE private_isg.equipment_default_periods (
  equipment_type text PRIMARY KEY REFERENCES private_isg.equipment_type_suggestions(equipment_type),
  period_months integer NOT NULL CHECK(period_months BETWEEN 1 AND 240),
  basis_note text NOT NULL CHECK(length(basis_note) BETWEEN 20 AND 500),
  created_at timestamptz NOT NULL DEFAULT now()
);
-- One general period, stated as one. The annex's own rule is "yearly unless
-- something else is specified", so that is what ships; a standard, a manual or
-- a sector exception is the expert's to enter, and the note says so on the row.
INSERT INTO private_isg.equipment_default_periods(equipment_type,period_months,basis_note)
SELECT s.equipment_type,12,
  'Yönetmelik ekinde aksi belirtilmedikçe genel periyot bir yıldır. Standart, '||
  'üretici kılavuzu veya sektör istisnası farklı bir süre öngörüyorsa uzman değiştirir.'
FROM private_isg.equipment_type_suggestions s;

-- A default is flagged for the expert's confirmation the same way an
-- unapproved fixture is. The schema forces it; no function can opt out.
ALTER TABLE private_isg.equipment_inspection_rules
  DROP CONSTRAINT equipment_inspection_rules_period_source_check;
ALTER TABLE private_isg.equipment_inspection_rules
  ADD CONSTRAINT equipment_inspection_rules_period_source_check
  CHECK(period_source IN ('manufacturer','rule_version','unapproved_fixture','regulation_default'));
ALTER TABLE private_isg.equipment_inspection_rules
  ADD CONSTRAINT equipment_inspection_rules_default_needs_review_check
  CHECK(period_source<>'regulation_default' OR needs_review);

-- Which answer the stored next date is: the one the period produced, or the one
-- the expert wrote. A date nobody derived is never presented as derived.
ALTER TABLE private_isg.equipment_inspections
  ADD COLUMN due_source text CHECK(due_source IS NULL OR due_source IN ('period','expert'));
-- The expert's own note that an assignment was made in İSG-KATİP for this
-- check. Optional, and never a verification.
ALTER TABLE private_isg.equipment_inspections
  ADD COLUMN katip_assignment_declared boolean NOT NULL DEFAULT false,
  ADD COLUMN katip_declared_note text CHECK(katip_declared_note IS NULL OR length(katip_declared_note)<=200),
  -- Same guarantee the KATİP contract table carries: this can only be false,
  -- so no row can ever say the official system was checked.
  ADD COLUMN katip_official_verification boolean NOT NULL DEFAULT false
    CHECK(NOT katip_official_verification),
  ADD CONSTRAINT equipment_inspection_katip_note_check
    CHECK(katip_assignment_declared OR katip_declared_note IS NULL);

-- Materialises the default period as a real, visible, editable company rule the
-- first time a type is used. Nothing is hidden: the rule shows up in the period
-- list with its source and its review flag.
CREATE FUNCTION private_isg.ensure_equipment_period(p_company uuid,p_type text,p_now timestamptz) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE fallback private_isg.equipment_default_periods;
BEGIN
  PERFORM 1 FROM private_isg.equipment_inspection_rules
    WHERE company_id=p_company AND equipment_type=p_type FOR SHARE;
  IF FOUND THEN RETURN; END IF;
  SELECT * INTO fallback FROM private_isg.equipment_default_periods WHERE equipment_type=p_type;
  -- A type the product has no default for keeps no period at all, and the row
  -- goes on reading 'period_unknown' rather than borrowing another type's.
  IF NOT FOUND THEN RETURN; END IF;
  INSERT INTO private_isg.equipment_inspection_rules(company_id,equipment_type,period_months,
      period_source,exception_note,needs_review,created_at)
    VALUES(p_company,p_type,fallback.period_months,'regulation_default',fallback.basis_note,true,p_now)
  ON CONFLICT(company_id,equipment_type) DO NOTHING;
END $$;

-- What the period would produce for a given report date, so the boundary can
-- tell the server's own answer apart from the expert's without recomputing the
-- rule in two places.
CREATE FUNCTION private_isg.equipment_period_due(p_company uuid,p_type text,p_performed_on date,
  p_result text) RETURNS date
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT CASE WHEN p_result='fail' THEN NULL
    ELSE (p_performed_on+make_interval(months=>r.period_months))::date END
  FROM private_isg.equipment_inspection_rules r
  WHERE r.company_id=p_company AND r.equipment_type=p_type
$$;

-- The row gains the three new facts, and the history carries them per report.
CREATE OR REPLACE FUNCTION private_isg.equipment_check_row(p_equipment uuid,p_today date,p_history boolean) RETURNS jsonb
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
    'period_months',rule.period_months,'period_source',rule.period_source,
    'period_needs_review',CASE WHEN rule.equipment_type IS NULL THEN NULL ELSE rule.needs_review END,
    'period_exception_note',rule.exception_note,
    'period_defined_after_report',rule.equipment_type IS NOT NULL AND latest.inspection_id IS NOT NULL
      AND latest.next_due_on IS NULL AND latest.result<>'fail',
    'last_performed_on',latest.performed_on,'last_result',latest.result,
    'last_inspector',latest.inspector,'last_external_ref',latest.external_ref,
    'next_due_on',latest.next_due_on,
    -- Whether that date is the one the period produced or the one the expert
    -- wrote. A changed date never reads as a derived one.
    'due_source',latest.due_source,
    'katip_assignment_declared',coalesce(latest.katip_assignment_declared,false),
    'katip_declared_note',latest.katip_declared_note,
    -- Structurally false: nothing here checked the official system.
    'katip_official_verification',false,
    'evidence_asset_id',latest.evidence_asset_id,
    'inspections',CASE WHEN p_history THEN
      (SELECT coalesce(jsonb_agg(jsonb_build_object('id',i.inspection_id,'performed_on',i.performed_on,
          'result',i.result,'next_due_on',i.next_due_on,'period_months',i.period_months,
          'due_source',i.due_source,'inspector',i.inspector,'external_ref',i.external_ref,'note',i.note,
          'katip_assignment_declared',i.katip_assignment_declared,
          'katip_declared_note',i.katip_declared_note,
          'evidence_asset_id',i.evidence_asset_id)
          ORDER BY i.performed_on DESC,i.inspection_id),'[]'::jsonb)
       FROM private_isg.equipment_inspections i WHERE i.equipment_id=p_equipment) END,
    'health_record',false);
END $$;

-- The catalogue tells the client what a type starts at and what that default
-- is, so a period on screen is never a number with no story.
CREATE OR REPLACE FUNCTION private_isg.read_equipment_checks(p_company uuid,p_kind text,p_query text,p_state text,
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
    RETURN jsonb_build_object('schema_version',2,'kind','catalog','notice_days',notice,
      'suggestions',(SELECT coalesce(jsonb_agg(jsonb_build_object('code',s.equipment_type,
          'ordinal',s.ordinal,'default_period_months',d.period_months,
          'default_basis_note',d.basis_note) ORDER BY s.ordinal),'[]'::jsonb)
        FROM private_isg.equipment_type_suggestions s
        LEFT JOIN private_isg.equipment_default_periods d ON d.equipment_type=s.equipment_type),
      -- The product now starts a type at a period. It is a general default that
      -- the expert confirms, never a determination made for this company.
      'period_defaults_offered',true,
      'period_default_source','regulation_default',
      'period_default_needs_review',true,
      'rules',(SELECT coalesce(jsonb_agg(jsonb_build_object('equipment_type',r.equipment_type,
          'period_months',r.period_months,'period_source',r.period_source,
          'needs_review',r.needs_review,'exception_note',r.exception_note) ORDER BY r.equipment_type),'[]'::jsonb)
        FROM private_isg.equipment_inspection_rules r WHERE p_company IS NOT NULL AND r.company_id=p_company),
      'workplaces',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',w.name)
          ORDER BY w.name),'[]'::jsonb)
        FROM private_isg.workplaces w
        WHERE p_company IS NOT NULL AND w.company_id=p_company AND w.owner_id=actor AND NOT w.is_archived),
      'katip_official_verification',false,
      'health_records_tracked',false);
  END IF;

  IF p_kind='detail' THEN
    IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM 1 FROM private_isg.equipment_items e
      JOIN public.companies c ON c.id=e.company_id AND c.user_id=actor
      WHERE e.equipment_id=p_id AND (p_company IS NULL OR e.company_id=p_company);
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',2,'kind','detail','today',today,
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

  RETURN jsonb_build_object('schema_version',2,'kind','list','rows',tally_rows,'today',today,
    'counts',tally_all,'companies',tally_companies,'type_counts',tally_types,
    'total',matching_rows,'returned',jsonb_array_length(tally_rows),
    'has_more',page_offset+jsonb_array_length(tally_rows)<matching_rows,
    'limit',page_limit,'offset',page_offset,'notice_days',notice,
    'katip_official_verification',false,
    'compliance_verdict',NULL,'health_records_tracked',false);
END $$;

-- Registering an item now materialises the type's default period, so the first
-- report already has something to work from. Recording one may carry the
-- expert's own next date and their own KATİP declaration.
CREATE OR REPLACE FUNCTION private_isg.mutate_equipment_checks(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.equipment_check_receipts;
  result jsonb; answer jsonb; target uuid; item private_isg.equipment_items;
  stamp timestamptz:=clock_timestamp(); today date; derived date; chosen date; inspection uuid;
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
      'external_ref','note','evidence_asset_id','next_due_on','katip_declared','katip_note']
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
    -- 'regulation_default' is the product's own label and the expert cannot
    -- claim it: the P10 function accepts only the three they stand behind.
    answer:=private_isg.set_equipment_inspection_rule(p_company,p_payload->>'equipment_type',
      (p_payload->>'period_months')::integer,p_payload->>'period_source',
      nullif(btrim(coalesce(p_payload->>'exception_note','')),''),stamp);
    result:=jsonb_build_object('schema_version',2,'action',p_action,'rule',answer);
  ELSIF p_action='register_equipment' THEN
    IF p_payload->>'workplace_id' IS NULL OR p_payload->>'equipment_type' IS NULL OR
       p_payload->>'serial_tag' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    PERFORM private_isg.ensure_equipment_period(p_company,p_payload->>'equipment_type',stamp);
    answer:=private_isg.register_equipment(p_company,(p_payload->>'workplace_id')::uuid,
      p_payload->>'equipment_type',p_payload->>'serial_tag',
      (p_payload->>'acquired_on')::date,stamp);
    target:=(answer->>'equipment_id')::uuid;
    IF NOT (answer->>'replayed')::boolean THEN
      UPDATE private_isg.equipment_items
        SET location_note=nullif(btrim(coalesce(p_payload->>'location_note','')),'')
        WHERE equipment_id=target;
    END IF;
    result:=jsonb_build_object('schema_version',2,'action',p_action,'equipment_id',target,
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
      UPDATE private_isg.equipment_items SET is_archived=true WHERE equipment_id=target;
    ELSE
      IF p_payload->>'performed_on' IS NULL OR p_payload->>'result' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      IF (p_payload->>'performed_on')::date>today THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PERFORMED_IN_THE_FUTURE'; END IF;
      -- The type starts at its default the first time it is used, so the next
      -- date is worked out rather than left empty.
      PERFORM private_isg.ensure_equipment_period(p_company,item.equipment_type,stamp);
      derived:=private_isg.equipment_period_due(p_company,item.equipment_type,
        (p_payload->>'performed_on')::date,p_payload->>'result');
      answer:=private_isg.record_equipment_inspection(target,(p_payload->>'performed_on')::date,
        p_payload->>'result',(p_payload->>'evidence_asset_id')::uuid,
        nullif(btrim(coalesce(p_payload->>'external_ref','')),''),
        nullif(btrim(coalesce(p_payload->>'note','')),''),stamp);
      inspection:=(answer->>'inspection_id')::uuid;
      IF NOT (answer->>'replayed')::boolean THEN
        chosen:=(p_payload->>'next_due_on')::date;
        -- A date the expert wrote is recorded as theirs. One that matches what
        -- the period produced is recorded as the period's, whoever typed it.
        IF chosen IS NOT NULL THEN
          IF chosen<=(p_payload->>'performed_on')::date THEN
            RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DUE_BEFORE_REPORT'; END IF;
          IF p_payload->>'result'='fail' THEN
            RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DUE_ON_A_FAILED_CHECK'; END IF;
        END IF;
        UPDATE private_isg.equipment_inspections SET
          inspector=nullif(btrim(coalesce(p_payload->>'inspector','')),''),
          next_due_on=coalesce(chosen,next_due_on),
          due_source=CASE
            WHEN coalesce(chosen,derived) IS NULL THEN NULL
            WHEN chosen IS NULL OR chosen=derived THEN 'period' ELSE 'expert' END,
          katip_assignment_declared=coalesce((p_payload->>'katip_declared')::boolean,false),
          katip_declared_note=CASE WHEN coalesce((p_payload->>'katip_declared')::boolean,false)
            THEN nullif(btrim(coalesce(p_payload->>'katip_note','')),'') END
          WHERE inspection_id=inspection;
      END IF;
    END IF;
    result:=jsonb_build_object('schema_version',2,'action',p_action,'equipment_id',target,
      'row',private_isg.equipment_check_row(target,today,true));
  END IF;

  INSERT INTO private_isg.equipment_check_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $$;

ALTER TABLE private_isg.equipment_default_periods ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private_isg FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION private_isg.ensure_equipment_period(uuid,text,timestamptz),
  private_isg.equipment_period_due(uuid,text,date,text) FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
