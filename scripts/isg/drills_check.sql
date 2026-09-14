-- Checks for the P10 drill client boundary. Disposable database only.
-- Expected values are written here by hand; none is read back from the function
-- under test to decide what the function under test should say.
\set ON_ERROR_STOP on
\set A '20000000-0000-0000-0000-000000000001'
\set CA '10000000-0000-0000-0000-000000000001'
\set CB '10000000-0000-0000-0000-000000000002'
\set WA '40000000-0000-0000-0000-000000000001'
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
CREATE FUNCTION pg_temp.drill(p_company uuid,p_action text,p_payload jsonb) RETURNS jsonb
LANGUAGE sql AS $$
  SELECT public.isg_drills_mutate_v1(p_company,p_action,gen_random_uuid(),gen_random_uuid(),p_payload) $$;
CREATE FUNCTION pg_temp.emergency(p_company uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE sql AS $$
  SELECT public.isg_emergency_plans_mutate_v1(p_company,'publish_plan',gen_random_uuid(),gen_random_uuid(),p_payload) $$;

SELECT set_config('test.actor',:'A',false);
UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='modules';
UPDATE private_isg.module_registry SET read_enabled=true,write_enabled=true WHERE module='emergency_plan';

-- 1. The slice adds no switch of its own, and the drill module is its own.
SELECT pg_temp.expect((SELECT read_enabled::text FROM private_isg.module_registry WHERE module='drill'),
  'false','the drill module is still closed');
SELECT pg_temp.expect_refusal(format('SELECT public.isg_drills_read_v1(%L,''list'',NULL,NULL,NULL,NULL,10,0)',:'CA'),
  'MODULE_UNAVAILABLE','a closed module refuses even while another is open');
UPDATE private_isg.module_registry SET read_enabled=true,write_enabled=true WHERE module='drill';

-- 2. A drill needs a plan in force to point at.
SELECT pg_temp.expect((SELECT jsonb_array_length(public.isg_drills_read_v1(:'CA','catalog',NULL,NULL,NULL,NULL,NULL,NULL)
  ->'plans')::text),'0','with no plan there is nothing to rehearse');
CREATE TEMP TABLE plan1 AS SELECT (pg_temp.emergency(:'CA',jsonb_build_object(
  'workplace_id',:'WA','scope','Tesis geneli','prepared_on',(current_date-30)::text,
  'valid_until',(current_date+300)::text,
  'team',jsonb_build_array(jsonb_build_object('full_name','Ayse','role','coordinator')),
  'review_note','Isveren talimati'))->>'plan_id')::uuid AS id;
SELECT pg_temp.expect((SELECT jsonb_array_length(public.isg_drills_read_v1(:'CA','catalog',NULL,NULL,NULL,NULL,NULL,NULL)
  ->'plans')::text),'1','a published plan can be rehearsed');

-- 3. The ownership check the core functions never had.
SELECT pg_temp.expect_refusal(format('SELECT public.isg_drills_read_v1(%L,''list'',NULL,NULL,NULL,NULL,10,0)',:'CB'),
  'ACCESS_DENIED','another owner company is refused');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.drill(%L,'plan_drill',jsonb_build_object(
  'plan_id','99999999-9999-4999-a999-999999999999','planned_on',current_date::text))$q$,:'CA'),
  'ACCESS_DENIED','a plan this company does not hold is refused');

-- 4. The client cannot name the plan version: the boundary pins the one in force.
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.drill(%L,'plan_drill',jsonb_build_object(
  'plan_id',%L,'plan_version',1,'planned_on',current_date::text))$q$,:'CA',(SELECT id FROM plan1)),
  'PAYLOAD_NOT_ALLOWED','a named plan version is refused');

-- 5. Planning is not performing.
CREATE TEMP TABLE upcoming AS SELECT (pg_temp.drill(:'CA','plan_drill',jsonb_build_object(
  'plan_id',(SELECT id FROM plan1),'planned_on',(current_date+60)::text))->>'drill_id')::uuid AS id;
SELECT pg_temp.expect((SELECT public.isg_drills_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM upcoming),NULL,NULL)
  ->'row'->>'state'),'scheduled','a drill planned for later is scheduled');
SELECT pg_temp.expect((SELECT public.isg_drills_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM upcoming),NULL,NULL)
  ->'row'->>'performed'),'false','and it is not performed');
-- A date that has passed is a drill that was missed, never one that was held.
CREATE TEMP TABLE missed AS SELECT (pg_temp.drill(:'CA','plan_drill',jsonb_build_object(
  'plan_id',(SELECT id FROM plan1),'planned_on',(current_date-5)::text))->>'drill_id')::uuid AS id;
SELECT pg_temp.expect((SELECT public.isg_drills_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM missed),NULL,NULL)
  ->'row'->>'state'),'overdue','a planned date that passed is overdue');
SELECT pg_temp.expect((SELECT public.isg_drills_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM missed),NULL,NULL)
  ->'row'->>'performed'),'false','and still not performed');
-- The warning window is 14 days.
CREATE TEMP TABLE soon AS SELECT (pg_temp.drill(:'CA','plan_drill',jsonb_build_object(
  'plan_id',(SELECT id FROM plan1),'planned_on',(current_date+14)::text))->>'drill_id')::uuid AS id;
SELECT pg_temp.expect((SELECT public.isg_drills_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM soon),NULL,NULL)
  ->'row'->>'state'),'due_soon','the last day of the window is due_soon');

-- 6. Recording a result: dates and participants belong to the server.
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.drill(%L,'record_result',jsonb_build_object(
  'drill_id',%L,'performed_on',(current_date+1)::text,'participants',jsonb_build_array(%L)))$q$,
  :'CA',(SELECT id FROM missed),:'E1'),
  'PERFORMED_IN_THE_FUTURE','a drill held tomorrow is refused');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.drill(%L,'record_result',jsonb_build_object(
  'drill_id',%L,'performed_on',current_date::text,'participants',jsonb_build_array(%L)))$q$,
  :'CA',(SELECT id FROM missed),:'OUTSIDER'),
  'PARTICIPANT_OUT_OF_SCOPE','a participant from another company is refused');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.drill(%L,'record_result',jsonb_build_object(
  'drill_id',%L,'performed_on',current_date::text,'participants',jsonb_build_array()))$q$,
  :'CA',(SELECT id FROM missed)),
  'VALIDATION_ERROR','an empty participant list is refused');

-- 7. Who was there is frozen at the moment it is recorded.
SELECT pg_temp.drill(:'CA','record_result',jsonb_build_object('drill_id',(SELECT id FROM missed),
  'performed_on',(current_date-4)::text,
  'participants',jsonb_build_array(:'E1',:'E2'),
  'observation','Tahliye 4 dakikada tamamlandi','improvement','Ikinci cikis levhasi yenilenecek'));
SELECT pg_temp.expect((SELECT public.isg_drills_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM missed),NULL,NULL)
  ->'row'->>'state'),'performed','the record says it was performed');
SELECT pg_temp.expect((SELECT public.isg_drills_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM missed),NULL,NULL)
  ->'row'->>'participant_count'),'2','both people are on the record');
SELECT pg_temp.expect((SELECT public.isg_drills_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM missed),NULL,NULL)
  ->'row'->>'participants_snapshotted'),'true','and the names were frozen, not linked');
CREATE TEMP TABLE before_rename AS
  SELECT participant_snapshot FROM private_isg.drill_records WHERE drill_id=(SELECT id FROM missed);
-- Renaming and archiving the register afterwards changes nothing here.
UPDATE private_isg.employees SET full_name='Ali Degisti',is_archived=true WHERE id=:'E1';
SELECT pg_temp.expect((SELECT participant_snapshot::text FROM private_isg.drill_records
  WHERE drill_id=(SELECT id FROM missed)),
  (SELECT participant_snapshot::text FROM before_rename),
  'renaming a person later does not edit a performed drill');
SELECT pg_temp.expect((SELECT public.isg_drills_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM missed),NULL,NULL)
  ->'row'->'participants'->0->>'full_name'),'Ali Calisan','the read still shows the name of the day');

-- 8. A performed drill is closed.
SELECT pg_temp.expect((pg_temp.drill(:'CA','record_result',jsonb_build_object('drill_id',(SELECT id FROM missed),
  'performed_on',(current_date-1)::text,'participants',jsonb_build_array(:'E2')))
  ->'answer'->>'replayed'),'true','a second result is a replay, not a rewrite');
SELECT pg_temp.expect((SELECT performed_on::text FROM private_isg.drill_records WHERE drill_id=(SELECT id FROM missed)),
  (current_date-4)::text,'and the first date stands');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.drill(%L,'cancel_drill',jsonb_build_object(
  'drill_id',%L,'reason','Vazgectik'))$q$,:'CA',(SELECT id FROM missed)),
  'DRILL_PERFORMED','a drill that was held is not withdrawn');

-- 9. Cancelling a planned drill demands a reason.
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.drill(%L,'cancel_drill',jsonb_build_object(
  'drill_id',%L))$q$,:'CA',(SELECT id FROM upcoming)),
  'VALIDATION_ERROR','cancelling with no reason is refused');
SELECT pg_temp.expect((pg_temp.drill(:'CA','cancel_drill',jsonb_build_object('drill_id',(SELECT id FROM upcoming),
  'reason','Uretim duruslari nedeniyle ertelendi'))->'answer'->>'state'),
  'cancelled','a planned drill can be cancelled with a reason');
SELECT pg_temp.expect((pg_temp.drill(:'CA','cancel_drill',jsonb_build_object('drill_id',(SELECT id FROM upcoming),
  'reason','Uretim duruslari nedeniyle ertelendi'))->'answer'->>'replayed'),
  'true','and cancelling twice is the same answer');

-- 10. A drill stays pinned to the version it rehearsed.
SELECT pg_temp.expect((SELECT public.isg_drills_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM missed),NULL,NULL)
  ->'row'->>'plan_version_superseded'),'false','the rehearsed version is still the one in force');
SELECT pg_temp.emergency(:'CA',jsonb_build_object('plan_id',(SELECT id FROM plan1),
  'workplace_id',:'WA','scope','Tesis geneli, revize','prepared_on',current_date::text,
  'team',jsonb_build_array(jsonb_build_object('full_name','Yeni','role','coordinator')),
  'review_note','Revizyon'));
SELECT pg_temp.expect((SELECT plan_version::text FROM private_isg.drill_records WHERE drill_id=(SELECT id FROM missed)),
  '1','publishing a newer plan does not re-point the drill');
SELECT pg_temp.expect((SELECT public.isg_drills_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM missed),NULL,NULL)
  ->'row'->>'plan_version_superseded'),'true','and the read says the version has moved on');

-- 11. The tally can never disagree with the list it counts.
SELECT pg_temp.expect(
  (SELECT sum((value)::int)::text FROM jsonb_each_text(
    public.isg_drills_read_v1(NULL,'list',NULL,NULL,NULL,NULL,100,0)->'counts')),
  (SELECT public.isg_drills_read_v1(NULL,'list',NULL,NULL,NULL,NULL,100,0)->>'total'),
  'the account counts add up to the rows they count');
SELECT pg_temp.expect((SELECT public.isg_drills_read_v1(NULL,'list',NULL,'closed',NULL,NULL,100,0)->>'total'),
  '2','the closed counter holds the performed one and the cancelled one');
SELECT pg_temp.expect((SELECT public.isg_drills_read_v1(NULL,'list',NULL,NULL,NULL,NULL,100,0)
  ->>'compliance_verdict'),NULL,'the list states no compliance verdict');

-- 12. The same mutation id replays instead of writing twice.
SELECT pg_temp.expect((public.isg_drills_mutate_v1(:'CA','plan_drill',
  '00000000-0000-0000-0000-00000000a001','00000000-0000-0000-0000-0000000000a1',
  jsonb_build_object('plan_id',(SELECT id FROM plan1),'planned_on',(current_date+90)::text))->>'replayed'),
  'false','first save writes');
SELECT pg_temp.expect((public.isg_drills_mutate_v1(:'CA','plan_drill',
  '00000000-0000-0000-0000-00000000a001','00000000-0000-0000-0000-0000000000a1',
  jsonb_build_object('plan_id',(SELECT id FROM plan1),'planned_on',(current_date+90)::text))->>'replayed'),
  'true','the same mutation replays');
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.drill_records WHERE planned_on=(current_date+90)),
  '1','and writes only once');
SELECT pg_temp.expect_refusal(format($q$SELECT public.isg_drills_mutate_v1(%L,'plan_drill',
  '00000000-0000-0000-0000-00000000a001','00000000-0000-0000-0000-0000000000a1',
  jsonb_build_object('plan_id',%L,'planned_on',(current_date+91)::text))$q$,:'CA',(SELECT id FROM plan1)),
  'IDEMPOTENCY_CONFLICT','the same id with a different body is refused');

-- 13. No table grant reaches a client role, and the wrappers are the only way in.
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.role_table_grants
  WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role')),
  '0','no client role holds a table grant in private_isg');
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.routine_privileges
  WHERE routine_schema='public' AND grantee='authenticated' AND routine_name LIKE 'isg_drills%'),
  '2','exactly the two public wrappers are callable');
SELECT 'ALL DRILL CHECKS PASSED' AS result;
