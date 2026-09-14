-- Run only in a fresh, disposable local database, never on a project database.
-- Stands in for the live objects the Evrak Takibi pilot bundle expects to
-- already exist: the P05 pilot gates, the company/workplace scope and the plan
-- check.
CREATE SCHEMA private_isg;
CREATE SCHEMA private;

CREATE TABLE public.companies(id uuid PRIMARY KEY,user_id uuid NOT NULL,name text NOT NULL,
  is_archived boolean NOT NULL DEFAULT false,UNIQUE(id,user_id));
CREATE TABLE public.profiles(id uuid PRIMARY KEY);
CREATE TABLE public.user_subscriptions(user_id uuid PRIMARY KEY,tier text NOT NULL,
  status text NOT NULL,current_period_ends_at timestamptz);
CREATE TABLE private_isg.workplaces(company_id uuid NOT NULL,id uuid NOT NULL,
  owner_id uuid NOT NULL,name text NOT NULL,needs_review boolean NOT NULL DEFAULT false,
  is_archived boolean NOT NULL DEFAULT false,UNIQUE(company_id,id));
CREATE TABLE private_isg.rollout(feature text PRIMARY KEY,
  read_enabled boolean NOT NULL DEFAULT false,write_enabled boolean NOT NULL DEFAULT false,
  CONSTRAINT rollout_check CHECK(NOT write_enabled OR read_enabled),
  CONSTRAINT rollout_feature_check CHECK(feature IN ('personnel','modules')));
INSERT INTO private_isg.rollout(feature,read_enabled,write_enabled) VALUES
  ('personnel',true,true),('modules',true,true);

CREATE FUNCTION private.user_plan_tier(p_user uuid) RETURNS text
LANGUAGE sql STABLE SET search_path='' AS $$
  SELECT tier FROM public.user_subscriptions WHERE user_id=p_user $$;
CREATE FUNCTION private_isg.active_actor() RETURNS uuid
LANGUAGE sql STABLE SET search_path='' AS $$
  SELECT nullif(current_setting('test.actor',true),'')::uuid $$;
-- The live gates, reduced to the two facts they decide.
CREATE FUNCTION private_isg.p05_pilot_account_enabled(p_actor uuid,p_write boolean) RETURNS boolean
LANGUAGE sql STABLE SET search_path='' AS $$
  SELECT p_actor IS NOT NULL AND current_setting('test.pilot',true)='true'
     AND (NOT p_write OR current_setting('test.pilot_write',true)<>'false') $$;
CREATE FUNCTION private_isg.p05_pilot_can_read(p_actor uuid,p_company uuid) RETURNS boolean
LANGUAGE sql STABLE SET search_path='' AS $$
  SELECT private_isg.p05_pilot_account_enabled(p_actor,false)
     AND EXISTS(SELECT 1 FROM public.companies WHERE id=p_company AND user_id=p_actor) $$;

INSERT INTO public.companies VALUES
  ('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Pilot Firma',false),
  ('10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','Diger Firma',false);
INSERT INTO public.profiles VALUES
  ('20000000-0000-0000-0000-000000000001'),('20000000-0000-0000-0000-000000000002');
INSERT INTO public.user_subscriptions VALUES
  ('20000000-0000-0000-0000-000000000001','pro','active',NULL),
  ('20000000-0000-0000-0000-000000000002','pro','active',NULL);
INSERT INTO private_isg.workplaces VALUES
  ('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Merkez',false,false),
  ('10000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','Sube',false,false);
