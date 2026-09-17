-- OSGB workspace foundation candidate. NOT DEPLOYED.
-- The deployment transport owns the transaction. Rehearse from the verified
-- pilot ledger; never apply this candidate with a general root `db push`.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='20s';

CREATE TABLE private_isg.workspace_rollout (
  feature text PRIMARY KEY CHECK(feature IN ('workspace_context','workspace_mutations','workspace_invitations',
    'workspace_companies','workspace_assignments','workspace_seats','workspace_wallet',
    'workspace_storage','workspace_ai','workspace_handover','workspace_admin','workspace_metrics',
    'workspace_billing')),
  read_enabled boolean NOT NULL DEFAULT false,
  write_enabled boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK(NOT write_enabled OR read_enabled)
);
INSERT INTO private_isg.workspace_rollout(feature) VALUES
  ('workspace_context'),('workspace_mutations'),('workspace_invitations');

CREATE TABLE private_isg.workspaces (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind text NOT NULL CHECK(kind IN ('personal','osgb')),
  name text NOT NULL CHECK(octet_length(name) BETWEEN 1 AND 200),
  status text NOT NULL CHECK(status IN ('active','pending_purchase','admin_trial','admin_sponsored','suspended','archived')),
  timezone text NOT NULL,
  created_by_user_id uuid NOT NULL,
  personal_owner_user_id uuid,
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  archived_at timestamptz,
  UNIQUE(id,kind),
  CHECK((kind='personal')=(personal_owner_user_id IS NOT NULL)),
  CHECK((status='archived')=(archived_at IS NOT NULL))
);
CREATE UNIQUE INDEX workspace_personal_owner_unique
  ON private_isg.workspaces(personal_owner_user_id) WHERE kind='personal';
CREATE INDEX workspace_status_kind_idx ON private_isg.workspaces(status,kind,id);

CREATE TABLE private_isg.workspace_memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES private_isg.workspaces(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text NOT NULL CHECK(role IN ('owner','admin','expert')),
  status text NOT NULL CHECK(status IN ('active','suspended','ended')),
  is_practicing_expert boolean NOT NULL DEFAULT false,
  permission_revision bigint NOT NULL DEFAULT 0 CHECK(permission_revision BETWEEN 0 AND 9007199254740991),
  joined_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  suspended_at timestamptz,
  ended_at timestamptz,
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(workspace_id,user_id),
  UNIQUE(workspace_id,id),
  CHECK((status='suspended')=(suspended_at IS NOT NULL)),
  CHECK((status='ended')=(ended_at IS NOT NULL)),
  CHECK(status='active' OR NOT is_practicing_expert)
);
CREATE INDEX workspace_membership_user_idx
  ON private_isg.workspace_memberships(user_id,status,workspace_id);
CREATE INDEX workspace_membership_role_idx
  ON private_isg.workspace_memberships(workspace_id,status,role,id);
CREATE UNIQUE INDEX workspace_active_owner_unique
  ON private_isg.workspace_memberships(workspace_id)
  WHERE role='owner' AND status='active';

CREATE TABLE private_isg.workspace_membership_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  workspace_id uuid NOT NULL,
  membership_id uuid NOT NULL,
  event_type text NOT NULL CHECK(event_type IN ('created','accepted','role_changed','practicing_changed','suspended','reactivated','ended','ownership_transferred')),
  actor_user_id uuid NOT NULL,
  from_state jsonb,
  to_state jsonb NOT NULL,
  reason text,
  correlation_id uuid NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY(workspace_id,membership_id)
    REFERENCES private_isg.workspace_memberships(workspace_id,id) ON DELETE RESTRICT,
  CHECK(reason IS NULL OR octet_length(reason) BETWEEN 1 AND 500)
);
CREATE INDEX workspace_membership_event_timeline
  ON private_isg.workspace_membership_events(workspace_id,membership_id,occurred_at,id);

CREATE TABLE private_isg.workspace_invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES private_isg.workspaces(id) ON DELETE CASCADE,
  email_normalized text NOT NULL CHECK(octet_length(email_normalized) BETWEEN 3 AND 254),
  role text NOT NULL CHECK(role IN ('admin','expert')),
  token_hash bytea NOT NULL UNIQUE CHECK(octet_length(token_hash)=32),
  status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','accepted','revoked','expired')),
  invited_by_user_id uuid NOT NULL,
  accepted_by_user_id uuid,
  seat_reservation_id uuid,
  expires_at timestamptz NOT NULL,
  accepted_at timestamptz,
  revoked_at timestamptz,
  version bigint NOT NULL DEFAULT 0 CHECK(version BETWEEN 0 AND 9007199254740991),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK(expires_at>created_at),
  CHECK((status='accepted')=(accepted_at IS NOT NULL)),
  CHECK((status='revoked')=(revoked_at IS NOT NULL)),
  CHECK(status<>'accepted' OR accepted_by_user_id IS NOT NULL)
);
CREATE UNIQUE INDEX workspace_pending_invitation_unique
  ON private_isg.workspace_invitations(workspace_id,email_normalized,role)
  WHERE status='pending';
CREATE INDEX workspace_invitation_expiry_idx
  ON private_isg.workspace_invitations(status,expires_at,workspace_id);

CREATE TABLE private_isg.workspace_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id uuid NOT NULL,
  mutation_id uuid NOT NULL,
  action text NOT NULL CHECK(octet_length(action) BETWEEN 1 AND 80),
  request_hash bytea NOT NULL CHECK(octet_length(request_hash)=32),
  workspace_id uuid,
  response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(actor_user_id,mutation_id)
);

CREATE TABLE private_isg.workspace_audit (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  workspace_id uuid,
  actor_user_id uuid NOT NULL,
  action text NOT NULL CHECK(octet_length(action) BETWEEN 1 AND 80),
  entity_type text NOT NULL CHECK(entity_type IN ('workspace','membership','invitation','company','assignment',
    'seat','subscription','wallet','asset','handover','workplace','department','employee','domain')),
  entity_id uuid NOT NULL,
  before_state jsonb,
  after_state jsonb NOT NULL,
  reason text,
  correlation_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK(reason IS NULL OR octet_length(reason) BETWEEN 1 AND 500)
);
CREATE INDEX workspace_audit_timeline ON private_isg.workspace_audit(workspace_id,created_at,id);

CREATE TABLE private_isg.workspace_outbox (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid,
  event_type text NOT NULL CHECK(octet_length(event_type) BETWEEN 1 AND 100),
  aggregate_type text NOT NULL CHECK(aggregate_type IN ('workspace','membership','invitation','company','assignment',
    'seat','subscription','wallet','asset','handover','workplace','department','employee','domain')),
  aggregate_id uuid NOT NULL,
  aggregate_version bigint NOT NULL CHECK(aggregate_version BETWEEN 0 AND 9007199254740991),
  payload jsonb NOT NULL,
  correlation_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(aggregate_type,aggregate_id,aggregate_version,event_type)
);
CREATE INDEX workspace_outbox_delivery_idx ON private_isg.workspace_outbox(created_at,id);

ALTER TABLE private_isg.workspace_rollout ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_membership_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE private_isg.workspace_outbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.workspace_rollout,private_isg.workspaces,
  private_isg.workspace_memberships,private_isg.workspace_membership_events,
  private_isg.workspace_invitations,private_isg.workspace_receipts,
  private_isg.workspace_audit,private_isg.workspace_outbox
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON SEQUENCE private_isg.workspace_membership_events_id_seq,
  private_isg.workspace_audit_id_seq FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.workspace_text(p_value text,p_max_bytes integer) RETURNS text
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE result text;
BEGIN
  IF p_value IS NULL OR p_max_bytes IS NULL OR p_max_bytes<1 OR octet_length(p_value)>4096 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  result:=normalize(regexp_replace(btrim(p_value,E' \t\r\n'),E'[ \t\r\n]+',' ','g'),NFC);
  IF result='' OR octet_length(result)>p_max_bytes OR result ~ '[[:cntrl:]]' OR result ~ U&'[\200B\FEFF]' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  RETURN result;
END $$;

CREATE FUNCTION private_isg.workspace_email(p_value text) RETURNS text
LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE result text;
BEGIN
  result:=lower(private_isg.workspace_text(p_value,254));
  IF result !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  RETURN result;
END $$;

CREATE FUNCTION private_isg.workspace_timezone(p_value text) RETURNS text
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE result text:=private_isg.workspace_text(p_value,80);
BEGIN
  PERFORM 1 FROM pg_catalog.pg_timezone_names WHERE name=result;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  RETURN result;
END $$;

CREATE FUNCTION private_isg.workspace_gate(p_feature text,p_write boolean) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF p_feature IS NULL OR p_write IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  PERFORM 1 FROM private_isg.workspace_rollout
    WHERE feature=p_feature AND read_enabled AND (NOT p_write OR write_enabled);
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='FEATURE_UNAVAILABLE'; END IF;
END $$;

CREATE FUNCTION private_isg.workspace_member_json(p_member private_isg.workspace_memberships) RETURNS jsonb
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT jsonb_build_object('membership_id',p_member.id,'user_id',p_member.user_id,
    'role',p_member.role,'status',p_member.status,'is_practicing_expert',p_member.is_practicing_expert,
    'permission_revision',p_member.permission_revision,'membership_version',p_member.version)
$$;

CREATE FUNCTION private_isg.workspace_membership_invariant() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE workspace private_isg.workspaces;
BEGIN
  SELECT * INTO workspace FROM private_isg.workspaces WHERE id=NEW.workspace_id;
  IF workspace.id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='23503',MESSAGE='WORKSPACE_NOT_FOUND';
  END IF;
  IF workspace.kind='personal' AND
     (NEW.user_id IS DISTINCT FROM workspace.personal_owner_user_id OR NEW.role<>'owner' OR
      NEW.status<>'active' OR NEW.is_practicing_expert) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PERSONAL_MEMBERSHIP_INVARIANT';
  END IF;
  IF NEW.is_practicing_expert AND (workspace.kind<>'osgb' OR NEW.status<>'active') THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='PRACTICING_MEMBERSHIP_INVARIANT';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER workspace_membership_invariant_before
BEFORE INSERT OR UPDATE ON private_isg.workspace_memberships
FOR EACH ROW EXECUTE FUNCTION private_isg.workspace_membership_invariant();

CREATE FUNCTION private_isg.workspace_context_json(p_actor uuid,p_workspace uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE workspace private_isg.workspaces; member private_isg.workspace_memberships;
  readable boolean; operable boolean;
BEGIN
  SELECT * INTO workspace FROM private_isg.workspaces WHERE id=p_workspace;
  SELECT * INTO member FROM private_isg.workspace_memberships
    WHERE workspace_id=p_workspace AND user_id=p_actor;
  IF NOT FOUND OR workspace.id IS NULL THEN RETURN NULL; END IF;
  readable:=member.status='active' AND workspace.status IN ('active','pending_purchase','admin_trial','admin_sponsored');
  operable:=member.status='active' AND workspace.status IN ('active','admin_trial','admin_sponsored');
  RETURN jsonb_build_object('schema_version',1,'workspace_id',workspace.id,'kind',workspace.kind,
    'name',workspace.name,'status',workspace.status,'timezone',workspace.timezone,
    'workspace_version',workspace.version,'membership',private_isg.workspace_member_json(member),
    'can_read',readable,'can_operate',operable,
    'can_manage_members',readable AND member.role IN ('owner','admin'),
    'can_manage_billing',readable AND member.role='owner');
END $$;

CREATE FUNCTION private_isg.workspace_require_member(p_workspace uuid,p_roles text[],p_operate boolean)
RETURNS private_isg.workspace_memberships
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); workspace private_isg.workspaces;
  member private_isg.workspace_memberships;
BEGIN
  IF p_workspace IS NULL OR p_roles IS NULL OR cardinality(p_roles)=0 OR p_operate IS NULL OR
     EXISTS(SELECT 1 FROM unnest(p_roles) role WHERE role NOT IN ('owner','admin','expert')) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO workspace FROM private_isg.workspaces WHERE id=p_workspace FOR SHARE;
  SELECT * INTO member FROM private_isg.workspace_memberships
    WHERE workspace_id=p_workspace AND user_id=actor FOR SHARE;
  IF workspace.id IS NULL OR member.id IS NULL OR member.status<>'active' OR member.role<>ALL(p_roles) OR
    workspace.status NOT IN ('active','pending_purchase','admin_trial','admin_sponsored') OR
    (p_operate AND workspace.status='pending_purchase') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  RETURN member;
END $$;

-- Phase H replaces this deny-by-default hook with the locked entitlement/seat authority.
CREATE FUNCTION private_isg.workspace_require_expert_seat(p_workspace uuid,p_user uuid,p_reference uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='SEAT_AUTHORITY_UNAVAILABLE';
END $$;

CREATE FUNCTION private_isg.workspace_receipt_replay(p_actor uuid,p_mutation uuid,p_action text,p_hash bytea)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE receipt private_isg.workspace_receipts;
BEGIN
  IF p_mutation IS NULL OR p_action IS NULL OR p_hash IS NULL OR octet_length(p_hash)<>32 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO receipt FROM private_isg.workspace_receipts
    WHERE actor_user_id=p_actor AND mutation_id=p_mutation;
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF receipt.action IS DISTINCT FROM p_action OR receipt.request_hash IS DISTINCT FROM p_hash THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='IDEMPOTENCY_CONFLICT'; END IF;
  RETURN receipt.response || jsonb_build_object('replayed',true);
END $$;

CREATE FUNCTION private_isg.workspace_record_effect(p_actor uuid,p_mutation uuid,p_action text,p_hash bytea,
  p_workspace uuid,p_entity_type text,p_entity uuid,p_version bigint,p_before jsonb,p_after jsonb,
  p_reason text,p_response jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  INSERT INTO private_isg.workspace_audit(workspace_id,actor_user_id,action,entity_type,entity_id,
    before_state,after_state,reason,correlation_id)
    VALUES(p_workspace,p_actor,p_action,p_entity_type,p_entity,p_before,p_after,p_reason,p_mutation);
  INSERT INTO private_isg.workspace_outbox(workspace_id,event_type,aggregate_type,aggregate_id,
    aggregate_version,payload,correlation_id)
    VALUES(p_workspace,'workspace.'||p_action,p_entity_type,p_entity,p_version,p_after,p_mutation)
    ON CONFLICT(aggregate_type,aggregate_id,aggregate_version,event_type) DO NOTHING;
  INSERT INTO private_isg.workspace_receipts(actor_user_id,mutation_id,action,request_hash,workspace_id,response)
    VALUES(p_actor,p_mutation,p_action,p_hash,p_workspace,p_response);
  RETURN p_response || jsonb_build_object('replayed',false);
END $$;

CREATE FUNCTION private_isg.workspace_list_mine() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); rows jsonb;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_context',false);
  SELECT coalesce(jsonb_agg(private_isg.workspace_context_json(actor,m.workspace_id)
    ORDER BY CASE w.kind WHEN 'personal' THEN 0 ELSE 1 END,w.created_at,w.id),'[]'::jsonb)
    INTO rows FROM private_isg.workspace_memberships m
    JOIN private_isg.workspaces w ON w.id=m.workspace_id
    WHERE m.user_id=actor AND m.status='active' AND w.status<>'archived';
  RETURN jsonb_build_object('schema_version',1,'user_id',actor,'workspaces',rows);
END $$;

CREATE FUNCTION private_isg.workspace_get_context(p_workspace uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); result jsonb;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_context',false);
  result:=private_isg.workspace_context_json(actor,p_workspace);
  IF result IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  RETURN result;
END $$;

CREATE FUNCTION private_isg.workspace_ensure_personal(p_mutation uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); workspace private_isg.workspaces;
  member private_isg.workspace_memberships; fingerprint bytea; replay jsonb; result jsonb;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_mutations',true);
  fingerprint:=sha256(convert_to(jsonb_build_array('personal')::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'personal.ensure',fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  PERFORM 1 FROM public.profiles WHERE id=actor FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO workspace FROM private_isg.workspaces
    WHERE kind='personal' AND personal_owner_user_id=actor FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO private_isg.workspaces(kind,name,status,timezone,created_by_user_id,personal_owner_user_id)
      VALUES('personal','Kişisel Çalışma Alanı','active','Europe/Istanbul',actor,actor) RETURNING * INTO workspace;
  END IF;
  INSERT INTO private_isg.workspace_memberships(workspace_id,user_id,role,status)
    VALUES(workspace.id,actor,'owner','active')
    ON CONFLICT(workspace_id,user_id) DO UPDATE SET
      status='active',role='owner',is_practicing_expert=false,suspended_at=NULL,ended_at=NULL,
      permission_revision=private_isg.workspace_memberships.permission_revision+1,
      version=private_isg.workspace_memberships.version+1,updated_at=clock_timestamp()
    WHERE private_isg.workspace_memberships.status<>'active' OR private_isg.workspace_memberships.role<>'owner'
    RETURNING * INTO member;
  IF member.id IS NULL THEN
    SELECT * INTO STRICT member FROM private_isg.workspace_memberships
      WHERE workspace_id=workspace.id AND user_id=actor;
  END IF;
  result:=private_isg.workspace_context_json(actor,workspace.id);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'personal.ensure',fingerprint,
    workspace.id,'workspace',workspace.id,workspace.version,NULL,result,NULL,result);
END $$;

CREATE FUNCTION private_isg.workspace_create_osgb(p_mutation uuid,p_name text,p_timezone text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); clean_name text; clean_timezone text;
  fingerprint bytea; replay jsonb; workspace private_isg.workspaces;
  member private_isg.workspace_memberships; result jsonb;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_mutations',true);
  clean_name:=private_isg.workspace_text(p_name,200);
  clean_timezone:=private_isg.workspace_timezone(p_timezone);
  fingerprint:=sha256(convert_to(jsonb_build_array(clean_name,clean_timezone)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'osgb.create',fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  PERFORM 1 FROM public.profiles WHERE id=actor FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  INSERT INTO private_isg.workspaces(kind,name,status,timezone,created_by_user_id)
    VALUES('osgb',clean_name,'pending_purchase',clean_timezone,actor) RETURNING * INTO workspace;
  INSERT INTO private_isg.workspace_memberships(workspace_id,user_id,role,status)
    VALUES(workspace.id,actor,'owner','active') RETURNING * INTO member;
  INSERT INTO private_isg.workspace_membership_events(workspace_id,membership_id,event_type,
    actor_user_id,to_state,correlation_id)
    VALUES(workspace.id,member.id,'created',actor,private_isg.workspace_member_json(member),p_mutation);
  result:=private_isg.workspace_context_json(actor,workspace.id);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'osgb.create',fingerprint,
    workspace.id,'workspace',workspace.id,workspace.version,NULL,result,NULL,result);
END $$;

CREATE FUNCTION private_isg.workspace_invite(p_mutation uuid,p_workspace uuid,p_email text,p_role text,
  p_expires_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); manager private_isg.workspace_memberships;
  email text; token text; token_hash bytea; fingerprint bytea; replay jsonb;
  invitation private_isg.workspace_invitations; response jsonb; prior private_isg.workspace_invitations;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_invitations',true);
  manager:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],false);
  email:=private_isg.workspace_email(p_email);
  IF p_role NOT IN ('admin','expert') OR p_expires_at IS NULL OR
     p_expires_at<=clock_timestamp()+interval '5 minutes' OR p_expires_at>clock_timestamp()+interval '30 days' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,email,p_role,p_expires_at)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'invitation.create',fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  SELECT * INTO prior FROM private_isg.workspace_invitations
    WHERE workspace_id=p_workspace AND email_normalized=email AND role=p_role AND status='pending' FOR UPDATE;
  IF FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='INVITATION_ALREADY_PENDING'; END IF;
  token:=encode(sha256(convert_to(gen_random_uuid()::text||gen_random_uuid()::text||
    clock_timestamp()::text,'UTF8')),'hex');
  token_hash:=sha256(convert_to(token,'UTF8'));
  INSERT INTO private_isg.workspace_invitations(workspace_id,email_normalized,role,token_hash,
    invited_by_user_id,expires_at) VALUES(p_workspace,email,p_role,token_hash,actor,p_expires_at)
    RETURNING * INTO invitation;
  response:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,
    'invitation_id',invitation.id,'role',p_role,'status','pending','expires_at',p_expires_at,
    'token_persisted',false);
  response:=private_isg.workspace_record_effect(actor,p_mutation,'invitation.create',fingerprint,
    p_workspace,'invitation',invitation.id,invitation.version,NULL,
    response,NULL,response);
  -- Returned exactly once. The plaintext token is absent from receipt/audit/outbox.
  RETURN response || jsonb_build_object('invitation_token',token);
END $$;

CREATE FUNCTION private_isg.workspace_accept_invitation(p_mutation uuid,p_token text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); clean_token text; wanted_hash bytea; fingerprint bytea;
  replay jsonb; invitation private_isg.workspace_invitations; member private_isg.workspace_memberships;
  account_email text; before_state jsonb; result jsonb;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_invitations',true);
  clean_token:=private_isg.workspace_text(p_token,128);
  IF clean_token !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  wanted_hash:=sha256(convert_to(clean_token,'UTF8'));
  fingerprint:=sha256(convert_to(jsonb_build_array(wanted_hash)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'invitation.accept',fingerprint);
  IF replay IS NOT NULL THEN
    PERFORM private_isg.workspace_require_member((replay->>'workspace_id')::uuid,
      ARRAY['owner','admin','expert'],false);
    RETURN replay;
  END IF;
  SELECT * INTO invitation FROM private_isg.workspace_invitations
    WHERE workspace_invitations.token_hash=wanted_hash FOR UPDATE;
  IF NOT FOUND OR invitation.status<>'pending' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='INVITATION_INVALID'; END IF;
  IF invitation.expires_at<=clock_timestamp() THEN
    UPDATE private_isg.workspace_invitations SET status='expired',version=version+1,
      updated_at=clock_timestamp() WHERE id=invitation.id;
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='INVITATION_EXPIRED'; END IF;
  SELECT lower(btrim(email)) INTO account_email FROM auth.users
    WHERE id=actor AND email_confirmed_at IS NOT NULL FOR SHARE;
  IF account_email IS NULL OR account_email IS DISTINCT FROM invitation.email_normalized THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='INVITATION_EMAIL_MISMATCH'; END IF;
  IF invitation.role='expert' THEN
    PERFORM private_isg.workspace_require_expert_seat(invitation.workspace_id,actor,invitation.id);
  END IF;
  SELECT private_isg.workspace_member_json(m) INTO before_state
    FROM private_isg.workspace_memberships m
    WHERE m.workspace_id=invitation.workspace_id AND m.user_id=actor FOR UPDATE;
  IF before_state IS NOT NULL THEN
    SELECT * INTO member FROM private_isg.workspace_memberships
      WHERE workspace_id=invitation.workspace_id AND user_id=actor;
    IF member.status<>'ended' OR member.role='owner' THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='MEMBERSHIP_CONFLICT'; END IF;
    UPDATE private_isg.workspace_memberships SET role=invitation.role,status='active',
      is_practicing_expert=(invitation.role='expert'),suspended_at=NULL,ended_at=NULL,
      permission_revision=permission_revision+1,version=version+1,updated_at=clock_timestamp()
      WHERE id=member.id RETURNING * INTO member;
  ELSE
    INSERT INTO private_isg.workspace_memberships(workspace_id,user_id,role,status,is_practicing_expert)
      VALUES(invitation.workspace_id,actor,invitation.role,'active',invitation.role='expert')
      RETURNING * INTO member;
  END IF;
  UPDATE private_isg.workspace_invitations SET status='accepted',accepted_by_user_id=actor,
    accepted_at=clock_timestamp(),version=version+1,updated_at=clock_timestamp()
    WHERE id=invitation.id;
  INSERT INTO private_isg.workspace_membership_events(workspace_id,membership_id,event_type,
    actor_user_id,from_state,to_state,correlation_id)
    VALUES(invitation.workspace_id,member.id,'accepted',actor,before_state,
      private_isg.workspace_member_json(member),p_mutation);
  result:=private_isg.workspace_context_json(actor,invitation.workspace_id);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'invitation.accept',fingerprint,
    invitation.workspace_id,'membership',member.id,member.version,before_state,result,NULL,result);
END $$;

CREATE FUNCTION private_isg.workspace_manage_invitation(p_mutation uuid,p_workspace uuid,p_invitation uuid,
  p_expected_version bigint,p_action text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); manager private_isg.workspace_memberships;
  invitation private_isg.workspace_invitations; fingerprint bytea; replay jsonb; before_state jsonb; result jsonb;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_invitations',true);
  manager:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],false);
  IF p_action<>'revoke' OR p_expected_version IS NULL OR p_expected_version<0 THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_invitation,p_expected_version,p_action)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'invitation.revoke',fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  SELECT * INTO invitation FROM private_isg.workspace_invitations
    WHERE id=p_invitation AND workspace_id=p_workspace FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF invitation.version<>p_expected_version THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  IF invitation.status<>'pending' THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='INVITATION_INVALID'; END IF;
  before_state:=jsonb_build_object('status',invitation.status,'version',invitation.version);
  UPDATE private_isg.workspace_invitations SET status='revoked',revoked_at=clock_timestamp(),
    version=version+1,updated_at=clock_timestamp() WHERE id=invitation.id RETURNING * INTO invitation;
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,
    'invitation_id',invitation.id,'status',invitation.status,'version',invitation.version);
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'invitation.revoke',fingerprint,
    p_workspace,'invitation',invitation.id,invitation.version,before_state,result,NULL,result);
END $$;

CREATE FUNCTION private_isg.workspace_manage_member(p_mutation uuid,p_workspace uuid,p_membership uuid,
  p_expected_version bigint,p_action text,p_value text,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=private_isg.active_actor(); manager private_isg.workspace_memberships;
  target private_isg.workspace_memberships; previous private_isg.workspace_memberships;
  fingerprint bytea; replay jsonb; clean_reason text; event text; result jsonb;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_mutations',true);
  manager:=private_isg.workspace_require_member(p_workspace,ARRAY['owner','admin'],false);
  IF p_expected_version IS NULL OR p_expected_version<0 OR p_action NOT IN
    ('suspend','reactivate','end','change_role','set_practicing','transfer_owner') THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_reason IS NOT NULL THEN clean_reason:=private_isg.workspace_text(p_reason,500); END IF;
  fingerprint:=sha256(convert_to(jsonb_build_array(p_workspace,p_membership,p_expected_version,p_action,p_value,clean_reason)::text,'UTF8'));
  replay:=private_isg.workspace_receipt_replay(actor,p_mutation,'membership.'||p_action,fingerprint);
  IF replay IS NOT NULL THEN RETURN replay; END IF;
  PERFORM 1 FROM private_isg.workspaces WHERE id=p_workspace FOR UPDATE;
  SELECT * INTO target FROM private_isg.workspace_memberships
    WHERE id=p_membership AND workspace_id=p_workspace FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF target.version<>p_expected_version THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
  previous:=target;
  IF p_action='suspend' THEN
    IF target.role='owner' OR target.status<>'active' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='MEMBERSHIP_CONFLICT'; END IF;
    UPDATE private_isg.workspace_memberships SET status='suspended',is_practicing_expert=false,
      suspended_at=clock_timestamp(),ended_at=NULL,permission_revision=permission_revision+1,
      version=version+1,updated_at=clock_timestamp() WHERE id=target.id RETURNING * INTO target;
    event:='suspended';
  ELSIF p_action='reactivate' THEN
    IF target.role='owner' OR target.status<>'suspended' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='MEMBERSHIP_CONFLICT'; END IF;
    UPDATE private_isg.workspace_memberships SET status='active',suspended_at=NULL,
      permission_revision=permission_revision+1,version=version+1,updated_at=clock_timestamp()
      WHERE id=target.id RETURNING * INTO target; event:='reactivated';
  ELSIF p_action='end' THEN
    IF target.role='owner' OR target.status='ended' THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='MEMBERSHIP_CONFLICT'; END IF;
    UPDATE private_isg.workspace_memberships SET status='ended',is_practicing_expert=false,
      suspended_at=NULL,ended_at=clock_timestamp(),permission_revision=permission_revision+1,
      version=version+1,updated_at=clock_timestamp() WHERE id=target.id RETURNING * INTO target; event:='ended';
  ELSIF p_action='change_role' THEN
    IF target.role='owner' OR target.status<>'active' OR p_value NOT IN ('admin','expert') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='MEMBERSHIP_CONFLICT'; END IF;
    IF p_value='expert' THEN PERFORM private_isg.workspace_require_expert_seat(p_workspace,target.user_id,target.id); END IF;
    UPDATE private_isg.workspace_memberships SET role=p_value,
      is_practicing_expert=(p_value='expert'),permission_revision=permission_revision+1,
      version=version+1,updated_at=clock_timestamp() WHERE id=target.id RETURNING * INTO target; event:='role_changed';
  ELSIF p_action='set_practicing' THEN
    IF target.status<>'active' OR p_value NOT IN ('true','false') THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='MEMBERSHIP_CONFLICT'; END IF;
    IF p_value='true' THEN PERFORM private_isg.workspace_require_expert_seat(p_workspace,target.user_id,target.id); END IF;
    UPDATE private_isg.workspace_memberships SET is_practicing_expert=(p_value='true'),
      permission_revision=permission_revision+1,version=version+1,updated_at=clock_timestamp()
      WHERE id=target.id RETURNING * INTO target; event:='practicing_changed';
  ELSE
    IF manager.role<>'owner' OR target.status<>'active' OR target.role='owner' OR target.id=manager.id THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='MEMBERSHIP_CONFLICT'; END IF;
    PERFORM 1 FROM private_isg.workspaces WHERE id=p_workspace FOR UPDATE;
    UPDATE private_isg.workspace_memberships SET role='admin',is_practicing_expert=false,
      permission_revision=permission_revision+1,version=version+1,updated_at=clock_timestamp()
      WHERE id=manager.id RETURNING * INTO manager;
    UPDATE private_isg.workspace_memberships SET role='owner',is_practicing_expert=false,
      permission_revision=permission_revision+1,version=version+1,updated_at=clock_timestamp()
      WHERE id=target.id RETURNING * INTO target;
    INSERT INTO private_isg.workspace_membership_events(workspace_id,membership_id,event_type,
      actor_user_id,from_state,to_state,reason,correlation_id)
      VALUES(p_workspace,manager.id,'ownership_transferred',actor,NULL,
        private_isg.workspace_member_json(manager),clean_reason,p_mutation);
    event:='ownership_transferred';
  END IF;
  INSERT INTO private_isg.workspace_membership_events(workspace_id,membership_id,event_type,
    actor_user_id,from_state,to_state,reason,correlation_id)
    VALUES(p_workspace,target.id,event,actor,private_isg.workspace_member_json(previous),
      private_isg.workspace_member_json(target),clean_reason,p_mutation);
  result:=jsonb_build_object('schema_version',1,'workspace_id',p_workspace,
    'membership',private_isg.workspace_member_json(target));
  RETURN private_isg.workspace_record_effect(actor,p_mutation,'membership.'||p_action,fingerprint,
    p_workspace,'membership',target.id,target.version,private_isg.workspace_member_json(previous),
    result,clean_reason,result);
END $$;

CREATE FUNCTION public.isg_workspace_list_v1() RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_list_mine() $$;
CREATE FUNCTION public.isg_workspace_context_v1(p_workspace uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_get_context(p_workspace) $$;
CREATE FUNCTION public.isg_personal_workspace_ensure_v1(p_mutation uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_ensure_personal(p_mutation) $$;
CREATE FUNCTION public.isg_osgb_workspace_create_v1(p_mutation uuid,p_name text,p_timezone text) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_create_osgb(p_mutation,p_name,p_timezone) $$;
CREATE FUNCTION public.isg_workspace_invite_v1(p_mutation uuid,p_workspace uuid,p_email text,p_role text,p_expires_at timestamptz) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_invite(p_mutation,p_workspace,p_email,p_role,p_expires_at) $$;
CREATE FUNCTION public.isg_workspace_invitation_accept_v1(p_mutation uuid,p_token text) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_accept_invitation(p_mutation,p_token) $$;
CREATE FUNCTION public.isg_workspace_invitation_mutate_v1(p_mutation uuid,p_workspace uuid,p_invitation uuid,p_expected_version bigint,p_action text) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_manage_invitation(p_mutation,p_workspace,p_invitation,p_expected_version,p_action) $$;
CREATE FUNCTION public.isg_workspace_member_mutate_v1(p_mutation uuid,p_workspace uuid,p_membership uuid,p_expected_version bigint,p_action text,p_value text,p_reason text) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT private_isg.workspace_manage_member(p_mutation,p_workspace,p_membership,p_expected_version,p_action,p_value,p_reason) $$;

REVOKE ALL ON FUNCTION private_isg.workspace_text(text,integer),private_isg.workspace_email(text),
  private_isg.workspace_timezone(text),private_isg.workspace_gate(text,boolean),
  private_isg.workspace_member_json(private_isg.workspace_memberships),
  private_isg.workspace_membership_invariant(),
  private_isg.workspace_context_json(uuid,uuid),private_isg.workspace_require_member(uuid,text[],boolean),
  private_isg.workspace_require_expert_seat(uuid,uuid,uuid),
  private_isg.workspace_receipt_replay(uuid,uuid,text,bytea),
  private_isg.workspace_record_effect(uuid,uuid,text,bytea,uuid,text,uuid,bigint,jsonb,jsonb,text,jsonb),
  private_isg.workspace_list_mine(),private_isg.workspace_get_context(uuid),
  private_isg.workspace_ensure_personal(uuid),private_isg.workspace_create_osgb(uuid,text,text),
  private_isg.workspace_invite(uuid,uuid,text,text,timestamptz),
  private_isg.workspace_accept_invitation(uuid,text),
  private_isg.workspace_manage_invitation(uuid,uuid,uuid,bigint,text),
  private_isg.workspace_manage_member(uuid,uuid,uuid,bigint,text,text,text),
  public.isg_workspace_list_v1(),public.isg_workspace_context_v1(uuid),
  public.isg_personal_workspace_ensure_v1(uuid),public.isg_osgb_workspace_create_v1(uuid,text,text),
  public.isg_workspace_invite_v1(uuid,uuid,text,text,timestamptz),
  public.isg_workspace_invitation_accept_v1(uuid,text),
  public.isg_workspace_invitation_mutate_v1(uuid,uuid,uuid,bigint,text),
  public.isg_workspace_member_mutate_v1(uuid,uuid,uuid,bigint,text,text,text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_list_mine(),private_isg.workspace_get_context(uuid),
  private_isg.workspace_ensure_personal(uuid),private_isg.workspace_create_osgb(uuid,text,text),
  private_isg.workspace_invite(uuid,uuid,text,text,timestamptz),
  private_isg.workspace_accept_invitation(uuid,text),
  private_isg.workspace_manage_invitation(uuid,uuid,uuid,bigint,text),
  private_isg.workspace_manage_member(uuid,uuid,uuid,bigint,text,text,text),
  public.isg_workspace_list_v1(),public.isg_workspace_context_v1(uuid),
  public.isg_personal_workspace_ensure_v1(uuid),public.isg_osgb_workspace_create_v1(uuid,text,text),
  public.isg_workspace_invite_v1(uuid,uuid,text,text,timestamptz),
  public.isg_workspace_invitation_accept_v1(uuid,text),
  public.isg_workspace_invitation_mutate_v1(uuid,uuid,uuid,bigint,text),
  public.isg_workspace_member_mutate_v1(uuid,uuid,uuid,bigint,text,text,text)
  TO authenticated;
NOTIFY pgrst,'reload schema';
