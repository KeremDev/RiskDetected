-- Run only in a fresh, disposable local database, never on a project database.
--
-- Stands in for everything the P08/P09/P10 client slices expect to already
-- exist when their own migration is applied on top: the account and company
-- scope, the personnel and workplace registers, the rollout table, and the four
-- helpers the domain functions call. One fixture serves every slice so a check
-- can be re-run without hunting for the shape it was written against.
CREATE SCHEMA private_isg;
CREATE SCHEMA private;
-- The module core creates btree_gist in the `extensions` schema the platform
-- provides; a bare Postgres has neither.
CREATE SCHEMA extensions;

CREATE TABLE public.companies(id uuid PRIMARY KEY,user_id uuid NOT NULL,name text NOT NULL,
  is_archived boolean NOT NULL DEFAULT false,UNIQUE(id,user_id));
CREATE TABLE public.profiles(id uuid PRIMARY KEY);
CREATE TABLE public.user_subscriptions(user_id uuid PRIMARY KEY,tier text NOT NULL,status text NOT NULL,
  current_period_ends_at timestamptz);
CREATE TABLE private_isg.workplaces(company_id uuid NOT NULL,id uuid NOT NULL,owner_id uuid NOT NULL,
  name text NOT NULL,needs_review boolean NOT NULL DEFAULT false,is_archived boolean NOT NULL DEFAULT false,
  UNIQUE(company_id,id));
CREATE TABLE private_isg.employees(id uuid PRIMARY KEY,company_id uuid,owner_id uuid,
  full_name text,is_archived boolean DEFAULT false,UNIQUE(company_id,id));
-- The feature list is the one the P08 slice inherits; each slice's own
-- migration widens it further if it needs to.
CREATE TABLE private_isg.rollout(feature text PRIMARY KEY,read_enabled boolean NOT NULL DEFAULT false,
  write_enabled boolean NOT NULL DEFAULT false,
  CONSTRAINT rollout_check CHECK(NOT write_enabled OR read_enabled),
  CONSTRAINT rollout_feature_check CHECK(feature IN ('personnel','event_dispatch','quota_ledger',
    'file_core','rule_engine','training','risk','nonconformity')));
INSERT INTO private_isg.rollout(feature,read_enabled,write_enabled) VALUES('personnel',true,true);
-- P04 owns the real asset table; the slices only ever read a scan verdict from
-- it, and none of them can promote one.
CREATE TABLE private_isg.file_assets(asset_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scan_status text NOT NULL DEFAULT 'clean');
-- P06 owns the real rule catalogue; the risk slice only reads published rows.
CREATE TABLE private_isg.rule_versions(rule_code text PRIMARY KEY,status text NOT NULL,
  period_kind text NOT NULL,period_length integer);

CREATE FUNCTION private.user_plan_tier(p_user uuid) RETURNS text
LANGUAGE sql STABLE SET search_path='' AS $$
  SELECT tier FROM public.user_subscriptions WHERE user_id=p_user $$;
CREATE FUNCTION private_isg.active_actor() RETURNS uuid
LANGUAGE sql STABLE SET search_path='' AS $$
  SELECT nullif(current_setting('test.actor',true),'')::uuid $$;
CREATE FUNCTION private_isg.text_value(value text,max_bytes integer) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path='' AS $$ SELECT left(btrim(value),max_bytes) $$;
CREATE FUNCTION private_isg.next_due_on(p_from date,p_kind text,p_length integer) RETURNS date
LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
BEGIN
  IF p_from IS NULL OR NOT isfinite(p_from) OR p_kind IS NULL OR p_kind NOT IN ('once','months','years') OR
     (p_kind='once')<>(p_length IS NULL) OR (p_length IS NOT NULL AND p_length NOT BETWEEN 1 AND 120) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  IF p_kind='once' THEN RETURN p_from; END IF;
  RETURN (p_from+CASE p_kind WHEN 'months' THEN make_interval(months=>p_length)
                             ELSE make_interval(years=>p_length) END)::date;
END $$;

-- Two accounts, so every slice can prove that one cannot reach the other.
INSERT INTO public.companies VALUES
  ('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','A Firma',false),
  ('10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','B Firma',false);
INSERT INTO public.profiles VALUES
  ('20000000-0000-0000-0000-000000000001'),('20000000-0000-0000-0000-000000000002');
INSERT INTO public.user_subscriptions VALUES
  ('20000000-0000-0000-0000-000000000001','pro','active',NULL),
  ('20000000-0000-0000-0000-000000000002','pro','active',NULL);
-- Two workplaces in the first company, so a scope can be told from another.
INSERT INTO private_isg.workplaces VALUES
  ('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Merkez',false,false),
  ('10000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001','Depo',false,false),
  ('10000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','Sube',false,false);
INSERT INTO private_isg.employees VALUES
  ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Ali Calisan',false),
  ('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Veli Calisan',false),
  ('30000000-0000-0000-0000-000000000009','10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','Baska Firma Calisani',false);
INSERT INTO private_isg.file_assets(asset_id,scan_status) VALUES
  ('50000000-0000-0000-0000-000000000001','clean'),('50000000-0000-0000-0000-000000000002','pending');
INSERT INTO private_isg.rule_versions VALUES ('RISK_GENERAL_4Y','published','years',4);
