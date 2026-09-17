-- Workspace and member-scoped OSGB metrics. NOT DEPLOYED.
-- A zero is returned only for a source this candidate owns and measures. Legacy
-- operational domains stay explicitly unavailable until their D-phase bridge is
-- proven against the deployed pilot schema.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='20s';

INSERT INTO private_isg.workspace_rollout(feature) VALUES('workspace_metrics');

CREATE FUNCTION private_isg.workspace_metrics_snapshot(p_workspace uuid,p_from timestamptz,p_to timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE member private_isg.workspace_memberships; manager boolean; company_ids uuid[];
  company_count bigint; unassigned_count bigint; active_experts bigint; reserved_seats bigint;
  ai_units bigint; current_bytes bigint; uploaded_bytes bigint; generated_bytes bigint; downloaded_bytes bigint;
  pending_handovers bigint; provider_pending bigint; provider_rejected bigint; wallet jsonb;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_metrics',false);
  member:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin','expert'],false);
  IF p_from IS NULL OR p_to IS NULL OR p_from>=p_to OR p_to-p_from>interval '366 days' OR
     p_to>clock_timestamp()+interval '1 day' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  manager:=member.role IN ('owner','admin');
  IF manager THEN
    SELECT coalesce(array_agg(id),'{}'::uuid[]) INTO company_ids
      FROM private_isg.workspace_companies WHERE workspace_id=p_workspace AND status='active';
    SELECT count(*) INTO unassigned_count FROM private_isg.workspace_companies c
      WHERE c.workspace_id=p_workspace AND c.status='active' AND NOT EXISTS(
        SELECT 1 FROM private_isg.company_assignments a WHERE a.workspace_id=p_workspace
          AND a.company_id=c.id AND a.starts_at<=clock_timestamp()
          AND (a.ends_at IS NULL OR a.ends_at>clock_timestamp()));
    SELECT count(*) INTO active_experts FROM private_isg.workspace_memberships
      WHERE workspace_id=p_workspace AND status='active' AND is_practicing_expert;
    SELECT count(*) INTO reserved_seats FROM private_isg.workspace_seat_reservations
      WHERE workspace_id=p_workspace AND status='reserved' AND expires_at>clock_timestamp();
    SELECT jsonb_build_object('posted_units',posted_units,'reserved_units',reserved_units,
      'debt_units',debt_units,'available_units',greatest(0,posted_units-reserved_units-debt_units),
      'version',version) INTO wallet FROM private_isg.workspace_wallets WHERE workspace_id=p_workspace;
  ELSE
    SELECT coalesce(array_agg(DISTINCT company_id),'{}'::uuid[]) INTO company_ids
      FROM private_isg.company_assignments WHERE workspace_id=p_workspace AND membership_id=member.id
        AND starts_at<=clock_timestamp() AND (ends_at IS NULL OR ends_at>clock_timestamp());
    unassigned_count:=NULL; active_experts:=NULL; reserved_seats:=NULL; wallet:=NULL;
  END IF;
  company_count:=cardinality(company_ids);
  SELECT coalesce(sum(charged_units),0) INTO ai_units FROM private_isg.workspace_usage_records
    WHERE workspace_id=p_workspace AND created_at>=p_from AND created_at<p_to
      AND (manager OR membership_id=member.id)
      AND (company_id IS NULL OR company_id=ANY(company_ids));
  SELECT coalesce(sum(byte_size),0) INTO current_bytes FROM private_isg.workspace_file_assets
    WHERE workspace_id=p_workspace AND lifecycle IN ('active','delete_requested')
      AND (manager OR uploaded_by_membership_id=member.id)
      AND (company_id IS NULL OR company_id=ANY(company_ids));
  SELECT coalesce(sum(byte_size) FILTER(WHERE source_kind='upload'),0),
    coalesce(sum(byte_size) FILTER(WHERE source_kind IN ('generated','derivative')),0)
    INTO uploaded_bytes,generated_bytes FROM private_isg.workspace_file_assets
    WHERE workspace_id=p_workspace AND finalized_at>=p_from AND finalized_at<p_to
      AND (manager OR uploaded_by_membership_id=member.id)
      AND (company_id IS NULL OR company_id=ANY(company_ids));
  SELECT coalesce(sum(d.delivered_bytes),0) INTO downloaded_bytes
    FROM private_isg.workspace_download_intents d
    JOIN private_isg.workspace_file_assets a ON a.id=d.asset_id AND a.workspace_id=d.workspace_id
    WHERE d.workspace_id=p_workspace AND d.status='delivered' AND d.delivered_at>=p_from AND d.delivered_at<p_to
      AND (manager OR d.membership_id=member.id)
      AND (a.company_id IS NULL OR a.company_id=ANY(company_ids));
  IF manager THEN
    SELECT count(*) INTO pending_handovers FROM private_isg.workspace_handovers
      WHERE workspace_id=p_workspace AND status IN ('draft','scheduled','in_progress','partially_completed');
    SELECT count(*) FILTER(WHERE state='received'),count(*) FILTER(WHERE state='rejected')
      INTO provider_pending,provider_rejected FROM private_isg.workspace_provider_inbox
      WHERE workspace_id=p_workspace;
  ELSE pending_handovers:=NULL; provider_pending:=NULL; provider_rejected:=NULL; END IF;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,
    'scope',CASE WHEN manager THEN 'workspace' ELSE 'member' END,
    'membership_id',member.id,'period',jsonb_build_object('from',p_from,'to',p_to,
      'timezone',(SELECT timezone FROM private_isg.workspaces WHERE id=p_workspace)),
    'measured_at',clock_timestamp(),'companies',jsonb_build_object('active',company_count,
      'unassigned',unassigned_count),'seats',jsonb_build_object('active_practicing',active_experts,
      'reserved',reserved_seats),'wallet',wallet,
    'ai',jsonb_build_object('charged_units',ai_units),
    'storage',jsonb_build_object('current_bytes',current_bytes,'uploaded_bytes',uploaded_bytes,
      'generated_bytes',generated_bytes,'delivered_download_bytes',downloaded_bytes),
    'handover',jsonb_build_object('pending',pending_handovers),
    'provider_health',jsonb_build_object('pending',provider_pending,'rejected',provider_rejected),
    'operational_domains',jsonb_build_object('measured',false,'status','unavailable'));
END $$;

CREATE FUNCTION private_isg.workspace_company_metrics(p_workspace uuid,p_company uuid,
  p_from timestamptz,p_to timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE member private_isg.workspace_memberships; current_bytes bigint; uploaded_bytes bigint;
  generated_bytes bigint; ai_units bigint; delivered_bytes bigint; active_assignments bigint;
  memory_events bigint;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_metrics',false);
  member:=private_isg.workspace_require_company(p_workspace,p_company,false);
  IF p_from IS NULL OR p_to IS NULL OR p_from>=p_to OR p_to-p_from>interval '366 days' OR
     p_to>clock_timestamp()+interval '1 day' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT coalesce(sum(byte_size),0) INTO current_bytes FROM private_isg.workspace_file_assets
    WHERE workspace_id=p_workspace AND company_id=p_company AND lifecycle IN ('active','delete_requested');
  SELECT coalesce(sum(byte_size) FILTER(WHERE source_kind='upload'),0),
    coalesce(sum(byte_size) FILTER(WHERE source_kind IN ('generated','derivative')),0)
    INTO uploaded_bytes,generated_bytes FROM private_isg.workspace_file_assets
    WHERE workspace_id=p_workspace AND company_id=p_company AND finalized_at>=p_from AND finalized_at<p_to;
  SELECT coalesce(sum(charged_units),0) INTO ai_units FROM private_isg.workspace_usage_records
    WHERE workspace_id=p_workspace AND company_id=p_company AND created_at>=p_from AND created_at<p_to;
  SELECT coalesce(sum(d.delivered_bytes),0) INTO delivered_bytes
    FROM private_isg.workspace_download_intents d JOIN private_isg.workspace_file_assets a ON a.id=d.asset_id
    WHERE d.workspace_id=p_workspace AND a.company_id=p_company AND d.status='delivered'
      AND d.delivered_at>=p_from AND d.delivered_at<p_to;
  SELECT count(*) INTO active_assignments FROM private_isg.company_assignments
    WHERE workspace_id=p_workspace AND company_id=p_company AND starts_at<=clock_timestamp()
      AND (ends_at IS NULL OR ends_at>clock_timestamp());
  SELECT count(*) INTO memory_events FROM private_isg.company_memory_events
    WHERE workspace_id=p_workspace AND company_id=p_company AND occurred_at>=p_from AND occurred_at<p_to;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',p_company,
    'period',jsonb_build_object('from',p_from,'to',p_to),'measured_at',clock_timestamp(),
    'assignments',jsonb_build_object('active',active_assignments),
    'ai',jsonb_build_object('charged_units',ai_units),
    'storage',jsonb_build_object('current_bytes',current_bytes,'uploaded_bytes',uploaded_bytes,
      'generated_bytes',generated_bytes,'delivered_download_bytes',delivered_bytes),
    'memory',jsonb_build_object('events',memory_events),
    'operational_domains',jsonb_build_object('measured',false,'status','unavailable'));
END $$;

CREATE FUNCTION private_isg.workspace_member_usage(p_workspace uuid,p_from timestamptz,p_to timestamptz,p_limit integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE manager private_isg.workspace_memberships; rows jsonb;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_metrics',false);
  manager:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],false);
  IF p_from IS NULL OR p_to IS NULL OR p_from>=p_to OR p_to-p_from>interval '366 days' OR
     p_limit NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT coalesce(jsonb_agg(row_value ORDER BY membership_id),'[]'::jsonb) INTO rows FROM (
    SELECT m.id membership_id,jsonb_build_object('membership_id',m.id,'role',m.role,'status',m.status,
      'is_practicing_expert',m.is_practicing_expert,
      'active_company_count',(SELECT count(*) FROM private_isg.company_assignments a
        WHERE a.workspace_id=p_workspace AND a.membership_id=m.id AND a.starts_at<=clock_timestamp()
          AND (a.ends_at IS NULL OR a.ends_at>clock_timestamp())),
      'ai_charged_units',(SELECT coalesce(sum(u.charged_units),0) FROM private_isg.workspace_usage_records u
        WHERE u.workspace_id=p_workspace AND u.membership_id=m.id AND u.created_at>=p_from AND u.created_at<p_to),
      'uploaded_bytes',(SELECT coalesce(sum(a.byte_size),0) FROM private_isg.workspace_file_assets a
        WHERE a.workspace_id=p_workspace AND a.uploaded_by_membership_id=m.id AND a.source_kind='upload'
          AND a.finalized_at>=p_from AND a.finalized_at<p_to)) row_value
    FROM private_isg.workspace_memberships m WHERE m.workspace_id=p_workspace
    ORDER BY m.id LIMIT p_limit) q;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'period',
    jsonb_build_object('from',p_from,'to',p_to),'rows',rows,'measured_at',clock_timestamp());
END $$;

CREATE FUNCTION public.isg_workspace_metrics_v1(p_workspace uuid,p_from timestamptz,p_to timestamptz)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_metrics_snapshot(p_workspace,p_from,p_to) $$;
CREATE FUNCTION public.isg_workspace_company_metrics_v1(p_workspace uuid,p_company uuid,p_from timestamptz,p_to timestamptz)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_company_metrics(p_workspace,p_company,p_from,p_to) $$;
CREATE FUNCTION public.isg_workspace_member_usage_v1(p_workspace uuid,p_from timestamptz,p_to timestamptz,p_limit integer)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$
  SELECT private_isg.workspace_member_usage(p_workspace,p_from,p_to,p_limit) $$;

REVOKE ALL ON FUNCTION private_isg.workspace_metrics_snapshot(uuid,timestamptz,timestamptz),
  private_isg.workspace_company_metrics(uuid,uuid,timestamptz,timestamptz),
  private_isg.workspace_member_usage(uuid,timestamptz,timestamptz,integer),
  public.isg_workspace_metrics_v1(uuid,timestamptz,timestamptz),
  public.isg_workspace_company_metrics_v1(uuid,uuid,timestamptz,timestamptz),
  public.isg_workspace_member_usage_v1(uuid,timestamptz,timestamptz,integer)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_metrics_snapshot(uuid,timestamptz,timestamptz),
  private_isg.workspace_company_metrics(uuid,uuid,timestamptz,timestamptz),
  private_isg.workspace_member_usage(uuid,timestamptz,timestamptz,integer),
  public.isg_workspace_metrics_v1(uuid,timestamptz,timestamptz),
  public.isg_workspace_company_metrics_v1(uuid,uuid,timestamptz,timestamptz),
  public.isg_workspace_member_usage_v1(uuid,timestamptz,timestamptz,integer)
  TO authenticated;
NOTIFY pgrst,'reload schema';
