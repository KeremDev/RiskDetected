-- Atamalar (appointment / employee representative letters): appointments.asset_id
-- already existed, unused. Wires it the same way katip_contracts.asset_id and
-- emergency_plan_versions.asset_id were wired, and drops letter_location — the
-- one live row has it null, so no data loss. live_appointments is a plain
-- passthrough view; recreated without the dropped column.
DROP VIEW private_isg.live_appointments;
ALTER TABLE private_isg.appointments DROP COLUMN letter_location;
CREATE VIEW private_isg.live_appointments AS
 SELECT appointment_id, company_id, employee_id, kind, scope_workplace_id, starts_on, ends_before,
   effective_dates, asset_id, created_at, updated_at, basis, basis_note, is_deleted
 FROM private_isg.appointments WHERE NOT is_deleted;

CREATE OR REPLACE FUNCTION private_isg.mutate_module_editor(p_company uuid, p_action text, p_operation uuid, p_mutation uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; module text:=p_payload->>'module'; id uuid; snapshot jsonb; values_ jsonb:=p_payload->'values';
 fingerprint bytea; receipt private_isg.module_edit_receipts; result jsonb; document uuid; allowed text[]; place uuid; person uuid; total numeric;
BEGIN
actor:=private_isg.module_editor_guard(module,p_company,true);
IF p_action NOT IN ('update','delete','link_document') OR p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL
 OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object' OR octet_length(p_payload::text)>32768
 OR p_payload->>'id' IS NULL OR p_payload->>'expected' IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN ('module','id','expected','values','document_id')) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;
id:=(p_payload->>'id')::uuid;
fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||p_mutation::text,8741));
SELECT * INTO receipt FROM private_isg.module_edit_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
IF FOUND THEN IF receipt.request_hash<>fingerprint THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF; RETURN receipt.response; END IF;
snapshot:=private_isg.module_editor_snapshot(module,p_company,id);
IF md5(snapshot::text)<>p_payload->>'expected' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
IF p_action='link_document' THEN
 IF NOT p_payload ? 'document_id' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
 document:=(p_payload->>'document_id')::uuid;
 IF document IS NOT NULL THEN
  PERFORM private_isg.require_document_tracking_company(p_company,false);
  PERFORM 1 FROM private_isg.document_obligations WHERE obligation_id=document AND company_id=p_company AND owner_id=actor AND NOT is_archived FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 END IF;
 INSERT INTO private_isg.module_record_links(module,record_id,company_id,owner_id,obligation_id) VALUES(module,id,p_company,actor,document)
 ON CONFLICT ON CONSTRAINT module_record_links_pkey DO UPDATE SET obligation_id=excluded.obligation_id;
ELSIF p_action='delete' THEN
 IF module='emergency_plan' AND EXISTS(SELECT 1 FROM private_isg.drill_records WHERE plan_id=id AND NOT is_deleted) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DEPENDENT_RECORDS'; END IF;
IF module='emergency_plan' THEN UPDATE private_isg.emergency_plan_versions SET is_deleted=true WHERE plan_id=id AND company_id=p_company; END IF;
IF module='drill' THEN UPDATE private_isg.drill_records SET is_deleted=true WHERE drill_id=id AND company_id=p_company; END IF;
IF module='ppe' THEN UPDATE private_isg.ppe_handovers SET is_deleted=true WHERE handover_id=id AND company_id=p_company; END IF;
IF module='appointment' THEN UPDATE private_isg.appointments SET is_deleted=true WHERE appointment_id=id AND company_id=p_company; END IF;
ELSE
 IF jsonb_typeof(values_) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
 allowed:=CASE module WHEN 'emergency_plan' THEN ARRAY['workplace_id','scope','prepared_on','valid_until','review_note','team_snapshot']
 WHEN 'drill' THEN ARRAY['plan_id','planned_on','performed_on','participants','observation','improvement']
 WHEN 'ppe' THEN ARRAY['employee_id','item','quantity','unit','handed_on','signed_copy_location']
 WHEN 'appointment' THEN ARRAY['employee_id','kind','scope_workplace_id','starts_on','ends_before','basis','basis_note','asset_id'] END;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(values_) k WHERE NOT k=ANY(allowed)) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;
 place:=coalesce((values_->>'workplace_id')::uuid,(values_->>'scope_workplace_id')::uuid);
 IF place IS NOT NULL THEN PERFORM 1 FROM private_isg.workplaces w WHERE w.id=place AND w.company_id=p_company AND w.owner_id=actor AND NOT w.is_archived FOR SHARE; IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF; END IF;
 person:=(values_->>'employee_id')::uuid;
 IF person IS NOT NULL THEN PERFORM 1 FROM private_isg.employees e WHERE e.id=person AND e.company_id=p_company AND NOT e.is_archived FOR SHARE; IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF; END IF;
 IF module='emergency_plan' THEN
  IF (values_->>'prepared_on')::date>(now() AT TIME ZONE 'Europe/Istanbul')::date THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  PERFORM private_isg.publish_emergency_plan(p_company,place,id,values_->>'scope',(values_->>'prepared_on')::date,
   (values_->>'valid_until')::date,private_isg.emergency_team_snapshot(values_->'team_snapshot'),NULL,nullif(btrim(values_->>'review_note'),''),clock_timestamp());
 ELSIF module='ppe' THEN
  SELECT coalesce(sum(quantity),0) INTO total FROM private_isg.ppe_returns WHERE handover_id=id;
  IF (values_->>'quantity')::numeric<total OR (values_->>'handed_on')::date>(now() AT TIME ZONE 'Europe/Istanbul')::date
   OR EXISTS(SELECT 1 FROM private_isg.ppe_returns WHERE handover_id=id AND returned_on<(values_->>'handed_on')::date)
   OR (total>0 AND ((values_->>'employee_id') IS DISTINCT FROM snapshot->>'employee_id' OR values_->>'unit' IS DISTINCT FROM snapshot->>'unit')) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RETURN_CONFLICT'; END IF;
  UPDATE private_isg.ppe_handovers SET employee_id=person,item=btrim(values_->>'item'),quantity=(values_->>'quantity')::numeric,
   unit=values_->>'unit',handed_on=(values_->>'handed_on')::date,signed_copy_location=nullif(btrim(values_->>'signed_copy_location'),'') WHERE handover_id=id;
 ELSIF module='appointment' THEN
  IF values_->>'basis' NOT IN ('elected','appointed') OR values_->>'basis' IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='BASIS_REQUIRED'; END IF;
  -- Only a clean, owned asset may be attached — the same rule the emergency
  -- plan and katip_contract enforce.
  IF values_ ? 'asset_id' AND values_->>'asset_id' IS NOT NULL THEN
   PERFORM 1 FROM private_isg.file_assets fa JOIN private_isg.file_library_entries fle ON fle.asset_id=fa.asset_id
     WHERE fa.asset_id=(values_->>'asset_id')::uuid AND fa.scan_status='clean' AND fle.company_id=p_company AND fle.owner_id=actor;
   IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  UPDATE private_isg.appointments SET employee_id=person,kind=values_->>'kind',scope_workplace_id=place,
   starts_on=(values_->>'starts_on')::date,ends_before=(values_->>'ends_before')::date,basis=values_->>'basis',
   basis_note=nullif(btrim(values_->>'basis_note'),''),asset_id=nullif(values_->>'asset_id','')::uuid,updated_at=clock_timestamp() WHERE appointment_id=id;
 ELSIF module='drill' THEN
  PERFORM 1 FROM private_isg.emergency_plan_versions WHERE plan_id=(values_->>'plan_id')::uuid AND company_id=p_company AND state='active' AND NOT is_deleted FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF snapshot->>'state'='performed' THEN
   IF (values_->>'performed_on')::date>(now() AT TIME ZONE 'Europe/Istanbul')::date OR jsonb_typeof(values_->'participants') IS DISTINCT FROM 'array'
    OR jsonb_array_length(values_->'participants') NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
   IF EXISTS(SELECT 1 FROM jsonb_array_elements_text(values_->'participants') p WHERE NOT EXISTS(SELECT 1 FROM private_isg.employees e WHERE e.company_id=p_company AND e.id::text=p AND NOT e.is_archived)) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PARTICIPANT_OUT_OF_SCOPE'; END IF;
  END IF;
  UPDATE private_isg.drill_records SET plan_id=(values_->>'plan_id')::uuid,
   plan_version=(SELECT version FROM private_isg.emergency_plan_versions WHERE plan_id=(values_->>'plan_id')::uuid AND state='active' AND NOT is_deleted),
   workplace_id=(SELECT workplace_id FROM private_isg.emergency_plan_versions WHERE plan_id=(values_->>'plan_id')::uuid AND state='active' AND NOT is_deleted),
   planned_on=(values_->>'planned_on')::date,performed_on=CASE WHEN state='performed' THEN (values_->>'performed_on')::date ELSE NULL END,
   participants=CASE WHEN state='performed' THEN values_->'participants' ELSE NULL END,
   observation=values_->>'observation',improvement=values_->>'improvement',updated_at=clock_timestamp() WHERE drill_id=id;
 END IF;
END IF;
INSERT INTO private_isg.module_record_history(module,record_id,company_id,actor_id,operation,before_snapshot) VALUES(module,id,p_company,actor,p_action,snapshot);
result:=jsonb_build_object('id',id,'deleted',p_action='delete');
INSERT INTO private_isg.module_edit_receipts VALUES(actor,p_mutation,fingerprint,result);
RETURN result;
END $function$;
