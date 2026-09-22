BEGIN;

-- A checklist answer owns only the observation text. If the expert later adds
-- a measure, legislation, responsible person or risk score from the common
-- nonconformity editor, recording the checklist answer again must not erase
-- those manually maintained fields.
CREATE OR REPLACE FUNCTION private_isg.record_run_item(p_run uuid,p_item text,p_result text,p_note text,p_asset uuid,
  p_open_nonconformity boolean,p_severity text,p_due_on date,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); run private_isg.checklist_runs;
  item private_isg.checklist_template_items; existing private_isg.checklist_run_items;
  detail private_isg.nonconformity_details;
  finding jsonb; record_id uuid; normalized text;
BEGIN
  PERFORM private_isg.nonconformity_gate(true);
  normalized:=CASE p_result WHEN 'compliant' THEN 'conform' WHEN 'non_compliant' THEN 'nonconform' ELSE p_result END;
  IF p_run IS NULL OR p_item IS NULL OR normalized IS NULL OR p_now IS NULL OR p_open_nonconformity IS NULL OR
     normalized NOT IN ('conform','nonconform','not_applicable') OR
     (p_open_nonconformity AND (normalized<>'nonconform' OR p_severity IS NULL)) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO run FROM private_isg.checklist_runs WHERE run_id=p_run FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO item FROM private_isg.checklist_template_items
    WHERE template_code=run.template_code AND version=run.template_version AND item_code=p_item;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF normalized='not_applicable' AND NOT item.allows_not_applicable THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF normalized IN ('nonconform','not_applicable') AND btrim(coalesce(p_note,''))='' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='EXPLANATION_REQUIRED'; END IF;
  IF p_asset IS NOT NULL THEN
    PERFORM 1 FROM private_isg.file_assets a
      WHERE a.asset_id=p_asset AND a.company_id=run.company_id AND a.scan_status='clean'
        AND private_isg.expert_company_visible(a.owner_id,a.company_id,actor) FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  SELECT * INTO existing FROM private_isg.checklist_run_items WHERE run_id=p_run AND item_code=p_item;
  record_id:=existing.nonconformity_id;
  IF p_open_nonconformity AND record_id IS NULL THEN
    finding:=private_isg.open_nonconformity(run.company_id,run.workplace_id,'checklist',p_run::text||':'||p_item,
      item.prompt,p_severity,run.started_on,p_due_on,p_now);
    record_id:=(finding->>'nonconformity_id')::uuid;
    UPDATE private_isg.nonconformities SET source_run_id=p_run,source_item_code=p_item
      WHERE nonconformity_id=record_id;
  END IF;
  IF record_id IS NOT NULL AND normalized='nonconform' THEN
    SELECT * INTO detail FROM private_isg.nonconformity_details WHERE nonconformity_id=record_id;
    PERFORM private_isg.set_nonconformity_detail(record_id,p_note,
      detail.control_measure,detail.legislation_ref,detail.responsible_contact,
      detail.risk_method,detail.fk_probability,detail.fk_frequency,detail.fk_severity,
      detail.m5_probability,detail.m5_severity,p_now);
  END IF;
  INSERT INTO private_isg.checklist_run_items(
      run_id,item_code,result,note,evidence_asset_id,nonconformity_id,recorded_at)
    VALUES(p_run,p_item,normalized,nullif(btrim(coalesce(p_note,'')),''),p_asset,record_id,p_now)
  ON CONFLICT(run_id,item_code) DO UPDATE SET result=excluded.result,note=excluded.note,
    evidence_asset_id=excluded.evidence_asset_id,
    nonconformity_id=coalesce(checklist_run_items.nonconformity_id,excluded.nonconformity_id),
    recorded_at=excluded.recorded_at;
  RETURN jsonb_build_object('schema_version',2,'run_id',p_run,'item_code',p_item,'result',normalized,
    'answer',CASE normalized WHEN 'conform' THEN 'compliant' WHEN 'nonconform' THEN 'non_compliant'
      ELSE 'not_applicable' END,'evidence_asset_id',p_asset,'nonconformity_id',record_id,
    'replayed',existing.result IS NOT DISTINCT FROM normalized AND
      existing.note IS NOT DISTINCT FROM nullif(btrim(coalesce(p_note,'')),''));
END $$;

REVOKE ALL ON FUNCTION private_isg.record_run_item(uuid,text,text,text,uuid,boolean,text,date,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;

NOTIFY pgrst,'reload schema';

COMMIT;
