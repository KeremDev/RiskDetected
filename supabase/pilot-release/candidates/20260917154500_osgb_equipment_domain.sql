-- D5 workspace equipment inventory and periodic checks. NOT DEPLOYED; default OFF.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='25s';

ALTER TABLE private_isg.workspace_audit DROP CONSTRAINT workspace_audit_entity_type_check;
ALTER TABLE private_isg.workspace_audit ADD CONSTRAINT workspace_audit_entity_type_check
  CHECK(entity_type IN ('workspace','membership','invitation','company','assignment','seat','subscription',
    'wallet','asset','handover','workplace','department','employee','domain','training','risk',
    'nonconformity','checklist','emergency_plan','drill','appointment','ppe','equipment'));
ALTER TABLE private_isg.workspace_outbox DROP CONSTRAINT workspace_outbox_aggregate_type_check;
ALTER TABLE private_isg.workspace_outbox ADD CONSTRAINT workspace_outbox_aggregate_type_check
  CHECK(aggregate_type IN ('workspace','membership','invitation','company','assignment','seat','subscription',
    'wallet','asset','handover','workplace','department','employee','domain','training','risk',
    'nonconformity','checklist','emergency_plan','drill','appointment','ppe','equipment'));

ALTER TABLE private_isg.equipment_items ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.equipment_items ADD COLUMN equipment_type_label text;
ALTER TABLE private_isg.equipment_items ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.equipment_items ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.equipment_items ADD COLUMN updated_at timestamptz NOT NULL DEFAULT clock_timestamp();
ALTER TABLE private_isg.equipment_items ADD COLUMN version bigint NOT NULL DEFAULT 0;
ALTER TABLE private_isg.equipment_items ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.equipment_items ADD CONSTRAINT equipment_items_type_label_check
  CHECK(equipment_type_label IS NULL OR octet_length(equipment_type_label) BETWEEN 1 AND 120);
ALTER TABLE private_isg.equipment_items ADD CONSTRAINT equipment_items_workspace_company_fk
  FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.equipment_items ADD CONSTRAINT equipment_items_workspace_workplace_fk
  FOREIGN KEY(workspace_id,company_id,workplace_id)
  REFERENCES private_isg.workplaces(workspace_id,company_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.equipment_items ADD CONSTRAINT equipment_items_workspace_identity_unique
  UNIQUE(workspace_id,company_id,equipment_id);

ALTER TABLE private_isg.equipment_inspection_rules ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.equipment_inspection_rules ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.equipment_inspection_rules ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.equipment_inspection_rules ADD COLUMN updated_at timestamptz NOT NULL DEFAULT clock_timestamp();
ALTER TABLE private_isg.equipment_inspection_rules ADD COLUMN version bigint NOT NULL DEFAULT 0;
ALTER TABLE private_isg.equipment_inspection_rules ADD CONSTRAINT equipment_rules_workspace_company_fk
  FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.equipment_inspection_rules ADD CONSTRAINT equipment_rules_workspace_identity_unique
  UNIQUE(workspace_id,company_id,equipment_type);

ALTER TABLE private_isg.equipment_inspections ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.equipment_inspections ADD COLUMN company_id uuid;
ALTER TABLE private_isg.equipment_inspections ADD COLUMN workspace_asset_id uuid
  REFERENCES private_isg.workspace_file_assets(id) ON DELETE RESTRICT;
ALTER TABLE private_isg.equipment_inspections ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.equipment_inspections ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.equipment_inspections ADD COLUMN updated_at timestamptz NOT NULL DEFAULT clock_timestamp();
ALTER TABLE private_isg.equipment_inspections ADD COLUMN version bigint NOT NULL DEFAULT 0;
ALTER TABLE private_isg.equipment_inspections ADD CONSTRAINT equipment_inspections_workspace_parent_fk
  FOREIGN KEY(workspace_id,company_id,equipment_id)
  REFERENCES private_isg.equipment_items(workspace_id,company_id,equipment_id) ON DELETE CASCADE;
ALTER TABLE private_isg.equipment_inspections ADD CONSTRAINT equipment_inspections_workspace_identity_unique
  UNIQUE(workspace_id,company_id,inspection_id);

UPDATE private_isg.equipment_items e SET workspace_id=c.workspace_id,
  equipment_type_label=coalesce(e.equipment_type_label,e.equipment_type),
  created_by_user_id=e.owner_id,updated_by_user_id=e.owner_id
FROM public.companies c WHERE c.id=e.company_id AND c.workspace_id IS NOT NULL;
UPDATE private_isg.equipment_inspection_rules r SET workspace_id=c.workspace_id,
  created_by_user_id=c.user_id,updated_by_user_id=c.user_id
FROM public.companies c WHERE c.id=r.company_id AND c.workspace_id IS NOT NULL;
UPDATE private_isg.equipment_inspections i SET workspace_id=e.workspace_id,company_id=e.company_id,
  created_by_user_id=e.created_by_user_id,updated_by_user_id=e.updated_by_user_id
FROM private_isg.equipment_items e WHERE e.equipment_id=i.equipment_id AND e.workspace_id IS NOT NULL;

CREATE INDEX equipment_workspace_page ON private_isg.equipment_items(workspace_id,company_id,is_archived,equipment_type,equipment_id);
CREATE INDEX equipment_inspection_workspace_page ON private_isg.equipment_inspections(workspace_id,company_id,equipment_id,performed_on DESC,inspection_id);
CREATE INDEX equipment_rule_workspace_page ON private_isg.equipment_inspection_rules(workspace_id,company_id,needs_review,equipment_type);

CREATE FUNCTION private_isg.workspace_equipment_item_invariant() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE company public.companies; workspace private_isg.workspaces;
BEGIN
  IF private_isg.workspace_is_legacy_company_write(NEW.company_id,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.workspace_id ELSE NULL END) THEN RETURN NEW; END IF;
  SELECT * INTO company FROM public.companies WHERE id=NEW.company_id FOR SHARE;
  IF NEW.workspace_id IS NULL THEN NEW.workspace_id:=company.workspace_id; END IF;
  IF company.id IS NULL OR NEW.workspace_id IS DISTINCT FROM company.workspace_id OR NOT EXISTS(
    SELECT 1 FROM private_isg.workplaces w WHERE w.workspace_id=NEW.workspace_id
      AND w.company_id=NEW.company_id AND w.id=NEW.workplace_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='EQUIPMENT_SCOPE_CONFLICT'; END IF;
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
END $$;
CREATE TRIGGER equipment_items_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.equipment_items
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_equipment_item_invariant();

CREATE FUNCTION private_isg.workspace_equipment_rule_invariant() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE company public.companies;
BEGIN
  IF private_isg.workspace_is_legacy_company_write(NEW.company_id,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.workspace_id ELSE NULL END) THEN RETURN NEW; END IF;
  SELECT * INTO company FROM public.companies WHERE id=NEW.company_id FOR SHARE;
  IF NEW.workspace_id IS NULL THEN NEW.workspace_id:=company.workspace_id; END IF;
  IF company.id IS NULL OR NEW.workspace_id IS DISTINCT FROM company.workspace_id THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='EQUIPMENT_RULE_SCOPE_CONFLICT'; END IF;
  IF NEW.created_by_user_id IS NULL OR NEW.updated_by_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACTOR_REQUIRED'; END IF;
  IF TG_OP='UPDATE' AND ROW(NEW.workspace_id,NEW.company_id,NEW.equipment_type,NEW.created_by_user_id)
    IS DISTINCT FROM ROW(OLD.workspace_id,OLD.company_id,OLD.equipment_type,OLD.created_by_user_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IMMUTABLE_SCOPE'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER equipment_rules_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.equipment_inspection_rules
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_equipment_rule_invariant();

CREATE FUNCTION private_isg.workspace_equipment_inspection_invariant() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE item private_isg.equipment_items; asset private_isg.workspace_file_assets;
BEGIN
  SELECT * INTO item FROM private_isg.equipment_items WHERE equipment_id=NEW.equipment_id FOR SHARE;
  IF item.equipment_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='EQUIPMENT_NOT_FOUND'; END IF;
  IF private_isg.workspace_is_legacy_company_write(item.company_id,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.workspace_id ELSE NULL END) THEN RETURN NEW; END IF;
  IF NEW.workspace_id IS NULL THEN NEW.workspace_id:=item.workspace_id; END IF;
  IF NEW.company_id IS NULL THEN NEW.company_id:=item.company_id; END IF;
  IF ROW(NEW.workspace_id,NEW.company_id) IS DISTINCT FROM ROW(item.workspace_id,item.company_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='INSPECTION_SCOPE_CONFLICT'; END IF;
  IF NEW.workspace_asset_id IS NOT NULL THEN
    SELECT * INTO asset FROM private_isg.workspace_file_assets WHERE id=NEW.workspace_asset_id FOR SHARE;
    IF asset.id IS NULL OR asset.workspace_id IS DISTINCT FROM NEW.workspace_id OR
       asset.company_id IS DISTINCT FROM NEW.company_id OR asset.lifecycle<>'active' THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSET_SCOPE_CONFLICT'; END IF;
  END IF;
  IF NEW.created_by_user_id IS NULL OR NEW.updated_by_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACTOR_REQUIRED'; END IF;
  IF TG_OP='UPDATE' AND ROW(NEW.workspace_id,NEW.company_id,NEW.equipment_id,NEW.inspection_id,
      NEW.performed_on,NEW.result,NEW.created_by_user_id) IS DISTINCT FROM
    ROW(OLD.workspace_id,OLD.company_id,OLD.equipment_id,OLD.inspection_id,
      OLD.performed_on,OLD.result,OLD.created_by_user_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IMMUTABLE_REPORT_FACT'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER equipment_inspections_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.equipment_inspections
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_equipment_inspection_invariant();

CREATE FUNCTION private_isg.workspace_equipment_state(p_due date,p_has boolean,p_result text,p_today date)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path='' AS $$
  SELECT CASE WHEN NOT p_has THEN 'never_inspected' WHEN p_result='fail' THEN 'failed'
    WHEN p_due IS NULL THEN 'period_unknown' WHEN p_due<p_today THEN 'overdue'
    WHEN p_due<=p_today+30 THEN 'due_soon' ELSE 'valid' END
$$;

CREATE FUNCTION private_isg.workspace_equipment_row(p_workspace uuid,p_company uuid,p_equipment uuid,p_history boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE item private_isg.equipment_items; latest private_isg.equipment_inspections;
  rule private_isg.equipment_inspection_rules; today date:=(clock_timestamp() AT TIME ZONE 'UTC')::date; state text;
BEGIN
  SELECT * INTO item FROM private_isg.equipment_items WHERE workspace_id=p_workspace
    AND company_id=p_company AND equipment_id=p_equipment;
  IF item.equipment_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO latest FROM private_isg.equipment_inspections WHERE workspace_id=p_workspace
    AND company_id=p_company AND equipment_id=p_equipment ORDER BY performed_on DESC,inspection_id DESC LIMIT 1;
  SELECT * INTO rule FROM private_isg.equipment_inspection_rules WHERE workspace_id=p_workspace
    AND company_id=p_company AND equipment_type=item.equipment_type;
  state:=private_isg.workspace_equipment_state(latest.next_due_on,latest.inspection_id IS NOT NULL,latest.result,today);
  RETURN jsonb_build_object('equipment_id',item.equipment_id,'workplace_id',item.workplace_id,
    'equipment_type',item.equipment_type,'equipment_type_label',coalesce(item.equipment_type_label,item.equipment_type),
    'serial_tag',item.serial_tag,'acquired_on',item.acquired_on,'location_note',item.location_note,
    'is_archived',item.is_archived,'version',item.version,'state',state,'notice_days',30,
    'period_months',rule.period_months,'period_source',rule.period_source,
    'period_needs_review',CASE WHEN rule.equipment_type IS NULL THEN NULL ELSE rule.needs_review END,
    'period_exception_note',rule.exception_note,'last_performed_on',latest.performed_on,
    'last_result',latest.result,'last_inspector',latest.inspector,'last_external_ref',latest.external_ref,
    'next_due_on',latest.next_due_on,'due_source',latest.due_source,
    'katip_assignment_declared',coalesce(latest.katip_assignment_declared,false),
    'katip_declared_note',latest.katip_declared_note,'katip_official_verification',false,
    'workspace_asset_id',latest.workspace_asset_id,
    'inspections',CASE WHEN p_history THEN (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'inspection_id',i.inspection_id,'performed_on',i.performed_on,'result',i.result,
      'next_due_on',i.next_due_on,'period_months',i.period_months,'due_source',i.due_source,
      'inspector',i.inspector,'external_ref',i.external_ref,'note',i.note,
      'workspace_asset_id',i.workspace_asset_id,'version',i.version,
      'katip_assignment_declared',i.katip_assignment_declared,'katip_declared_note',i.katip_declared_note,
      'created_by_user_id',i.created_by_user_id) ORDER BY i.performed_on DESC,i.inspection_id DESC),'[]'::jsonb)
      FROM private_isg.equipment_inspections i WHERE i.workspace_id=p_workspace
        AND i.company_id=p_company AND i.equipment_id=p_equipment) END,
    'created_by_user_id',item.created_by_user_id);
END $$;

CREATE FUNCTION private_isg.workspace_equipment_read(p_workspace uuid,p_company uuid,p_kind text,p_id uuid,
  p_query text,p_state text,p_type text,p_limit integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE rows jsonb; catalog jsonb; needle text:=lower(btrim(coalesce(p_query,'')));
BEGIN
  PERFORM private_isg.workspace_domain_gate('equipment',false);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,false);
  IF p_kind NOT IN ('inventory','detail','catalog','rules') OR p_limit NOT BETWEEN 1 AND 100 OR
     (p_kind='detail' AND p_id IS NULL) OR
     (p_state IS NOT NULL AND p_state NOT IN ('never_inspected','period_unknown','failed','overdue','due_soon','valid')) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_kind='catalog' THEN
    SELECT jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
      'notice_days',30,'suggestions',(SELECT coalesce(jsonb_agg(jsonb_build_object('code',s.equipment_type,
        'ordinal',s.ordinal,'default_period_months',d.period_months,'default_basis_note',d.basis_note)
        ORDER BY s.ordinal),'[]'::jsonb) FROM private_isg.equipment_type_suggestions s
        LEFT JOIN private_isg.equipment_default_periods d ON d.equipment_type=s.equipment_type),
      'rules',(SELECT coalesce(jsonb_agg(jsonb_build_object('equipment_type',r.equipment_type,
        'period_months',r.period_months,'period_source',r.period_source,'needs_review',r.needs_review,
        'exception_note',r.exception_note,'version',r.version) ORDER BY r.equipment_type),'[]'::jsonb)
        FROM private_isg.equipment_inspection_rules r WHERE r.workspace_id=p_workspace AND r.company_id=p_company)) INTO catalog;
    RETURN catalog;
  ELSIF p_kind='rules' THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object('equipment_type',r.equipment_type,'period_months',r.period_months,
      'period_source',r.period_source,'needs_review',r.needs_review,'exception_note',r.exception_note,
      'version',r.version) ORDER BY r.equipment_type),'[]'::jsonb) INTO rows
    FROM private_isg.equipment_inspection_rules r WHERE r.workspace_id=p_workspace AND r.company_id=p_company;
  ELSE
    SELECT coalesce(jsonb_agg(row_payload ORDER BY equipment_id),'[]'::jsonb) INTO rows FROM (
      SELECT e.equipment_id,private_isg.workspace_equipment_row(p_workspace,p_company,e.equipment_id,p_kind='detail') row_payload
      FROM private_isg.equipment_items e WHERE e.workspace_id=p_workspace AND e.company_id=p_company
        AND (p_kind='detail' OR NOT e.is_archived) AND (p_id IS NULL OR e.equipment_id=p_id)
        AND (p_type IS NULL OR e.equipment_type=p_type)
        AND (needle='' OR lower(e.serial_tag||' '||coalesce(e.equipment_type_label,e.equipment_type)||' '||coalesce(e.location_note,'')) LIKE '%'||needle||'%')
        AND (p_state IS NULL OR private_isg.workspace_equipment_row(p_workspace,p_company,e.equipment_id,false)->>'state'=p_state)
      ORDER BY e.created_at DESC,e.equipment_id LIMIT p_limit) q;
    IF p_kind='detail' AND jsonb_array_length(rows)=0 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  END IF;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'kind',p_kind,'rows',rows,'total',jsonb_array_length(rows));
END $$;

CREATE FUNCTION private_isg.workspace_equipment_mutate(p_mutation uuid,p_workspace uuid,p_company uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); action text; fingerprint bytea; replay jsonb; target uuid;
  expected bigint; item private_isg.equipment_items; rule private_isg.equipment_inspection_rules;
  report private_isg.equipment_inspections; result jsonb; before_state jsonb; aggregate_version bigint:=0;
  performed date; derived date; chosen date; source text; needs boolean; label text; asset uuid;
BEGIN
  PERFORM private_isg.workspace_domain_gate('equipment',true);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,true);
  IF p_mutation IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>32768 OR
     EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) AS keys(key) WHERE key NOT IN
       ('action','id','inspection_id','expected_version','workplace_id','equipment_type','equipment_type_label',
        'serial_tag','acquired_on','location_note','period_months','period_source','exception_note',
        'performed_on','result','next_due_on','inspector','external_ref','note','workspace_asset_id',
        'katip_declared','katip_note')) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  action:=p_payload->>'action'; target:=(p_payload->>'id')::uuid;
  IF action IS NULL OR action NOT IN ('set_rule','register','update','archive','record_inspection','update_inspection') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_company,p_payload)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'equipment.'||action,fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;

  IF action='set_rule' THEN
    source:=p_payload->>'period_source'; needs:=source='unapproved_fixture';
    IF coalesce(p_payload->>'equipment_type','') !~ '^[a-z][a-z0-9_]{2,40}$' OR
       (p_payload->>'period_months')::integer NOT BETWEEN 1 AND 240 OR
       source NOT IN ('manufacturer','rule_version','unapproved_fixture') OR
       (needs AND length(btrim(coalesce(p_payload->>'exception_note','')))<10) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    SELECT * INTO rule FROM private_isg.equipment_inspection_rules WHERE workspace_id=p_workspace
      AND company_id=p_company AND equipment_type=p_payload->>'equipment_type' FOR UPDATE;
    before_state:=CASE WHEN rule.equipment_type IS NULL THEN NULL ELSE to_jsonb(rule) END;
    INSERT INTO private_isg.equipment_inspection_rules(workspace_id,company_id,equipment_type,period_months,
      period_source,exception_note,needs_review,created_by_user_id,updated_by_user_id)
    VALUES(p_workspace,p_company,p_payload->>'equipment_type',(p_payload->>'period_months')::integer,source,
      nullif(btrim(coalesce(p_payload->>'exception_note','')),''),needs,actor,actor)
    ON CONFLICT(company_id,equipment_type) DO UPDATE SET period_months=excluded.period_months,
      period_source=excluded.period_source,exception_note=excluded.exception_note,needs_review=excluded.needs_review,
      version=private_isg.equipment_inspection_rules.version+1,updated_by_user_id=actor,updated_at=clock_timestamp()
    RETURNING * INTO rule;
    target:=p_company; aggregate_version:=rule.version;
    result:=jsonb_build_object('equipment_type',rule.equipment_type,'period_months',rule.period_months,
      'period_source',rule.period_source,'needs_review',rule.needs_review,'version',rule.version);
  ELSIF action='register' THEN
    label:=private_isg.workspace_text(coalesce(p_payload->>'equipment_type_label',p_payload->>'equipment_type'),120);
    IF coalesce(p_payload->>'equipment_type','') !~ '^[a-z][a-z0-9_]{2,40}$' THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    INSERT INTO private_isg.equipment_items(workspace_id,company_id,owner_id,workplace_id,equipment_type,
      equipment_type_label,serial_tag,acquired_on,location_note,created_by_user_id,updated_by_user_id)
    VALUES(p_workspace,p_company,NULL,(p_payload->>'workplace_id')::uuid,p_payload->>'equipment_type',label,
      private_isg.workspace_text(p_payload->>'serial_tag',100),(p_payload->>'acquired_on')::date,
      nullif(btrim(coalesce(p_payload->>'location_note','')),''),actor,actor) RETURNING * INTO item;
    IF NOT EXISTS(SELECT 1 FROM private_isg.equipment_inspection_rules WHERE workspace_id=p_workspace
      AND company_id=p_company AND equipment_type=item.equipment_type) THEN
      INSERT INTO private_isg.equipment_inspection_rules(workspace_id,company_id,equipment_type,period_months,
        period_source,exception_note,needs_review,created_by_user_id,updated_by_user_id)
      SELECT p_workspace,p_company,d.equipment_type,d.period_months,'regulation_default',d.basis_note,true,actor,actor
      FROM private_isg.equipment_default_periods d WHERE d.equipment_type=item.equipment_type
      ON CONFLICT(company_id,equipment_type) DO NOTHING;
    END IF;
    target:=item.equipment_id; aggregate_version:=item.version;
    result:=private_isg.workspace_equipment_row(p_workspace,p_company,target,true);
  ELSE
    expected:=(p_payload->>'expected_version')::bigint;
    SELECT * INTO item FROM private_isg.equipment_items WHERE workspace_id=p_workspace
      AND company_id=p_company AND equipment_id=target FOR UPDATE;
    IF item.equipment_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF item.version<>expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    before_state:=private_isg.workspace_equipment_row(p_workspace,p_company,target,true);
    IF action='update' THEN
      UPDATE private_isg.equipment_items SET
        workplace_id=coalesce((p_payload->>'workplace_id')::uuid,workplace_id),
        serial_tag=coalesce(private_isg.workspace_text(p_payload->>'serial_tag',100),serial_tag),
        acquired_on=CASE WHEN p_payload ? 'acquired_on' THEN (p_payload->>'acquired_on')::date ELSE acquired_on END,
        location_note=CASE WHEN p_payload ? 'location_note' THEN nullif(btrim(coalesce(p_payload->>'location_note','')),'') ELSE location_note END,
        version=version+1,updated_by_user_id=actor,updated_at=clock_timestamp()
      WHERE equipment_id=target RETURNING * INTO item;
    ELSIF action='archive' THEN
      UPDATE private_isg.equipment_items SET is_archived=true,version=version+1,
        updated_by_user_id=actor,updated_at=clock_timestamp() WHERE equipment_id=target RETURNING * INTO item;
    ELSIF action='record_inspection' THEN
      IF item.is_archived THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      performed:=(p_payload->>'performed_on')::date;
      IF performed IS NULL OR performed>(clock_timestamp() AT TIME ZONE 'UTC')::date OR
         p_payload->>'result' NOT IN ('pass','fail','conditional') THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      SELECT * INTO rule FROM private_isg.equipment_inspection_rules WHERE workspace_id=p_workspace
        AND company_id=p_company AND equipment_type=item.equipment_type;
      IF rule.equipment_type IS NOT NULL AND p_payload->>'result'<>'fail' THEN
        derived:=(performed+make_interval(months=>rule.period_months))::date; END IF;
      chosen:=coalesce((p_payload->>'next_due_on')::date,derived);
      IF chosen IS NOT NULL AND (chosen<=performed OR p_payload->>'result'='fail') THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DUE_DATE_CONFLICT'; END IF;
      asset:=(p_payload->>'workspace_asset_id')::uuid;
      INSERT INTO private_isg.equipment_inspections(workspace_id,company_id,equipment_id,performed_on,result,
        next_due_on,period_months,inspector,external_ref,note,due_source,katip_assignment_declared,
        katip_declared_note,workspace_asset_id,created_by_user_id,updated_by_user_id)
      VALUES(p_workspace,p_company,target,performed,p_payload->>'result',chosen,rule.period_months,
        nullif(btrim(coalesce(p_payload->>'inspector','')),''),nullif(btrim(coalesce(p_payload->>'external_ref','')),''),
        nullif(btrim(coalesce(p_payload->>'note','')),''),CASE WHEN chosen IS NULL THEN NULL
          WHEN chosen=derived THEN 'period' ELSE 'expert' END,
        coalesce((p_payload->>'katip_declared')::boolean,false),
        CASE WHEN coalesce((p_payload->>'katip_declared')::boolean,false)
          THEN nullif(btrim(coalesce(p_payload->>'katip_note','')),'') END,asset,actor,actor)
      RETURNING * INTO report;
      UPDATE private_isg.equipment_items SET version=version+1,updated_by_user_id=actor,
        updated_at=clock_timestamp() WHERE equipment_id=target RETURNING * INTO item;
    ELSE
      SELECT * INTO report FROM private_isg.equipment_inspections WHERE workspace_id=p_workspace
        AND company_id=p_company AND equipment_id=target AND inspection_id=(p_payload->>'inspection_id')::uuid FOR UPDATE;
      IF report.inspection_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
      SELECT * INTO rule FROM private_isg.equipment_inspection_rules WHERE workspace_id=p_workspace
        AND company_id=p_company AND equipment_type=item.equipment_type;
      IF rule.equipment_type IS NOT NULL AND report.result<>'fail' THEN
        derived:=(report.performed_on+make_interval(months=>rule.period_months))::date; END IF;
      chosen:=CASE WHEN p_payload ? 'next_due_on' THEN (p_payload->>'next_due_on')::date ELSE report.next_due_on END;
      IF chosen IS NOT NULL AND (chosen<=report.performed_on OR report.result='fail') THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DUE_DATE_CONFLICT'; END IF;
      asset:=CASE WHEN p_payload ? 'workspace_asset_id' THEN (p_payload->>'workspace_asset_id')::uuid ELSE report.workspace_asset_id END;
      UPDATE private_isg.equipment_inspections SET next_due_on=chosen,
        due_source=CASE WHEN chosen IS NULL THEN NULL WHEN chosen=derived THEN 'period' ELSE 'expert' END,
        inspector=CASE WHEN p_payload ? 'inspector' THEN nullif(btrim(coalesce(p_payload->>'inspector','')),'') ELSE inspector END,
        external_ref=CASE WHEN p_payload ? 'external_ref' THEN nullif(btrim(coalesce(p_payload->>'external_ref','')),'') ELSE external_ref END,
        note=CASE WHEN p_payload ? 'note' THEN nullif(btrim(coalesce(p_payload->>'note','')),'') ELSE note END,
        workspace_asset_id=asset,
        katip_assignment_declared=CASE WHEN p_payload ? 'katip_declared' THEN coalesce((p_payload->>'katip_declared')::boolean,false) ELSE katip_assignment_declared END,
        katip_declared_note=CASE WHEN p_payload ? 'katip_declared' AND NOT coalesce((p_payload->>'katip_declared')::boolean,false) THEN NULL
          WHEN p_payload ? 'katip_note' THEN nullif(btrim(coalesce(p_payload->>'katip_note','')),'') ELSE katip_declared_note END,
        version=version+1,updated_by_user_id=actor,updated_at=clock_timestamp()
      WHERE inspection_id=report.inspection_id RETURNING * INTO report;
      UPDATE private_isg.equipment_items SET version=version+1,updated_by_user_id=actor,
        updated_at=clock_timestamp() WHERE equipment_id=target RETURNING * INTO item;
    END IF;
    aggregate_version:=item.version;
    result:=private_isg.workspace_equipment_row(p_workspace,p_company,target,true);
  END IF;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'action',action,'row',result);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'equipment.'||action,fingerprint,p_workspace,
    'equipment',target,aggregate_version,before_state,result,NULL,result);
END $$;

CREATE FUNCTION private_isg.workspace_equipment_metrics(p_workspace uuid,p_company uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb;
BEGIN
  PERFORM private_isg.workspace_domain_gate('equipment',false);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,false);
  WITH states AS (SELECT private_isg.workspace_equipment_row(p_workspace,p_company,e.equipment_id,false)->>'state' state
    FROM private_isg.equipment_items e WHERE e.workspace_id=p_workspace AND e.company_id=p_company AND NOT e.is_archived)
  SELECT jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,'measured',true,
    'total',(SELECT count(*) FROM states),'overdue',(SELECT count(*) FROM states WHERE state='overdue'),
    'failed',(SELECT count(*) FROM states WHERE state='failed'),'untracked',(SELECT count(*) FROM states WHERE state IN ('never_inspected','period_unknown')),
    'due_soon',(SELECT count(*) FROM states WHERE state='due_soon'),'current',(SELECT count(*) FROM states WHERE state='valid'),
    'periods_needing_review',(SELECT count(*) FROM private_isg.equipment_inspection_rules
      WHERE workspace_id=p_workspace AND company_id=p_company AND needs_review)) INTO result;
  RETURN result;
END $$;

CREATE FUNCTION public.isg_workspace_equipment_read_v1(p_workspace uuid,p_company uuid,p_kind text,
  p_id uuid DEFAULT NULL,p_query text DEFAULT NULL,p_state text DEFAULT NULL,p_type text DEFAULT NULL,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_equipment_read(p_workspace,p_company,p_kind,p_id,p_query,p_state,p_type,p_limit) $$;
CREATE FUNCTION public.isg_workspace_equipment_mutate_v1(p_mutation uuid,p_workspace uuid,p_company uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_equipment_mutate(p_mutation,p_workspace,p_company,p_payload) $$;
CREATE FUNCTION public.isg_workspace_equipment_metrics_v1(p_workspace uuid,p_company uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_equipment_metrics(p_workspace,p_company) $$;

REVOKE ALL ON FUNCTION private_isg.workspace_equipment_item_invariant(),
  private_isg.workspace_equipment_rule_invariant(),private_isg.workspace_equipment_inspection_invariant(),
  private_isg.workspace_equipment_state(date,boolean,text,date),
  private_isg.workspace_equipment_row(uuid,uuid,uuid,boolean),
  private_isg.workspace_equipment_read(uuid,uuid,text,uuid,text,text,text,integer),
  private_isg.workspace_equipment_mutate(uuid,uuid,uuid,jsonb),private_isg.workspace_equipment_metrics(uuid,uuid),
  public.isg_workspace_equipment_read_v1(uuid,uuid,text,uuid,text,text,text,integer),
  public.isg_workspace_equipment_mutate_v1(uuid,uuid,uuid,jsonb),public.isg_workspace_equipment_metrics_v1(uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_equipment_read(uuid,uuid,text,uuid,text,text,text,integer),
  private_isg.workspace_equipment_mutate(uuid,uuid,uuid,jsonb),private_isg.workspace_equipment_metrics(uuid,uuid),
  public.isg_workspace_equipment_read_v1(uuid,uuid,text,uuid,text,text,text,integer),
  public.isg_workspace_equipment_mutate_v1(uuid,uuid,uuid,jsonb),public.isg_workspace_equipment_metrics_v1(uuid,uuid)
  TO authenticated;
NOTIFY pgrst,'reload schema';
