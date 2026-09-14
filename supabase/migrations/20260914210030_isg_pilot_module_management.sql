SET LOCAL lock_timeout='5s';
ALTER TABLE private_isg.emergency_plan_versions ADD COLUMN is_deleted boolean NOT NULL DEFAULT false;
CREATE VIEW private_isg.live_emergency_plan_versions WITH (security_invoker=true) AS SELECT * FROM private_isg.emergency_plan_versions WHERE NOT is_deleted;
REVOKE ALL ON private_isg.live_emergency_plan_versions FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE private_isg.drill_records ADD COLUMN is_deleted boolean NOT NULL DEFAULT false;
CREATE VIEW private_isg.live_drill_records WITH (security_invoker=true) AS SELECT * FROM private_isg.drill_records WHERE NOT is_deleted;
REVOKE ALL ON private_isg.live_drill_records FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE private_isg.ppe_handovers ADD COLUMN is_deleted boolean NOT NULL DEFAULT false;
CREATE VIEW private_isg.live_ppe_handovers WITH (security_invoker=true) AS SELECT * FROM private_isg.ppe_handovers WHERE NOT is_deleted;
REVOKE ALL ON private_isg.live_ppe_handovers FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE private_isg.appointments ADD COLUMN is_deleted boolean NOT NULL DEFAULT false;
CREATE VIEW private_isg.live_appointments WITH (security_invoker=true) AS SELECT * FROM private_isg.appointments WHERE NOT is_deleted;
REVOKE ALL ON private_isg.live_appointments FROM PUBLIC,anon,authenticated,service_role;
DO $rewrite$ DECLARE r record; definition text; BEGIN
FOR r IN SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND p.proname IN ('read_emergency_plans','emergency_plan_row') LOOP definition:=pg_get_functiondef(r.oid); definition:=replace(definition,'private_isg.emergency_plan_versions','private_isg.live_emergency_plan_versions'); EXECUTE definition; END LOOP;
FOR r IN SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND p.proname IN ('read_drills','drill_row') LOOP definition:=pg_get_functiondef(r.oid); definition:=replace(definition,'private_isg.drill_records','private_isg.live_drill_records'); EXECUTE definition; END LOOP;
FOR r IN SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND p.proname IN ('read_ppe_handovers','ppe_handover_row') LOOP definition:=pg_get_functiondef(r.oid); definition:=replace(definition,'private_isg.ppe_handovers','private_isg.live_ppe_handovers'); EXECUTE definition; END LOOP;
FOR r IN SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private_isg' AND p.proname IN ('read_appointments','appointment_row') LOOP definition:=pg_get_functiondef(r.oid); definition:=replace(definition,'private_isg.appointments','private_isg.live_appointments'); EXECUTE definition; END LOOP;
END $rewrite$;
CREATE TABLE private_isg.module_record_links (
 module text NOT NULL CHECK(module IN ('emergency_plan','drill','ppe','appointment')),
 record_id uuid NOT NULL,company_id uuid NOT NULL,owner_id uuid NOT NULL,
 obligation_id uuid REFERENCES private_isg.document_obligations(obligation_id) ON DELETE RESTRICT,
 PRIMARY KEY(module,record_id), FOREIGN KEY(company_id,owner_id) REFERENCES public.companies(id,user_id));
CREATE INDEX module_record_links_document_idx ON private_isg.module_record_links(obligation_id);
CREATE TABLE private_isg.module_record_history (
 revision_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), module text NOT NULL,record_id uuid NOT NULL,
 company_id uuid NOT NULL, actor_id uuid NOT NULL, operation text NOT NULL,
 before_snapshot jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX module_record_history_record_idx ON private_isg.module_record_history(module,record_id);
CREATE TABLE private_isg.module_edit_receipts (
 actor_id uuid NOT NULL,mutation_id uuid NOT NULL,request_hash bytea NOT NULL,response jsonb NOT NULL,
 PRIMARY KEY(actor_id,mutation_id));
ALTER TABLE private_isg.module_record_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.module_record_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.module_edit_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.module_record_links,private_isg.module_record_history,private_isg.module_edit_receipts FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION private_isg.module_editor_guard(p_module text,p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$ BEGIN
 CASE p_module
 WHEN 'emergency_plan' THEN RETURN private_isg.require_emergency_company(p_company,p_write);
 WHEN 'drill' THEN RETURN private_isg.require_drill_company(p_company,p_write);
 WHEN 'ppe' THEN RETURN private_isg.require_ppe_company(p_company,p_write);
 WHEN 'appointment' THEN RETURN private_isg.require_appointment_company(p_company,p_write);
 ELSE RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END CASE;
END $$;
CREATE FUNCTION private_isg.module_editor_snapshot(p_module text,p_company uuid,p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$ DECLARE result jsonb; BEGIN
IF p_module='emergency_plan' THEN SELECT to_jsonb(t) INTO result FROM private_isg.emergency_plan_versions t WHERE t.plan_id=p_id AND t.company_id=p_company AND NOT t.is_deleted ORDER BY t.version DESC LIMIT 1 FOR UPDATE; END IF;
IF p_module='drill' THEN SELECT to_jsonb(t) INTO result FROM private_isg.drill_records t WHERE t.drill_id=p_id AND t.company_id=p_company AND NOT t.is_deleted LIMIT 1 FOR UPDATE; END IF;
IF p_module='ppe' THEN SELECT to_jsonb(t) INTO result FROM private_isg.ppe_handovers t WHERE t.handover_id=p_id AND t.company_id=p_company AND NOT t.is_deleted LIMIT 1 FOR UPDATE; END IF;
IF p_module='appointment' THEN SELECT to_jsonb(t) INTO result FROM private_isg.appointments t WHERE t.appointment_id=p_id AND t.company_id=p_company AND NOT t.is_deleted LIMIT 1 FOR UPDATE; END IF;
IF result IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
IF p_module='ppe' THEN result:=result||jsonb_build_object('returns',(SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.return_id),'[]') FROM private_isg.ppe_returns r WHERE r.handover_id=p_id)); END IF;
RETURN result||jsonb_build_object('document_id',(SELECT obligation_id FROM private_isg.module_record_links WHERE module=p_module AND record_id=p_id));
END $$;
CREATE FUNCTION private_isg.read_module_editor(p_module text,p_company uuid,p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid; snapshot jsonb; BEGIN
actor:=private_isg.module_editor_guard(p_module,p_company,false);
snapshot:=private_isg.module_editor_snapshot(p_module,p_company,p_id);
RETURN jsonb_build_object('snapshot',snapshot,'expected',md5(snapshot::text),'company_name',(SELECT name FROM public.companies WHERE id=p_company),
 'workplaces',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) ORDER BY name),'[]') FROM private_isg.workplaces WHERE company_id=p_company AND NOT is_archived),
 'employees',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',full_name) ORDER BY full_name),'[]') FROM private_isg.employees WHERE company_id=p_company AND NOT is_archived),
 'documents',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',obligation_id,'name',title) ORDER BY title),'[]') FROM private_isg.document_obligations WHERE company_id=p_company AND owner_id=actor AND NOT is_archived),
 'plans',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',plan_id,'name',scope) ORDER BY scope),'[]') FROM private_isg.emergency_plan_versions WHERE company_id=p_company AND state='active' AND NOT is_deleted));
END $$;
CREATE FUNCTION private_isg.mutate_module_editor(p_company uuid,p_action text,p_operation uuid,p_mutation uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
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
 WHEN 'appointment' THEN ARRAY['employee_id','kind','scope_workplace_id','starts_on','ends_before','basis','basis_note','letter_location'] END;
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
  UPDATE private_isg.appointments SET employee_id=person,kind=values_->>'kind',scope_workplace_id=place,
   starts_on=(values_->>'starts_on')::date,ends_before=(values_->>'ends_before')::date,basis=values_->>'basis',
   basis_note=nullif(btrim(values_->>'basis_note'),''),letter_location=nullif(btrim(values_->>'letter_location'),''),updated_at=clock_timestamp() WHERE appointment_id=id;
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
END $$;
CREATE FUNCTION public.isg_pilot_module_editor_v1(p_module text,p_company uuid,p_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.read_module_editor(p_module,p_company,p_id) $$;
CREATE FUNCTION public.isg_pilot_module_mutate_v1(p_company uuid,p_action text,p_operation uuid,p_mutation uuid,p_payload jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.mutate_module_editor(p_company,p_action,p_operation,p_mutation,p_payload) $$;
REVOKE ALL ON FUNCTION private_isg.module_editor_guard(text,uuid,boolean),private_isg.module_editor_snapshot(text,uuid,uuid),private_isg.read_module_editor(text,uuid,uuid),private_isg.mutate_module_editor(uuid,text,uuid,uuid,jsonb),public.isg_pilot_module_editor_v1(text,uuid,uuid),public.isg_pilot_module_mutate_v1(uuid,text,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.read_module_editor(text,uuid,uuid),private_isg.mutate_module_editor(uuid,text,uuid,uuid,jsonb),public.isg_pilot_module_editor_v1(text,uuid,uuid),public.isg_pilot_module_mutate_v1(uuid,text,uuid,uuid,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';

SET LOCAL search_path=public,extensions;
DO $$ DECLARE constraint_name text; BEGIN
 SELECT conname INTO constraint_name FROM pg_constraint WHERE conrelid='private_isg.appointments'::regclass AND contype='x';
 EXECUTE format('ALTER TABLE private_isg.appointments DROP CONSTRAINT %I',constraint_name);
END $$;
ALTER TABLE private_isg.appointments ADD CONSTRAINT appointment_live_overlap EXCLUDE USING gist
 (company_id WITH =,employee_id WITH =,kind WITH =,scope_workplace_id WITH =,effective_dates WITH &&) WHERE (NOT is_deleted);
CREATE FUNCTION private_isg.guard_deleted_module_record() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
BEGIN
 IF OLD.is_deleted THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RECORD_DELETED'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER guard_deleted_module_record BEFORE UPDATE ON private_isg.emergency_plan_versions FOR EACH ROW EXECUTE FUNCTION private_isg.guard_deleted_module_record();
CREATE TRIGGER guard_deleted_module_record BEFORE UPDATE ON private_isg.drill_records FOR EACH ROW EXECUTE FUNCTION private_isg.guard_deleted_module_record();
CREATE TRIGGER guard_deleted_module_record BEFORE UPDATE ON private_isg.ppe_handovers FOR EACH ROW EXECUTE FUNCTION private_isg.guard_deleted_module_record();
CREATE TRIGGER guard_deleted_module_record BEFORE UPDATE ON private_isg.appointments FOR EACH ROW EXECUTE FUNCTION private_isg.guard_deleted_module_record();

CREATE FUNCTION private_isg.guard_deleted_module_parent() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $$
DECLARE parent_deleted boolean; BEGIN
 IF TG_TABLE_NAME='ppe_returns' THEN
  SELECT is_deleted INTO parent_deleted FROM private_isg.ppe_handovers WHERE handover_id=CASE WHEN TG_OP='DELETE' THEN OLD.handover_id ELSE NEW.handover_id END;
 ELSE
  SELECT is_deleted INTO parent_deleted FROM private_isg.emergency_plan_versions WHERE plan_id=NEW.plan_id AND version=NEW.plan_version;
 END IF;
 IF parent_deleted THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RECORD_DELETED'; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF; RETURN NEW;
END $$;
CREATE TRIGGER guard_deleted_parent BEFORE INSERT OR UPDATE OR DELETE ON private_isg.ppe_returns FOR EACH ROW EXECUTE FUNCTION private_isg.guard_deleted_module_parent();
CREATE TRIGGER guard_deleted_parent BEFORE INSERT OR UPDATE ON private_isg.drill_records FOR EACH ROW EXECUTE FUNCTION private_isg.guard_deleted_module_parent();
REVOKE ALL ON FUNCTION private_isg.guard_deleted_module_record(),private_isg.guard_deleted_module_parent() FROM PUBLIC,anon,authenticated,service_role;
