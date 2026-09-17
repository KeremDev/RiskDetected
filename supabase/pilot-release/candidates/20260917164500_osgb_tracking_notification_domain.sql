-- D9 scoped dashboard/search/realtime/notifications, cleanup safety and signed PPE evidence.
-- NOT DEPLOYED; `tracking_notifications` remains OFF by default.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='35s';

ALTER TABLE private_isg.workspace_audit DROP CONSTRAINT workspace_audit_entity_type_check;
ALTER TABLE private_isg.workspace_audit ADD CONSTRAINT workspace_audit_entity_type_check CHECK(entity_type IN
  ('workspace','membership','invitation','company','assignment','seat','subscription','wallet','asset','handover',
   'workplace','department','employee','domain','training','risk','nonconformity','checklist','emergency_plan',
   'drill','appointment','ppe','equipment','katip_contract','annual_plan','board','work_permit','site_visit',
   'notebook_archive','file_entry','file_reference','analysis','export','notification'));
ALTER TABLE private_isg.workspace_outbox DROP CONSTRAINT workspace_outbox_aggregate_type_check;
ALTER TABLE private_isg.workspace_outbox ADD CONSTRAINT workspace_outbox_aggregate_type_check CHECK(aggregate_type IN
  ('workspace','membership','invitation','company','assignment','seat','subscription','wallet','asset','handover',
   'workplace','department','employee','domain','training','risk','nonconformity','checklist','emergency_plan',
   'drill','appointment','ppe','equipment','katip_contract','annual_plan','board','work_permit','site_visit',
   'notebook_archive','file_entry','file_reference','analysis','export','notification'));

ALTER TABLE private_isg.ppe_handovers ADD COLUMN signed_file_entry_id uuid;
ALTER TABLE private_isg.ppe_handovers ADD COLUMN signed_asset_id uuid;
ALTER TABLE private_isg.ppe_handovers ADD CONSTRAINT ppe_signed_entry_fk
  FOREIGN KEY(workspace_id,signed_file_entry_id) REFERENCES private_isg.workspace_file_entries(workspace_id,id) ON DELETE RESTRICT;
ALTER TABLE private_isg.ppe_handovers ADD CONSTRAINT ppe_signed_asset_fk
  FOREIGN KEY(workspace_id,signed_asset_id) REFERENCES private_isg.workspace_file_assets(workspace_id,id) ON DELETE RESTRICT;
-- Legacy signed_copy uses an external/paper reference. New evidence IDs are
-- mandatory for OSGB only; a global CHECK would reject populated personal data.
ALTER TABLE private_isg.ppe_handovers ADD CONSTRAINT ppe_signed_evidence_shape
  CHECK((signed_file_entry_id IS NULL)=(signed_asset_id IS NULL));
CREATE FUNCTION private_isg.workspace_ppe_signed_evidence_invariant() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF EXISTS(SELECT 1 FROM public.companies c WHERE c.id=NEW.company_id AND c.user_id IS NULL) AND
    NOT ((NEW.signed_copy AND NEW.signed_file_entry_id IS NOT NULL AND NEW.signed_asset_id IS NOT NULL) OR
         (NOT NEW.signed_copy AND NEW.signed_file_entry_id IS NULL AND NEW.signed_asset_id IS NULL)) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PPE_SIGNED_EVIDENCE_REQUIRED';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private_isg.workspace_ppe_signed_evidence_invariant() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER ppe_signed_evidence_before BEFORE INSERT OR UPDATE ON private_isg.ppe_handovers
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_ppe_signed_evidence_invariant();

CREATE TABLE private_isg.workspace_change_feed (
  sequence_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  outbox_id uuid NOT NULL UNIQUE REFERENCES private_isg.workspace_outbox(id) ON DELETE RESTRICT,
  workspace_id uuid NOT NULL REFERENCES private_isg.workspaces(id) ON DELETE RESTRICT,
  company_id uuid,
  visibility text NOT NULL CHECK(visibility IN ('workspace_management','company_team')),
  event_type text NOT NULL CHECK(octet_length(event_type) BETWEEN 1 AND 100),
  aggregate_type text NOT NULL,
  aggregate_id uuid NOT NULL,
  aggregate_version bigint NOT NULL,
  occurred_at timestamptz NOT NULL,
  FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT,
  CHECK((visibility='company_team')=(company_id IS NOT NULL))
);
CREATE INDEX workspace_change_feed_page ON private_isg.workspace_change_feed(workspace_id,company_id,sequence_id);

CREATE TABLE private_isg.workspace_notification_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  company_id uuid NOT NULL,
  recipient_membership_id uuid NOT NULL,
  recipient_user_id uuid NOT NULL,
  permission_revision bigint NOT NULL CHECK(permission_revision>=0),
  kind text NOT NULL CHECK(kind IN ('deadline_due','deadline_soon','assignment_changed','export_ready','handover_ready')),
  parent_kind text NOT NULL CHECK(parent_kind IN ('nonconformity','equipment','training','risk','export','handover')),
  parent_id uuid NOT NULL,
  event_key text NOT NULL CHECK(octet_length(event_key) BETWEEN 1 AND 200),
  due_at timestamptz NOT NULL,
  deep_link_path text NOT NULL CHECK(deep_link_path ~ '^/[a-z0-9_/-]{1,250}$'),
  status text NOT NULL DEFAULT 'queued' CHECK(status IN ('queued','leased','sent','failed','cancelled')),
  attempt_count integer NOT NULL DEFAULT 0 CHECK(attempt_count BETWEEN 0 AND 20),
  lease_token uuid,
  lease_until timestamptz,
  last_error text CHECK(last_error IS NULL OR octet_length(last_error)<=200),
  sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(workspace_id,event_key,recipient_membership_id),
  FOREIGN KEY(workspace_id,company_id) REFERENCES public.companies(workspace_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,recipient_membership_id)
    REFERENCES private_isg.workspace_memberships(workspace_id,id) ON DELETE RESTRICT,
  CHECK((status='leased')=(lease_token IS NOT NULL AND lease_until IS NOT NULL)),
  CHECK((status='sent')=(sent_at IS NOT NULL))
);
CREATE INDEX workspace_notification_due ON private_isg.workspace_notification_jobs(status,due_at,id)
  WHERE status IN ('queued','failed','leased');

ALTER TABLE private_isg.workspace_change_feed ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_notification_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.workspace_change_feed,private_isg.workspace_notification_jobs
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON SEQUENCE private_isg.workspace_change_feed_sequence_id_seq FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.workspace_event_company(p_payload jsonb) RETURNS uuid
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE value text;
BEGIN
  value:=coalesce(p_payload->>'company_id',p_payload->'row'->>'company_id',p_payload->'after'->>'company_id');
  IF value IS NULL THEN RETURN NULL; END IF;
  RETURN value::uuid;
EXCEPTION WHEN invalid_text_representation THEN RETURN NULL;
END $$;

CREATE FUNCTION private_isg.workspace_project_outbox() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE company uuid:=private_isg.workspace_event_company(NEW.payload);
BEGIN
  IF NEW.workspace_id IS NULL THEN RETURN NEW; END IF;
  IF company IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.companies c WHERE c.workspace_id=NEW.workspace_id AND c.id=company) THEN
    company:=NULL; END IF;
  INSERT INTO private_isg.workspace_change_feed(outbox_id,workspace_id,company_id,visibility,event_type,
    aggregate_type,aggregate_id,aggregate_version,occurred_at)
  VALUES(NEW.id,NEW.workspace_id,company,CASE WHEN company IS NULL THEN 'workspace_management' ELSE 'company_team' END,
    NEW.event_type,NEW.aggregate_type,NEW.aggregate_id,NEW.aggregate_version,NEW.created_at)
  ON CONFLICT(outbox_id) DO NOTHING;
  RETURN NEW;
END $$;
CREATE TRIGGER workspace_outbox_change_feed_after AFTER INSERT ON private_isg.workspace_outbox
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_project_outbox();

INSERT INTO private_isg.workspace_change_feed(outbox_id,workspace_id,company_id,visibility,event_type,
  aggregate_type,aggregate_id,aggregate_version,occurred_at)
SELECT o.id,o.workspace_id,c.company_id,CASE WHEN c.company_id IS NULL THEN 'workspace_management' ELSE 'company_team' END,
  o.event_type,o.aggregate_type,o.aggregate_id,o.aggregate_version,o.created_at
FROM private_isg.workspace_outbox o
CROSS JOIN LATERAL (SELECT private_isg.workspace_event_company(o.payload) company_id) c
WHERE o.workspace_id IS NOT NULL AND (c.company_id IS NULL OR EXISTS(
  SELECT 1 FROM public.companies co WHERE co.workspace_id=o.workspace_id AND co.id=c.company_id))
ON CONFLICT(outbox_id) DO NOTHING;

CREATE FUNCTION private_isg.workspace_dashboard(p_workspace uuid,p_company uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE member private_isg.workspace_memberships; today date:=(clock_timestamp() AT TIME ZONE 'UTC')::date;
BEGIN
  PERFORM private_isg.workspace_domain_gate('tracking_notifications',false);
  -- An unavailable source is not a measured zero and must not leak via aggregates.
  PERFORM private_isg.workspace_domain_gate('risk_nonconformity',false);
  PERFORM private_isg.workspace_domain_gate('training',false);
  PERFORM private_isg.workspace_domain_gate('equipment',false);
  PERFORM private_isg.workspace_domain_gate('operations',false);
  member:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin','expert'],false);
  IF p_company IS NOT NULL THEN member:=private_isg.workspace_require_company(p_workspace,p_company,false);
  ELSIF member.role='expert' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='COMPANY_REQUIRED'; END IF;
  SELECT (clock_timestamp() AT TIME ZONE w.timezone)::date INTO today FROM private_isg.workspaces w WHERE w.id=p_workspace;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,'measured',true,
    'companies',jsonb_build_object(
      'total',(SELECT count(*) FROM public.companies c WHERE c.workspace_id=p_workspace AND c.is_archived=false AND (p_company IS NULL OR c.id=p_company)),
      'unassigned',CASE WHEN member.role IN ('owner','admin') THEN (SELECT count(*) FROM public.companies c
        WHERE c.workspace_id=p_workspace AND c.is_archived=false AND (p_company IS NULL OR c.id=p_company)
          AND NOT EXISTS(SELECT 1 FROM private_isg.company_assignments a WHERE a.workspace_id=p_workspace AND a.company_id=c.id
            AND a.starts_at<=clock_timestamp() AND (a.ends_at IS NULL OR a.ends_at>clock_timestamp()))) ELSE NULL END),
    'experts',jsonb_build_object('active',CASE WHEN member.role IN ('owner','admin') THEN
      (SELECT count(*) FROM private_isg.workspace_memberships m WHERE m.workspace_id=p_workspace AND m.status='active' AND m.is_practicing_expert) ELSE NULL END),
    'nonconformities',jsonb_build_object(
      'open',(SELECT count(*) FROM private_isg.nonconformities n WHERE n.workspace_id=p_workspace
        AND (p_company IS NULL OR n.company_id=p_company) AND n.state NOT IN ('closed','cancelled')),
      'overdue',(SELECT count(*) FROM private_isg.nonconformities n WHERE n.workspace_id=p_workspace
        AND (p_company IS NULL OR n.company_id=p_company) AND n.state NOT IN ('closed','cancelled') AND n.due_on<today)),
    'visits',jsonb_build_object(
      'total',(SELECT count(*) FROM private_isg.site_visits v WHERE v.workspace_id=p_workspace AND (p_company IS NULL OR v.company_id=p_company)),
      'last_30_days',(SELECT count(*) FROM private_isg.site_visits v WHERE v.workspace_id=p_workspace
        AND (p_company IS NULL OR v.company_id=p_company) AND v.visited_on BETWEEN today-29 AND today)),
    'training',jsonb_build_object(
      'planned',(SELECT count(*) FROM private_isg.pilot_training_records t WHERE t.workspace_id=p_workspace
        AND (p_company IS NULL OR t.company_id=p_company) AND t.state='planned'),
      'completed',(SELECT count(*) FROM private_isg.pilot_training_records t WHERE t.workspace_id=p_workspace
        AND (p_company IS NULL OR t.company_id=p_company) AND t.state='completed')),
    'deadlines',jsonb_build_object(
      'equipment_due_soon',(SELECT count(*) FROM private_isg.equipment_items e LEFT JOIN LATERAL (
        SELECT i.next_due_on FROM private_isg.equipment_inspections i WHERE i.equipment_id=e.equipment_id ORDER BY i.performed_on DESC,i.inspection_id DESC LIMIT 1) last ON true
        WHERE e.workspace_id=p_workspace AND (p_company IS NULL OR e.company_id=p_company) AND NOT e.is_archived AND last.next_due_on BETWEEN today AND today+30),
      'risk_due_soon',(SELECT count(*) FROM private_isg.risk_assessments r WHERE r.workspace_id=p_workspace
        AND (p_company IS NULL OR r.company_id=p_company) AND r.valid_until BETWEEN today AND today+60)));
END $$;

CREATE FUNCTION private_isg.workspace_search(p_workspace uuid,p_company uuid,p_query text,p_after_kind text,
  p_after_id uuid,p_limit integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE needle text:=nullif(btrim(coalesce(p_query,'')),''); rows jsonb; next_kind text; next_id uuid; member private_isg.workspace_memberships;
BEGIN
  PERFORM private_isg.workspace_domain_gate('tracking_notifications',false);
  member:=private_isg.workspace_require_company(p_workspace,p_company,false);
  IF needle IS NULL OR octet_length(needle) NOT BETWEEN 2 AND 120 OR p_limit NOT BETWEEN 1 AND 100 OR
     (p_after_kind IS NULL)<>(p_after_id IS NULL) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  WITH candidates AS (
    SELECT 'company' kind,c.id,c.name title,c.hazard_class subtitle,c.updated_at FROM public.companies c
      WHERE c.workspace_id=p_workspace AND c.id=p_company AND NOT c.is_archived
    UNION ALL SELECT 'employee',e.id,e.full_name,e.employee_code,e.registered_at FROM private_isg.employees e
      WHERE e.workspace_id=p_workspace AND e.company_id=p_company AND NOT e.is_archived AND EXISTS(SELECT 1 FROM private_isg.workspace_domain_rollout WHERE domain='personnel' AND read_enabled)
    UNION ALL SELECT 'nonconformity',n.nonconformity_id,n.title,n.state,n.updated_at FROM private_isg.nonconformities n
      WHERE n.workspace_id=p_workspace AND n.company_id=p_company AND EXISTS(SELECT 1 FROM private_isg.workspace_domain_rollout WHERE domain='risk_nonconformity' AND read_enabled)
    UNION ALL SELECT 'equipment',e.equipment_id,e.serial_tag,e.equipment_type,e.created_at FROM private_isg.equipment_items e
      WHERE e.workspace_id=p_workspace AND e.company_id=p_company AND NOT e.is_archived AND EXISTS(SELECT 1 FROM private_isg.workspace_domain_rollout WHERE domain='equipment' AND read_enabled)
    UNION ALL SELECT 'training',t.id,t.title,t.state,t.updated_at FROM private_isg.pilot_training_records t
      WHERE t.workspace_id=p_workspace AND t.company_id=p_company AND EXISTS(SELECT 1 FROM private_isg.workspace_domain_rollout WHERE domain='training' AND read_enabled)
    UNION ALL SELECT 'file',f.id,f.title,f.original_filename,f.updated_at FROM private_isg.workspace_file_entries f
      WHERE f.workspace_id=p_workspace AND f.company_id=p_company AND f.state='active' AND EXISTS(SELECT 1 FROM private_isg.workspace_domain_rollout WHERE domain='files' AND read_enabled) AND private_isg.workspace_file_can_access(f,member)
  ), page AS (
    SELECT * FROM candidates c WHERE (c.title ILIKE '%'||needle||'%' OR coalesce(c.subtitle,'') ILIKE '%'||needle||'%')
      AND (p_after_kind IS NULL OR ROW(c.kind,c.id)>ROW(p_after_kind,p_after_id)) ORDER BY c.kind,c.id LIMIT p_limit
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('kind',kind,'id',id,'title',title,'subtitle',subtitle,
    'updated_at',updated_at) ORDER BY kind,id),'[]') INTO rows FROM page;
  IF jsonb_array_length(rows)>0 THEN
    next_kind:=rows->-1->>'kind'; next_id:=(rows->-1->>'id')::uuid;
  END IF;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'rows',rows,'returned',jsonb_array_length(rows),'next',CASE WHEN jsonb_array_length(rows)=p_limit THEN
      jsonb_build_object('kind',next_kind,'id',next_id) ELSE NULL END);
END $$;

CREATE FUNCTION private_isg.workspace_change_read(p_workspace uuid,p_company uuid,p_after bigint,p_limit integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE member private_isg.workspace_memberships; rows jsonb; next_value bigint;
BEGIN
  PERFORM private_isg.workspace_domain_gate('tracking_notifications',false);
  member:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin','expert'],false);
  IF p_company IS NULL THEN
    IF member.role='expert' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='COMPANY_REQUIRED'; END IF;
  ELSE member:=private_isg.workspace_require_company(p_workspace,p_company,false); END IF;
  IF coalesce(p_after,0)<0 OR p_limit NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('sequence',f.sequence_id,'event_type',f.event_type,
    'aggregate_type',f.aggregate_type,'aggregate_id',f.aggregate_id,'aggregate_version',f.aggregate_version,
    'occurred_at',f.occurred_at) ORDER BY f.sequence_id),'[]'),max(f.sequence_id) INTO rows,next_value
  FROM (SELECT * FROM private_isg.workspace_change_feed WHERE workspace_id=p_workspace
    AND (p_company IS NULL OR company_id=p_company) AND sequence_id>coalesce(p_after,0)
    AND (aggregate_type NOT IN ('file_entry','file_reference','asset') OR
      (aggregate_type='file_entry' AND EXISTS(SELECT 1 FROM private_isg.workspace_file_entries e
        WHERE e.workspace_id=p_workspace AND e.id=aggregate_id AND private_isg.workspace_file_can_access(e,member))) OR
      (aggregate_type='file_reference' AND EXISTS(SELECT 1 FROM private_isg.workspace_file_references r
        JOIN private_isg.workspace_file_entries e ON e.workspace_id=r.workspace_id AND e.id=r.entry_id
        WHERE r.workspace_id=p_workspace AND r.id=aggregate_id AND private_isg.workspace_file_can_access(e,member))))
    AND (aggregate_type IN ('workspace','membership','invitation','company','assignment','seat','subscription','wallet','handover','domain') OR
      EXISTS(SELECT 1 FROM private_isg.workspace_domain_rollout d WHERE d.read_enabled AND d.domain=CASE
        WHEN aggregate_type IN ('workplace','department','employee') THEN 'personnel'
        WHEN aggregate_type='training' THEN 'training'
        WHEN aggregate_type IN ('risk','nonconformity','checklist') THEN 'risk_nonconformity'
        WHEN aggregate_type IN ('emergency_plan','drill','appointment','ppe') THEN 'emergency_ppe'
        WHEN aggregate_type='equipment' THEN 'equipment'
        WHEN aggregate_type IN ('katip_contract','annual_plan','board','work_permit','site_visit','notebook_archive') THEN 'operations'
        WHEN aggregate_type IN ('file_entry','file_reference','asset') THEN 'files'
        WHEN aggregate_type IN ('analysis','export') THEN 'analysis_exports'
        WHEN aggregate_type='notification' THEN 'tracking_notifications' END))
    ORDER BY sequence_id LIMIT p_limit) f;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'rows',rows,'next',coalesce(next_value,p_after,0));
END $$;

CREATE FUNCTION private_isg.workspace_notification_parent_exists(p_workspace uuid,p_company uuid,p_kind text,p_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT CASE p_kind
    WHEN 'nonconformity' THEN EXISTS(SELECT 1 FROM private_isg.nonconformities WHERE workspace_id=p_workspace AND company_id=p_company AND nonconformity_id=p_id)
    WHEN 'equipment' THEN EXISTS(SELECT 1 FROM private_isg.equipment_items WHERE workspace_id=p_workspace AND company_id=p_company AND equipment_id=p_id)
    WHEN 'training' THEN EXISTS(SELECT 1 FROM private_isg.pilot_training_records WHERE workspace_id=p_workspace AND company_id=p_company AND id=p_id)
    WHEN 'risk' THEN EXISTS(SELECT 1 FROM private_isg.risk_assessments WHERE workspace_id=p_workspace AND company_id=p_company AND assessment_id=p_id)
    WHEN 'export' THEN EXISTS(SELECT 1 FROM private_isg.workspace_export_jobs WHERE workspace_id=p_workspace AND company_id=p_company AND id=p_id)
    WHEN 'handover' THEN EXISTS(SELECT 1 FROM private_isg.workspace_handover_items
      WHERE workspace_id=p_workspace AND company_id=p_company AND handover_id=p_id)
    ELSE false END
$$;

CREATE FUNCTION private_isg.workspace_notification_enqueue(p_workspace uuid,p_company uuid,p_recipient uuid,
  p_kind text,p_parent_kind text,p_parent uuid,p_event_key text,p_due_at timestamptz,p_deep_link text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE member private_isg.workspace_memberships; job private_isg.workspace_notification_jobs;
BEGIN
  IF p_kind NOT IN ('deadline_due','deadline_soon','assignment_changed','export_ready','handover_ready') OR
     p_parent_kind NOT IN ('nonconformity','equipment','training','risk','export','handover') OR p_due_at IS NULL OR
     p_event_key IS NULL OR octet_length(p_event_key) NOT BETWEEN 1 AND 200 OR
     p_deep_link !~ '^/[a-z0-9_/-]{1,250}$' OR
     NOT private_isg.workspace_notification_parent_exists(p_workspace,p_company,p_parent_kind,p_parent) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO member FROM private_isg.workspace_memberships WHERE workspace_id=p_workspace AND id=p_recipient;
  IF member.id IS NULL OR member.status<>'active' OR (member.role='expert' AND NOT EXISTS(
      SELECT 1 FROM private_isg.company_assignments a WHERE a.workspace_id=p_workspace AND a.company_id=p_company
        AND a.membership_id=member.id AND a.starts_at<=p_due_at AND (a.ends_at IS NULL OR a.ends_at>p_due_at))) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='RECIPIENT_NOT_AUTHORIZED'; END IF;
  INSERT INTO private_isg.workspace_notification_jobs(workspace_id,company_id,recipient_membership_id,
    recipient_user_id,permission_revision,kind,parent_kind,parent_id,event_key,due_at,deep_link_path)
  VALUES(p_workspace,p_company,member.id,member.user_id,member.permission_revision,p_kind,p_parent_kind,p_parent,
    private_isg.workspace_text(p_event_key,200),p_due_at,p_deep_link)
  ON CONFLICT(workspace_id,event_key,recipient_membership_id) DO UPDATE SET updated_at=private_isg.workspace_notification_jobs.updated_at
  RETURNING * INTO job;
  RETURN jsonb_build_object('job_id',job.id,'status',job.status,'replayed',job.created_at<>job.updated_at);
END $$;

CREATE FUNCTION private_isg.workspace_notification_claim(p_limit integer,p_now timestamptz,p_lease_seconds integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job private_isg.workspace_notification_jobs; member private_isg.workspace_memberships; rows jsonb:='[]'; token uuid;
BEGIN
  IF p_limit NOT BETWEEN 1 AND 100 OR p_now IS NULL OR p_lease_seconds NOT BETWEEN 30 AND 300 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  FOR job IN SELECT * FROM private_isg.workspace_notification_jobs j
      WHERE ((j.status IN ('queued','failed') AND j.due_at<=p_now) OR (j.status='leased' AND j.lease_until<=p_now))
        AND j.attempt_count<20 ORDER BY j.due_at,j.id FOR UPDATE SKIP LOCKED LIMIT p_limit LOOP
    SELECT * INTO member FROM private_isg.workspace_memberships WHERE workspace_id=job.workspace_id AND id=job.recipient_membership_id;
    IF member.id IS NULL OR member.status<>'active' OR member.user_id<>job.recipient_user_id OR
       member.permission_revision<>job.permission_revision OR (member.role='expert' AND NOT EXISTS(
         SELECT 1 FROM private_isg.company_assignments a WHERE a.workspace_id=job.workspace_id AND a.company_id=job.company_id
           AND a.membership_id=member.id AND a.starts_at<=p_now AND (a.ends_at IS NULL OR a.ends_at>p_now))) THEN
      UPDATE private_isg.workspace_notification_jobs SET status='cancelled',lease_token=NULL,lease_until=NULL,
        last_error='AUTHORITY_REVOKED',updated_at=clock_timestamp() WHERE id=job.id;
    ELSE
      token:=gen_random_uuid();
      UPDATE private_isg.workspace_notification_jobs SET status='leased',lease_token=token,
        lease_until=p_now+make_interval(secs=>p_lease_seconds),attempt_count=attempt_count+1,updated_at=clock_timestamp()
        WHERE id=job.id;
      rows:=rows||jsonb_build_array(jsonb_build_object('job_id',job.id,'lease_token',token,
        'recipient_user_id',job.recipient_user_id,'kind',job.kind,'deep_link_path',job.deep_link_path));
    END IF;
  END LOOP;
  RETURN jsonb_build_object('jobs',rows,'claimed',jsonb_array_length(rows));
END $$;

CREATE FUNCTION private_isg.workspace_notification_complete(p_job uuid,p_token uuid,p_sent boolean,p_error text,p_now timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE job private_isg.workspace_notification_jobs;
BEGIN
  IF p_job IS NULL OR p_token IS NULL OR p_sent IS NULL OR p_now IS NULL OR
     (NOT p_sent AND (p_error IS NULL OR octet_length(p_error) NOT BETWEEN 1 AND 200)) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO job FROM private_isg.workspace_notification_jobs WHERE id=p_job FOR UPDATE;
  IF job.id IS NULL OR job.status<>'leased' OR job.lease_token<>p_token OR job.lease_until<p_now THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='LEASE_CONFLICT'; END IF;
  UPDATE private_isg.workspace_notification_jobs SET status=CASE WHEN p_sent THEN 'sent' ELSE 'failed' END,
    sent_at=CASE WHEN p_sent THEN p_now END,last_error=CASE WHEN p_sent THEN NULL ELSE left(p_error,200) END,
    lease_token=NULL,lease_until=NULL,updated_at=clock_timestamp() WHERE id=p_job RETURNING * INTO job;
  RETURN jsonb_build_object('job_id',job.id,'status',job.status,'attempt_count',job.attempt_count);
END $$;

CREATE FUNCTION private_isg.workspace_ppe_signed_handover(p_mutation uuid,p_workspace uuid,p_company uuid,
  p_employee uuid,p_item text,p_quantity numeric,p_unit text,p_handed_on date,p_external_ref text,p_file_entry uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); member private_isg.workspace_memberships; fingerprint bytea;
  replay jsonb; entry private_isg.workspace_file_entries; file_version private_isg.workspace_file_versions;
  handover private_isg.ppe_handovers; reference_id uuid; result jsonb;
BEGIN
  PERFORM private_isg.workspace_domain_gate('tracking_notifications',true);
  PERFORM private_isg.workspace_domain_gate('emergency_ppe',true);
  PERFORM private_isg.workspace_domain_gate('files',true);
  member:=private_isg.workspace_require_company(p_workspace,p_company,true);
  IF p_mutation IS NULL OR p_quantity<=0 OR p_unit NOT IN ('piece','pair','set','metre','litre') OR
     p_handed_on IS NULL OR NOT isfinite(p_handed_on) OR NOT EXISTS(SELECT 1 FROM private_isg.employees e
       WHERE e.workspace_id=p_workspace AND e.company_id=p_company AND e.id=p_employee AND NOT e.is_archived) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO entry FROM private_isg.workspace_file_entries WHERE workspace_id=p_workspace AND company_id=p_company
    AND id=p_file_entry AND state='active';
  IF entry.id IS NULL OR NOT private_isg.workspace_file_can_access(entry,member) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SIGNED_EVIDENCE_REQUIRED'; END IF;
  SELECT * INTO file_version FROM private_isg.workspace_file_versions WHERE workspace_id=p_workspace
    AND entry_id=entry.id AND revision=entry.active_revision;
  IF file_version.asset_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SIGNED_EVIDENCE_REQUIRED'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_company,p_employee,p_item,p_quantity,p_unit,
    p_handed_on,p_external_ref,p_file_entry,entry.active_revision)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'ppe.signed_handover',fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  INSERT INTO private_isg.ppe_handovers(workspace_id,company_id,employee_id,item,quantity,unit,handed_on,
    signed_copy,signed_file_entry_id,signed_asset_id,external_ref,created_by_user_id,updated_by_user_id)
  VALUES(p_workspace,p_company,p_employee,private_isg.workspace_text(p_item,200),p_quantity,p_unit,p_handed_on,
    true,entry.id,file_version.asset_id,nullif(btrim(coalesce(p_external_ref,'')),''),actor,actor) RETURNING * INTO handover;
  INSERT INTO private_isg.workspace_file_references(workspace_id,company_id,entry_id,entry_revision,asset_id,
    parent_kind,parent_id,field_name,created_by_user_id)
  VALUES(p_workspace,p_company,entry.id,entry.active_revision,file_version.asset_id,'ppe',handover.handover_id,'signed_copy',actor)
  RETURNING id INTO reference_id;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'handover_id',handover.handover_id,'version',handover.version,'signed_copy',true,
    'file_entry_id',entry.id,'reference_id',reference_id,'success_message_key','ppe_handover_created');
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'ppe.signed_handover',fingerprint,p_workspace,
    'ppe',handover.handover_id,handover.version,NULL,result,NULL,result);
END $$;

CREATE FUNCTION private_isg.workspace_cleanup_candidates(p_workspace uuid,p_before timestamptz,p_limit integer)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE rows jsonb;
BEGIN
  IF p_workspace IS NULL OR p_before IS NULL OR p_limit NOT BETWEEN 1 AND 500 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('asset_id',a.id,'source_kind',a.source_kind,
    'byte_size',a.byte_size,'created_at',a.created_at) ORDER BY a.created_at,a.id),'[]') INTO rows
  FROM (SELECT * FROM private_isg.workspace_file_assets a WHERE a.workspace_id=p_workspace
    AND a.source_kind IN ('generated','derivative') AND a.lifecycle='active' AND a.created_at<p_before
    AND private_isg.workspace_asset_reference_count(p_workspace,a.id)=0
    ORDER BY a.created_at,a.id LIMIT p_limit) a;
  RETURN jsonb_build_object('workspace_id',p_workspace,'rows',rows,'source_uploads_excluded',true);
END $$;

CREATE FUNCTION public.isg_workspace_dashboard_v1(p_workspace uuid,p_company uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_dashboard(p_workspace,p_company) $$;
CREATE FUNCTION public.isg_workspace_search_v1(p_workspace uuid,p_company uuid,p_query text,p_after_kind text DEFAULT NULL,
  p_after_id uuid DEFAULT NULL,p_limit integer DEFAULT 30) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_search(p_workspace,p_company,p_query,p_after_kind,p_after_id,p_limit) $$;
CREATE FUNCTION public.isg_workspace_change_read_v1(p_workspace uuid,p_company uuid DEFAULT NULL,p_after bigint DEFAULT 0,
  p_limit integer DEFAULT 100) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_change_read(p_workspace,p_company,p_after,p_limit) $$;
CREATE FUNCTION public.isg_workspace_ppe_signed_handover_v1(p_mutation uuid,p_workspace uuid,p_company uuid,
  p_employee uuid,p_item text,p_quantity numeric,p_unit text,p_handed_on date,p_external_ref text,p_file_entry uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_ppe_signed_handover(p_mutation,p_workspace,
  p_company,p_employee,p_item,p_quantity,p_unit,p_handed_on,p_external_ref,p_file_entry) $$;

REVOKE ALL ON FUNCTION private_isg.workspace_event_company(jsonb),private_isg.workspace_project_outbox(),
  private_isg.workspace_dashboard(uuid,uuid),private_isg.workspace_search(uuid,uuid,text,text,uuid,integer),
  private_isg.workspace_change_read(uuid,uuid,bigint,integer),
  private_isg.workspace_notification_parent_exists(uuid,uuid,text,uuid),
  private_isg.workspace_notification_enqueue(uuid,uuid,uuid,text,text,uuid,text,timestamptz,text),
  private_isg.workspace_notification_claim(integer,timestamptz,integer),
  private_isg.workspace_notification_complete(uuid,uuid,boolean,text,timestamptz),
  private_isg.workspace_ppe_signed_handover(uuid,uuid,uuid,uuid,text,numeric,text,date,text,uuid),
  private_isg.workspace_cleanup_candidates(uuid,timestamptz,integer),
  public.isg_workspace_dashboard_v1(uuid,uuid),public.isg_workspace_search_v1(uuid,uuid,text,text,uuid,integer),
  public.isg_workspace_change_read_v1(uuid,uuid,bigint,integer),
  public.isg_workspace_ppe_signed_handover_v1(uuid,uuid,uuid,uuid,text,numeric,text,date,text,uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_dashboard(uuid,uuid),
  private_isg.workspace_search(uuid,uuid,text,text,uuid,integer),private_isg.workspace_change_read(uuid,uuid,bigint,integer),
  private_isg.workspace_ppe_signed_handover(uuid,uuid,uuid,uuid,text,numeric,text,date,text,uuid),
  public.isg_workspace_dashboard_v1(uuid,uuid),public.isg_workspace_search_v1(uuid,uuid,text,text,uuid,integer),
  public.isg_workspace_change_read_v1(uuid,uuid,bigint,integer),
  public.isg_workspace_ppe_signed_handover_v1(uuid,uuid,uuid,uuid,text,numeric,text,date,text,uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION private_isg.workspace_notification_enqueue(uuid,uuid,uuid,text,text,uuid,text,timestamptz,text),
  private_isg.workspace_notification_claim(integer,timestamptz,integer),
  private_isg.workspace_notification_complete(uuid,uuid,boolean,text,timestamptz),
  private_isg.workspace_cleanup_candidates(uuid,timestamptz,integer) TO service_role;
NOTIFY pgrst,'reload schema';
