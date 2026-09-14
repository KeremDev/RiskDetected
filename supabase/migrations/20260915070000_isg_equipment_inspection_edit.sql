-- P10 fourth slice: correcting a report that is already on file. Additive. No
-- switch is added or opened.
--
-- The previous slice let the expert change the next date while recording a
-- check. Once saved, nothing could be corrected: a mistyped date, inspector or
-- report number stayed, and the identity rule (one report per equipment per
-- date) meant re-filing the same day returned the original instead of fixing
-- it. This adds the correction.
--
-- What it deliberately does NOT allow:
--   * the check date, because that is the report's identity;
--   * the result, because that is what the check found. Changing either would
--     silently rewrite what happened. The right answer to a wrong result is the
--     right report, and the screen says so.
--
-- The İSG-KATİP mark stays exactly what it is: a tick the expert sets for their
-- own information. It is stored, shown and editable, and it still touches no
-- state, no counter and no filter — nothing about it can move a row.
BEGIN;
SET LOCAL lock_timeout='5s';

CREATE OR REPLACE FUNCTION private_isg.mutate_equipment_checks(p_company uuid,p_action text,p_operation uuid,
  p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.equipment_check_receipts;
  result jsonb; answer jsonb; target uuid; item private_isg.equipment_items;
  report private_isg.equipment_inspections;
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
      IF p_payload ? 'evidence_asset_id' AND p_payload->>'evidence_asset_id' IS NOT NULL THEN
        -- The same rule the P10 function applies: an asset nobody cleared is
        -- not attachable, whichever action reaches for it.
        PERFORM 1 FROM private_isg.file_assets
          WHERE asset_id=(p_payload->>'evidence_asset_id')::uuid AND scan_status='clean' FOR SHARE;
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
        evidence_asset_id=CASE WHEN p_payload ? 'evidence_asset_id'
          THEN (p_payload->>'evidence_asset_id')::uuid ELSE evidence_asset_id END,
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
END $$;
NOTIFY pgrst,'reload schema';
COMMIT;
