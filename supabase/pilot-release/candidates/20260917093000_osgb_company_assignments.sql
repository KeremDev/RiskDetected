-- Workspace companies, expert profiles and assignment history. NOT DEPLOYED.
-- `public.companies.user_id` remains the legacy personal owner; OSGB ownership is
-- represented only by workspace membership and this separate aggregate.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='20s';

INSERT INTO private_isg.workspace_rollout(feature) VALUES('workspace_companies'),('workspace_assignments');

CREATE TABLE private_isg.workspace_companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES private_isg.workspaces(id) ON DELETE RESTRICT,
  legacy_company_id uuid UNIQUE,
  name text NOT NULL CHECK(octet_length(name) BETWEEN 1 AND 200),
  hazard_class text NOT NULL CHECK(hazard_class IN ('low','medium','high')),
  logo_path text,
  status text NOT NULL DEFAULT 'active' CHECK(status IN ('active','archived')),
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  created_by_user_id uuid NOT NULL,
  updated_by_user_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  archived_at timestamptz,
  UNIQUE(workspace_id,id),
  CHECK((status='archived')=(archived_at IS NOT NULL))
);
-- Legacy clients allow same-name companies; identity is the company UUID.
CREATE INDEX workspace_company_active_name_idx
  ON private_isg.workspace_companies(workspace_id,lower(name)) WHERE status='active';
CREATE INDEX workspace_company_list_idx
  ON private_isg.workspace_companies(workspace_id,status,created_at,id);

CREATE TABLE private_isg.expert_profiles (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE RESTRICT,
  display_name text NOT NULL CHECK(octet_length(display_name) BETWEEN 1 AND 160),
  registration_number text,
  phone text,
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE private_isg.workspace_expert_profiles (
  workspace_id uuid NOT NULL,
  membership_id uuid NOT NULL,
  title text,
  internal_note text,
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(workspace_id,membership_id),
  FOREIGN KEY(workspace_id,membership_id)
    REFERENCES private_isg.workspace_memberships(workspace_id,id) ON DELETE RESTRICT,
  CHECK(title IS NULL OR octet_length(title)<=160),
  CHECK(internal_note IS NULL OR octet_length(internal_note)<=4000)
);

CREATE TABLE private_isg.company_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  company_id uuid NOT NULL,
  membership_id uuid NOT NULL,
  assignment_role text NOT NULL CHECK(assignment_role IN ('primary','support')),
  starts_at timestamptz NOT NULL,
  ends_at timestamptz,
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  created_by_user_id uuid NOT NULL,
  ended_by_user_id uuid,
  reason text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY(workspace_id,company_id)
    REFERENCES private_isg.workspace_companies(workspace_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(workspace_id,membership_id)
    REFERENCES private_isg.workspace_memberships(workspace_id,id) ON DELETE RESTRICT,
  CHECK(ends_at IS NULL OR ends_at>starts_at OR (ends_at=starts_at AND ended_by_user_id IS NOT NULL AND reason IS NOT NULL)),
  CHECK(reason IS NULL OR octet_length(reason) BETWEEN 1 AND 500)
);
CREATE UNIQUE INDEX company_assignment_active_primary_unique
  ON private_isg.company_assignments(workspace_id,company_id)
  WHERE assignment_role='primary' AND ends_at IS NULL;
CREATE INDEX company_assignment_member_timeline
  ON private_isg.company_assignments(workspace_id,membership_id,starts_at,id);
CREATE INDEX company_assignment_company_timeline
  ON private_isg.company_assignments(workspace_id,company_id,starts_at,id);

CREATE TABLE private_isg.company_assignment_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  workspace_id uuid NOT NULL,
  assignment_id uuid NOT NULL REFERENCES private_isg.company_assignments(id) ON DELETE RESTRICT,
  event_type text NOT NULL CHECK(event_type IN ('created','ended','corrected')),
  actor_user_id uuid NOT NULL,
  before_state jsonb,
  after_state jsonb NOT NULL,
  reason text,
  correlation_id uuid NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK(reason IS NULL OR octet_length(reason) BETWEEN 1 AND 500)
);
CREATE INDEX company_assignment_event_timeline
  ON private_isg.company_assignment_events(workspace_id,assignment_id,occurred_at,id);

ALTER TABLE private_isg.workspace_companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.expert_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_expert_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.company_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.company_assignment_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.workspace_companies,private_isg.expert_profiles,
  private_isg.workspace_expert_profiles,private_isg.company_assignments,
  private_isg.company_assignment_events FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON SEQUENCE private_isg.company_assignment_events_id_seq
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.company_assignment_json(p_row private_isg.company_assignments) RETURNS jsonb
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT jsonb_build_object('schema_version',1,'assignment_id',p_row.id,'workspace_id',p_row.workspace_id,
    'company_id',p_row.company_id,'membership_id',p_row.membership_id,
    'assignment_role',p_row.assignment_role,'starts_at',p_row.starts_at,'ends_at',p_row.ends_at,
    'version',p_row.version)
$$;

CREATE FUNCTION private_isg.company_assignment_invariant() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE member private_isg.workspace_memberships;
BEGIN
  IF TG_OP='UPDATE' AND ROW(NEW.workspace_id,NEW.company_id,NEW.membership_id,NEW.assignment_role,NEW.starts_at)
    IS DISTINCT FROM ROW(OLD.workspace_id,OLD.company_id,OLD.membership_id,OLD.assignment_role,OLD.starts_at) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IMMUTABLE_SCOPE';
  END IF;
  -- Serialize the whole company's schedule, including different primary experts.
  PERFORM pg_advisory_xact_lock(hashtextextended(NEW.workspace_id::text||':'||NEW.company_id::text,0));
  SELECT * INTO member FROM private_isg.workspace_memberships
    WHERE workspace_id=NEW.workspace_id AND id=NEW.membership_id FOR SHARE;
  -- Revoking a member must not prevent a manager from closing their old work.
  -- Only shorten/close an existing interval; never create or extend access.
  IF member.id IS NULL OR ((member.status<>'active' OR NOT member.is_practicing_expert) AND NOT (
    TG_OP='UPDATE' AND NEW.ends_at IS NOT NULL AND NEW.ended_by_user_id IS NOT NULL
    AND (OLD.ends_at IS NULL OR NEW.ends_at<=OLD.ends_at)
    AND NEW.ends_at<=greatest(NEW.starts_at,clock_timestamp()))) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PRACTICING_MEMBERSHIP_REQUIRED';
  END IF;
  IF EXISTS(SELECT 1 FROM private_isg.company_assignments a
    WHERE a.workspace_id=NEW.workspace_id AND a.company_id=NEW.company_id
      AND (a.membership_id=NEW.membership_id OR
        (a.assignment_role='primary' AND NEW.assignment_role='primary')) AND a.id<>NEW.id
      AND tstzrange(a.starts_at,a.ends_at,'[)') && tstzrange(NEW.starts_at,NEW.ends_at,'[)')) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSIGNMENT_OVERLAP';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER company_assignment_invariant_before
BEFORE INSERT OR UPDATE ON private_isg.company_assignments
FOR EACH ROW EXECUTE FUNCTION private_isg.company_assignment_invariant();

CREATE FUNCTION private_isg.workspace_require_company(p_workspace uuid,p_company uuid,p_write boolean)
RETURNS private_isg.workspace_memberships
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE member private_isg.workspace_memberships; workspace private_isg.workspaces;
BEGIN
  member:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin','expert'],p_write);
  SELECT * INTO workspace FROM private_isg.workspaces WHERE id=p_workspace;
  PERFORM 1 FROM private_isg.workspace_companies c
    WHERE c.workspace_id=p_workspace AND c.id=p_company AND (NOT p_write OR c.status='active') FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF workspace.kind='osgb' AND member.role='expert' AND NOT EXISTS(
    SELECT 1 FROM private_isg.company_assignments a WHERE a.workspace_id=p_workspace
      AND a.company_id=p_company AND a.membership_id=member.id
      AND a.starts_at<=clock_timestamp() AND (a.ends_at IS NULL OR a.ends_at>clock_timestamp())) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSIGNMENT_REQUIRED';
  END IF;
  RETURN member;
END $$;

CREATE FUNCTION private_isg.workspace_company_create(p_mutation uuid,p_workspace uuid,p_name text,p_hazard text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); manager private_isg.workspace_memberships;
  clean_name text; fingerprint bytea; replay jsonb; company private_isg.workspace_companies; result jsonb;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_companies',true);
  manager:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],true);
  clean_name:=private_isg.workspace_text(p_name,200);
  IF p_hazard NOT IN ('low','medium','high') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,clean_name,p_hazard)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'company.create',fingerprint);
  IF replay IS NOT NULL THEN
    PERFORM private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],true); RETURN replay;
  END IF;
  INSERT INTO private_isg.workspace_companies(workspace_id,name,hazard_class,created_by_user_id,updated_by_user_id)
    VALUES(p_workspace,clean_name,p_hazard,actor,actor) RETURNING * INTO company;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'company_id',company.id,
    'name',company.name,'hazard_class',company.hazard_class,'status',company.status,'version',company.version);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'company.create',fingerprint,p_workspace,
    'company',company.id,company.version,NULL,result,NULL,result);
END $$;

CREATE FUNCTION private_isg.workspace_company_list(p_workspace uuid,p_after uuid,p_limit integer)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); member private_isg.workspace_memberships; rows jsonb; next_id uuid;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_companies',false);
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  member:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin','expert'],false);
  WITH visible AS (
    SELECT c.* FROM private_isg.workspace_companies c
    WHERE c.workspace_id=p_workspace AND c.status='active' AND (p_after IS NULL OR c.id>p_after)
      AND (member.role IN ('owner','admin') OR EXISTS(SELECT 1 FROM private_isg.company_assignments a
        WHERE a.workspace_id=p_workspace AND a.company_id=c.id AND a.membership_id=member.id
          AND a.starts_at<=clock_timestamp() AND (a.ends_at IS NULL OR a.ends_at>clock_timestamp())))
    ORDER BY c.id LIMIT p_limit+1
  ), page AS (SELECT * FROM visible ORDER BY id LIMIT p_limit)
  SELECT coalesce(jsonb_agg(jsonb_build_object('company_id',id,'name',name,'hazard_class',hazard_class,
      'status',status,'version',version) ORDER BY id),'[]'::jsonb),
    CASE WHEN (SELECT count(*) FROM visible)>p_limit THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END
    INTO rows,next_id FROM page;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,'rows',rows,'next',next_id);
END $$;

CREATE FUNCTION private_isg.workspace_assignment_list(p_workspace uuid,p_company uuid,p_status text,
  p_after uuid,p_limit integer) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE manager private_isg.workspace_memberships; rows jsonb; next_id uuid;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_assignments',false);
  IF p_status IS NULL OR p_status NOT IN ('all','current','ended','future')
     OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR';
  END IF;
  manager:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],false);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,false);
  WITH visible AS (
    SELECT a.*,m.user_id,m.role AS membership_role,m.status AS membership_status
    FROM private_isg.company_assignments a
    JOIN private_isg.workspace_memberships m
      ON m.workspace_id=a.workspace_id AND m.id=a.membership_id
    WHERE a.workspace_id=p_workspace AND a.company_id=p_company
      AND (p_after IS NULL OR a.id>p_after)
      AND (p_status='all'
        OR (p_status='current' AND a.starts_at<=clock_timestamp()
          AND (a.ends_at IS NULL OR a.ends_at>clock_timestamp()))
        OR (p_status='ended' AND a.ends_at IS NOT NULL
          AND (a.ends_at<=clock_timestamp() OR a.ends_at=a.starts_at))
        OR (p_status='future' AND a.starts_at>clock_timestamp()
          AND (a.ends_at IS NULL OR a.ends_at>a.starts_at)))
    ORDER BY a.id LIMIT p_limit+1
  ), page AS (SELECT * FROM visible ORDER BY id LIMIT p_limit)
  SELECT coalesce(jsonb_agg(jsonb_build_object('assignment_id',page.id,
      'workspace_id',page.workspace_id,'company_id',page.company_id,
      'membership_id',page.membership_id,'assignment_role',page.assignment_role,
      'starts_at',page.starts_at,'ends_at',page.ends_at,'version',page.version,
      'user_id',page.user_id,'membership_role',page.membership_role,
      'membership_status',page.membership_status) ORDER BY page.id),'[]'::jsonb),
    CASE WHEN (SELECT count(*) FROM visible)>p_limit
      THEN (SELECT id FROM page ORDER BY id DESC LIMIT 1) END
    INTO rows,next_id FROM page;
  RETURN jsonb_build_object('schema_version',1,'workspace_id',p_workspace,
    'company_id',p_company,'rows',rows,'next',next_id);
END $$;

CREATE FUNCTION private_isg.workspace_assignment_mutate(p_mutation uuid,p_workspace uuid,p_company uuid,
  p_assignment uuid,p_membership uuid,p_expected bigint,p_action text,p_role text,
  p_starts_at timestamptz,p_ends_at timestamptz,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); manager private_isg.workspace_memberships;
  target private_isg.workspace_memberships; assignment private_isg.company_assignments;
  before_state jsonb; clean_reason text; fingerprint bytea; replay jsonb; result jsonb;
  effective_end timestamptz;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_assignments',true);
  manager:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],true);
  PERFORM private_isg.workspace_require_company(p_workspace,p_company,true);
  clean_reason:=private_isg.workspace_text(p_reason,500);
  IF p_action IS NULL OR p_action NOT IN ('create','end') OR p_expected IS NULL OR p_expected<0 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_company,p_assignment,p_membership,
    p_expected,p_action,p_role,p_starts_at,p_ends_at,clean_reason)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'assignment.'||p_action,fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  IF p_action='create' THEN
    IF p_assignment IS NOT NULL OR p_membership IS NULL OR p_expected<>0 OR
       p_role IS NULL OR p_role NOT IN ('primary','support') OR p_starts_at IS NULL OR NOT isfinite(p_starts_at) OR
       (p_ends_at IS NOT NULL AND NOT isfinite(p_ends_at)) OR
       p_starts_at>clock_timestamp()+interval '365 days' OR (p_ends_at IS NOT NULL AND p_ends_at<=p_starts_at) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    SELECT * INTO target FROM private_isg.workspace_memberships
      WHERE workspace_id=p_workspace AND id=p_membership FOR SHARE;
    IF target.id IS NULL OR target.status<>'active' OR NOT target.is_practicing_expert THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PRACTICING_MEMBERSHIP_REQUIRED'; END IF;
    INSERT INTO private_isg.company_assignments(workspace_id,company_id,membership_id,assignment_role,
      starts_at,ends_at,created_by_user_id,reason)
      VALUES(p_workspace,p_company,p_membership,p_role,p_starts_at,p_ends_at,actor,clean_reason)
      RETURNING * INTO assignment;
    before_state:=NULL;
  ELSE
    IF p_assignment IS NULL OR p_membership IS NOT NULL OR p_ends_at IS NULL OR NOT isfinite(p_ends_at) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    SELECT * INTO assignment FROM private_isg.company_assignments
      WHERE id=p_assignment AND workspace_id=p_workspace AND company_id=p_company FOR UPDATE;
    IF assignment.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
    IF assignment.version<>p_expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    -- Future cancellation is an empty interval; active finite periods may be
    -- shortened, but ending must never extend or reopen historical access.
    effective_end:=greatest(p_ends_at,assignment.starts_at);
    IF assignment.ended_by_user_id IS NOT NULL OR
       (assignment.ends_at IS NOT NULL AND
         (assignment.ends_at<=clock_timestamp() OR effective_end>=assignment.ends_at)) OR
       (assignment.starts_at<=clock_timestamp() AND effective_end<=assignment.starts_at) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ASSIGNMENT_CONFLICT'; END IF;
    before_state:=private_isg.company_assignment_json(assignment);
    UPDATE private_isg.company_assignments SET ends_at=effective_end,ended_by_user_id=actor,
      reason=clean_reason,version=version+1,updated_at=clock_timestamp()
      WHERE id=assignment.id RETURNING * INTO assignment;
  END IF;
  IF target.id IS NULL THEN
    SELECT * INTO target FROM private_isg.workspace_memberships
      WHERE workspace_id=p_workspace AND id=assignment.membership_id;
  END IF;
  IF target.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='INTEGRITY_ERROR';
  END IF;
  result:=private_isg.company_assignment_json(assignment)||jsonb_build_object(
    'user_id',target.user_id,'membership_role',target.role,'membership_status',target.status);
  INSERT INTO private_isg.company_assignment_events(workspace_id,assignment_id,event_type,actor_user_id,
    before_state,after_state,reason,correlation_id)
    VALUES(p_workspace,assignment.id,CASE p_action WHEN 'create' THEN 'created' ELSE 'ended' END,
      actor,before_state,result,clean_reason,p_mutation);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'assignment.'||p_action,fingerprint,p_workspace,
    'assignment',assignment.id,assignment.version,before_state,result,clean_reason,result);
END $$;

CREATE FUNCTION public.isg_workspace_company_create_v1(p_mutation uuid,p_workspace uuid,p_name text,p_hazard text) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_company_create(p_mutation,p_workspace,p_name,p_hazard) $$;
CREATE FUNCTION public.isg_workspace_company_list_v1(p_workspace uuid,p_after uuid,p_limit integer) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_company_list(p_workspace,p_after,p_limit) $$;
CREATE FUNCTION public.isg_workspace_assignment_list_v1(p_workspace uuid,p_company uuid,p_status text,
  p_after uuid,p_limit integer) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_assignment_list(
  p_workspace,p_company,p_status,p_after,p_limit) $$;
CREATE FUNCTION public.isg_workspace_assignment_mutate_v1(p_mutation uuid,p_workspace uuid,p_company uuid,
  p_assignment uuid,p_membership uuid,p_expected bigint,p_action text,p_role text,
  p_starts_at timestamptz,p_ends_at timestamptz,p_reason text) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_assignment_mutate(
  p_mutation,p_workspace,p_company,p_assignment,p_membership,p_expected,p_action,p_role,p_starts_at,p_ends_at,p_reason) $$;

REVOKE ALL ON FUNCTION private_isg.company_assignment_json(private_isg.company_assignments),
  private_isg.company_assignment_invariant(),private_isg.workspace_require_company(uuid,uuid,boolean),
  private_isg.workspace_company_create(uuid,uuid,text,text),private_isg.workspace_company_list(uuid,uuid,integer),
  private_isg.workspace_assignment_list(uuid,uuid,text,uuid,integer),
  private_isg.workspace_assignment_mutate(uuid,uuid,uuid,uuid,uuid,bigint,text,text,timestamptz,timestamptz,text),
  public.isg_workspace_company_create_v1(uuid,uuid,text,text),public.isg_workspace_company_list_v1(uuid,uuid,integer),
  public.isg_workspace_assignment_list_v1(uuid,uuid,text,uuid,integer),
  public.isg_workspace_assignment_mutate_v1(uuid,uuid,uuid,uuid,uuid,bigint,text,text,timestamptz,timestamptz,text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_company_create(uuid,uuid,text,text),
  private_isg.workspace_company_list(uuid,uuid,integer),
  private_isg.workspace_assignment_list(uuid,uuid,text,uuid,integer),
  private_isg.workspace_assignment_mutate(uuid,uuid,uuid,uuid,uuid,bigint,text,text,timestamptz,timestamptz,text),
  public.isg_workspace_company_create_v1(uuid,uuid,text,text),public.isg_workspace_company_list_v1(uuid,uuid,integer),
  public.isg_workspace_assignment_list_v1(uuid,uuid,text,uuid,integer),
  public.isg_workspace_assignment_mutate_v1(uuid,uuid,uuid,uuid,uuid,bigint,text,text,timestamptz,timestamptz,text)
  TO authenticated;
NOTIFY pgrst,'reload schema';
