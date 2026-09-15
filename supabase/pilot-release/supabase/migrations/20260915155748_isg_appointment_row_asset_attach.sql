-- appointment_row and mutate_appointments (the real "Atama ve Temsilciler"
-- record flow, separate from the generic module editor already wired in
-- isg_appointment_asset_attach) still referenced letter_location, which that
-- migration dropped from the table. Wires the same asset_id attach here,
-- catching a break before it shipped.
CREATE OR REPLACE FUNCTION private_isg.appointment_row(p_appointment uuid, p_today date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
DECLARE entry private_isg.live_appointments; person private_isg.employees;
  place private_isg.workplaces; usual text; shown_state text;
BEGIN
  SELECT * INTO entry FROM private_isg.live_appointments WHERE appointment_id=p_appointment;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO person FROM private_isg.employees
    WHERE company_id=entry.company_id AND id=entry.employee_id;
  SELECT * INTO place FROM private_isg.workplaces
    WHERE company_id=entry.company_id AND id=entry.scope_workplace_id;
  SELECT usual_basis INTO usual FROM private_isg.appointment_kinds WHERE kind=entry.kind;
  shown_state:=private_isg.appointment_status(entry.starts_on,entry.ends_before,p_today);
  RETURN jsonb_build_object(
    'id',entry.appointment_id,'company_id',entry.company_id,
    'employee_id',entry.employee_id,'employee_name',person.full_name,
    'employee_archived',coalesce(person.is_archived,false),
    'workplace_id',entry.scope_workplace_id,'workplace_name',place.name,
    'kind',entry.kind,'usual_basis',usual,
    'starts_on',entry.starts_on,'ends_before',entry.ends_before,
    'state',shown_state,'state_authority','computed_at_read',
    'basis',entry.basis,'basis_note',entry.basis_note,
    'asset_id',entry.asset_id,
    'asset_download',(SELECT jsonb_build_object('bucket',bucket,'path',immutable_path)
      FROM private_isg.file_assets WHERE asset_id=entry.asset_id),
    -- No legal condition was checked, and there is nowhere to record that one
    -- was. Holding a role is not the same as being qualified for it.
    'qualification_verified',false,
    -- No approved catalogue says how many a workplace needs.
    'required_count_known',false,
    'compliance_verdict',NULL,'health_records_tracked',false);
END $function$;

CREATE OR REPLACE FUNCTION private_isg.mutate_appointments(p_company uuid, p_action text, p_operation uuid, p_mutation uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid; allowed text[]; offending text; fingerprint bytea; prior private_isg.appointment_receipts;
  result jsonb; answer jsonb; appointment uuid; entry private_isg.appointments; asset uuid;
  stamp timestamptz:=clock_timestamp(); today date;
BEGIN
  actor:=private_isg.require_appointment_company(p_company,true);
  IF p_action IS NULL OR p_operation IS NULL OR p_mutation IS NULL OR p_payload IS NULL OR
     jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>4096 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  today:=(stamp AT TIME ZONE 'Europe/Istanbul')::date;
  allowed:=CASE p_action
    -- No qualification field of any kind: holding a role is not being
    -- qualified for it, and nothing here may say otherwise.
    WHEN 'record_appointment' THEN ARRAY['employee_id','kind','workplace_id','starts_on','ends_before',
      'basis','basis_note','asset_id']
    WHEN 'end_appointment' THEN ARRAY['appointment_id','ends_before']
    ELSE NULL END;
  IF allowed IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT key INTO offending FROM jsonb_object_keys(p_payload) AS keys(key)
    WHERE NOT (key=ANY(allowed)) ORDER BY key LIMIT 1;
  IF offending IS NOT NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;

  fingerprint:=sha256(convert_to(jsonb_build_array(p_company,p_action,p_operation,p_payload)::text,'UTF8'));
  PERFORM pg_advisory_xact_lock(hashtextextended(actor::text||':isg-appointment:'||p_mutation::text,0));
  SELECT * INTO prior FROM private_isg.appointment_receipts WHERE actor_id=actor AND mutation_id=p_mutation;
  IF FOUND THEN
    IF prior.request_hash IS DISTINCT FROM fingerprint THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
    RETURN prior.response||jsonb_build_object('replayed',true);
  END IF;

  IF p_action='record_appointment' THEN
    IF p_payload->>'employee_id' IS NULL OR p_payload->>'kind' IS NULL OR
       p_payload->>'workplace_id' IS NULL OR p_payload->>'starts_on' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    -- Saying why the person holds the role is the point of the field.
    IF p_payload->>'basis' IS NULL OR p_payload->>'basis' NOT IN ('elected','appointed') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='BASIS_REQUIRED'; END IF;
    PERFORM 1 FROM private_isg.workplaces WHERE company_id=p_company
      AND id=(p_payload->>'workplace_id')::uuid AND owner_id=actor AND NOT is_archived;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    -- Only a clean, owned asset may be attached — the same rule every other
    -- module's asset_id enforces.
    IF p_payload->>'asset_id' IS NOT NULL THEN
      asset:=(p_payload->>'asset_id')::uuid;
      PERFORM 1 FROM private_isg.file_assets fa JOIN private_isg.file_library_entries fle ON fle.asset_id=fa.asset_id
        WHERE fa.asset_id=asset AND fa.scan_status='clean' AND fle.company_id=p_company AND fle.owner_id=actor;
      IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    END IF;
    answer:=private_isg.record_appointment(p_company,(p_payload->>'employee_id')::uuid,
      p_payload->>'kind',(p_payload->>'workplace_id')::uuid,
      (p_payload->>'starts_on')::date,(p_payload->>'ends_before')::date,NULL,stamp);
    appointment:=(answer->>'appointment_id')::uuid;
    UPDATE private_isg.appointments SET basis=p_payload->>'basis',
      basis_note=nullif(btrim(coalesce(p_payload->>'basis_note','')),''),
      asset_id=asset
      WHERE appointment_id=appointment;
  ELSE
    appointment:=(p_payload->>'appointment_id')::uuid;
    SELECT * INTO entry FROM private_isg.appointments
      WHERE appointment_id=appointment AND company_id=p_company FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF p_payload->>'ends_before' IS NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    answer:=private_isg.end_appointment(appointment,(p_payload->>'ends_before')::date,stamp);
  END IF;

  result:=jsonb_build_object('schema_version',1,'action',p_action,'appointment_id',appointment,
    'answer',answer,'row',private_isg.appointment_row(appointment,today));
  INSERT INTO private_isg.appointment_receipts(actor_id,mutation_id,company_id,operation_id,request_hash,response)
    VALUES(actor,p_mutation,p_company,p_operation,fingerprint,result);
  RETURN result||jsonb_build_object('replayed',false);
END $function$;
