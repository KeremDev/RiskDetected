-- D3 workspace risk, nonconformity and checklist slice. NOT DEPLOYED; default OFF.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='25s';

ALTER TABLE private_isg.workspace_audit DROP CONSTRAINT workspace_audit_entity_type_check;
ALTER TABLE private_isg.workspace_audit ADD CONSTRAINT workspace_audit_entity_type_check
  CHECK(entity_type IN ('workspace','membership','invitation','company','assignment','seat','subscription',
    'wallet','asset','handover','workplace','department','employee','domain','training','risk',
    'nonconformity','checklist'));
ALTER TABLE private_isg.workspace_outbox DROP CONSTRAINT workspace_outbox_aggregate_type_check;
ALTER TABLE private_isg.workspace_outbox ADD CONSTRAINT workspace_outbox_aggregate_type_check
  CHECK(aggregate_type IN ('workspace','membership','invitation','company','assignment','seat','subscription',
    'wallet','asset','handover','workplace','department','employee','domain','training','risk',
    'nonconformity','checklist'));

ALTER TABLE private_isg.risk_assessments ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.risk_assessments ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.risk_assessments ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.risk_assessments ADD COLUMN version bigint NOT NULL DEFAULT 0;
ALTER TABLE private_isg.risk_assessments ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.risk_assessments ADD CONSTRAINT risk_assessments_workspace_company_fk
  FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.risk_assessments ADD CONSTRAINT risk_assessments_workspace_workplace_fk
  FOREIGN KEY(workspace_id,company_id,workplace_id)
  REFERENCES private_isg.workplaces(workspace_id,company_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.risk_assessments ADD CONSTRAINT risk_assessments_workspace_identity_unique
  UNIQUE(workspace_id,company_id,assessment_id);

ALTER TABLE private_isg.risk_assessment_versions ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.risk_assessment_versions ADD COLUMN company_id uuid;
ALTER TABLE private_isg.risk_assessment_versions ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.risk_assessment_versions ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.risk_assessment_versions ADD CONSTRAINT risk_versions_workspace_parent_fk
  FOREIGN KEY(workspace_id,company_id,assessment_id)
  REFERENCES private_isg.risk_assessments(workspace_id,company_id,assessment_id) ON DELETE CASCADE;
ALTER TABLE private_isg.risk_assessment_versions ADD CONSTRAINT risk_versions_workspace_identity_unique
  UNIQUE(workspace_id,company_id,assessment_id,version);

ALTER TABLE private_isg.risk_source_links ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.risk_source_links ADD COLUMN company_id uuid;
ALTER TABLE private_isg.risk_source_links ADD COLUMN selected_by_user_id uuid;
ALTER TABLE private_isg.risk_source_links ADD CONSTRAINT risk_sources_workspace_version_fk
  FOREIGN KEY(workspace_id,company_id,assessment_id,version)
  REFERENCES private_isg.risk_assessment_versions(workspace_id,company_id,assessment_id,version) ON DELETE CASCADE;

ALTER TABLE private_isg.nonconformities ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.nonconformities ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.nonconformities ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.nonconformities ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.nonconformities ADD CONSTRAINT nonconformities_workspace_company_fk
  FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.nonconformities ADD CONSTRAINT nonconformities_workspace_workplace_fk
  FOREIGN KEY(workspace_id,company_id,workplace_id)
  REFERENCES private_isg.workplaces(workspace_id,company_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.nonconformities ADD CONSTRAINT nonconformities_workspace_identity_unique
  UNIQUE(workspace_id,company_id,nonconformity_id);

ALTER TABLE private_isg.nonconformity_transitions ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.nonconformity_transitions ADD COLUMN company_id uuid;
ALTER TABLE private_isg.nonconformity_transitions ADD CONSTRAINT nonconformity_transitions_workspace_parent_fk
  FOREIGN KEY(workspace_id,company_id,nonconformity_id)
  REFERENCES private_isg.nonconformities(workspace_id,company_id,nonconformity_id) ON DELETE CASCADE;
ALTER TABLE private_isg.nonconformity_actions ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.nonconformity_actions ADD COLUMN company_id uuid;
ALTER TABLE private_isg.nonconformity_actions ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.nonconformity_actions ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.nonconformity_actions ADD CONSTRAINT nonconformity_actions_workspace_parent_fk
  FOREIGN KEY(workspace_id,company_id,nonconformity_id)
  REFERENCES private_isg.nonconformities(workspace_id,company_id,nonconformity_id) ON DELETE CASCADE;
ALTER TABLE private_isg.verification_records ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.verification_records ADD COLUMN company_id uuid;
ALTER TABLE private_isg.verification_records ADD CONSTRAINT verification_records_workspace_parent_fk
  FOREIGN KEY(workspace_id,company_id,nonconformity_id)
  REFERENCES private_isg.nonconformities(workspace_id,company_id,nonconformity_id) ON DELETE CASCADE;

ALTER TABLE private_isg.checklist_runs ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.checklist_runs ADD COLUMN created_by_user_id uuid;
ALTER TABLE private_isg.checklist_runs ADD COLUMN updated_by_user_id uuid;
ALTER TABLE private_isg.checklist_runs ADD COLUMN version bigint NOT NULL DEFAULT 0;
ALTER TABLE private_isg.checklist_runs ADD COLUMN updated_at timestamptz NOT NULL DEFAULT clock_timestamp();
ALTER TABLE private_isg.checklist_runs ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE private_isg.checklist_runs ADD CONSTRAINT checklist_runs_workspace_company_fk
  FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.checklist_runs ADD CONSTRAINT checklist_runs_workspace_workplace_fk
  FOREIGN KEY(workspace_id,company_id,workplace_id)
  REFERENCES private_isg.workplaces(workspace_id,company_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.checklist_runs ADD CONSTRAINT checklist_runs_workspace_identity_unique
  UNIQUE(workspace_id,company_id,run_id);
ALTER TABLE private_isg.checklist_run_items ADD COLUMN workspace_id uuid;
ALTER TABLE private_isg.checklist_run_items ADD COLUMN company_id uuid;
ALTER TABLE private_isg.checklist_run_items ADD COLUMN recorded_by_user_id uuid;
ALTER TABLE private_isg.checklist_run_items ADD CONSTRAINT checklist_items_workspace_parent_fk
  FOREIGN KEY(workspace_id,company_id,run_id)
  REFERENCES private_isg.checklist_runs(workspace_id,company_id,run_id) ON DELETE CASCADE;

UPDATE private_isg.risk_assessments a SET workspace_id=c.workspace_id,
  created_by_user_id=a.owner_id,updated_by_user_id=a.owner_id
FROM public.companies c WHERE c.id=a.company_id AND c.workspace_id IS NOT NULL;
UPDATE private_isg.risk_assessment_versions v SET workspace_id=a.workspace_id,company_id=a.company_id,
  created_by_user_id=coalesce(v.verified_by,a.created_by_user_id),updated_by_user_id=coalesce(v.verified_by,a.updated_by_user_id)
FROM private_isg.risk_assessments a WHERE a.assessment_id=v.assessment_id AND a.workspace_id IS NOT NULL;
UPDATE private_isg.risk_source_links l SET workspace_id=v.workspace_id,company_id=v.company_id,
  selected_by_user_id=v.created_by_user_id FROM private_isg.risk_assessment_versions v
WHERE v.assessment_id=l.assessment_id AND v.version=l.version AND v.workspace_id IS NOT NULL;
UPDATE private_isg.nonconformities n SET workspace_id=c.workspace_id,
  created_by_user_id=n.owner_id,updated_by_user_id=n.owner_id
FROM public.companies c WHERE c.id=n.company_id AND c.workspace_id IS NOT NULL;
UPDATE private_isg.nonconformity_transitions t SET workspace_id=n.workspace_id,company_id=n.company_id
FROM private_isg.nonconformities n WHERE n.nonconformity_id=t.nonconformity_id AND n.workspace_id IS NOT NULL;
UPDATE private_isg.nonconformity_actions a SET workspace_id=n.workspace_id,company_id=n.company_id,
  created_by_user_id=n.created_by_user_id,updated_by_user_id=n.updated_by_user_id
FROM private_isg.nonconformities n WHERE n.nonconformity_id=a.nonconformity_id AND n.workspace_id IS NOT NULL;
UPDATE private_isg.verification_records v SET workspace_id=n.workspace_id,company_id=n.company_id
FROM private_isg.nonconformities n WHERE n.nonconformity_id=v.nonconformity_id AND n.workspace_id IS NOT NULL;
UPDATE private_isg.checklist_runs r SET workspace_id=c.workspace_id,
  created_by_user_id=r.owner_id,updated_by_user_id=r.owner_id
FROM public.companies c WHERE c.id=r.company_id AND c.workspace_id IS NOT NULL;
UPDATE private_isg.checklist_run_items i SET workspace_id=r.workspace_id,company_id=r.company_id,
  recorded_by_user_id=r.created_by_user_id
FROM private_isg.checklist_runs r WHERE r.run_id=i.run_id AND r.workspace_id IS NOT NULL;

CREATE INDEX risk_assessments_workspace_page ON private_isg.risk_assessments(workspace_id,company_id,valid_until,assessment_id);
CREATE INDEX nonconformities_workspace_page ON private_isg.nonconformities(workspace_id,company_id,state,due_on,nonconformity_id);
CREATE INDEX checklist_runs_workspace_page ON private_isg.checklist_runs(workspace_id,company_id,state,run_id);

CREATE FUNCTION private_isg.workspace_assurance_root_invariant() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE company public.companies; workspace private_isg.workspaces; workplace_id uuid;
BEGIN
  IF private_isg.workspace_is_legacy_company_write(NEW.company_id,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.workspace_id ELSE NULL END) THEN RETURN NEW; END IF;
  SELECT * INTO company FROM public.companies WHERE id=NEW.company_id FOR SHARE;
  IF company.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='COMPANY_NOT_FOUND'; END IF;
  IF NEW.workspace_id IS NULL THEN NEW.workspace_id:=company.workspace_id; END IF;
  IF NEW.workspace_id IS DISTINCT FROM company.workspace_id THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='COMPANY_SCOPE_CONFLICT'; END IF;
  IF NEW.workspace_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO workspace FROM private_isg.workspaces WHERE id=NEW.workspace_id;
  IF workspace.kind='osgb' AND NEW.owner_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEGACY_OWNER_FORBIDDEN'; END IF;
  IF workspace.kind='personal' AND NEW.owner_id IS DISTINCT FROM company.user_id THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEGACY_OWNER_MISMATCH'; END IF;
  IF NOT EXISTS(SELECT 1 FROM private_isg.workplaces w WHERE w.workspace_id=NEW.workspace_id
      AND w.company_id=NEW.company_id AND w.id=NEW.workplace_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='WORKPLACE_SCOPE_CONFLICT'; END IF;
  IF NEW.created_by_user_id IS NULL OR NEW.updated_by_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACTOR_REQUIRED'; END IF;
  IF TG_OP='UPDATE' AND ROW(NEW.workspace_id,NEW.company_id,NEW.owner_id,NEW.workplace_id,NEW.created_by_user_id)
    IS DISTINCT FROM ROW(OLD.workspace_id,OLD.company_id,OLD.owner_id,OLD.workplace_id,OLD.created_by_user_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IMMUTABLE_SCOPE'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER risk_assessments_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.risk_assessments
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_assurance_root_invariant();
CREATE TRIGGER nonconformities_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.nonconformities
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_assurance_root_invariant();
CREATE TRIGGER checklist_runs_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.checklist_runs
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_assurance_root_invariant();

CREATE FUNCTION private_isg.workspace_risk_child_invariant() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE parent private_isg.risk_assessments;
BEGIN
  SELECT * INTO parent FROM private_isg.risk_assessments WHERE assessment_id=NEW.assessment_id FOR SHARE;
  IF parent.assessment_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='RISK_PARENT_NOT_FOUND'; END IF;
  IF private_isg.workspace_is_legacy_company_write(parent.company_id,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.workspace_id ELSE NULL END) THEN RETURN NEW; END IF;
  IF NEW.workspace_id IS NULL THEN NEW.workspace_id:=parent.workspace_id; END IF;
  IF NEW.company_id IS NULL THEN NEW.company_id:=parent.company_id; END IF;
  IF ROW(NEW.workspace_id,NEW.company_id) IS DISTINCT FROM ROW(parent.workspace_id,parent.company_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RISK_SCOPE_CONFLICT'; END IF;
  IF TG_OP='UPDATE' AND ROW(NEW.workspace_id,NEW.company_id,NEW.assessment_id)
    IS DISTINCT FROM ROW(OLD.workspace_id,OLD.company_id,OLD.assessment_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IMMUTABLE_SCOPE'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER risk_versions_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.risk_assessment_versions
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_risk_child_invariant();
CREATE TRIGGER risk_sources_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.risk_source_links
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_risk_child_invariant();

CREATE FUNCTION private_isg.workspace_nonconformity_child_invariant() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE parent private_isg.nonconformities;
BEGIN
  SELECT * INTO parent FROM private_isg.nonconformities WHERE nonconformity_id=NEW.nonconformity_id FOR SHARE;
  IF parent.nonconformity_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='NONCONFORMITY_PARENT_NOT_FOUND'; END IF;
  IF private_isg.workspace_is_legacy_company_write(parent.company_id,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.workspace_id ELSE NULL END) THEN RETURN NEW; END IF;
  IF NEW.workspace_id IS NULL THEN NEW.workspace_id:=parent.workspace_id; END IF;
  IF NEW.company_id IS NULL THEN NEW.company_id:=parent.company_id; END IF;
  IF ROW(NEW.workspace_id,NEW.company_id) IS DISTINCT FROM ROW(parent.workspace_id,parent.company_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='NONCONFORMITY_SCOPE_CONFLICT'; END IF;
  IF TG_OP='UPDATE' AND ROW(NEW.workspace_id,NEW.company_id,NEW.nonconformity_id)
    IS DISTINCT FROM ROW(OLD.workspace_id,OLD.company_id,OLD.nonconformity_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IMMUTABLE_SCOPE'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER nonconformity_transitions_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.nonconformity_transitions
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_nonconformity_child_invariant();
CREATE TRIGGER nonconformity_actions_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.nonconformity_actions
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_nonconformity_child_invariant();
CREATE TRIGGER verification_records_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.verification_records
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_nonconformity_child_invariant();

CREATE FUNCTION private_isg.workspace_checklist_item_invariant() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE parent private_isg.checklist_runs;
BEGIN
  SELECT * INTO parent FROM private_isg.checklist_runs WHERE run_id=NEW.run_id FOR SHARE;
  IF parent.run_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='CHECKLIST_PARENT_NOT_FOUND'; END IF;
  IF private_isg.workspace_is_legacy_company_write(parent.company_id,NEW.workspace_id,
      CASE WHEN TG_OP='UPDATE' THEN OLD.workspace_id ELSE NULL END) THEN RETURN NEW; END IF;
  IF NEW.workspace_id IS NULL THEN NEW.workspace_id:=parent.workspace_id; END IF;
  IF NEW.company_id IS NULL THEN NEW.company_id:=parent.company_id; END IF;
  IF ROW(NEW.workspace_id,NEW.company_id) IS DISTINCT FROM ROW(parent.workspace_id,parent.company_id) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CHECKLIST_SCOPE_CONFLICT'; END IF;
  IF TG_OP='UPDATE' AND ROW(NEW.workspace_id,NEW.company_id,NEW.run_id,NEW.item_code)
    IS DISTINCT FROM ROW(OLD.workspace_id,OLD.company_id,OLD.run_id,OLD.item_code) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IMMUTABLE_SCOPE'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER checklist_items_workspace_scope_before BEFORE INSERT OR UPDATE ON private_isg.checklist_run_items
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_checklist_item_invariant();

CREATE FUNCTION private_isg.workspace_risk_row(p_workspace uuid,p_company uuid,p_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT jsonb_build_object('assessment_id',a.assessment_id,'company_id',a.company_id,
    'workplace_id',a.workplace_id,'current_version',a.current_version,
    'base_assessment_on',a.base_assessment_on,'valid_until',a.valid_until,'version',a.version,
    'created_by_user_id',a.created_by_user_id,
    'versions',coalesce((SELECT jsonb_agg(jsonb_build_object('version',v.version,'kind',v.kind,
      'assessment_on',v.assessment_on,'revision_on',v.revision_on,'scope',v.scope,'reason',v.reason,
      'state',v.state,'valid_until',v.valid_until,'period_years',v.period_years,
      'period_source',v.period_source,'period_needs_review',v.period_needs_review,
      'source_drift',v.source_drift,'created_by_user_id',v.created_by_user_id) ORDER BY v.version DESC)
      FROM private_isg.risk_assessment_versions v WHERE v.workspace_id=p_workspace
        AND v.company_id=p_company AND v.assessment_id=a.assessment_id),'[]'::jsonb))
  FROM private_isg.risk_assessments a
  WHERE a.workspace_id=p_workspace AND a.company_id=p_company AND a.assessment_id=p_id
$$;

CREATE FUNCTION private_isg.workspace_risk_read(p_workspace uuid,p_company uuid,p_id uuid,p_after uuid,p_limit integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE rows jsonb; next_id uuid;
BEGIN
  PERFORM private_isg.workspace_domain_gate('risk_nonconformity',false);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,false);
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 OR (p_id IS NOT NULL AND p_after IS NOT NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_id IS NOT NULL THEN
    rows:=private_isg.workspace_risk_row(p_workspace,p_company,p_id);
    IF rows IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,'row',rows);
  END IF;
  WITH page AS (
    SELECT assessment_id FROM private_isg.risk_assessments
    WHERE workspace_id=p_workspace AND company_id=p_company
      AND (p_after IS NULL OR assessment_id>p_after)
    ORDER BY assessment_id LIMIT p_limit+1
  ), numbered AS (
    SELECT assessment_id,row_number() OVER (ORDER BY assessment_id) ordinal,count(*) OVER () total FROM page
  )
  SELECT coalesce(jsonb_agg(private_isg.workspace_risk_row(p_workspace,p_company,assessment_id)
      ORDER BY assessment_id) FILTER (WHERE ordinal<=p_limit),'[]'::jsonb),
    (array_agg(assessment_id) FILTER (WHERE ordinal=p_limit AND total>p_limit))[1]
    INTO rows,next_id FROM numbered;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'rows',rows,'next',next_id);
END $$;

CREATE FUNCTION private_isg.workspace_risk_mutate(p_mutation uuid,p_workspace uuid,p_company uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); action text; fingerprint bytea; replay jsonb;
  assessment private_isg.risk_assessments; revision private_isg.risk_assessment_versions;
  workplace uuid; expected integer; version_no integer; kind text; assessed date; revised date;
  years integer; valid date; before_state jsonb; result jsonb;
BEGIN
  PERFORM private_isg.workspace_domain_gate('risk_nonconformity',true);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,true);
  IF p_mutation IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>32768
    OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN
      ('action','assessment_id','workplace_id','expected_current','version','kind','assessment_on',
       'revision_on','scope','reason','period_years')) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  action:=p_payload->>'action';
  IF action NOT IN ('draft','finalize') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_company,p_payload)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'risk.'||action,fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  expected:=coalesce((p_payload->>'expected_current')::integer,0);
  IF action='draft' THEN
    workplace:=(p_payload->>'workplace_id')::uuid; kind:=p_payload->>'kind';
    assessed:=(p_payload->>'assessment_on')::date; revised:=(p_payload->>'revision_on')::date;
    IF workplace IS NULL OR kind NOT IN ('full','partial','metadata','rescan') OR assessed IS NULL OR
       NOT isfinite(assessed) OR assessed>(clock_timestamp() AT TIME ZONE 'UTC')::date OR
       (revised IS NOT NULL AND (NOT isfinite(revised) OR revised<assessed)) OR
       (kind='partial' AND jsonb_typeof(p_payload->'scope') IS DISTINCT FROM 'object') OR
       (kind IN ('partial','metadata') AND length(btrim(coalesce(p_payload->>'reason','')))<10) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    SELECT * INTO assessment FROM private_isg.risk_assessments WHERE workspace_id=p_workspace
      AND company_id=p_company AND workplace_id=workplace FOR UPDATE;
    IF assessment.assessment_id IS NULL THEN
      IF expected<>0 OR kind<>'full' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
      INSERT INTO private_isg.risk_assessments(workspace_id,company_id,owner_id,workplace_id,
        created_by_user_id,updated_by_user_id)
      VALUES(p_workspace,p_company,NULL,workplace,actor,actor) RETURNING * INTO assessment;
    ELSIF assessment.current_version<>expected THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT';
    END IF;
    IF EXISTS(SELECT 1 FROM private_isg.risk_assessment_versions WHERE assessment_id=assessment.assessment_id AND state='draft') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='DRAFT_ALREADY_OPEN'; END IF;
    IF (assessment.current_version=0)<>(kind='full') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    SELECT coalesce(max(version),0)+1 INTO version_no FROM private_isg.risk_assessment_versions
      WHERE assessment_id=assessment.assessment_id;
    INSERT INTO private_isg.risk_assessment_versions(workspace_id,company_id,assessment_id,version,kind,
      previous_version,assessment_on,revision_on,scope,reason,date_needs_review,created_by_user_id,updated_by_user_id)
    VALUES(p_workspace,p_company,assessment.assessment_id,version_no,kind,
      CASE WHEN kind='full' THEN NULL ELSE assessment.current_version END,assessed,revised,p_payload->'scope',
      nullif(btrim(coalesce(p_payload->>'reason','')),''),assessed<(clock_timestamp() AT TIME ZONE 'UTC')::date-interval '10 years',
      actor,actor) RETURNING * INTO revision;
    UPDATE private_isg.risk_assessments SET version=version+1,updated_by_user_id=actor,
      updated_at=clock_timestamp() WHERE assessment_id=assessment.assessment_id RETURNING * INTO assessment;
  ELSE
    SELECT * INTO assessment FROM private_isg.risk_assessments WHERE workspace_id=p_workspace
      AND company_id=p_company AND assessment_id=(p_payload->>'assessment_id')::uuid FOR UPDATE;
    version_no:=(p_payload->>'version')::integer;
    IF assessment.assessment_id IS NULL OR assessment.current_version<>expected THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    SELECT * INTO revision FROM private_isg.risk_assessment_versions WHERE workspace_id=p_workspace
      AND company_id=p_company AND assessment_id=assessment.assessment_id AND version=version_no FOR UPDATE;
    IF revision.assessment_id IS NULL OR revision.state<>'draft' THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    years:=(p_payload->>'period_years')::integer;
    IF revision.kind='full' AND years NOT BETWEEN 1 AND 20 THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    IF revision.kind<>'full' AND years IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    valid:=CASE WHEN revision.kind='full' THEN (revision.assessment_on+make_interval(years=>years))::date
      ELSE assessment.valid_until END;
    before_state:=private_isg.workspace_risk_row(p_workspace,p_company,assessment.assessment_id);
    UPDATE private_isg.risk_assessment_versions SET state='superseded',updated_at=clock_timestamp(),
      updated_by_user_id=actor WHERE assessment_id=assessment.assessment_id AND state='final';
    UPDATE private_isg.risk_assessment_versions SET state='final',verified_by=actor,finalized_at=clock_timestamp(),
      period_years=years,period_source=CASE WHEN years IS NULL THEN NULL ELSE 'unapproved_fixture' END,
      period_needs_review=(years IS NOT NULL),valid_until=valid,updated_at=clock_timestamp(),updated_by_user_id=actor
      WHERE assessment_id=assessment.assessment_id AND version=version_no RETURNING * INTO revision;
    UPDATE private_isg.risk_assessments SET current_version=version_no,
      base_assessment_on=CASE WHEN revision.kind='full' THEN revision.assessment_on ELSE base_assessment_on END,
      valid_until=valid,version=version+1,updated_by_user_id=actor,updated_at=clock_timestamp()
      WHERE assessment_id=assessment.assessment_id RETURNING * INTO assessment;
  END IF;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'row',private_isg.workspace_risk_row(p_workspace,p_company,assessment.assessment_id));
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'risk.'||action,fingerprint,p_workspace,
    'risk',assessment.assessment_id,assessment.version,before_state,result,NULL,result);
END $$;

CREATE FUNCTION private_isg.workspace_nonconformity_row(p_workspace uuid,p_company uuid,p_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT jsonb_build_object('nonconformity_id',n.nonconformity_id,'company_id',n.company_id,
    'workplace_id',n.workplace_id,'source_kind',n.source_kind,'source_ref',n.source_ref,
    'title',n.title,'severity',n.severity,'opened_on',n.opened_on,'due_on',n.due_on,
    'assignee_contact',n.assignee_contact,'state',n.state,'version',n.version,'closed_on',n.closed_on,
    'verification_outcome',(SELECT v.outcome FROM private_isg.verification_records v
      WHERE v.workspace_id=p_workspace AND v.company_id=p_company
        AND v.nonconformity_id=n.nonconformity_id AND v.cycle=n.version LIMIT 1),
    'created_by_user_id',n.created_by_user_id,
    'actions',coalesce((SELECT jsonb_agg(jsonb_build_object('action_id',a.action_id,
      'description',a.description,'assignee_contact',a.assignee_contact,'due_on',a.due_on,'state',a.state)
      ORDER BY a.created_at,a.action_id) FROM private_isg.nonconformity_actions a
      WHERE a.workspace_id=p_workspace AND a.company_id=p_company AND a.nonconformity_id=n.nonconformity_id),'[]'::jsonb),
    'transitions',coalesce((SELECT jsonb_agg(jsonb_build_object('from',t.from_state,'to',t.to_state,
      'reason',t.reason,'actor_id',t.actor_id,'occurred_at',t.occurred_at) ORDER BY t.version)
      FROM private_isg.nonconformity_transitions t WHERE t.workspace_id=p_workspace
        AND t.company_id=p_company AND t.nonconformity_id=n.nonconformity_id),'[]'::jsonb))
  FROM private_isg.nonconformities n
  WHERE n.workspace_id=p_workspace AND n.company_id=p_company AND n.nonconformity_id=p_id
$$;

CREATE FUNCTION private_isg.workspace_nonconformity_read(p_workspace uuid,p_company uuid,p_id uuid,
  p_state text,p_after uuid,p_limit integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE rows jsonb; next_id uuid;
BEGIN
  PERFORM private_isg.workspace_domain_gate('risk_nonconformity',false);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,false);
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 OR (p_id IS NOT NULL AND p_after IS NOT NULL) OR
    (p_state IS NOT NULL AND p_state NOT IN
    ('draft','open','assigned','in_progress','pending_verification','closed','reopened','cancelled')) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_id IS NOT NULL THEN
    rows:=private_isg.workspace_nonconformity_row(p_workspace,p_company,p_id);
    IF rows IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,'row',rows);
  END IF;
  WITH page AS (
    SELECT nonconformity_id FROM private_isg.nonconformities WHERE workspace_id=p_workspace
      AND company_id=p_company AND (p_state IS NULL OR state=p_state)
      AND (p_after IS NULL OR nonconformity_id>p_after)
    ORDER BY nonconformity_id LIMIT p_limit+1
  ), numbered AS (
    SELECT nonconformity_id,row_number() OVER (ORDER BY nonconformity_id) ordinal,count(*) OVER () total FROM page
  )
  SELECT coalesce(jsonb_agg(private_isg.workspace_nonconformity_row(p_workspace,p_company,nonconformity_id)
      ORDER BY nonconformity_id) FILTER (WHERE ordinal<=p_limit),'[]'::jsonb),
    (array_agg(nonconformity_id) FILTER (WHERE ordinal=p_limit AND total>p_limit))[1]
    INTO rows,next_id FROM numbered;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'rows',rows,'next',next_id);
END $$;

CREATE FUNCTION private_isg.workspace_nonconformity_mutate(p_mutation uuid,p_workspace uuid,p_company uuid,
  p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); action text; fingerprint bytea; replay jsonb;
  entry private_isg.nonconformities; edge private_isg.nonconformity_state_edges;
  workplace uuid; target uuid; expected bigint; clean_title text; clean_source_kind text; clean_source_ref text;
  severity text; opened date; due date; desired_state text; clean_reason text; clean_assignee text;
  before_state jsonb; result jsonb; action_row private_isg.nonconformity_actions; existing_outcome text;
BEGIN
  PERFORM private_isg.workspace_domain_gate('risk_nonconformity',true);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,true);
  IF p_mutation IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>32768
    OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN
      ('action','id','expected_version','workplace_id','source_kind','source_ref','title','severity',
       'opened_on','due_on','to_state','reason','assignee_contact','description','verified_on','outcome','note')) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  action:=p_payload->>'action'; target:=(p_payload->>'id')::uuid;
  IF action NOT IN ('create','transition','add_action','verify') OR (action='create')<>(target IS NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_company,p_payload)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'nonconformity.'||action,fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  IF action='create' THEN
    workplace:=(p_payload->>'workplace_id')::uuid; clean_source_kind:=coalesce(p_payload->>'source_kind','manual');
    clean_source_ref:=nullif(btrim(coalesce(p_payload->>'source_ref','')),'');
    clean_title:=private_isg.workspace_text(p_payload->>'title',300); severity:=p_payload->>'severity';
    opened:=(p_payload->>'opened_on')::date; due:=(p_payload->>'due_on')::date;
    -- Analysis findings are accepted only by the D8 verified bridge. This D3
    -- command cannot trust a client-supplied analysis or finding identifier.
    IF clean_source_kind NOT IN ('manual','risk_version','checklist') OR severity NOT IN ('low','medium','high','critical')
      OR workplace IS NULL OR opened IS NULL OR NOT isfinite(opened) OR (due IS NOT NULL AND due<opened)
      OR (clean_source_kind<>'manual' AND clean_source_ref IS NULL) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    IF clean_source_ref IS NOT NULL THEN
      SELECT * INTO entry FROM private_isg.nonconformities WHERE workspace_id=p_workspace
        AND company_id=p_company AND source_kind=clean_source_kind
        AND nonconformities.source_ref=clean_source_ref FOR UPDATE;
    END IF;
    IF entry.nonconformity_id IS NULL THEN
      INSERT INTO private_isg.nonconformities(workspace_id,company_id,owner_id,workplace_id,source_kind,
        source_ref,title,severity,opened_on,due_on,created_by_user_id,updated_by_user_id)
      VALUES(p_workspace,p_company,NULL,workplace,clean_source_kind,clean_source_ref,clean_title,severity,opened,due,actor,actor)
      RETURNING * INTO entry;
    END IF;
  ELSE
    expected:=(p_payload->>'expected_version')::bigint;
    SELECT * INTO entry FROM private_isg.nonconformities WHERE workspace_id=p_workspace
      AND company_id=p_company AND nonconformity_id=target FOR UPDATE;
    IF entry.nonconformity_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF entry.version<>expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    before_state:=private_isg.workspace_nonconformity_row(p_workspace,p_company,target);
    IF action='transition' THEN
      desired_state:=p_payload->>'to_state';
      SELECT * INTO edge FROM private_isg.nonconformity_state_edges
        WHERE from_state=entry.state AND to_state=desired_state;
      IF edge.from_state IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='TRANSITION_NOT_ALLOWED'; END IF;
      clean_reason:=nullif(btrim(coalesce(p_payload->>'reason','')),'');
      clean_assignee:=nullif(btrim(coalesce(p_payload->>'assignee_contact',entry.assignee_contact,'')),'');
      IF edge.requires_reason AND (clean_reason IS NULL OR length(clean_reason)<5) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='REASON_REQUIRED'; END IF;
      IF edge.requires_assignee AND clean_assignee IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSIGNEE_REQUIRED'; END IF;
      IF edge.requires_verification AND NOT EXISTS(SELECT 1 FROM private_isg.verification_records
          WHERE workspace_id=p_workspace AND company_id=p_company AND nonconformity_id=target
            AND cycle=entry.version AND outcome='accepted') THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERIFICATION_REQUIRED'; END IF;
      UPDATE private_isg.nonconformities SET state=desired_state,assignee_contact=clean_assignee,
        cancelled_reason=CASE WHEN desired_state='cancelled' THEN clean_reason ELSE cancelled_reason END,
        closed_on=CASE WHEN desired_state='closed' THEN (clock_timestamp() AT TIME ZONE 'UTC')::date ELSE NULL END,
        version=version+1,updated_by_user_id=actor,updated_at=clock_timestamp()
        WHERE nonconformity_id=target RETURNING * INTO entry;
      INSERT INTO private_isg.nonconformity_transitions(workspace_id,company_id,nonconformity_id,version,
        from_state,to_state,reason,actor_id,occurred_at)
      VALUES(p_workspace,p_company,target,entry.version,before_state->>'state',desired_state,clean_reason,actor,clock_timestamp());
    ELSIF action='add_action' THEN
      INSERT INTO private_isg.nonconformity_actions(workspace_id,company_id,nonconformity_id,description,
        assignee_contact,due_on,created_by_user_id,updated_by_user_id)
      VALUES(p_workspace,p_company,target,private_isg.workspace_text(p_payload->>'description',1000),
        nullif(btrim(coalesce(p_payload->>'assignee_contact','')),''),(p_payload->>'due_on')::date,actor,actor)
      RETURNING * INTO action_row;
      UPDATE private_isg.nonconformities SET version=version+1,updated_by_user_id=actor,
        updated_at=clock_timestamp() WHERE nonconformity_id=target RETURNING * INTO entry;
    ELSE
      IF p_payload->>'outcome' NOT IN ('accepted','rejected') OR (p_payload->>'verified_on')::date IS NULL THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      SELECT outcome INTO existing_outcome FROM private_isg.verification_records
        WHERE workspace_id=p_workspace AND company_id=p_company
          AND nonconformity_id=target AND cycle=entry.version FOR UPDATE;
      IF FOUND AND existing_outcome IS DISTINCT FROM p_payload->>'outcome' THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
      IF NOT FOUND THEN
        INSERT INTO private_isg.verification_records(workspace_id,company_id,nonconformity_id,cycle,outcome,
          verified_by,verified_on,note)
        VALUES(p_workspace,p_company,target,entry.version,p_payload->>'outcome',actor,
          (p_payload->>'verified_on')::date,nullif(btrim(coalesce(p_payload->>'note','')),''));
      END IF;
      UPDATE private_isg.nonconformities SET updated_by_user_id=actor,
        updated_at=clock_timestamp() WHERE nonconformity_id=target RETURNING * INTO entry;
    END IF;
  END IF;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'row',private_isg.workspace_nonconformity_row(p_workspace,p_company,entry.nonconformity_id));
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'nonconformity.'||action,fingerprint,p_workspace,
    'nonconformity',entry.nonconformity_id,entry.version,before_state,result,NULL,result);
END $$;

CREATE FUNCTION private_isg.workspace_checklist_read(p_workspace uuid,p_company uuid,p_id uuid,p_after uuid,p_limit integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE rows jsonb; next_id uuid;
BEGIN
  PERFORM private_isg.workspace_domain_gate('risk_nonconformity',false);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,false);
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 OR (p_id IS NOT NULL AND p_after IS NOT NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  WITH page AS (
    SELECT run_id FROM private_isg.checklist_runs WHERE workspace_id=p_workspace AND company_id=p_company
      AND (p_id IS NULL OR run_id=p_id) AND (p_after IS NULL OR run_id>p_after)
    ORDER BY run_id LIMIT CASE WHEN p_id IS NULL THEN p_limit+1 ELSE 1 END
  ), numbered AS (
    SELECT run_id,row_number() OVER (ORDER BY run_id) ordinal,count(*) OVER () total FROM page
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('run_id',r.run_id,'workplace_id',r.workplace_id,
    'template_code',r.template_code,'template_version',r.template_version,'state',r.state,
    'started_on',r.started_on,'submitted_at',r.submitted_at,'version',r.version,
    'items',coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'item_code',t.item_code,'prompt',t.prompt,'allows_not_applicable',t.allows_not_applicable,
      'result',i.result,'note',i.note,'nonconformity_id',i.nonconformity_id)) ORDER BY t.position)
      FROM private_isg.checklist_template_items t
      LEFT JOIN private_isg.checklist_run_items i ON i.workspace_id=p_workspace
        AND i.company_id=p_company AND i.run_id=r.run_id AND i.item_code=t.item_code
      WHERE t.template_code=r.template_code AND t.version=r.template_version),'[]'::jsonb)) ORDER BY r.run_id)
      FILTER (WHERE n.ordinal<=p_limit),'[]'::jsonb),
    (array_agg(r.run_id) FILTER (WHERE n.ordinal=p_limit AND n.total>p_limit))[1]
    INTO rows,next_id FROM numbered n JOIN private_isg.checklist_runs r ON r.run_id=n.run_id;
  IF p_id IS NOT NULL AND jsonb_array_length(rows)=0 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'rows',rows,'next',CASE WHEN p_id IS NULL THEN next_id ELSE NULL END,
    'templates',coalesce((SELECT jsonb_agg(jsonb_build_object('code',v.template_code,'version',v.version,
      'title',t.title,'item_count',(SELECT count(*) FROM private_isg.checklist_template_items i
        WHERE i.template_code=v.template_code AND i.version=v.version)) ORDER BY t.title,v.template_code)
      FROM private_isg.checklist_template_versions v
      JOIN private_isg.checklist_templates t ON t.template_code=v.template_code
      WHERE v.status='published' AND EXISTS(
        SELECT 1 FROM private_isg.checklist_template_items i
        WHERE i.template_code=v.template_code AND i.version=v.version
      )),'[]'::jsonb));
END $$;

CREATE FUNCTION private_isg.workspace_checklist_mutate(p_mutation uuid,p_workspace uuid,p_company uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); action text; fingerprint bytea; replay jsonb;
  run private_isg.checklist_runs; target uuid; expected bigint; requested_item text; result_code text;
  finding uuid; before_state jsonb; response jsonb; prompt text; allows_na boolean; create_finding boolean;
BEGIN
  PERFORM private_isg.workspace_domain_gate('risk_nonconformity',true);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,true);
  IF p_mutation IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>32768
    OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN
      ('action','id','expected_version','workplace_id','template_code','template_version','started_on',
       'item_code','result','note','create_nonconformity','severity','due_on')) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  action:=p_payload->>'action'; target:=(p_payload->>'id')::uuid;
  IF action NOT IN ('create','answer','submit','cancel') OR (action='create')<>(target IS NULL) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_company,p_payload)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'checklist.'||action,fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  IF action='create' THEN
    IF NOT EXISTS(SELECT 1 FROM private_isg.checklist_template_versions v
      WHERE v.template_code=p_payload->>'template_code' AND v.version=(p_payload->>'template_version')::integer
        AND v.status='published') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='TEMPLATE_UNAVAILABLE'; END IF;
    INSERT INTO private_isg.checklist_runs(workspace_id,company_id,owner_id,workplace_id,template_code,
      template_version,started_on,created_by_user_id,updated_by_user_id)
    VALUES(p_workspace,p_company,NULL,(p_payload->>'workplace_id')::uuid,p_payload->>'template_code',
      (p_payload->>'template_version')::integer,(p_payload->>'started_on')::date,actor,actor)
    RETURNING * INTO run;
  ELSE
    expected:=(p_payload->>'expected_version')::bigint;
    SELECT * INTO run FROM private_isg.checklist_runs WHERE workspace_id=p_workspace
      AND company_id=p_company AND run_id=target FOR UPDATE;
    IF run.run_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF run.version<>expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    IF run.state<>'open' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CHECKLIST_LOCKED'; END IF;
    before_state:=(private_isg.workspace_checklist_read(p_workspace,p_company,target,NULL,1)->'rows'->0);
    IF action='answer' THEN
      requested_item:=p_payload->>'item_code'; result_code:=p_payload->>'result';
      create_finding:=coalesce((p_payload->>'create_nonconformity')::boolean,false);
      SELECT i.prompt,i.allows_not_applicable INTO prompt,allows_na FROM private_isg.checklist_template_items i
      WHERE i.template_code=run.template_code AND i.version=run.template_version AND i.item_code=requested_item;
      IF prompt IS NULL OR result_code NOT IN ('conform','nonconform','not_applicable')
        OR (result_code='not_applicable' AND NOT allows_na)
        OR (create_finding AND result_code<>'nonconform')
        OR (result_code='nonconform' AND create_finding AND
          (coalesce(p_payload->>'severity','medium') NOT IN ('low','medium','high','critical')
          OR (p_payload->>'due_on')::date IS NULL OR (p_payload->>'due_on')::date<run.started_on)) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      IF result_code='nonconform' AND create_finding THEN
        INSERT INTO private_isg.nonconformities(workspace_id,company_id,owner_id,workplace_id,source_kind,
          source_ref,title,severity,opened_on,due_on,state,created_by_user_id,updated_by_user_id)
        VALUES(p_workspace,p_company,NULL,run.workplace_id,'checklist',run.run_id::text||':'||requested_item,
          prompt,coalesce(p_payload->>'severity','medium'),run.started_on,(p_payload->>'due_on')::date,
          'open',actor,actor)
        ON CONFLICT(company_id,source_kind,source_ref) WHERE source_ref IS NOT NULL DO UPDATE
          SET updated_at=private_isg.nonconformities.updated_at
        RETURNING nonconformity_id INTO finding;
      END IF;
      INSERT INTO private_isg.checklist_run_items(workspace_id,company_id,run_id,item_code,result,note,
        nonconformity_id,recorded_at,recorded_by_user_id)
      VALUES(p_workspace,p_company,target,requested_item,result_code,nullif(btrim(coalesce(p_payload->>'note','')),''),
        finding,clock_timestamp(),actor)
      ON CONFLICT(run_id,item_code) DO UPDATE SET result=excluded.result,note=excluded.note,
        nonconformity_id=coalesce(private_isg.checklist_run_items.nonconformity_id,excluded.nonconformity_id),
        recorded_at=excluded.recorded_at,recorded_by_user_id=excluded.recorded_by_user_id;
    ELSIF action='submit' THEN
      IF (SELECT count(*) FROM private_isg.checklist_run_items WHERE workspace_id=p_workspace
          AND company_id=p_company AND run_id=target)<>(SELECT count(*) FROM private_isg.checklist_template_items
          WHERE template_code=run.template_code AND version=run.template_version) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='CHECKLIST_INCOMPLETE'; END IF;
      UPDATE private_isg.checklist_runs SET state='submitted',submitted_at=clock_timestamp()
        WHERE run_id=target;
    ELSE
      UPDATE private_isg.checklist_runs SET state='cancelled' WHERE run_id=target;
    END IF;
    UPDATE private_isg.checklist_runs SET version=version+1,updated_by_user_id=actor,
      updated_at=clock_timestamp() WHERE run_id=target RETURNING * INTO run;
  END IF;
  response:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'row',(private_isg.workspace_checklist_read(p_workspace,p_company,run.run_id,NULL,1)->'rows'->0));
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'checklist.'||action,fingerprint,p_workspace,
    'checklist',run.run_id,run.version,before_state,response,NULL,response);
END $$;

CREATE FUNCTION private_isg.workspace_assurance_metrics(p_workspace uuid,p_company uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result jsonb; today date:=(clock_timestamp() AT TIME ZONE 'UTC')::date;
BEGIN
  PERFORM private_isg.workspace_domain_gate('risk_nonconformity',false);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,false);
  SELECT jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,'measured',true,
    'risk',jsonb_build_object(
      'total',(SELECT count(*) FROM private_isg.risk_assessments WHERE workspace_id=p_workspace AND company_id=p_company),
      'untracked',(SELECT count(*) FROM private_isg.risk_assessments WHERE workspace_id=p_workspace AND company_id=p_company AND current_version=0),
      'expired',(SELECT count(*) FROM private_isg.risk_assessments WHERE workspace_id=p_workspace AND company_id=p_company AND valid_until<today),
      'due_soon',(SELECT count(*) FROM private_isg.risk_assessments WHERE workspace_id=p_workspace AND company_id=p_company AND valid_until BETWEEN today AND today+60)),
    'nonconformity',jsonb_build_object(
      'total',(SELECT count(*) FROM private_isg.nonconformities WHERE workspace_id=p_workspace AND company_id=p_company),
      'open',(SELECT count(*) FROM private_isg.nonconformities WHERE workspace_id=p_workspace AND company_id=p_company AND state NOT IN ('closed','cancelled')),
      'overdue',(SELECT count(*) FROM private_isg.nonconformities WHERE workspace_id=p_workspace AND company_id=p_company AND state NOT IN ('closed','cancelled') AND due_on<today),
      'closed',(SELECT count(*) FROM private_isg.nonconformities WHERE workspace_id=p_workspace AND company_id=p_company AND state='closed')),
    'checklists',jsonb_build_object(
      'open',(SELECT count(*) FROM private_isg.checklist_runs WHERE workspace_id=p_workspace AND company_id=p_company AND state='open'),
      'submitted',(SELECT count(*) FROM private_isg.checklist_runs WHERE workspace_id=p_workspace AND company_id=p_company AND state='submitted'))) INTO result;
  RETURN result;
END $$;

CREATE FUNCTION public.isg_workspace_risk_read_v1(p_workspace uuid,p_company uuid,p_id uuid DEFAULT NULL,p_after uuid DEFAULT NULL,p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_risk_read(p_workspace,p_company,p_id,p_after,p_limit) $$;
CREATE FUNCTION public.isg_workspace_risk_mutate_v1(p_mutation uuid,p_workspace uuid,p_company uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_risk_mutate(p_mutation,p_workspace,p_company,p_payload) $$;
CREATE FUNCTION public.isg_workspace_nonconformity_read_v1(p_workspace uuid,p_company uuid,p_id uuid DEFAULT NULL,
  p_state text DEFAULT NULL,p_after uuid DEFAULT NULL,p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_nonconformity_read(p_workspace,p_company,p_id,p_state,p_after,p_limit) $$;
CREATE FUNCTION public.isg_workspace_nonconformity_mutate_v1(p_mutation uuid,p_workspace uuid,p_company uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_nonconformity_mutate(p_mutation,p_workspace,p_company,p_payload) $$;
CREATE FUNCTION public.isg_workspace_checklist_read_v1(p_workspace uuid,p_company uuid,p_id uuid DEFAULT NULL,p_after uuid DEFAULT NULL,p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_checklist_read(p_workspace,p_company,p_id,p_after,p_limit) $$;
CREATE FUNCTION public.isg_workspace_checklist_mutate_v1(p_mutation uuid,p_workspace uuid,p_company uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_checklist_mutate(p_mutation,p_workspace,p_company,p_payload) $$;
CREATE FUNCTION public.isg_workspace_assurance_metrics_v1(p_workspace uuid,p_company uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_assurance_metrics(p_workspace,p_company) $$;

REVOKE ALL ON FUNCTION private_isg.workspace_assurance_root_invariant(),private_isg.workspace_risk_child_invariant(),
  private_isg.workspace_nonconformity_child_invariant(),private_isg.workspace_checklist_item_invariant(),
  private_isg.workspace_risk_row(uuid,uuid,uuid),private_isg.workspace_risk_read(uuid,uuid,uuid,uuid,integer),
  private_isg.workspace_risk_mutate(uuid,uuid,uuid,jsonb),private_isg.workspace_nonconformity_row(uuid,uuid,uuid),
  private_isg.workspace_nonconformity_read(uuid,uuid,uuid,text,uuid,integer),
  private_isg.workspace_nonconformity_mutate(uuid,uuid,uuid,jsonb),
  private_isg.workspace_checklist_read(uuid,uuid,uuid,uuid,integer),private_isg.workspace_checklist_mutate(uuid,uuid,uuid,jsonb),
  private_isg.workspace_assurance_metrics(uuid,uuid),public.isg_workspace_risk_read_v1(uuid,uuid,uuid,uuid,integer),
  public.isg_workspace_risk_mutate_v1(uuid,uuid,uuid,jsonb),
  public.isg_workspace_nonconformity_read_v1(uuid,uuid,uuid,text,uuid,integer),
  public.isg_workspace_nonconformity_mutate_v1(uuid,uuid,uuid,jsonb),
  public.isg_workspace_checklist_read_v1(uuid,uuid,uuid,uuid,integer),
  public.isg_workspace_checklist_mutate_v1(uuid,uuid,uuid,jsonb),
  public.isg_workspace_assurance_metrics_v1(uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_risk_read(uuid,uuid,uuid,uuid,integer),
  private_isg.workspace_risk_mutate(uuid,uuid,uuid,jsonb),
  private_isg.workspace_nonconformity_read(uuid,uuid,uuid,text,uuid,integer),
  private_isg.workspace_nonconformity_mutate(uuid,uuid,uuid,jsonb),
  private_isg.workspace_checklist_read(uuid,uuid,uuid,uuid,integer),private_isg.workspace_checklist_mutate(uuid,uuid,uuid,jsonb),
  private_isg.workspace_assurance_metrics(uuid,uuid),public.isg_workspace_risk_read_v1(uuid,uuid,uuid,uuid,integer),
  public.isg_workspace_risk_mutate_v1(uuid,uuid,uuid,jsonb),
  public.isg_workspace_nonconformity_read_v1(uuid,uuid,uuid,text,uuid,integer),
  public.isg_workspace_nonconformity_mutate_v1(uuid,uuid,uuid,jsonb),
  public.isg_workspace_checklist_read_v1(uuid,uuid,uuid,uuid,integer),
  public.isg_workspace_checklist_mutate_v1(uuid,uuid,uuid,jsonb),
  public.isg_workspace_assurance_metrics_v1(uuid,uuid)
  TO authenticated;
NOTIFY pgrst,'reload schema';
