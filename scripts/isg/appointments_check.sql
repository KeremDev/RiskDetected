-- Checks for the P10 appointment client boundary. Disposable database only.
-- Expected values are written here by hand; none is read back from the function
-- under test to decide what the function under test should say.
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

SELECT set_config('test.actor',:'A',false);

-- 1. The slice adds no switch of its own and opens none.
SELECT pg_temp.expect_refusal(format('SELECT public.isg_appointments_read_v1(%L,''list'',NULL,NULL,NULL,NULL,NULL,10,0)',:'CA'),
  'FEATURE_UNAVAILABLE','a closed feature refuses ahead of the module');
UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='modules';
SELECT pg_temp.expect_refusal(format('SELECT public.isg_appointments_read_v1(%L,''list'',NULL,NULL,NULL,NULL,NULL,10,0)',:'CA'),
  'MODULE_UNAVAILABLE','a closed module refuses on its own');
UPDATE private_isg.module_registry SET read_enabled=true,write_enabled=true WHERE module='appointment';

-- 2. The ownership check the core function never had.
SELECT pg_temp.expect_refusal(format('SELECT public.isg_appointments_read_v1(%L,''list'',NULL,NULL,NULL,NULL,NULL,10,0)',:'CB'),
  'ACCESS_DENIED','another owner company is refused');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.appt(%L,'record_appointment',jsonb_build_object(
  'employee_id',%L,'kind','representative','workplace_id',%L,'starts_on',current_date::text,
  'basis','elected'))$q$,:'CA',:'OUTSIDER',:'WA'),
  'ACCESS_DENIED','an employee of another company is refused');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.appt(%L,'record_appointment',jsonb_build_object(
  'employee_id',%L,'kind','representative','workplace_id','40000000-0000-0000-0000-000000000002',
  'starts_on',current_date::text,'basis','elected'))$q$,:'CA',:'E1'),
  'ACCESS_DENIED','a workplace of another company is refused');

-- 3. Saying why the person holds the role is required.
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.appt(%L,'record_appointment',jsonb_build_object(
  'employee_id',%L,'kind','representative','workplace_id',%L,'starts_on',current_date::text))$q$,
  :'CA',:'E1',:'WA'),
  'BASIS_REQUIRED','an appointment with no stated basis is refused');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.appt(%L,'record_appointment',jsonb_build_object(
  'employee_id',%L,'kind','representative','workplace_id',%L,'starts_on',current_date::text,
  'basis','atandi'))$q$,:'CA',:'E1',:'WA'),
  'BASIS_REQUIRED','and a basis the schema does not know is refused');

-- 4. Nobody is ever labelled qualified, and the product never says how many
--    are needed.
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.appt(%L,'record_appointment',jsonb_build_object(
  'employee_id',%L,'kind','representative','workplace_id',%L,'starts_on',current_date::text,
  'basis','elected','qualification_verified',true))$q$,:'CA',:'E1',:'WA'),
  'PAYLOAD_NOT_ALLOWED','a qualification claim is refused');
SELECT pg_temp.expect((SELECT public.isg_appointments_read_v1(:'CA','catalog',NULL,NULL,NULL,NULL,NULL,NULL,NULL)
  ->>'qualification_check_available'),'false','the catalogue says no qualification is checked');
SELECT pg_temp.expect((SELECT public.isg_appointments_read_v1(:'CA','catalog',NULL,NULL,NULL,NULL,NULL,NULL,NULL)
  ->>'required_count_known'),'false','and that the required number is unknown');
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.columns
  WHERE table_schema='private_isg' AND table_name='appointments'
    AND column_name IN ('qualification_verified','is_qualified','required_count')),
  '0','the schema has nowhere to put a qualification');

-- 5. An appointment is recorded, and its state comes from its own dates.
CREATE TEMP TABLE rep AS SELECT (pg_temp.appt(:'CA','record_appointment',jsonb_build_object(
  'employee_id',:'E1','kind','representative','workplace_id',:'WA',
  'starts_on',(current_date-30)::text,'basis','elected',
  'basis_note','Calisan secimi tutanagi 2026/3','letter_location','Personel dosyasi'))
  ->>'appointment_id')::uuid AS id;
SELECT pg_temp.expect((SELECT public.isg_appointments_read_v1(:'CA','detail',NULL,NULL,NULL,NULL,(SELECT id FROM rep),NULL,NULL)
  ->'row'->>'state'),'active','an appointment that has begun and not ended is active');
SELECT pg_temp.expect((SELECT public.isg_appointments_read_v1(:'CA','detail',NULL,NULL,NULL,NULL,(SELECT id FROM rep),NULL,NULL)
  ->'row'->>'basis'),'elected','the basis is on the record');
SELECT pg_temp.expect((SELECT public.isg_appointments_read_v1(:'CA','detail',NULL,NULL,NULL,NULL,(SELECT id FROM rep),NULL,NULL)
  ->'row'->>'qualification_verified'),'false','and the row states that nothing was verified');
SELECT pg_temp.expect((SELECT public.isg_appointments_read_v1(:'CA','detail',NULL,NULL,NULL,NULL,(SELECT id FROM rep),NULL,NULL)
  ->'row'->>'letter_stored'),'false','the letter itself is not held here');
SELECT pg_temp.expect((SELECT public.isg_appointments_read_v1(:'CA','detail',NULL,NULL,NULL,NULL,(SELECT id FROM rep),NULL,NULL)
  ->'row'->>'letter_location'),'Personel dosyasi','only where it is');
-- A future start is upcoming, never active.
CREATE TEMP TABLE later AS SELECT (pg_temp.appt(:'CA','record_appointment',jsonb_build_object(
  'employee_id',:'E2','kind','first_aid','workplace_id',:'WA',
  'starts_on',(current_date+30)::text,'basis','appointed'))->>'appointment_id')::uuid AS id;
SELECT pg_temp.expect((SELECT public.isg_appointments_read_v1(:'CA','detail',NULL,NULL,NULL,NULL,(SELECT id FROM later),NULL,NULL)
  ->'row'->>'state'),'upcoming','an appointment that starts later is upcoming');

-- 6. The same person cannot hold the same role twice in the same scope at once.
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.appt(%L,'record_appointment',jsonb_build_object(
  'employee_id',%L,'kind','representative','workplace_id',%L,'starts_on',(current_date-10)::text,
  'basis','elected'))$q$,:'CA',:'E1',:'WA'),
  'APPOINTMENT_OVERLAP','an overlapping appointment in the same role and scope is refused');
-- The same person in another role, or the same role in another scope, is fine.
SELECT pg_temp.expect((pg_temp.appt(:'CA','record_appointment',jsonb_build_object(
  'employee_id',:'E1','kind','fire_team','workplace_id',:'WA','starts_on',(current_date-10)::text,
  'basis','appointed'))->'row'->>'state'),'active','the same person in another role is allowed');
SELECT pg_temp.expect((pg_temp.appt(:'CA','record_appointment',jsonb_build_object(
  'employee_id',:'E1','kind','representative','workplace_id',:'WB','starts_on',(current_date-10)::text,
  'basis','elected'))->'row'->>'state'),'active','and the same role in another workplace is allowed');

-- 7. Ending an appointment, and correcting the end date.
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.appt(%L,'end_appointment',jsonb_build_object(
  'appointment_id',%L,'ends_before',(current_date-60)::text))$q$,:'CA',(SELECT id FROM rep)),
  'VALIDATION_ERROR','an end before the start is refused');
SELECT pg_temp.expect((pg_temp.appt(:'CA','end_appointment',jsonb_build_object(
  'appointment_id',(SELECT id FROM rep),'ends_before',(current_date-1)::text))->'row'->>'state'),
  'ended','ending it closes the appointment');
SELECT pg_temp.expect((pg_temp.appt(:'CA','end_appointment',jsonb_build_object(
  'appointment_id',(SELECT id FROM rep),'ends_before',(current_date-1)::text))->'answer'->>'replayed'),
  'true','and ending it again with the same date replays');
-- A corrected end date is allowed, and the constraint guards it.
SELECT pg_temp.expect((pg_temp.appt(:'CA','end_appointment',jsonb_build_object(
  'appointment_id',(SELECT id FROM rep),'ends_before',(current_date-5)::text))->'row'->>'ends_before'),
  (current_date-5)::text,'a mistyped end date can be corrected');
-- Once it has ended, the same person may hold the role again from a later day.
CREATE TEMP TABLE again AS SELECT (pg_temp.appt(:'CA','record_appointment',jsonb_build_object(
  'employee_id',:'E1','kind','representative','workplace_id',:'WA',
  'starts_on',(current_date-4)::text,'basis','elected'))->>'appointment_id')::uuid AS id;
SELECT pg_temp.expect((SELECT public.isg_appointments_read_v1(:'CA','detail',NULL,NULL,NULL,NULL,(SELECT id FROM again),NULL,NULL)
  ->'row'->>'state'),'active','the role can be held again after it ended');
-- And a correction cannot be stretched back over that later appointment.
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.appt(%L,'end_appointment',jsonb_build_object(
  'appointment_id',%L,'ends_before',(current_date+10)::text))$q$,:'CA',(SELECT id FROM rep)),
  'APPOINTMENT_OVERLAP','stretching an end date over the next appointment is refused');

-- 8. An appointment of another company cannot be ended.
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000002',false);
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.appt(%L,'end_appointment',jsonb_build_object(
  'appointment_id',%L,'ends_before',current_date::text))$q$,:'CB',(SELECT id FROM again)),
  'ACCESS_DENIED','an appointment outside the company is refused');
SELECT set_config('test.actor',:'A',false);

-- 9. The tally can never disagree with the list it counts.
SELECT pg_temp.expect(
  (SELECT sum((value)::int)::text FROM jsonb_each_text(
    public.isg_appointments_read_v1(NULL,'list',NULL,NULL,NULL,NULL,NULL,100,0)->'counts')),
  (SELECT public.isg_appointments_read_v1(NULL,'list',NULL,NULL,NULL,NULL,NULL,100,0)->>'total'),
  'the account counts add up to the rows they count');
SELECT pg_temp.expect((SELECT public.isg_appointments_read_v1(NULL,'list',NULL,'ended',NULL,NULL,NULL,100,0)->>'total'),
  '1','the ended filter agrees with its counter');
SELECT pg_temp.expect((SELECT public.isg_appointments_read_v1(NULL,'list',NULL,NULL,NULL,'representative',NULL,100,0)->>'total'),
  '3','the role filter counts only that role');
SELECT pg_temp.expect_refusal('SELECT public.isg_appointments_read_v1(NULL,''list'',NULL,NULL,NULL,''baskan'',NULL,100,0)',
  'VALIDATION_ERROR','a role the schema does not know is refused as a filter');
SELECT pg_temp.expect((SELECT public.isg_appointments_read_v1(NULL,'list',NULL,NULL,NULL,NULL,NULL,100,0)
  ->>'compliance_verdict'),NULL,'the list states no compliance verdict');
SELECT pg_temp.expect((SELECT public.isg_appointments_read_v1(NULL,'list',NULL,NULL,NULL,NULL,NULL,100,0)
  ->>'required_count_known'),'false','and never says how many are needed');

-- 10. The same mutation id replays instead of writing twice.
SELECT pg_temp.expect((public.isg_appointments_mutate_v1(:'CA','record_appointment',
  '00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000000000c1',
  jsonb_build_object('employee_id',:'E2','kind','support_staff','workplace_id',:'WA',
    'starts_on',current_date::text,'basis','appointed'))->>'replayed'),'false','first save writes');
SELECT pg_temp.expect((public.isg_appointments_mutate_v1(:'CA','record_appointment',
  '00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000000000c1',
  jsonb_build_object('employee_id',:'E2','kind','support_staff','workplace_id',:'WA',
    'starts_on',current_date::text,'basis','appointed'))->>'replayed'),'true','the same mutation replays');
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.appointments WHERE kind='support_staff'),
  '1','and writes only once');
SELECT pg_temp.expect_refusal(format($q$SELECT public.isg_appointments_mutate_v1(%L,'record_appointment',
  '00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000000000c1',
  jsonb_build_object('employee_id',%L,'kind','team_member','workplace_id',%L,
    'starts_on',current_date::text,'basis','appointed'))$q$,:'CA',:'E2',:'WA'),
  'IDEMPOTENCY_CONFLICT','the same id with a different body is refused');

-- 11. No table grant reaches a client role, and the wrappers are the only way in.
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.role_table_grants
  WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role')),
  '0','no client role holds a table grant in private_isg');
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.routine_privileges
  WHERE routine_schema='public' AND grantee='authenticated' AND routine_name LIKE 'isg_appointments%'),
  '2','exactly the two public wrappers are callable');
SELECT 'ALL APPOINTMENT CHECKS PASSED' AS result;
