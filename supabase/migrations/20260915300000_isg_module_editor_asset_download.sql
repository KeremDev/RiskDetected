-- Resolves a download location for any module row that carries an asset_id
-- (appointment now; emergency_plan already had its own resolved value via the
-- specialized publish flow, this generic snapshot gets the same shape too),
-- the same 'asset_download' shape process_row and emergency_plan_row expose.
CREATE OR REPLACE FUNCTION private_isg.module_editor_snapshot(p_module text, p_company uuid, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$ DECLARE result jsonb; BEGIN
IF p_module='emergency_plan' THEN SELECT to_jsonb(t) INTO result FROM private_isg.emergency_plan_versions t WHERE t.plan_id=p_id AND t.company_id=p_company AND NOT t.is_deleted ORDER BY t.version DESC LIMIT 1 FOR UPDATE; END IF;
IF p_module='drill' THEN SELECT to_jsonb(t) INTO result FROM private_isg.drill_records t WHERE t.drill_id=p_id AND t.company_id=p_company AND NOT t.is_deleted LIMIT 1 FOR UPDATE; END IF;
IF p_module='ppe' THEN SELECT to_jsonb(t) INTO result FROM private_isg.ppe_handovers t WHERE t.handover_id=p_id AND t.company_id=p_company AND NOT t.is_deleted LIMIT 1 FOR UPDATE; END IF;
IF p_module='appointment' THEN SELECT to_jsonb(t) INTO result FROM private_isg.appointments t WHERE t.appointment_id=p_id AND t.company_id=p_company AND NOT t.is_deleted LIMIT 1 FOR UPDATE; END IF;
IF result IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
IF p_module='ppe' THEN result:=result||jsonb_build_object('returns',(SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.return_id),'[]') FROM private_isg.ppe_returns r WHERE r.handover_id=p_id)); END IF;
IF result ? 'asset_id' AND result->>'asset_id' IS NOT NULL THEN
 result:=result||jsonb_build_object('asset_download',(SELECT jsonb_build_object('bucket',bucket,'path',immutable_path) FROM private_isg.file_assets WHERE asset_id=(result->>'asset_id')::uuid));
END IF;
RETURN result||jsonb_build_object('document_id',(SELECT obligation_id FROM private_isg.module_record_links WHERE module=p_module AND record_id=p_id));
END $function$;
