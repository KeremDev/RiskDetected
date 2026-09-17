-- Remaining workspace/company management operations. NOT DEPLOYED.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='20s';

CREATE FUNCTION private_isg.workspace_settings_update(p_mutation uuid,p_workspace uuid,p_expected bigint,
  p_name text,p_timezone text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); manager private_isg.workspace_memberships;
  workspace private_isg.workspaces; clean_name text; clean_timezone text; before_state jsonb;
  fingerprint bytea; replay jsonb; result jsonb;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_mutations',true);
  manager:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],true);
  clean_name:=private_isg.workspace_text(p_name,200); clean_timezone:=private_isg.workspace_timezone(p_timezone);
  IF p_mutation IS NULL OR p_expected IS NULL OR p_expected<0 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_expected,clean_name,clean_timezone)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'workspace.settings',fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  SELECT * INTO workspace FROM private_isg.workspaces
    WHERE id=p_workspace AND kind='osgb' AND status<>'archived' FOR UPDATE;
  IF workspace.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF workspace.version<>p_expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  before_state:=jsonb_build_object('name',workspace.name,'timezone',workspace.timezone,'version',workspace.version);
  UPDATE private_isg.workspaces SET name=clean_name,timezone=clean_timezone,version=version+1,
    updated_at=clock_timestamp() WHERE id=workspace.id RETURNING * INTO workspace;
  result:=jsonb_build_object('schema_version',1,'workspace_id',workspace.id,'name',workspace.name,
    'timezone',workspace.timezone,'status',workspace.status,'version',workspace.version);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'workspace.settings',fingerprint,p_workspace,
    'workspace',workspace.id,workspace.version,before_state,result,NULL,result);
END $$;

CREATE FUNCTION private_isg.workspace_archive(p_mutation uuid,p_workspace uuid,p_expected bigint,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); owner private_isg.workspace_memberships;
  workspace private_isg.workspaces; clean_reason text; fingerprint bytea; replay jsonb; result jsonb;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_mutations',true);
  owner:=private_isg.workspace_require_member(p_workspace,ARRAY['owner'],true);
  clean_reason:=private_isg.workspace_text(p_reason,500);
  IF p_mutation IS NULL OR p_expected IS NULL OR p_expected<0 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_expected,clean_reason)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'workspace.archive',fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  SELECT * INTO workspace FROM private_isg.workspaces WHERE id=p_workspace AND kind='osgb' FOR UPDATE;
  IF workspace.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF workspace.version<>p_expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  IF workspace.status='archived' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='WORKSPACE_INACTIVE'; END IF;
  UPDATE private_isg.workspaces SET status='archived',archived_at=clock_timestamp(),version=version+1,
    updated_at=clock_timestamp() WHERE id=workspace.id RETURNING * INTO workspace;
  result:=jsonb_build_object('schema_version',1,'workspace_id',workspace.id,'status',workspace.status,
    'version',workspace.version,'archived_at',workspace.archived_at,'data_deleted',false);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'workspace.archive',fingerprint,p_workspace,
    'workspace',workspace.id,workspace.version,jsonb_build_object('status','active'),result,clean_reason,result);
END $$;

CREATE FUNCTION private_isg.workspace_invitation_resend(p_mutation uuid,p_workspace uuid,p_invitation uuid,
  p_expected bigint,p_expires_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); manager private_isg.workspace_memberships;
  invitation private_isg.workspace_invitations; token text; fingerprint bytea; replay jsonb; result jsonb;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_invitations',true);
  manager:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],false);
  IF p_mutation IS NULL OR p_expected IS NULL OR p_expected<0 OR p_expires_at IS NULL OR
     p_expires_at<=clock_timestamp()+interval '5 minutes' OR p_expires_at>clock_timestamp()+interval '30 days' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_invitation,p_expected,p_expires_at)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'invitation.resend',fingerprint);
  IF replay IS NOT NULL THEN RETURN replay||jsonb_build_object('token_returned',false); END IF;
  SELECT * INTO invitation FROM private_isg.workspace_invitations
    WHERE id=p_invitation AND workspace_id=p_workspace FOR UPDATE;
  IF invitation.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF invitation.version<>p_expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  IF invitation.status<>'pending' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='INVITATION_INVALID'; END IF;
  token:=private_isg.workspace_random_token();
  UPDATE private_isg.workspace_invitations SET token_hash=sha256(convert_to(token,'UTF8')),
    expires_at=p_expires_at,version=version+1,updated_at=clock_timestamp()
    WHERE id=invitation.id RETURNING * INTO invitation;
  UPDATE private_isg.workspace_seat_reservations SET expires_at=p_expires_at,updated_at=clock_timestamp()
    WHERE workspace_id=p_workspace AND reference_kind='invitation' AND reference_id=invitation.id
      AND status='reserved';
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'invitation_id',invitation.id,
    'status',invitation.status,'role',invitation.role,'expires_at',invitation.expires_at,
    'version',invitation.version,'token_returned',false);
  result:=private_isg.workspace_record_effect(actor,p_mutation,'invitation.resend',fingerprint,p_workspace,
    'invitation',invitation.id,invitation.version,NULL,result,NULL,result);
  RETURN result||jsonb_build_object('invitation_token',token,'token_returned',true);
END $$;

CREATE FUNCTION private_isg.workspace_member_list(p_workspace uuid,p_status text,p_after uuid,p_limit integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE manager private_isg.workspace_memberships; rows jsonb; next_id uuid;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_context',false);
  manager:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],false);
  IF p_status NOT IN ('all','active','suspended','ended') OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  WITH visible AS (
    SELECT m.* FROM private_isg.workspace_memberships m WHERE m.workspace_id=p_workspace
      AND (p_status='all' OR m.status=p_status) AND (p_after IS NULL OR m.id>p_after)
      ORDER BY m.id LIMIT p_limit+1
  ), page AS (SELECT * FROM visible ORDER BY id LIMIT p_limit)
  SELECT coalesce(jsonb_agg(jsonb_build_object('membership_id',id,'user_id',user_id,'role',role,
      'status',status,'is_practicing_expert',is_practicing_expert,
      'permission_revision',permission_revision,'version',version,
      'active_company_count',(SELECT count(*) FROM private_isg.company_assignments a
        WHERE a.workspace_id=p_workspace AND a.membership_id=page.id AND a.starts_at<=clock_timestamp()
          AND (a.ends_at IS NULL OR a.ends_at>clock_timestamp()))) ORDER BY id),'[]'::jsonb),
    CASE WHEN (SELECT count(*) FROM visible)>p_limit THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END
    INTO rows,next_id FROM page;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'rows',rows,'next',next_id);
END $$;

CREATE FUNCTION private_isg.workspace_invitation_list(p_workspace uuid,p_status text,p_after uuid,p_limit integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE manager private_isg.workspace_memberships; rows jsonb; next_id uuid;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_invitations',false);
  manager:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],false);
  IF p_status NOT IN ('all','pending','accepted','revoked','expired') OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  WITH visible AS (
    SELECT i.* FROM private_isg.workspace_invitations i WHERE i.workspace_id=p_workspace
      AND (p_status='all' OR i.status=p_status) AND (p_after IS NULL OR i.id>p_after)
      ORDER BY i.id LIMIT p_limit+1
  ), page AS (SELECT * FROM visible ORDER BY id LIMIT p_limit)
  SELECT coalesce(jsonb_agg(jsonb_build_object('invitation_id',id,'email',email_normalized,'role',role,
      'status',status,'expires_at',expires_at,'version',version) ORDER BY id),'[]'::jsonb),
    CASE WHEN (SELECT count(*) FROM visible)>p_limit THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END
    INTO rows,next_id FROM page;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'rows',rows,'next',next_id);
END $$;

CREATE FUNCTION private_isg.workspace_company_update(p_mutation uuid,p_workspace uuid,p_company uuid,
  p_expected bigint,p_name text,p_hazard text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); manager private_isg.workspace_memberships;
  company private_isg.workspace_companies; clean_name text; fingerprint bytea; replay jsonb;
  before_state jsonb; result jsonb;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_companies',true);
  manager:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],true);
  clean_name:=private_isg.workspace_text(p_name,200);
  IF p_mutation IS NULL OR p_expected IS NULL OR p_expected<0 OR p_hazard NOT IN ('low','medium','high') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_company,p_expected,clean_name,p_hazard)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'company.update',fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  SELECT * INTO company FROM private_isg.workspace_companies
    WHERE id=p_company AND workspace_id=p_workspace AND status='active' FOR UPDATE;
  IF company.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF company.version<>p_expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  before_state:=jsonb_build_object('name',company.name,'hazard_class',company.hazard_class,'version',company.version);
  UPDATE private_isg.workspace_companies SET name=clean_name,hazard_class=p_hazard,
    updated_by_user_id=actor,version=version+1,updated_at=clock_timestamp()
    WHERE id=company.id RETURNING * INTO company;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',company.id,
    'name',company.name,'hazard_class',company.hazard_class,'status',company.status,'version',company.version);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'company.update',fingerprint,p_workspace,
    'company',company.id,company.version,before_state,result,NULL,result);
END $$;

CREATE FUNCTION private_isg.workspace_company_archive(p_mutation uuid,p_workspace uuid,p_company uuid,
  p_expected bigint,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); manager private_isg.workspace_memberships;
  company private_isg.workspace_companies; assignment private_isg.company_assignments;
  clean_reason text; fingerprint bytea; replay jsonb; before_state jsonb; result jsonb; ended integer:=0;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_companies',true);
  manager:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],true);
  clean_reason:=private_isg.workspace_text(p_reason,500);
  IF p_mutation IS NULL OR p_expected IS NULL OR p_expected<0 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_company,p_expected,clean_reason)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'company.archive',fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  SELECT * INTO company FROM private_isg.workspace_companies
    WHERE id=p_company AND workspace_id=p_workspace AND status='active' FOR UPDATE;
  IF company.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF company.version<>p_expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  before_state:=jsonb_build_object('status',company.status,'version',company.version);
  FOR assignment IN SELECT * FROM private_isg.company_assignments a
    WHERE a.workspace_id=p_workspace AND a.company_id=p_company AND (a.ends_at IS NULL OR a.ends_at>clock_timestamp()) AND a.ends_at IS DISTINCT FROM a.starts_at FOR UPDATE LOOP
    UPDATE private_isg.company_assignments SET ends_at=greatest(starts_at,clock_timestamp()),ended_by_user_id=actor,
      reason=clean_reason,version=version+1,updated_at=clock_timestamp()
      WHERE id=assignment.id RETURNING * INTO assignment;
    INSERT INTO private_isg.company_assignment_events(workspace_id,assignment_id,event_type,actor_user_id,
      before_state,after_state,reason,correlation_id) VALUES(p_workspace,assignment.id,'ended',actor,NULL,
      private_isg.company_assignment_json(assignment),clean_reason,p_mutation);
    ended:=ended+1;
  END LOOP;
  UPDATE private_isg.workspace_companies SET status='archived',archived_at=clock_timestamp(),
    updated_by_user_id=actor,version=version+1,updated_at=clock_timestamp()
    WHERE id=company.id RETURNING * INTO company;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',company.id,
    'status',company.status,'version',company.version,'archived_at',company.archived_at,
    'ended_assignments',ended,'data_deleted',false);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'company.archive',fingerprint,p_workspace,
    'company',company.id,company.version,before_state,result,clean_reason,result);
END $$;

CREATE FUNCTION public.isg_workspace_settings_update_v1(p_mutation uuid,p_workspace uuid,p_expected bigint,p_name text,p_timezone text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_settings_update(p_mutation,p_workspace,p_expected,p_name,p_timezone) $$;
CREATE FUNCTION public.isg_workspace_archive_v1(p_mutation uuid,p_workspace uuid,p_expected bigint,p_reason text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_archive(p_mutation,p_workspace,p_expected,p_reason) $$;
CREATE FUNCTION public.isg_workspace_invitation_resend_v1(p_mutation uuid,p_workspace uuid,p_invitation uuid,p_expected bigint,p_expires_at timestamptz)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_invitation_resend(p_mutation,p_workspace,p_invitation,p_expected,p_expires_at) $$;
CREATE FUNCTION public.isg_workspace_member_list_v1(p_workspace uuid,p_status text,p_after uuid,p_limit integer)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_member_list(p_workspace,p_status,p_after,p_limit) $$;
CREATE FUNCTION public.isg_workspace_invitation_list_v1(p_workspace uuid,p_status text,p_after uuid,p_limit integer)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_invitation_list(p_workspace,p_status,p_after,p_limit) $$;
CREATE FUNCTION public.isg_workspace_company_update_v1(p_mutation uuid,p_workspace uuid,p_company uuid,p_expected bigint,p_name text,p_hazard text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_company_update(p_mutation,p_workspace,p_company,p_expected,p_name,p_hazard) $$;
CREATE FUNCTION public.isg_workspace_company_archive_v1(p_mutation uuid,p_workspace uuid,p_company uuid,p_expected bigint,p_reason text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_company_archive(p_mutation,p_workspace,p_company,p_expected,p_reason) $$;

REVOKE ALL ON FUNCTION private_isg.workspace_settings_update(uuid,uuid,bigint,text,text),
  private_isg.workspace_archive(uuid,uuid,bigint,text),
  private_isg.workspace_invitation_resend(uuid,uuid,uuid,bigint,timestamptz),
  private_isg.workspace_member_list(uuid,text,uuid,integer),private_isg.workspace_invitation_list(uuid,text,uuid,integer),
  private_isg.workspace_company_update(uuid,uuid,uuid,bigint,text,text),
  private_isg.workspace_company_archive(uuid,uuid,uuid,bigint,text),
  public.isg_workspace_settings_update_v1(uuid,uuid,bigint,text,text),
  public.isg_workspace_archive_v1(uuid,uuid,bigint,text),
  public.isg_workspace_invitation_resend_v1(uuid,uuid,uuid,bigint,timestamptz),
  public.isg_workspace_member_list_v1(uuid,text,uuid,integer),public.isg_workspace_invitation_list_v1(uuid,text,uuid,integer),
  public.isg_workspace_company_update_v1(uuid,uuid,uuid,bigint,text,text),
  public.isg_workspace_company_archive_v1(uuid,uuid,uuid,bigint,text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_settings_update(uuid,uuid,bigint,text,text),
  private_isg.workspace_archive(uuid,uuid,bigint,text),
  private_isg.workspace_invitation_resend(uuid,uuid,uuid,bigint,timestamptz),
  private_isg.workspace_member_list(uuid,text,uuid,integer),private_isg.workspace_invitation_list(uuid,text,uuid,integer),
  private_isg.workspace_company_update(uuid,uuid,uuid,bigint,text,text),
  private_isg.workspace_company_archive(uuid,uuid,uuid,bigint,text),
  public.isg_workspace_settings_update_v1(uuid,uuid,bigint,text,text),
  public.isg_workspace_archive_v1(uuid,uuid,bigint,text),
  public.isg_workspace_invitation_resend_v1(uuid,uuid,uuid,bigint,timestamptz),
  public.isg_workspace_member_list_v1(uuid,text,uuid,integer),public.isg_workspace_invitation_list_v1(uuid,text,uuid,integer),
  public.isg_workspace_company_update_v1(uuid,uuid,uuid,bigint,text,text),
  public.isg_workspace_company_archive_v1(uuid,uuid,uuid,bigint,text)
  TO authenticated;
NOTIFY pgrst,'reload schema';
