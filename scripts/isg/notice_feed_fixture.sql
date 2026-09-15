-- Run only in a fresh, disposable local database, never on a project database.
--
-- Stands in for the LIVE pilot shape the notice feed is written against: the
-- pilot account gates, the company/workplace/personnel scope, the two switch
-- tables, and the ten record tables the feed reads. Columns are the live ones
-- (checked against private_isg on the pilot project), not the dev chain's.
CREATE SCHEMA private_isg;
-- The platform roles the REVOKE/GRANT lines name.
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $$;

CREATE TABLE public.profiles(id uuid PRIMARY KEY);
CREATE TABLE public.companies(id uuid PRIMARY KEY,user_id uuid NOT NULL,name text NOT NULL,
  is_archived boolean NOT NULL DEFAULT false,UNIQUE(id,user_id));

CREATE TABLE private_isg.rollout(feature text PRIMARY KEY,
  read_enabled boolean NOT NULL DEFAULT false,write_enabled boolean NOT NULL DEFAULT false);
INSERT INTO private_isg.rollout(feature,read_enabled,write_enabled) VALUES
  ('personnel',true,true),('modules',true,true),('risk',true,true),('document_tracking',true,true);
CREATE TABLE private_isg.module_registry(module text PRIMARY KEY,
  read_enabled boolean NOT NULL DEFAULT false,write_enabled boolean NOT NULL DEFAULT false);
INSERT INTO private_isg.module_registry(module,read_enabled,write_enabled) VALUES
  ('katip_contract',true,true),('appointment',true,true),('emergency_plan',true,true),
  ('drill',true,true),('annual_work_plan',true,true),('board',true,true),
  ('equipment',true,true),('ppe',true,true),('site_visit',true,true),
  ('work_permit',true,true),('contractor',true,true);

-- The pilot audience. The real functions read p05_pilot_accounts/_grants; the
-- stand-ins keep the same signature and the same two answers.
CREATE TABLE private_isg.p05_pilot_accounts(actor_id uuid PRIMARY KEY,
  read_enabled boolean NOT NULL DEFAULT true,write_enabled boolean NOT NULL DEFAULT true);
CREATE TABLE private_isg.p05_pilot_grants(actor_id uuid NOT NULL,company_id uuid NOT NULL,
  PRIMARY KEY(actor_id,company_id));
CREATE TABLE private_isg.actor_stub(actor_id uuid);
CREATE FUNCTION private_isg.active_actor() RETURNS uuid
LANGUAGE sql STABLE SET search_path='' AS $$ SELECT actor_id FROM private_isg.actor_stub LIMIT 1 $$;
CREATE FUNCTION private_isg.p05_pilot_account_enabled(p_actor uuid,p_write boolean) RETURNS boolean
LANGUAGE sql STABLE SET search_path='' AS $$
  SELECT coalesce((SELECT a.read_enabled AND (NOT p_write OR a.write_enabled)
    FROM private_isg.p05_pilot_accounts a JOIN private_isg.rollout r ON r.feature='personnel'
    WHERE a.actor_id=p_actor AND r.read_enabled AND (NOT p_write OR r.write_enabled)),false) $$;
CREATE FUNCTION private_isg.p05_pilot_can_read(p_actor uuid,p_company uuid) RETURNS boolean
LANGUAGE sql STABLE SET search_path='' AS $$
  SELECT private_isg.p05_pilot_account_enabled(p_actor,false)
     AND (p_company IS NULL OR EXISTS(SELECT 1 FROM private_isg.p05_pilot_grants g
            JOIN public.companies c ON c.id=g.company_id AND c.user_id=g.actor_id
            WHERE g.actor_id=p_actor AND g.company_id=p_company)) $$;

-- The four modules that already own a notice window. The live values are
-- 60/30/14/30; the feed asks these rather than keeping its own copy.
CREATE FUNCTION private_isg.risk_notice_days() RETURNS integer
LANGUAGE sql IMMUTABLE SET search_path='' AS $$ SELECT 60 $$;
CREATE FUNCTION private_isg.emergency_notice_days() RETURNS integer
LANGUAGE sql IMMUTABLE SET search_path='' AS $$ SELECT 30 $$;
CREATE FUNCTION private_isg.drill_notice_days() RETURNS integer
LANGUAGE sql IMMUTABLE SET search_path='' AS $$ SELECT 14 $$;
CREATE FUNCTION private_isg.equipment_notice_days() RETURNS integer
LANGUAGE sql IMMUTABLE SET search_path='' AS $$ SELECT 30 $$;

CREATE TABLE private_isg.workplaces(id uuid NOT NULL,company_id uuid NOT NULL,owner_id uuid NOT NULL,
  name text NOT NULL,is_archived boolean NOT NULL DEFAULT false,UNIQUE(company_id,id),PRIMARY KEY(id));
CREATE TABLE private_isg.employees(id uuid PRIMARY KEY,company_id uuid NOT NULL,owner_id uuid NOT NULL,
  full_name text NOT NULL,is_archived boolean NOT NULL DEFAULT false);

CREATE TABLE private_isg.katip_contracts(contract_id uuid PRIMARY KEY,company_id uuid NOT NULL,
  owner_id uuid NOT NULL,workplace_id uuid,counterparty text NOT NULL,expert_contact text,scope text,
  starts_on date NOT NULL,ends_before date,term_state text,state text NOT NULL DEFAULT 'active',
  is_deleted boolean NOT NULL DEFAULT false);
CREATE TABLE private_isg.appointments(appointment_id uuid PRIMARY KEY,company_id uuid NOT NULL,
  employee_id uuid NOT NULL,kind text NOT NULL,scope_workplace_id uuid,starts_on date NOT NULL,
  ends_before date,is_deleted boolean NOT NULL DEFAULT false);
CREATE TABLE private_isg.emergency_plan_versions(plan_id uuid NOT NULL,version integer NOT NULL,
  company_id uuid NOT NULL,owner_id uuid,workplace_id uuid,scope text,prepared_on date,
  valid_until date,state text NOT NULL,is_deleted boolean NOT NULL DEFAULT false,
  PRIMARY KEY(plan_id,version));
CREATE TABLE private_isg.drill_records(drill_id uuid PRIMARY KEY,company_id uuid NOT NULL,
  workplace_id uuid,plan_id uuid,planned_on date,performed_on date,state text NOT NULL,
  is_deleted boolean NOT NULL DEFAULT false);
CREATE TABLE private_isg.annual_work_plans(plan_id uuid PRIMARY KEY,company_id uuid NOT NULL,
  owner_id uuid,workplace_id uuid,plan_year integer,state text,is_deleted boolean NOT NULL DEFAULT false);
CREATE TABLE private_isg.annual_work_plan_items(item_id uuid PRIMARY KEY,plan_id uuid NOT NULL,
  activity text NOT NULL,planned_on date,performed_on date,state text NOT NULL,
  is_deleted boolean NOT NULL DEFAULT false);
CREATE TABLE private_isg.board_meetings(meeting_id uuid PRIMARY KEY,company_id uuid NOT NULL,
  owner_id uuid,workplace_id uuid,planned_on date,held_on date,state text NOT NULL,
  is_deleted boolean NOT NULL DEFAULT false);
CREATE TABLE private_isg.board_decisions(decision_id uuid PRIMARY KEY,meeting_id uuid NOT NULL,
  decision_no integer,decision_text text,due_on date,state text NOT NULL,
  is_deleted boolean NOT NULL DEFAULT false);
CREATE TABLE private_isg.risk_assessments(assessment_id uuid PRIMARY KEY,company_id uuid NOT NULL,
  owner_id uuid NOT NULL,workplace_id uuid NOT NULL,current_version integer NOT NULL DEFAULT 0,
  base_assessment_on date,valid_until date);
CREATE TABLE private_isg.equipment_items(equipment_id uuid PRIMARY KEY,company_id uuid NOT NULL,
  owner_id uuid NOT NULL,workplace_id uuid NOT NULL,equipment_type text NOT NULL,serial_tag text NOT NULL,
  is_archived boolean NOT NULL DEFAULT false);
CREATE TABLE private_isg.equipment_inspections(inspection_id uuid PRIMARY KEY,equipment_id uuid NOT NULL,
  performed_on date NOT NULL,result text NOT NULL,next_due_on date);
CREATE TABLE private_isg.document_obligations(obligation_id uuid PRIMARY KEY,company_id uuid NOT NULL,
  owner_id uuid NOT NULL,workplace_id uuid,kind_code text,title text NOT NULL,
  notice_days integer NOT NULL DEFAULT 30,is_archived boolean NOT NULL DEFAULT false);
CREATE TABLE private_isg.document_obligation_records(record_id uuid PRIMARY KEY,obligation_id uuid NOT NULL,
  company_id uuid NOT NULL,owner_id uuid NOT NULL,issued_on date NOT NULL,valid_until date);
