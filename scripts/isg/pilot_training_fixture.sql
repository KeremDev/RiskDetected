-- Run only in a fresh, disposable local database, never on a project database.
CREATE SCHEMA private_isg;
CREATE TABLE public.companies(id uuid PRIMARY KEY,user_id uuid NOT NULL,is_archived boolean DEFAULT false,UNIQUE(id,user_id));
CREATE TABLE private_isg.employees(id uuid PRIMARY KEY,company_id uuid,owner_id uuid,full_name text,is_archived boolean DEFAULT false,UNIQUE(company_id,id));
CREATE FUNCTION private_isg.require_company(p_company uuid,p_write boolean) RETURNS uuid
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE actor uuid:=nullif(current_setting('test.actor',true),'')::uuid;
BEGIN
  IF actor IS NULL OR current_setting('test.expired',true)='true' OR
    NOT EXISTS(SELECT 1 FROM public.companies WHERE id=p_company AND user_id=actor AND (NOT p_write OR NOT is_archived)) THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  RETURN actor;
END $$;
INSERT INTO public.companies VALUES
('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',false),
('10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002',false);
INSERT INTO private_isg.employees VALUES
('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Test Person',false),
('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','Other Person',false);
