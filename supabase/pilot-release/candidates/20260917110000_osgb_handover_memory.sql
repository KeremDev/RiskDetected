-- OSGB company handover and deterministic company memory. NOT DEPLOYED.
-- Each company executes in its own transaction. Preview snapshots are rechecked
-- at commit time so a stale plan cannot overwrite a newer assignment.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='20s';

INSERT INTO private_isg.workspace_rollout(feature) VALUES('workspace_handover');

CREATE TABLE private_isg.workspace_handovers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES private_isg.workspaces(id) ON DELETE RESTRICT,
  source_membership_id uuid NOT NULL,
  target_membership_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','scheduled','in_progress','completed','partially_completed','cancelled')),
  effective_at timestamptz NOT NULL,
  reason text NOT NULL CHECK(octet_length(reason) BETWEEN 1 AND 500),
  preview_hash bytea NOT NULL CHECK(octet_length(preview_hash)=32),
  source_membership_version bigint NOT NULL CHECK(source_membership_version>=0),
  target_membership_version bigint NOT NULL CHECK(target_membership_version>=0),
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  created_by_user_id uuid NOT NULL,
  cancelled_by_user_id uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  completed_at timestamptz,
  cancelled_at timestamptz,
  UNIQUE(workspace_id,id),
  FOREIGN KEY(workspace_id,source_membership_id)
    REFERENCES private_isg.workspace_memberships(workspace_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,target_membership_id)
    REFERENCES private_isg.workspace_memberships(workspace_id,id) ON DELETE RESTRICT,
  CHECK(source_membership_id<>target_membership_id),
  CHECK((status='cancelled')=(cancelled_at IS NOT NULL)),
  CHECK((status='completed')=(completed_at IS NOT NULL))
);
CREATE INDEX workspace_handover_timeline
  ON private_isg.workspace_handovers(workspace_id,created_at,id);

CREATE TABLE private_isg.workspace_handover_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  handover_id uuid NOT NULL,
  company_id uuid NOT NULL,
  source_assignment_id uuid NOT NULL,
  source_assignment_version bigint NOT NULL CHECK(source_assignment_version>=0),
  company_version bigint NOT NULL CHECK(company_version>=0),
  status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','completed','failed','cancelled')),
  target_assignment_id uuid,
  failure_code text,
  execution_mutation_id uuid,
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  executed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(handover_id,company_id),
  UNIQUE(workspace_id,id),
  FOREIGN KEY(workspace_id,handover_id)
    REFERENCES private_isg.workspace_handovers(workspace_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,company_id)
    REFERENCES private_isg.workspace_companies(workspace_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(source_assignment_id) REFERENCES private_isg.company_assignments(id) ON DELETE RESTRICT,
  FOREIGN KEY(target_assignment_id) REFERENCES private_isg.company_assignments(id) ON DELETE RESTRICT,
  CHECK((status='completed')=(target_assignment_id IS NOT NULL)),
  CHECK(status<>'completed' OR executed_at IS NOT NULL),
  CHECK(status<>'failed' OR failure_code IS NOT NULL)
);
CREATE INDEX workspace_handover_item_progress
  ON private_isg.workspace_handover_items(workspace_id,handover_id,status,company_id);

-- A completed handover is never rewritten or deleted. A correction is a new,
-- versioned reverse handover linked to the original completed company item.
ALTER TABLE private_isg.workspace_handovers
  ADD COLUMN compensation_for_handover_id uuid,
  ADD COLUMN compensation_for_item_id uuid,
  ADD CONSTRAINT workspace_handover_compensation_pair
    CHECK((compensation_for_handover_id IS NULL)=(compensation_for_item_id IS NULL)),
  ADD CONSTRAINT workspace_handover_compensation_handover_fk
    FOREIGN KEY(workspace_id,compensation_for_handover_id)
      REFERENCES private_isg.workspace_handovers(workspace_id,id) ON DELETE RESTRICT,
  ADD CONSTRAINT workspace_handover_compensation_item_fk
    FOREIGN KEY(workspace_id,compensation_for_item_id)
      REFERENCES private_isg.workspace_handover_items(workspace_id,id) ON DELETE RESTRICT;
CREATE UNIQUE INDEX workspace_handover_active_compensation_unique
  ON private_isg.workspace_handovers(compensation_for_item_id)
  WHERE compensation_for_item_id IS NOT NULL AND status<>'cancelled';

CREATE TABLE private_isg.company_memory_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  company_id uuid NOT NULL,
  event_kind text NOT NULL CHECK(event_kind IN ('assignment_handover','assignment_started','assignment_ended','operational_note')),
  source_type text NOT NULL CHECK(source_type IN ('handover_item','assignment','manual')),
  source_id uuid NOT NULL,
  source_version bigint NOT NULL CHECK(source_version>=0),
  event_key text NOT NULL CHECK(octet_length(event_key) BETWEEN 1 AND 160),
  occurred_at timestamptz NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  title text NOT NULL CHECK(octet_length(title) BETWEEN 1 AND 200),
  summary text NOT NULL CHECK(octet_length(summary) BETWEEN 1 AND 1000),
  visibility text NOT NULL DEFAULT 'workspace' CHECK(visibility='workspace'),
  created_by_user_id uuid NOT NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE(workspace_id,source_type,source_id,source_version,event_key),
  FOREIGN KEY(workspace_id,company_id)
    REFERENCES private_isg.workspace_companies(workspace_id,id) ON DELETE RESTRICT,
  CHECK(jsonb_typeof(metadata)='object'),
  CHECK(NOT (metadata ?| ARRAY['internal_note','private_note','invitation_token','provider_payload']))
);
CREATE INDEX company_memory_timeline
  ON private_isg.company_memory_events(workspace_id,company_id,occurred_at DESC,id DESC);

CREATE TABLE private_isg.company_handover_briefs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  company_id uuid NOT NULL,
  handover_item_id uuid NOT NULL,
  generator text NOT NULL DEFAULT 'deterministic_v1' CHECK(generator='deterministic_v1'),
  source_watermark timestamptz NOT NULL,
  content jsonb NOT NULL,
  status text NOT NULL DEFAULT 'ready' CHECK(status IN ('ready','reviewed','superseded')),
  reviewed_by_user_id uuid,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(workspace_id,handover_item_id,generator),
  FOREIGN KEY(workspace_id,company_id)
    REFERENCES private_isg.workspace_companies(workspace_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,handover_item_id)
    REFERENCES private_isg.workspace_handover_items(workspace_id,id) ON DELETE RESTRICT,
  CHECK(jsonb_typeof(content)='object'),
  CHECK((status='reviewed')=(reviewed_at IS NOT NULL))
);

ALTER TABLE private_isg.workspace_handovers ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_handover_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.company_memory_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.company_handover_briefs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.workspace_handovers,private_isg.workspace_handover_items,
  private_isg.company_memory_events,private_isg.company_handover_briefs
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.handover_refresh_status(p_handover uuid) RETURNS private_isg.workspace_handovers
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE result private_isg.workspace_handovers; pending_count integer; completed_count integer;
BEGIN
  SELECT count(*) FILTER(WHERE status='pending'),count(*) FILTER(WHERE status='completed')
    INTO pending_count,completed_count FROM private_isg.workspace_handover_items WHERE handover_id=p_handover;
  UPDATE private_isg.workspace_handovers SET
    status=CASE
      WHEN pending_count=0 THEN 'completed'
      WHEN completed_count>0 THEN 'partially_completed'
      WHEN effective_at>clock_timestamp() THEN 'scheduled'
      ELSE 'in_progress' END,
    completed_at=CASE WHEN pending_count=0 THEN coalesce(completed_at,clock_timestamp()) ELSE NULL END,
    version=version+1,updated_at=clock_timestamp()
    WHERE id=p_handover AND status<>'cancelled' RETURNING * INTO result;
  RETURN result;
END $$;

CREATE FUNCTION private_isg.workspace_handover_preview(p_mutation uuid,p_workspace uuid,
  p_source_membership uuid,p_target_membership uuid,p_companies uuid[],p_effective_at timestamptz,
  p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); manager private_isg.workspace_memberships;
  source_member private_isg.workspace_memberships; target_member private_isg.workspace_memberships;
  v_company_id uuid; item_snapshot jsonb; company private_isg.workspace_companies; assignment private_isg.company_assignments;
  clean_companies uuid[]; clean_reason text; snapshot jsonb:='[]'::jsonb; preview_hash bytea;
  fingerprint bytea; replay jsonb; handover private_isg.workspace_handovers; item_count integer:=0; result jsonb;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_handover',true);
  manager:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],true);
  clean_reason:=private_isg.workspace_text(p_reason,500);
  IF p_mutation IS NULL OR p_source_membership IS NULL OR p_target_membership IS NULL OR
     p_source_membership=p_target_membership OR p_companies IS NULL OR cardinality(p_companies)<1 OR
     p_effective_at IS NULL OR p_effective_at<clock_timestamp()-interval '5 minutes' OR
     p_effective_at>clock_timestamp()+interval '365 days' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT array_agg(value ORDER BY value) INTO clean_companies FROM (SELECT DISTINCT unnest(p_companies) value) q;
  SELECT * INTO source_member FROM private_isg.workspace_memberships
    WHERE workspace_id=p_workspace AND id=p_source_membership FOR SHARE;
  SELECT * INTO target_member FROM private_isg.workspace_memberships
    WHERE workspace_id=p_workspace AND id=p_target_membership FOR SHARE;
  IF source_member.id IS NULL OR target_member.id IS NULL OR
     source_member.status<>'active' OR target_member.status<>'active' OR
     NOT source_member.is_practicing_expert OR NOT target_member.is_practicing_expert THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PRACTICING_MEMBERSHIP_REQUIRED'; END IF;
  FOREACH v_company_id IN ARRAY clean_companies LOOP
    SELECT * INTO company FROM private_isg.workspace_companies
      WHERE workspace_id=p_workspace AND id=v_company_id AND status='active' FOR SHARE;
    IF company.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    SELECT a.* INTO assignment FROM private_isg.company_assignments a
      WHERE a.workspace_id=p_workspace AND a.company_id=v_company_id AND a.membership_id=p_source_membership
        AND a.assignment_role='primary' AND a.starts_at<=p_effective_at
        AND (a.ends_at IS NULL OR a.ends_at>p_effective_at) FOR SHARE;
    IF assignment.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SOURCE_ASSIGNMENT_REQUIRED'; END IF;
    IF EXISTS(SELECT 1 FROM private_isg.company_assignments a
      WHERE a.workspace_id=p_workspace AND a.company_id=v_company_id AND a.membership_id=p_target_membership
        AND tstzrange(a.starts_at,a.ends_at,'[)') && tstzrange(p_effective_at,NULL,'[)')) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='TARGET_ASSIGNMENT_CONFLICT'; END IF;
    snapshot:=snapshot||jsonb_build_array(jsonb_build_object('company_id',company.id,
      'company_version',company.version,'source_assignment_id',assignment.id,
      'source_assignment_version',assignment.version));
    item_count:=item_count+1;
  END LOOP;
  preview_hash:=sha256(convert_to(jsonb_build_object('workspace_id',p_workspace,
    'source_membership_id',source_member.id,'source_membership_version',source_member.version,
    'target_membership_id',target_member.id,'target_membership_version',target_member.version,
    'effective_at',p_effective_at,'reason',clean_reason,'items',snapshot)::text,'UTF8'));
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_source_membership,p_target_membership,
    clean_companies,p_effective_at,clean_reason)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'handover.preview',fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  INSERT INTO private_isg.workspace_handovers(workspace_id,source_membership_id,target_membership_id,
    effective_at,reason,preview_hash,source_membership_version,target_membership_version,created_by_user_id)
    VALUES(p_workspace,source_member.id,target_member.id,p_effective_at,clean_reason,preview_hash,
      source_member.version,target_member.version,actor) RETURNING * INTO handover;
  FOR item_snapshot IN SELECT jsonb_array_elements(snapshot) LOOP
    INSERT INTO private_isg.workspace_handover_items(workspace_id,handover_id,company_id,
      source_assignment_id,source_assignment_version,company_version)
      VALUES(p_workspace,handover.id,(item_snapshot->>'company_id')::uuid,
        (item_snapshot->>'source_assignment_id')::uuid,(item_snapshot->>'source_assignment_version')::bigint,
        (item_snapshot->>'company_version')::bigint);
  END LOOP;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'handover_id',handover.id,
    'status',handover.status,'version',handover.version,'effective_at',handover.effective_at,
    'preview_hash',encode(preview_hash,'hex'),'item_count',item_count,'items',snapshot);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'handover.preview',fingerprint,p_workspace,
    'handover',handover.id,handover.version,NULL,result,clean_reason,result);
END $$;

CREATE FUNCTION private_isg.workspace_handover_execute_item(p_mutation uuid,p_workspace uuid,
  p_handover uuid,p_company uuid,p_expected_version bigint,p_preview_hash text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); manager private_isg.workspace_memberships;
  handover private_isg.workspace_handovers; item private_isg.workspace_handover_items;
  company private_isg.workspace_companies; source_member private_isg.workspace_memberships;
  target_member private_isg.workspace_memberships; source_assignment private_isg.company_assignments;
  target_assignment private_isg.company_assignments; fingerprint bytea; replay jsonb;
  event private_isg.company_memory_events; brief jsonb; result jsonb;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_handover',true);
  manager:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],true);
  IF p_expected_version IS NULL OR p_expected_version<0 OR p_preview_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_handover,p_company,
    p_expected_version,p_preview_hash)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'handover.execute',fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  SELECT * INTO handover FROM private_isg.workspace_handovers
    WHERE id=p_handover AND workspace_id=p_workspace FOR UPDATE;
  IF handover.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF handover.status='cancelled' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='HANDOVER_CANCELLED'; END IF;
  IF handover.version<>p_expected_version OR encode(handover.preview_hash,'hex')<>p_preview_hash THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  SELECT * INTO item FROM private_isg.workspace_handover_items
    WHERE handover_id=p_handover AND workspace_id=p_workspace AND company_id=p_company FOR UPDATE;
  IF item.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF item.status='completed' THEN
    RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'handover_id',handover.id,
      'company_id',p_company,'item_status','completed','target_assignment_id',item.target_assignment_id,
      'handover_status',handover.status,'version',handover.version,'replayed',true);
  END IF;
  IF handover.effective_at>clock_timestamp() THEN
    IF handover.status='draft' THEN
      UPDATE private_isg.workspace_handovers SET status='scheduled',version=version+1,
        updated_at=clock_timestamp() WHERE id=handover.id RETURNING * INTO handover;
    END IF;
    result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'handover_id',handover.id,
      'company_id',p_company,'item_status','pending','handover_status',handover.status,
      'effective_at',handover.effective_at,'version',handover.version);
    RETURN private_isg.workspace_record_effect(actor,p_mutation,'handover.execute',fingerprint,p_workspace,
      'handover',handover.id,handover.version,NULL,result,handover.reason,result);
  END IF;
  SELECT * INTO source_member FROM private_isg.workspace_memberships
    WHERE workspace_id=p_workspace AND id=handover.source_membership_id FOR SHARE;
  SELECT * INTO target_member FROM private_isg.workspace_memberships
    WHERE workspace_id=p_workspace AND id=handover.target_membership_id FOR SHARE;
  IF source_member.status<>'active' OR target_member.status<>'active' OR
     NOT source_member.is_practicing_expert OR NOT target_member.is_practicing_expert THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PRACTICING_MEMBERSHIP_REQUIRED'; END IF;
  IF source_member.version<>handover.source_membership_version OR
     target_member.version<>handover.target_membership_version THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  SELECT * INTO company FROM private_isg.workspace_companies
    WHERE workspace_id=p_workspace AND id=p_company FOR SHARE;
  IF company.id IS NULL OR company.status<>'active' OR company.version<>item.company_version THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  SELECT * INTO source_assignment FROM private_isg.company_assignments
    WHERE id=item.source_assignment_id AND workspace_id=p_workspace AND company_id=p_company FOR UPDATE;
  IF source_assignment.id IS NULL OR source_assignment.membership_id<>handover.source_membership_id OR
     source_assignment.assignment_role<>'primary' OR source_assignment.version<>item.source_assignment_version OR
     source_assignment.ends_at IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  UPDATE private_isg.company_assignments SET ends_at=handover.effective_at,ended_by_user_id=actor,
    reason=handover.reason,version=version+1,updated_at=clock_timestamp()
    WHERE id=source_assignment.id RETURNING * INTO source_assignment;
  INSERT INTO private_isg.company_assignment_events(workspace_id,assignment_id,event_type,actor_user_id,
    before_state,after_state,reason,correlation_id)
    VALUES(p_workspace,source_assignment.id,'ended',actor,NULL,
      private_isg.company_assignment_json(source_assignment),handover.reason,p_mutation);
  INSERT INTO private_isg.company_assignments(workspace_id,company_id,membership_id,assignment_role,
    starts_at,created_by_user_id,reason)
    VALUES(p_workspace,p_company,target_member.id,'primary',handover.effective_at,actor,handover.reason)
    RETURNING * INTO target_assignment;
  INSERT INTO private_isg.company_assignment_events(workspace_id,assignment_id,event_type,actor_user_id,
    after_state,reason,correlation_id)
    VALUES(p_workspace,target_assignment.id,'created',actor,
      private_isg.company_assignment_json(target_assignment),handover.reason,p_mutation);
  UPDATE private_isg.workspace_handover_items SET status='completed',target_assignment_id=target_assignment.id,
    execution_mutation_id=p_mutation,executed_at=clock_timestamp(),version=version+1,
    updated_at=clock_timestamp() WHERE id=item.id RETURNING * INTO item;
  INSERT INTO private_isg.company_memory_events(workspace_id,company_id,event_kind,source_type,source_id,
    source_version,event_key,occurred_at,title,summary,created_by_user_id,metadata)
    VALUES(p_workspace,p_company,'assignment_handover','handover_item',item.id,item.version,
      'primary_assignment_transferred',handover.effective_at,'Uzman sorumluluğu devredildi',
      'Birincil uzman sorumluluğu çalışma alanı yöneticisi tarafından yeni uzmana devredildi.',actor,
      jsonb_build_object('source_membership_id',source_member.id,'target_membership_id',target_member.id,
        'source_assignment_id',source_assignment.id,'target_assignment_id',target_assignment.id))
    RETURNING * INTO event;
  brief:=jsonb_build_object('schema_version',1,'company_id',p_company,'handover_id',handover.id,
    'effective_at',handover.effective_at,'event_count',1,'latest_event_title',event.title,
    'latest_event_summary',event.summary,'generated_by','deterministic_v1');
  INSERT INTO private_isg.company_handover_briefs(workspace_id,company_id,handover_item_id,
    source_watermark,content) VALUES(p_workspace,p_company,item.id,event.recorded_at,brief);
  handover:=private_isg.handover_refresh_status(handover.id);
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'handover_id',handover.id,
    'company_id',p_company,'item_status','completed','target_assignment_id',target_assignment.id,
    'handover_status',handover.status,'version',handover.version,'brief',brief);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'handover.execute',fingerprint,p_workspace,
    'handover',handover.id,handover.version,NULL,result,handover.reason,result);
END $$;

CREATE FUNCTION private_isg.workspace_company_memory(p_workspace uuid,p_company uuid,p_limit integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE member private_isg.workspace_memberships; rows jsonb;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_handover',false);
  IF p_limit NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  member:=private_isg.workspace_require_company(p_workspace,p_company,false);
  SELECT coalesce(jsonb_agg(row_value ORDER BY occurred_at DESC,id DESC),'[]'::jsonb) INTO rows
  FROM (SELECT id,occurred_at,jsonb_build_object('event_id',id,'event_kind',event_kind,
    'occurred_at',occurred_at,'title',title,'summary',summary,'metadata',metadata) row_value
    FROM private_isg.company_memory_events WHERE workspace_id=p_workspace AND company_id=p_company
    ORDER BY occurred_at DESC,id DESC LIMIT p_limit) q;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,'rows',rows);
END $$;

CREATE FUNCTION private_isg.workspace_handover_cancel(p_mutation uuid,p_workspace uuid,
  p_handover uuid,p_expected_version bigint,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); manager private_isg.workspace_memberships;
  handover private_isg.workspace_handovers; before_state jsonb; result jsonb;
  fingerprint bytea; replay jsonb; clean_reason text;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_handover',true);
  manager:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],true);
  clean_reason:=private_isg.workspace_text(p_reason,500);
  IF p_mutation IS NULL OR p_handover IS NULL OR p_expected_version IS NULL OR p_expected_version<0 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_handover,p_expected_version,clean_reason)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'handover.cancel',fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  SELECT * INTO handover FROM private_isg.workspace_handovers
    WHERE id=p_handover AND workspace_id=p_workspace FOR UPDATE;
  IF handover.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF handover.version<>p_expected_version THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  IF handover.status NOT IN ('draft','scheduled') OR EXISTS(
    SELECT 1 FROM private_isg.workspace_handover_items WHERE handover_id=p_handover AND status='completed') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='HANDOVER_NOT_CANCELLABLE'; END IF;
  before_state:=jsonb_build_object('status',handover.status,'version',handover.version,
    'effective_at',handover.effective_at);
  UPDATE private_isg.workspace_handover_items SET status='cancelled',version=version+1,
    updated_at=clock_timestamp() WHERE handover_id=p_handover AND status='pending';
  UPDATE private_isg.workspace_handovers SET status='cancelled',cancelled_by_user_id=actor,
    cancelled_at=clock_timestamp(),version=version+1,updated_at=clock_timestamp()
    WHERE id=p_handover RETURNING * INTO handover;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'handover_id',handover.id,
    'status',handover.status,'version',handover.version,'cancelled_at',handover.cancelled_at);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'handover.cancel',fingerprint,p_workspace,
    'handover',handover.id,handover.version,before_state,result,clean_reason,result);
END $$;

CREATE FUNCTION private_isg.workspace_handover_compensation_preview(p_mutation uuid,p_workspace uuid,
  p_original_handover uuid,p_company uuid,p_effective_at timestamptz,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE manager private_isg.workspace_memberships; original private_isg.workspace_handovers;
  original_item private_isg.workspace_handover_items; current_assignment private_isg.company_assignments;
  source_member private_isg.workspace_memberships; result jsonb; clean_reason text;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_handover',true);
  manager:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],true);
  clean_reason:=private_isg.workspace_text(p_reason,480);
  SELECT * INTO original FROM private_isg.workspace_handovers
    WHERE id=p_original_handover AND workspace_id=p_workspace FOR SHARE;
  SELECT * INTO original_item FROM private_isg.workspace_handover_items
    WHERE handover_id=p_original_handover AND workspace_id=p_workspace AND company_id=p_company FOR SHARE;
  IF original.id IS NULL OR original_item.id IS NULL OR original_item.status<>'completed' OR
     original_item.target_assignment_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='COMPENSATION_SOURCE_INVALID'; END IF;
  SELECT * INTO current_assignment FROM private_isg.company_assignments
    WHERE id=original_item.target_assignment_id AND workspace_id=p_workspace AND company_id=p_company FOR SHARE;
  SELECT * INTO source_member FROM private_isg.workspace_memberships
    WHERE id=original.source_membership_id AND workspace_id=p_workspace FOR SHARE;
  IF current_assignment.id IS NULL OR current_assignment.ends_at IS NOT NULL OR
     current_assignment.membership_id<>original.target_membership_id OR
     source_member.id IS NULL OR source_member.status<>'active' OR NOT source_member.is_practicing_expert THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='COMPENSATION_VERSION_CONFLICT'; END IF;
  IF EXISTS(SELECT 1 FROM private_isg.workspace_handovers h
    WHERE h.compensation_for_item_id=original_item.id AND h.status<>'cancelled') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='COMPENSATION_ALREADY_PLANNED'; END IF;
  result:=private_isg.workspace_handover_preview(p_mutation,p_workspace,
    original.target_membership_id,original.source_membership_id,ARRAY[p_company],p_effective_at,
    private_isg.workspace_text('Ters devir: '||clean_reason,500));
  UPDATE private_isg.workspace_handovers SET compensation_for_handover_id=original.id,
    compensation_for_item_id=original_item.id
    WHERE id=(result->>'handover_id')::uuid AND workspace_id=p_workspace;
  RETURN result||jsonb_build_object('compensates_handover_id',original.id,
    'compensates_item_id',original_item.id);
END $$;

CREATE FUNCTION public.isg_workspace_handover_preview_v1(p_mutation uuid,p_workspace uuid,
  p_source_membership uuid,p_target_membership uuid,p_companies uuid[],p_effective_at timestamptz,p_reason text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_handover_preview(
  p_mutation,p_workspace,p_source_membership,p_target_membership,p_companies,p_effective_at,p_reason) $$;
CREATE FUNCTION public.isg_workspace_handover_execute_v1(p_mutation uuid,p_workspace uuid,p_handover uuid,
  p_company uuid,p_expected_version bigint,p_preview_hash text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_handover_execute_item(
  p_mutation,p_workspace,p_handover,p_company,p_expected_version,p_preview_hash) $$;
CREATE FUNCTION public.isg_workspace_company_memory_v1(p_workspace uuid,p_company uuid,p_limit integer)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_company_memory(
  p_workspace,p_company,p_limit) $$;
CREATE FUNCTION public.isg_workspace_handover_cancel_v1(p_mutation uuid,p_workspace uuid,
  p_handover uuid,p_expected_version bigint,p_reason text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_handover_cancel(
  p_mutation,p_workspace,p_handover,p_expected_version,p_reason) $$;
CREATE FUNCTION public.isg_workspace_handover_compensate_v1(p_mutation uuid,p_workspace uuid,
  p_original_handover uuid,p_company uuid,p_effective_at timestamptz,p_reason text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_handover_compensation_preview(
  p_mutation,p_workspace,p_original_handover,p_company,p_effective_at,p_reason) $$;

REVOKE ALL ON FUNCTION private_isg.handover_refresh_status(uuid),
  private_isg.workspace_handover_preview(uuid,uuid,uuid,uuid,uuid[],timestamptz,text),
  private_isg.workspace_handover_execute_item(uuid,uuid,uuid,uuid,bigint,text),
  private_isg.workspace_handover_cancel(uuid,uuid,uuid,bigint,text),
  private_isg.workspace_handover_compensation_preview(uuid,uuid,uuid,uuid,timestamptz,text),
  private_isg.workspace_company_memory(uuid,uuid,integer),
  public.isg_workspace_handover_preview_v1(uuid,uuid,uuid,uuid,uuid[],timestamptz,text),
  public.isg_workspace_handover_execute_v1(uuid,uuid,uuid,uuid,bigint,text),
  public.isg_workspace_handover_cancel_v1(uuid,uuid,uuid,bigint,text),
  public.isg_workspace_handover_compensate_v1(uuid,uuid,uuid,uuid,timestamptz,text),
  public.isg_workspace_company_memory_v1(uuid,uuid,integer)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_handover_preview(uuid,uuid,uuid,uuid,uuid[],timestamptz,text),
  private_isg.workspace_handover_execute_item(uuid,uuid,uuid,uuid,bigint,text),
  private_isg.workspace_handover_cancel(uuid,uuid,uuid,bigint,text),
  private_isg.workspace_handover_compensation_preview(uuid,uuid,uuid,uuid,timestamptz,text),
  private_isg.workspace_company_memory(uuid,uuid,integer),
  public.isg_workspace_handover_preview_v1(uuid,uuid,uuid,uuid,uuid[],timestamptz,text),
  public.isg_workspace_handover_execute_v1(uuid,uuid,uuid,uuid,bigint,text),
  public.isg_workspace_handover_cancel_v1(uuid,uuid,uuid,bigint,text),
  public.isg_workspace_handover_compensate_v1(uuid,uuid,uuid,uuid,timestamptz,text),
  public.isg_workspace_company_memory_v1(uuid,uuid,integer)
  TO authenticated;
NOTIFY pgrst,'reload schema';
