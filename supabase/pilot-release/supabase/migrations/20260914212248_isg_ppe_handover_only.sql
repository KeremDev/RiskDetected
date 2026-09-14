SET LOCAL lock_timeout='5s';
-- Quantity columns remain only for compatibility with historical records.
ALTER TABLE private_isg.ppe_handovers ADD COLUMN form_snapshot jsonb;
CREATE FUNCTION private_isg.ppe_form_snapshot_trigger() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$ BEGIN
 NEW.form_snapshot:=jsonb_build_object('id',NEW.handover_id,'company',(SELECT name FROM public.companies WHERE id=NEW.company_id),'employee',(SELECT full_name FROM private_isg.employees WHERE id=NEW.employee_id),'item',NEW.item,'date',NEW.handed_on,'version',1);
 RETURN NEW;
END $$;
CREATE TRIGGER ppe_form_snapshot BEFORE INSERT ON private_isg.ppe_handovers FOR EACH ROW EXECUTE FUNCTION private_isg.ppe_form_snapshot_trigger();
REVOKE ALL ON FUNCTION private_isg.ppe_form_snapshot_trigger() FROM PUBLIC,anon,authenticated,service_role;
ALTER FUNCTION private_isg.mutate_ppe_handovers(uuid,text,uuid,uuid,jsonb) RENAME TO mutate_ppe_handovers_legacy;
REVOKE ALL ON FUNCTION private_isg.mutate_ppe_handovers_legacy(uuid,text,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private_isg.mutate_ppe_handovers(p_company uuid,p_action text,p_operation uuid,p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ BEGIN
 PERFORM private_isg.require_ppe_company(p_company,true);
 IF p_action IS DISTINCT FROM 'create_form' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
 IF p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN ('employee_id','item','handed_on')) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PAYLOAD_NOT_ALLOWED'; END IF;
 RETURN private_isg.mutate_ppe_handovers_legacy(p_company,'record_handover',p_operation,p_mutation,p_payload||'{"quantity":1,"unit":"piece"}'::jsonb);
END $$;
-- Replace wrapper after rename: do not leave a bound reference to legacy code.
CREATE OR REPLACE FUNCTION public.isg_ppe_mutate_v1(p_company uuid,p_action text,p_operation uuid,p_mutation uuid,p_payload jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.mutate_ppe_handovers(p_company,p_action,p_operation,p_mutation,p_payload) $$;
REVOKE ALL ON FUNCTION private_isg.mutate_ppe_handovers(uuid,text,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.mutate_ppe_handovers(uuid,text,uuid,uuid,jsonb) TO authenticated;
CREATE OR REPLACE FUNCTION private_isg.module_editor_guard(p_module text,p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$ BEGIN
 CASE p_module
 WHEN 'emergency_plan' THEN RETURN private_isg.require_emergency_company(p_company,p_write);
 WHEN 'drill' THEN RETURN private_isg.require_drill_company(p_company,p_write);
 WHEN 'ppe' THEN PERFORM private_isg.require_ppe_company(p_company,p_write); RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE';
 WHEN 'appointment' THEN RETURN private_isg.require_appointment_company(p_company,p_write);
 ELSE RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END CASE;
END $$;
CREATE FUNCTION public.isg_ppe_form_v1(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ DECLARE entry private_isg.ppe_handovers; BEGIN
 SELECT * INTO entry FROM private_isg.ppe_handovers WHERE handover_id=p_id AND NOT is_deleted;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
 PERFORM private_isg.require_ppe_company(entry.company_id,false);
 -- Legacy records are labelled and frozen from the first available form read.
 UPDATE private_isg.ppe_handovers SET form_snapshot=coalesce(form_snapshot,jsonb_build_object('id',handover_id,'company',(SELECT name FROM public.companies WHERE id=company_id),'employee',(SELECT full_name FROM private_isg.employees WHERE id=employee_id),'item',item,'date',handed_on,'version',1,'legacy',true)) WHERE handover_id=p_id AND form_snapshot IS NULL;
 RETURN (SELECT form_snapshot FROM private_isg.ppe_handovers WHERE handover_id=p_id);
END $$;
REVOKE ALL ON FUNCTION public.isg_ppe_form_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.isg_ppe_form_v1(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
