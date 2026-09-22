-- Only for an empty, disposable local database. Never apply to a Supabase project.
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $$;
CREATE SCHEMA auth;
CREATE SCHEMA private_isg;
CREATE FUNCTION private_isg.text_value(value text,max_bytes integer) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
 IF value IS NULL OR octet_length(btrim(value))>max_bytes OR btrim(value)='' THEN RAISE EXCEPTION 'VALIDATION_ERROR'; END IF;
 RETURN btrim(value);
END $$;
CREATE TABLE auth.users(id uuid PRIMARY KEY,deleted_at timestamptz,banned_until timestamptz,is_anonymous boolean DEFAULT false);
CREATE TABLE auth.sessions(id uuid PRIMARY KEY,user_id uuid,not_after timestamptz);
CREATE TABLE public.profiles(id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE);
CREATE TABLE public.companies(id uuid PRIMARY KEY,user_id uuid,name text);
CREATE TABLE public.push_device_tokens(id uuid PRIMARY KEY,user_id uuid,token text,provider text,installation_id uuid,notifications_enabled boolean,environment text,application_id text);
CREATE TABLE public.notification_preferences(user_id uuid PRIMARY KEY,enabled boolean,app_reminders boolean);
CREATE TABLE private_isg.rollout(feature text PRIMARY KEY,read_enabled boolean NOT NULL DEFAULT false,write_enabled boolean NOT NULL DEFAULT false);
CREATE TABLE private_isg.workspace_companies(id uuid,workspace_id uuid,legacy_company_id uuid,name text);
CREATE TABLE private_isg.personnel_audit(actor_id uuid,operation_id uuid,action text,created_at timestamptz);
DO $$ DECLARE name text; BEGIN
 FOREACH name IN ARRAY ARRAY['appointment_receipts','checklist_receipts','document_tracking_receipts','drill_receipts',
 'education_receipts','emergency_plan_receipts','equipment_check_receipts','file_library_receipts','module_edit_receipts',
 'nonconformity_receipts','personnel_receipts','pilot_training_receipts','pilot_training_session_receipts','ppe_receipts','risk_version_receipts'] LOOP
 EXECUTE format('CREATE TABLE private_isg.%I(actor_id uuid,owner_id uuid,mutation_id uuid,company_id uuid,operation_id uuid,response jsonb)',name);
 END LOOP;
END $$;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql AS $$ SELECT current_setting('request.jwt.claims')::jsonb $$;
CREATE FUNCTION private_isg.active_actor() RETURNS uuid LANGUAGE sql AS $$ SELECT (auth.jwt()->>'sub')::uuid $$;
CREATE TABLE private_isg.workspaces(id uuid PRIMARY KEY);
CREATE TABLE private_isg.workspace_memberships(id uuid PRIMARY KEY,workspace_id uuid,user_id uuid,role text,status text,joined_at timestamptz,ended_at timestamptz,suspended_at timestamptz);
CREATE FUNCTION private_isg.workspace_require_member(p_workspace uuid,p_roles text[],p_operate boolean)
RETURNS private_isg.workspace_memberships LANGUAGE plpgsql AS $$
DECLARE m private_isg.workspace_memberships;
BEGIN
 SELECT * INTO m FROM private_isg.workspace_memberships WHERE workspace_id=p_workspace AND user_id=private_isg.active_actor() AND status='active' AND role=ANY(p_roles);
 IF m.id IS NULL THEN RAISE EXCEPTION 'ACCESS_DENIED'; END IF;
 RETURN m;
END $$;
CREATE TABLE private_isg.workspace_audit(id bigint PRIMARY KEY,workspace_id uuid,actor_user_id uuid,action text,entity_type text,entity_id uuid,before_state jsonb,after_state jsonb,correlation_id uuid,created_at timestamptz);
