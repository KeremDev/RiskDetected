-- OSGB risk draft lifecycle parity with the personal Nova module.
-- Additive/replace-only candidate: no personal table, policy or RPC is changed.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='25s';

CREATE OR REPLACE FUNCTION private_isg.workspace_risk_row(p_workspace uuid,p_company uuid,p_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT jsonb_build_object('assessment_id',a.assessment_id,'company_id',a.company_id,
    'workplace_id',a.workplace_id,'current_version',a.current_version,
    'base_assessment_on',a.base_assessment_on,'valid_until',a.valid_until,'version',a.version,
    'created_by_user_id',a.created_by_user_id,
    'versions',coalesce((SELECT jsonb_agg(jsonb_build_object('version',v.version,
      'edit_revision',v.edit_revision,'cancellation_note',v.cancellation_note,'kind',v.kind,
      'assessment_on',v.assessment_on,'revision_on',v.revision_on,'scope',v.scope,'reason',v.reason,
      'state',v.state,'valid_until',v.valid_until,'period_years',v.period_years,
      'period_source',v.period_source,'period_needs_review',v.period_needs_review,
      'source_drift',v.source_drift,'created_by_user_id',v.created_by_user_id) ORDER BY v.version DESC)
      FROM private_isg.risk_assessment_versions v WHERE v.workspace_id=p_workspace
        AND v.company_id=p_company AND v.assessment_id=a.assessment_id),'[]'::jsonb))
  FROM private_isg.risk_assessments a
  WHERE a.workspace_id=p_workspace AND a.company_id=p_company AND a.assessment_id=p_id
$$;

CREATE OR REPLACE FUNCTION private_isg.workspace_risk_mutate(p_mutation uuid,p_workspace uuid,p_company uuid,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); action text; fingerprint bytea; replay jsonb;
  assessment private_isg.risk_assessments; revision private_isg.risk_assessment_versions;
  workplace uuid; expected integer; expected_edit integer; version_no integer; kind text; assessed date; revised date;
  years integer; valid date; before_state jsonb; result jsonb; cancellation text;
BEGIN
  PERFORM private_isg.workspace_domain_gate('risk_nonconformity',true);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,true);
  IF p_mutation IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>32768
    OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN
      ('action','assessment_id','workplace_id','expected_current','expected_edit_revision','version','kind',
       'assessment_on','revision_on','scope','reason','cancellation_note','period_years')) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  action:=p_payload->>'action';
  IF action NOT IN ('draft','edit_draft','cancel_draft','finalize') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
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
    IF EXISTS(SELECT 1 FROM private_isg.risk_assessment_versions
      WHERE assessment_id=assessment.assessment_id AND state='draft') THEN
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

  ELSIF action IN ('edit_draft','cancel_draft') THEN
    SELECT * INTO assessment FROM private_isg.risk_assessments WHERE workspace_id=p_workspace
      AND company_id=p_company AND assessment_id=(p_payload->>'assessment_id')::uuid FOR UPDATE;
    version_no:=(p_payload->>'version')::integer;
    expected_edit:=coalesce((p_payload->>'expected_edit_revision')::integer,-1);
    IF assessment.assessment_id IS NULL OR assessment.current_version<>expected THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    SELECT * INTO revision FROM private_isg.risk_assessment_versions WHERE workspace_id=p_workspace
      AND company_id=p_company AND assessment_id=assessment.assessment_id AND version=version_no FOR UPDATE;
    IF revision.assessment_id IS NULL OR revision.state<>'draft' THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF revision.edit_revision<>expected_edit THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    before_state:=private_isg.workspace_risk_row(p_workspace,p_company,assessment.assessment_id);
    IF action='cancel_draft' THEN
      cancellation:=btrim(coalesce(p_payload->>'cancellation_note',''));
      IF length(cancellation)<5 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      UPDATE private_isg.risk_assessment_versions SET state='cancelled',cancellation_note=cancellation,
        edit_revision=edit_revision+1,updated_at=clock_timestamp(),updated_by_user_id=actor
      WHERE assessment_id=assessment.assessment_id AND version=version_no RETURNING * INTO revision;
    ELSE
      assessed:=(p_payload->>'assessment_on')::date; revised:=(p_payload->>'revision_on')::date;
      IF assessed IS NULL OR NOT isfinite(assessed) OR assessed>(clock_timestamp() AT TIME ZONE 'UTC')::date OR
         (revision.kind='full' AND revised IS NOT NULL) OR
         (revision.kind<>'full' AND assessed<>revision.assessment_on) OR
         (revision.kind<>'full' AND (revised IS NULL OR NOT isfinite(revised) OR revised<assessed)) OR
         (revision.kind='partial' AND (jsonb_typeof(p_payload->'scope') IS DISTINCT FROM 'object' OR
            length(btrim(coalesce(p_payload->'scope'->>'summary','')))=0)) OR
         (revision.kind IN ('partial','metadata') AND length(btrim(coalesce(p_payload->>'reason','')))<10) THEN
        RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
      UPDATE private_isg.risk_assessment_versions SET
        assessment_on=CASE WHEN revision.kind='full' THEN assessed ELSE assessment_on END,
        revision_on=CASE WHEN revision.kind='full' THEN NULL ELSE revised END,
        scope=CASE WHEN revision.kind='partial' THEN p_payload->'scope' ELSE scope END,
        reason=CASE WHEN revision.kind IN ('partial','metadata') THEN btrim(p_payload->>'reason') ELSE reason END,
        date_needs_review=(CASE WHEN revision.kind='full' THEN assessed ELSE assessment_on END)<
          (clock_timestamp() AT TIME ZONE 'UTC')::date-interval '10 years',
        edit_revision=edit_revision+1,updated_at=clock_timestamp(),updated_by_user_id=actor
      WHERE assessment_id=assessment.assessment_id AND version=version_no RETURNING * INTO revision;
    END IF;
    UPDATE private_isg.risk_assessments SET version=version+1,updated_by_user_id=actor,
      updated_at=clock_timestamp() WHERE assessment_id=assessment.assessment_id RETURNING * INTO assessment;

  ELSE
    SELECT * INTO assessment FROM private_isg.risk_assessments WHERE workspace_id=p_workspace
      AND company_id=p_company AND assessment_id=(p_payload->>'assessment_id')::uuid FOR UPDATE;
    version_no:=(p_payload->>'version')::integer;
    expected_edit:=coalesce((p_payload->>'expected_edit_revision')::integer,0);
    IF assessment.assessment_id IS NULL OR assessment.current_version<>expected THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    SELECT * INTO revision FROM private_isg.risk_assessment_versions WHERE workspace_id=p_workspace
      AND company_id=p_company AND assessment_id=assessment.assessment_id AND version=version_no FOR UPDATE;
    IF revision.assessment_id IS NULL OR revision.state<>'draft' OR revision.edit_revision<>expected_edit THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
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

REVOKE ALL ON FUNCTION private_isg.workspace_risk_row(uuid,uuid,uuid),
  private_isg.workspace_risk_mutate(uuid,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_risk_row(uuid,uuid,uuid),
  private_isg.workspace_risk_mutate(uuid,uuid,uuid,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
