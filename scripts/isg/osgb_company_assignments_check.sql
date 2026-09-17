\set ON_ERROR_STOP on
CREATE TEMP TABLE company_test_state(key text PRIMARY KEY,value text NOT NULL);
UPDATE private_isg.workspace_rollout SET read_enabled=true,write_enabled=true
  WHERE feature IN ('workspace_companies','workspace_assignments');

INSERT INTO private_isg.workspaces(id,kind,name,status,timezone,created_by_user_id) VALUES
  ('41000000-0000-4000-8000-000000000001','osgb','A OSGB','active','Europe/Istanbul','20000000-0000-0000-0000-000000000001'),
  ('41000000-0000-4000-8000-000000000002','osgb','B OSGB','active','Europe/Istanbul','20000000-0000-0000-0000-000000000004');
INSERT INTO private_isg.workspace_memberships(id,workspace_id,user_id,role,status,is_practicing_expert) VALUES
  ('42000000-0000-4000-8000-000000000001','41000000-0000-4000-8000-000000000001','20000000-0000-0000-0000-000000000001','owner','active',false),
  ('42000000-0000-4000-8000-000000000002','41000000-0000-4000-8000-000000000001','20000000-0000-0000-0000-000000000003','expert','active',true),
  ('42000000-0000-4000-8000-000000000003','41000000-0000-4000-8000-000000000001','20000000-0000-0000-0000-000000000002','expert','active',true),
  ('42000000-0000-4000-8000-000000000004','41000000-0000-4000-8000-000000000002','20000000-0000-0000-0000-000000000004','owner','active',false);

SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
WITH made AS (
  SELECT public.isg_workspace_company_create_v1('43000000-0000-4000-8000-000000000001',
    '41000000-0000-4000-8000-000000000001','A Firması','high') body
) INSERT INTO company_test_state VALUES('company',(SELECT body->>'company_id' FROM made));
DO $$ DECLARE body jsonb; BEGIN
  body:=public.isg_workspace_company_create_v1('43000000-0000-4000-8000-000000000001',
    '41000000-0000-4000-8000-000000000001','A Firması','high');
  IF (body->>'replayed')::boolean IS NOT TRUE OR
     (SELECT count(*) FROM private_isg.workspace_companies)<>1 THEN RAISE EXCEPTION 'company replay failed: %',body; END IF;
END $$;

-- Unassigned experts see an empty portfolio.
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000003',false);
DO $$ DECLARE body jsonb; BEGIN
  body:=public.isg_workspace_company_list_v1('41000000-0000-4000-8000-000000000001',NULL,20);
  IF jsonb_array_length(body->'rows')<>0 THEN RAISE EXCEPTION 'unassigned expert saw company'; END IF;
END $$;

-- Another workspace owner cannot read or assign A's company.
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000004',false);
DO $$ BEGIN
  PERFORM public.isg_workspace_company_list_v1('41000000-0000-4000-8000-000000000001',NULL,20);
  RAISE EXCEPTION 'EXPECTED_CROSS_WORKSPACE_DENIAL';
EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'ACCESS_DENIED' THEN RAISE; END IF; END $$;

-- Owner assigns the practicing expert and the portfolio becomes visible.
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
WITH made AS (
  SELECT public.isg_workspace_assignment_mutate_v1('43000000-0000-4000-8000-000000000002',
    '41000000-0000-4000-8000-000000000001',(SELECT value::uuid FROM company_test_state WHERE key='company'),
    NULL,'42000000-0000-4000-8000-000000000002',0,'create','primary',clock_timestamp()-interval '1 hour',NULL,'ilk atama') body
) INSERT INTO company_test_state VALUES('assignment',(SELECT body->>'assignment_id' FROM made
    WHERE body->>'schema_version'='1' AND body->>'user_id'='20000000-0000-0000-0000-000000000003'
      AND body->>'membership_role'='expert' AND body->>'membership_status'='active'));
DO $$ DECLARE body jsonb; BEGIN
  body:=public.isg_workspace_assignment_list_v1(
    '41000000-0000-4000-8000-000000000001',
    (SELECT value::uuid FROM company_test_state WHERE key='company'),'current',NULL,20);
  IF body->>'schema_version'<>'1' OR body->>'workspace_id'<>'41000000-0000-4000-8000-000000000001' OR
     jsonb_array_length(body->'rows')<>1 OR
     body->'rows'->0->>'membership_id'<>'42000000-0000-4000-8000-000000000002' OR
     body->'rows'->0->>'membership_status'<>'active' THEN
    RAISE EXCEPTION 'assignment list failed: %',body; END IF;
END $$;
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000003',false);
DO $$ DECLARE body jsonb; BEGIN
  body:=public.isg_workspace_company_list_v1('41000000-0000-4000-8000-000000000001',NULL,20);
  IF jsonb_array_length(body->'rows')<>1 OR body->'rows'->0->>'name'<>'A Firması' THEN
    RAISE EXCEPTION 'assigned expert portfolio failed: %',body; END IF;
END $$;

-- The same expert/company interval cannot overlap, even with another role.
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
DO $$ BEGIN
  PERFORM public.isg_workspace_assignment_mutate_v1('43000000-0000-4000-8000-000000000003',
    '41000000-0000-4000-8000-000000000001',(SELECT value::uuid FROM company_test_state WHERE key='company'),
    NULL,'42000000-0000-4000-8000-000000000002',0,'create','support',clock_timestamp(),NULL,'çakışan atama');
  RAISE EXCEPTION 'EXPECTED_ASSIGNMENT_OVERLAP';
EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'ASSIGNMENT_OVERLAP' THEN RAISE; END IF; END $$;

DO $$ DECLARE body jsonb; BEGIN
  body:=public.isg_workspace_assignment_mutate_v1('43000000-0000-4000-8000-000000000004',
    '41000000-0000-4000-8000-000000000001',(SELECT value::uuid FROM company_test_state WHERE key='company'),
    (SELECT value::uuid FROM company_test_state WHERE key='assignment'),NULL,0,'end',NULL,NULL,
    clock_timestamp(),'sorumluluk sona erdi');
  IF (body->>'version')::integer<>1 OR body->>'ends_at' IS NULL THEN RAISE EXCEPTION 'assignment end failed: %',body; END IF;
END $$;
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000003',false);
DO $$ DECLARE body jsonb; BEGIN
  body:=public.isg_workspace_company_list_v1('41000000-0000-4000-8000-000000000001',NULL,20);
  IF jsonb_array_length(body->'rows')<>0 THEN RAISE EXCEPTION 'ended assignment still visible'; END IF;
END $$;
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',false);
DO $$ DECLARE body jsonb; BEGIN
  body:=public.isg_workspace_assignment_list_v1(
    '41000000-0000-4000-8000-000000000001',
    (SELECT value::uuid FROM company_test_state WHERE key='company'),'ended',NULL,20);
  IF jsonb_array_length(body->'rows')<>1 OR body->'rows'->0->>'version'<>'1' THEN
    RAISE EXCEPTION 'ended assignment history failed: %',body; END IF;
END $$;

DO $$ BEGIN
  IF has_table_privilege('authenticated','private_isg.workspace_companies','SELECT') OR
     has_table_privilege('service_role','private_isg.company_assignments','UPDATE') OR
     (SELECT count(*) FROM private_isg.company_assignment_events)<>2 THEN
    RAISE EXCEPTION 'company assignment grant/history failed'; END IF;
  RAISE NOTICE 'ok workspace company idempotency, portfolio isolation, assignment visibility, overlap and history';
END $$;
