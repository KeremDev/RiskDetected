-- Periyodik Kontroller: record_equipment_inspection and mutate_equipment_checks
-- already carried an evidence_asset_id/p_asset parameter shaped for this, but
-- refused it outright — "PILOT DIVERGENCE" — because file storage did not
-- exist yet. It does now (isg_pilot_file_storage_core_and_library). Adds the
-- column that was missing (unlike katip_contract/appointments, this one truly
-- never had it) and wires the same clean-and-owned check every other module
-- uses.
ALTER TABLE private_isg.equipment_inspections ADD COLUMN evidence_asset_id uuid;

CREATE OR REPLACE FUNCTION private_isg.record_equipment_inspection(p_equipment uuid, p_performed_on date, p_result text, p_asset uuid, p_external_ref text, p_note text, p_now timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE item private_isg.equipment_items; rule private_isg.equipment_inspection_rules;
  inspection uuid; existing private_isg.equipment_inspections; due date;
BEGIN
  PERFORM private_isg.module_gate('equipment',true);
  IF p_equipment IS NULL OR p_performed_on IS NULL OR NOT isfinite(p_performed_on) OR p_result IS NULL OR
     p_now IS NULL OR p_result NOT IN ('pass','fail','conditional') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO item FROM private_isg.equipment_items WHERE equipment_id=p_equipment FOR SHARE;
  IF NOT FOUND OR item.is_archived THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  -- Only a clean, owned asset may be attached — the same rule every other
  -- module's asset_id enforces.
  IF p_asset IS NOT NULL THEN
    PERFORM 1 FROM private_isg.file_assets fa JOIN private_isg.file_library_entries fle ON fle.asset_id=fa.asset_id
      WHERE fa.asset_id=p_asset AND fa.scan_status='clean' AND fle.company_id=item.company_id AND fle.owner_id=item.owner_id;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  SELECT * INTO existing FROM private_isg.equipment_inspections
    WHERE equipment_id=p_equipment AND performed_on=p_performed_on;
  IF FOUND THEN RETURN jsonb_build_object('schema_version',1,'inspection_id',existing.inspection_id,
    'next_due_on',existing.next_due_on,'replayed',true); END IF;
  SELECT * INTO rule FROM private_isg.equipment_inspection_rules
    WHERE company_id=item.company_id AND equipment_type=item.equipment_type FOR SHARE;
  -- No type rule means no invented due date: the period is unknown, not a year.
  IF FOUND AND p_result<>'fail' THEN
    due:=(p_performed_on+make_interval(months=>rule.period_months))::date; END IF;
  INSERT INTO private_isg.equipment_inspections(equipment_id,performed_on,result,next_due_on,period_months,
      external_ref,note,evidence_asset_id,created_at)
    VALUES(p_equipment,p_performed_on,p_result,due,rule.period_months,p_external_ref,p_note,p_asset,p_now)
    RETURNING inspection_id INTO inspection;
  RETURN jsonb_build_object('schema_version',1,'inspection_id',inspection,'result',p_result,'next_due_on',due,
    'period_months',rule.period_months,'period_source',rule.period_source,
    'period_needs_review',coalesce(rule.needs_review,true),'exception_note',rule.exception_note,'replayed',false);
END $function$;

CREATE OR REPLACE FUNCTION private_isg.equipment_check_row(p_equipment uuid, p_today date, p_history boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
    'evidence_download',(SELECT jsonb_build_object('bucket',bucket,'path',immutable_path)
      FROM private_isg.file_assets WHERE asset_id=latest.evidence_asset_id),
    'inspections',CASE WHEN p_history THEN
      (SELECT coalesce(jsonb_agg(jsonb_build_object('id',i.inspection_id,'performed_on',i.performed_on,
          'result',i.result,'next_due_on',i.next_due_on,'period_months',i.period_months,
          'due_source',i.due_source,'inspector',i.inspector,'external_ref',i.external_ref,'note',i.note,
          'katip_assignment_declared',i.katip_assignment_declared,
          'katip_declared_note',i.katip_declared_note,
          'evidence_asset_id',i.evidence_asset_id,
          'evidence_download',(SELECT jsonb_build_object('bucket',bucket,'path',immutable_path)
            FROM private_isg.file_assets WHERE asset_id=i.evidence_asset_id))
          ORDER BY i.performed_on DESC,i.inspection_id),'[]'::jsonb)
       FROM private_isg.equipment_inspections i WHERE i.equipment_id=p_equipment) END,
    'health_record',false);
END $function$;

CREATE OR REPLACE FUNCTION private_isg.mutate_equipment_checks(p_company uuid, p_action text, p_operation uuid, p_mutation uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.equipment_check_receipts;
  result jsonb; answer jsonb; target uuid; item private_isg.equipment_items;
  report private_isg.equipment_inspections;
  stamp timestamptz:=clock_timestamp(); today date; derived date; chosen date; inspection uuid; asset uuid;
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
    -- The date and the result are not here: they are what the report is.
    WHEN 'update_inspection' THEN ARRAY['equipment_id','inspection_id','inspector',
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
    answer:=private_isg.set_equipment_inspection_rule(p_company,p_payload->>'equipment_type',
      (p_payload->>'period_months')::integer,p_payload->>'period_source',
      nullif(btrim(coalesce(p_payload->>'exception_note','')),''),stamp);
    result:=jsonb_build_object('schema_version',3,'action',p_action,'rule',answer);
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
    result:=jsonb_build_object('schema_version',3,'action',p_action,'equipment_id',target,
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

    ELSIF p_action='update_inspection' THEN
      IF p_payload->>'inspection_id' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      SELECT * INTO report FROM private_isg.equipment_inspections
        WHERE inspection_id=(p_payload->>'inspection_id')::uuid AND equipment_id=target FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      -- Only a clean, owned asset may be attached — the same rule every other
      -- module's asset_id enforces.
      IF p_payload ? 'evidence_asset_id' AND p_payload->>'evidence_asset_id' IS NOT NULL THEN
        asset:=(p_payload->>'evidence_asset_id')::uuid;
        PERFORM 1 FROM private_isg.file_assets fa JOIN private_isg.file_library_entries fle ON fle.asset_id=fa.asset_id
          WHERE fa.asset_id=asset AND fa.scan_status='clean' AND fle.company_id=p_company AND fle.owner_id=actor;
        IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      END IF;
      -- The date is measured against the report's own date and result, which
      -- this action cannot change.
      derived:=private_isg.equipment_period_due(p_company,item.equipment_type,
        report.performed_on,report.result);
      chosen:=CASE WHEN p_payload ? 'next_due_on' THEN (p_payload->>'next_due_on')::date
                   ELSE report.next_due_on END;
      IF chosen IS NOT NULL THEN
        IF chosen<=report.performed_on THEN
          RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DUE_BEFORE_REPORT'; END IF;
        IF report.result='fail' THEN
          RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DUE_ON_A_FAILED_CHECK'; END IF;
      END IF;
      UPDATE private_isg.equipment_inspections SET
        inspector=CASE WHEN p_payload ? 'inspector'
          THEN nullif(btrim(coalesce(p_payload->>'inspector','')),'') ELSE inspector END,
        external_ref=CASE WHEN p_payload ? 'external_ref'
          THEN nullif(btrim(coalesce(p_payload->>'external_ref','')),'') ELSE external_ref END,
        note=CASE WHEN p_payload ? 'note'
          THEN nullif(btrim(coalesce(p_payload->>'note','')),'') ELSE note END,
        evidence_asset_id=CASE WHEN p_payload ? 'evidence_asset_id' THEN asset ELSE evidence_asset_id END,
        next_due_on=chosen,
        -- Recomputed the same way it is on entry: a corrected date that lands
        -- on what the period produces reads as the period's answer again.
        due_source=CASE WHEN chosen IS NULL THEN NULL
          WHEN chosen=derived THEN 'period' ELSE 'expert' END,
        katip_assignment_declared=CASE WHEN p_payload ? 'katip_declared'
          THEN coalesce((p_payload->>'katip_declared')::boolean,false)
          ELSE katip_assignment_declared END,
        katip_declared_note=CASE
          WHEN p_payload ? 'katip_declared' AND NOT coalesce((p_payload->>'katip_declared')::boolean,false) THEN NULL
          WHEN p_payload ? 'katip_note' THEN nullif(btrim(coalesce(p_payload->>'katip_note','')),'')
          ELSE katip_declared_note END
        WHERE inspection_id=report.inspection_id;

    ELSE
      IF p_payload->>'performed_on' IS NULL OR p_payload->>'result' IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      IF (p_payload->>'performed_on')::date>today THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PERFORMED_IN_THE_FUTURE'; END IF;
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
    result:=jsonb_build_object('schema_version',3,'action',p_action,'equipment_id',target,
      'row',private_isg.equipment_check_row(target,today,true));
  END IF;

  INSERT INTO private_isg.equipment_check_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $function$;
