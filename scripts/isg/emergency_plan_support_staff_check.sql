-- Checks for the emergency plan's support-staff suggestion list. Disposable
-- database only. Expected values are written here by hand; none is read back
-- from the function under test to decide what the function under test should
-- say. Applies module_core + the appointments client slice + the emergency
-- plans client slice + this slice, in that order.
\set ON_ERROR_STOP on
\set A '20000000-0000-0000-0000-000000000001'
\set CA '10000000-0000-0000-0000-000000000001'
\set CB '10000000-0000-0000-0000-000000000002'
\set WA '40000000-0000-0000-0000-000000000001'
\set WB '40000000-0000-0000-0000-000000000003'
\set E1 '30000000-0000-0000-0000-000000000001'
\set E2 '30000000-0000-0000-0000-000000000002'
\set OUTSIDER '30000000-0000-0000-0000-000000000009'

CREATE FUNCTION pg_temp.expect_refusal(sql text,want text,label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE sql;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM=want THEN RAISE NOTICE 'ok   % (%)',label,want; RETURN; END IF;
    RAISE EXCEPTION '% expected % got %',label,want,SQLERRM;
  END;
  RAISE EXCEPTION '% expected % but the call succeeded',label,want;
END $$;
CREATE FUNCTION pg_temp.expect(got text,want text,label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF got IS NOT DISTINCT FROM want THEN RAISE NOTICE 'ok   % (%)',label,coalesce(want,'NULL'); RETURN; END IF;
  RAISE EXCEPTION '% expected % got %',label,coalesce(want,'NULL'),coalesce(got,'NULL');
END $$;
CREATE FUNCTION pg_temp.appt(p_company uuid,p_action text,p_payload jsonb) RETURNS jsonb
LANGUAGE sql AS $$
  SELECT public.isg_appointments_mutate_v1(p_company,p_action,gen_random_uuid(),gen_random_uuid(),p_payload) $$;
CREATE FUNCTION pg_temp.catalog(p_company uuid) RETURNS jsonb
LANGUAGE sql AS $$ SELECT public.isg_emergency_plans_read_v1(p_company,'catalog',NULL,NULL,NULL,NULL,NULL,NULL) $$;
CREATE FUNCTION pg_temp.names(p_company uuid) RETURNS text[]
LANGUAGE sql AS $$
  SELECT coalesce(array_agg(x->>'full_name' ORDER BY x->>'full_name'),'{}')
    FROM jsonb_array_elements(pg_temp.catalog(p_company)->'support_staff') x $$;

SELECT set_config('test.actor',:'A',false);
UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='modules';
UPDATE private_isg.module_registry SET read_enabled=true,write_enabled=true WHERE module IN ('appointment','emergency_plan');

-- 1. No support staff on record yet: the list is empty, not an error.
SELECT pg_temp.expect(pg_temp.names(:'CA')::text,'{}','with no appointments the suggestion list is empty');

-- 2. A support_staff appointment appears; a representative does not.
SELECT pg_temp.appt(:'CA','record_appointment',jsonb_build_object(
  'employee_id',:'E1','kind','support_staff','workplace_id',:'WA','starts_on',(current_date-30)::text,
  'basis','appointed'));
SELECT pg_temp.appt(:'CA','record_appointment',jsonb_build_object(
  'employee_id',:'E2','kind','representative','workplace_id',:'WA','starts_on',(current_date-30)::text,
  'basis','elected'));
SELECT pg_temp.expect(pg_temp.names(:'CA')::text,'{"Ali Calisan"}','only the support staff appointment is suggested');
SELECT pg_temp.expect((SELECT (x->>'appointment_id') IS NOT NULL FROM
    jsonb_array_elements(pg_temp.catalog(:'CA')->'support_staff') x LIMIT 1)::text,
  'true','each suggestion carries the appointment it came from');
SELECT pg_temp.expect((SELECT x->>'workplace_name' FROM
    jsonb_array_elements(pg_temp.catalog(:'CA')->'support_staff') x LIMIT 1),
  'Merkez','and the workplace the appointment is scoped to');

-- 3. A second, ended support_staff appointment does not double the name, and
--    an appointment that has already ended is not suggested.
SELECT pg_temp.appt(:'CA','record_appointment',jsonb_build_object(
  'employee_id',:'E2','kind','support_staff','workplace_id',:'WB','starts_on',(current_date-400)::text,
  'ends_before',(current_date-1)::text,'basis','appointed'));
SELECT pg_temp.expect(pg_temp.names(:'CA')::text,'{"Ali Calisan"}','an ended support staff appointment is not suggested');

-- 4. A future-starting one still counts: "holds the role" is not the same as
--    "the role has already started"; scope stays company-wide.
SELECT pg_temp.appt(:'CA','record_appointment',jsonb_build_object(
  'employee_id',:'E2','kind','support_staff','workplace_id',:'WB','starts_on',(current_date+10)::text,
  'basis','appointed'));
SELECT pg_temp.expect(pg_temp.names(:'CA')::text,'{"Ali Calisan","Veli Calisan"}',
  'a support staff appointment that has not started yet is still suggested');

-- 5. Another owner's company stays unreachable through this catalog too, the
--    same as through every other read on this slice.
SELECT pg_temp.expect_refusal(format('SELECT public.isg_emergency_plans_read_v1(%L,''catalog'',NULL,NULL,NULL,NULL,NULL,NULL)',:'CB'),
  'ACCESS_DENIED','another owner''s company is refused by the catalog as well');

-- 6. A closed appointment module empties the suggestion list without failing
--    the emergency plan catalog itself.
UPDATE private_isg.module_registry SET read_enabled=false,write_enabled=false WHERE module='appointment';
SELECT pg_temp.expect(pg_temp.names(:'CA')::text,'{}','a closed appointment module suggests nothing');
SELECT pg_temp.expect((pg_temp.catalog(:'CA')->>'kind'),'catalog',
  'and the emergency plan catalog itself still answers');
UPDATE private_isg.module_registry SET read_enabled=true,write_enabled=true WHERE module='appointment';
SELECT pg_temp.expect(pg_temp.names(:'CA')::text,'{"Ali Calisan","Veli Calisan"}',
  'reopening the module brings the suggestions back');

-- 7. With no company named, there is nothing to suggest: the account-wide
--    read never mixes one company's appointments into another's picker.
SELECT pg_temp.expect((pg_temp.catalog(NULL)->'support_staff')::text,'[]',
  'the whole-account catalog offers no support staff at all');

-- 8. Picking a suggestion only lends a name; publishing still freezes the
--    team as a plain snapshot, unlinked to the appointment.
CREATE TEMP TABLE plan1 AS SELECT (public.isg_emergency_plans_mutate_v1(:'CA','publish_plan',
  gen_random_uuid(),gen_random_uuid(),jsonb_build_object(
    'workplace_id',:'WA','scope','Ana bina','prepared_on',current_date::text,
    'team',jsonb_build_array(jsonb_build_object('full_name','Ali Calisan','role','other',
      'contact','0555'))))->>'plan_id')::uuid AS id;
SELECT pg_temp.expect((SELECT public.isg_emergency_plans_read_v1(:'CA','detail',NULL,NULL,NULL,
    (SELECT id FROM plan1),NULL,NULL)->'row'->'team'->0->>'full_name'),'Ali Calisan',
  'the picked name lands in the team exactly as any typed name would');
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.columns
    WHERE table_schema='private_isg' AND table_name='emergency_plan_versions'
      AND column_name IN ('appointment_id','employee_id')),'0',
  'the plan itself stores no pointer back to any appointment');

-- 9. The client boundary is unchanged: no table grant, no new function reaches
--    a client directly.
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.role_table_grants
  WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role')),
  '0','no client role holds a table grant in private_isg');
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.routine_privileges
  WHERE routine_schema='public' AND grantee='authenticated' AND routine_name LIKE 'isg_emergency_plans%'),
  '2','still exactly the two public wrappers are callable');

SELECT 'ALL EMERGENCY PLAN SUPPORT STAFF CHECKS PASSED' AS result;
