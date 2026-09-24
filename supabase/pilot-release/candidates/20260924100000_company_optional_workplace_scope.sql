-- OSGB pilot: a company with no real workplace is itself a valid record scope.
-- Keep company authorization intact; only the workplace dimension is optional.
BEGIN;

ALTER TABLE private_isg.equipment_items ALTER COLUMN workplace_id DROP NOT NULL;

CREATE OR REPLACE FUNCTION private_isg.module_scope(
  p_module text, p_company uuid, p_workplace uuid, p_write boolean)
RETURNS uuid LANGUAGE plpgsql SET search_path TO '' AS $scope$
DECLARE owner uuid; actor uuid := private_isg.active_actor();
BEGIN
  IF p_company IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='VALIDATION_ERROR';
  END IF;
  IF private_isg.expert_workspace() IS NOT NULL THEN
    PERFORM private_isg.expert_require_company(p_company,p_write,NULL);
    IF p_workplace IS NULL THEN
      IF EXISTS (SELECT 1 FROM private_isg.workplaces w
                 WHERE w.company_id=p_company AND NOT w.is_archived) THEN
        RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='WORKPLACE_REQUIRED';
      END IF;
    ELSE
      PERFORM 1 FROM private_isg.workplaces w
       WHERE w.company_id=p_company AND w.id=p_workplace
         AND (w.workspace_id=private_isg.expert_workspace() OR w.workspace_id IS NULL)
         AND NOT w.is_archived;
      IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='ACCESS_DENIED'; END IF;
    END IF;
    RETURN actor;
  END IF;
  PERFORM private_isg.module_gate(p_module,p_write);
  IF p_workplace IS NULL THEN
    SELECT c.user_id INTO owner FROM public.companies c
      WHERE c.id=p_company AND c.user_id=actor AND NOT c.is_archived FOR SHARE;
    IF owner IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='ACCESS_DENIED';
    END IF;
    IF EXISTS (SELECT 1 FROM private_isg.workplaces w
               WHERE w.company_id=p_company AND NOT w.is_archived) THEN
      RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='WORKPLACE_REQUIRED';
    END IF;
    RETURN owner;
  END IF;
  SELECT w.owner_id INTO owner FROM private_isg.workplaces w
    WHERE w.company_id=p_company AND w.id=p_workplace FOR SHARE;
  IF owner IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='ACCESS_DENIED'; END IF;
  RETURN owner;
END $scope$;

CREATE OR REPLACE FUNCTION private_isg.workspace_equipment_item_invariant()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $equipment$
DECLARE company public.companies; workspace private_isg.workspaces;
BEGIN
  IF private_isg.workspace_is_legacy_company_write(NEW.company_id,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.workspace_id ELSE NULL END) THEN RETURN NEW; END IF;
  SELECT * INTO company FROM public.companies WHERE id=NEW.company_id FOR SHARE;
  IF NEW.workspace_id IS NULL THEN NEW.workspace_id:=company.workspace_id; END IF;
  IF company.id IS NULL OR NEW.workspace_id IS DISTINCT FROM company.workspace_id THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='EQUIPMENT_SCOPE_CONFLICT'; END IF;
  IF NEW.workplace_id IS NULL THEN
    IF TG_OP='INSERT' AND EXISTS (
      SELECT 1 FROM private_isg.workplaces w WHERE w.company_id=NEW.company_id
        AND NOT w.is_archived) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='WORKPLACE_REQUIRED'; END IF;
  ELSIF NOT EXISTS (
    SELECT 1 FROM private_isg.workplaces w WHERE w.workspace_id=NEW.workspace_id
      AND w.company_id=NEW.company_id AND w.id=NEW.workplace_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='EQUIPMENT_SCOPE_CONFLICT';
  END IF;
  IF NEW.workspace_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO workspace FROM private_isg.workspaces WHERE id=NEW.workspace_id;
  IF workspace.kind='osgb' AND NEW.owner_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEGACY_OWNER_FORBIDDEN'; END IF;
  IF workspace.kind='personal' AND NEW.owner_id IS DISTINCT FROM company.user_id THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEGACY_OWNER_MISMATCH'; END IF;
  IF NEW.created_by_user_id IS NULL OR NEW.updated_by_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACTOR_REQUIRED'; END IF;
  IF TG_OP='UPDATE' AND ROW(NEW.workspace_id,NEW.company_id,NEW.owner_id,NEW.equipment_id,
      NEW.equipment_type,NEW.created_by_user_id) IS DISTINCT FROM
    ROW(OLD.workspace_id,OLD.company_id,OLD.owner_id,OLD.equipment_id,
      OLD.equipment_type,OLD.created_by_user_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IMMUTABLE_SCOPE'; END IF;
  RETURN NEW;
END $equipment$;

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
    IF p_payload->>'equipment_type' IS NULL OR
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
      WHERE equipment_id=target AND company_id=p_company AND private_isg.expert_company_visible(owner_id,company_id,actor) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;

    IF p_action='update_equipment' THEN
      IF p_payload->>'workplace_id' IS NOT NULL THEN
        PERFORM 1 FROM private_isg.workplaces WHERE id=(p_payload->>'workplace_id')::uuid
          AND company_id=p_company AND private_isg.expert_company_visible(owner_id,company_id,actor) AND NOT is_archived;
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
          WHERE fa.asset_id=asset AND fa.scan_status='clean' AND fle.company_id=p_company AND private_isg.expert_company_visible(fle.owner_id,fle.company_id,actor);
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
END $function$
;

COMMIT;
