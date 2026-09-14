-- LOCAL ONLY, after pilot_training_fixture.sql and v1 register migration.
CREATE SCHEMA auth;
CREATE TABLE auth.users(id uuid PRIMARY KEY);
INSERT INTO auth.users VALUES('20000000-0000-0000-0000-000000000001'),('20000000-0000-0000-0000-000000000002');
ALTER TABLE public.companies ADD COLUMN name text DEFAULT 'Fixture company', ADD COLUMN hazard_class text DEFAULT 'high';
CREATE FUNCTION private_isg.active_actor() RETURNS uuid LANGUAGE sql AS $$ SELECT current_setting('test.actor')::uuid $$;
CREATE FUNCTION private_isg.p05_pilot_account_enabled(uuid,boolean) RETURNS boolean LANGUAGE sql AS $$ SELECT coalesce(current_setting('test.expired',true),'')<>'true' $$;
CREATE FUNCTION private_isg.p05_pilot_can_read(uuid,uuid) RETURNS boolean LANGUAGE sql AS $$ SELECT EXISTS(SELECT 1 FROM public.companies WHERE id=$2 AND user_id=$1) $$;
GRANT USAGE ON SCHEMA private_isg TO authenticated;
