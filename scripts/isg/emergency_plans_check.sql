-- Checks for the P10 emergency plan client boundary. Disposable database only.
-- Expected values are written here by hand; none is read back from the function
-- under test to decide what the function under test should say.
\set ON_ERROR_STOP on
\set A '20000000-0000-0000-0000-000000000001'
\set CA '10000000-0000-0000-0000-000000000001'
\set CB '10000000-0000-0000-0000-000000000002'
\set WA '40000000-0000-0000-0000-000000000001'
\set WB '40000000-0000-0000-0000-000000000002'

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
CREATE FUNCTION pg_temp.mutate(p_company uuid,p_payload jsonb) RETURNS jsonb
LANGUAGE sql AS $$
  SELECT public.isg_emergency_plans_mutate_v1(p_company,'publish_plan',gen_random_uuid(),gen_random_uuid(),p_payload) $$;
CREATE FUNCTION pg_temp.team(p_role text) RETURNS jsonb
LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_array(jsonb_build_object('full_name','Ekip Uyesi','role',p_role,'contact','0555')) $$;

SELECT set_config('test.actor',:'A',false);

-- 1. The slice adds no switch of its own and opens none. Both switches must be
--    open before it answers, and they fail differently.
SELECT pg_temp.expect((SELECT read_enabled::text||','||write_enabled::text FROM private_isg.rollout WHERE feature='modules'),
  'false,false','the modules feature is still closed');
SELECT pg_temp.expect((SELECT read_enabled::text||','||write_enabled::text FROM private_isg.module_registry WHERE module='emergency_plan'),
  'false,false','and so is the emergency plan module');
SELECT pg_temp.expect_refusal(format('SELECT public.isg_emergency_plans_read_v1(%L,''list'',NULL,NULL,NULL,NULL,10,0)',:'CA'),
  'FEATURE_UNAVAILABLE','a closed feature refuses ahead of the module');
UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='modules';
SELECT pg_temp.expect_refusal(format('SELECT public.isg_emergency_plans_read_v1(%L,''list'',NULL,NULL,NULL,NULL,10,0)',:'CA'),
  'MODULE_UNAVAILABLE','a closed module refuses on its own');
UPDATE private_isg.module_registry SET read_enabled=true,write_enabled=true WHERE module='emergency_plan';
-- Opening this module opens nothing else.
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.module_registry WHERE read_enabled),
  '1','opening one module opens only that one');

-- 2. The ownership check the core function never had.
SELECT pg_temp.expect_refusal(format('SELECT public.isg_emergency_plans_read_v1(%L,''list'',NULL,NULL,NULL,NULL,10,0)',:'CB'),
  'ACCESS_DENIED','another owner company is refused');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,jsonb_build_object(
  'workplace_id',%L,'scope','Tesis geneli','prepared_on',current_date::text,'team',pg_temp.team('coordinator')))$q$,
  :'CA',:'WB'),
  'ACCESS_DENIED','a workplace of another company is refused');

-- 3. A team snapshot cannot be arbitrary JSON.
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,jsonb_build_object(
  'workplace_id',%L,'scope','X','prepared_on',current_date::text,'team',jsonb_build_array('duz metin')))$q$,
  :'CA',:'WA'),
  'VALIDATION_ERROR','a team entry that is not an object is refused');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,jsonb_build_object(
  'workplace_id',%L,'scope','X','prepared_on',current_date::text,
  'team',jsonb_build_array(jsonb_build_object('full_name','A','role','coordinator','tckn','123'))))$q$,
  :'CA',:'WA'),
  'PAYLOAD_NOT_ALLOWED','an unexpected key in a team entry is refused');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,jsonb_build_object(
  'workplace_id',%L,'scope','X','prepared_on',current_date::text,
  'team',jsonb_build_array(jsonb_build_object('full_name','A','role','baskan'))))$q$,
  :'CA',:'WA'),
  'TEAM_ROLE_UNKNOWN','a role the schema does not know is refused');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,jsonb_build_object(
  'workplace_id',%L,'scope','X','prepared_on',current_date::text,
  'team',jsonb_build_array(jsonb_build_object('role','coordinator'))))$q$,
  :'CA',:'WA'),
  'VALIDATION_ERROR','a team entry with no name is refused');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,jsonb_build_object(
  'workplace_id',%L,'scope','X','prepared_on',current_date::text,'team',jsonb_build_array()))$q$,
  :'CA',:'WA'),
  'VALIDATION_ERROR','an empty team is refused');

-- 4. Dates belong to the server.
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,jsonb_build_object(
  'workplace_id',%L,'scope','X','prepared_on',(current_date+1)::text,'team',pg_temp.team('fire')))$q$,
  :'CA',:'WA'),
  'PREPARED_IN_THE_FUTURE','a plan prepared tomorrow is refused');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,jsonb_build_object(
  'workplace_id',%L,'scope','X','prepared_on',current_date::text,
  'valid_until',(current_date-1)::text,'team',pg_temp.team('fire')))$q$,
  :'CA',:'WA'),
  'VALIDATION_ERROR','an end date before the start is refused');

-- 5. An unverified basis stays in review, and no payload field can clear it.
CREATE TEMP TABLE plan1 AS SELECT (pg_temp.mutate(:'CA',jsonb_build_object(
  'workplace_id',:'WA','scope','Tesis geneli','prepared_on',(current_date-10)::text,
  'valid_until',(current_date+300)::text,
  'team',jsonb_build_array(
    jsonb_build_object('full_name','Ayse Koordinator','role','coordinator','contact','0555'),
    jsonb_build_object('full_name','Mehmet Yangin','role','fire'))))->>'plan_id')::uuid AS id;
SELECT pg_temp.expect((SELECT public.isg_emergency_plans_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM plan1),NULL,NULL)
  ->'row'->>'needs_review'),'true','a plan with no written basis stays in review');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,jsonb_build_object(
  'workplace_id',%L,'scope','X','prepared_on',current_date::text,'team',pg_temp.team('fire'),
  'needs_review',false))$q$,:'CA',:'WA'),
  'PAYLOAD_NOT_ALLOWED','the review flag cannot be set by the client');

-- 6. The date is the expert's, and a plan with no date never reads as valid.
SELECT pg_temp.expect((SELECT public.isg_emergency_plans_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM plan1),NULL,NULL)
  ->'row'->>'period_source'),'expert','the validity date is attributed to the expert');
SELECT pg_temp.expect((SELECT public.isg_emergency_plans_read_v1(:'CA','catalog',NULL,NULL,NULL,NULL,NULL,NULL)
  ->>'period_defaults_offered'),'false','the product proposes no renewal period');
CREATE TEMP TABLE dateless AS SELECT (pg_temp.mutate(:'CA',jsonb_build_object(
  'workplace_id',:'WA','scope','Sure yazilmamis plan','prepared_on',(current_date-5)::text,
  'team',pg_temp.team('evacuation'),'review_note','Isveren beyani'))->>'plan_id')::uuid AS id;
SELECT pg_temp.expect((SELECT public.isg_emergency_plans_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM dateless),NULL,NULL)
  ->'row'->>'state'),'period_unknown','a plan with no end date is a gap, not a clean bill');
SELECT pg_temp.expect((SELECT public.isg_emergency_plans_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM dateless),NULL,NULL)
  ->'row'->>'needs_review'),'false','and a written basis clears the review flag');

-- 7. The states the dates produce, at their boundaries. The window is 30 days.
CREATE TEMP TABLE soon AS SELECT (pg_temp.mutate(:'CA',jsonb_build_object(
  'workplace_id',:'WA','scope','Yaklasan plan','prepared_on',(current_date-100)::text,
  'valid_until',(current_date+30)::text,'team',pg_temp.team('fire')))->>'plan_id')::uuid AS id;
SELECT pg_temp.expect((SELECT public.isg_emergency_plans_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM soon),NULL,NULL)
  ->'row'->>'state'),'due_soon','the last day of the window is due_soon');
CREATE TEMP TABLE gone AS SELECT (pg_temp.mutate(:'CA',jsonb_build_object(
  'workplace_id',:'WA','scope','Suresi dolmus plan','prepared_on',(current_date-400)::text,
  'valid_until',(current_date-1)::text,'team',pg_temp.team('fire')))->>'plan_id')::uuid AS id;
SELECT pg_temp.expect((SELECT public.isg_emergency_plans_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM gone),NULL,NULL)
  ->'row'->>'state'),'expired','yesterday is expired');
SELECT pg_temp.expect((SELECT public.isg_emergency_plans_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM plan1),NULL,NULL)
  ->'row'->>'state'),'valid','and a plan with room left is valid');

-- 8. A renewal is a new version. The one before it keeps everything it had.
CREATE TEMP TABLE before_renewal AS
  SELECT scope,prepared_on,valid_until,team_snapshot FROM private_isg.emergency_plan_versions
  WHERE plan_id=(SELECT id FROM plan1) AND version=1;
SELECT pg_temp.mutate(:'CA',jsonb_build_object('plan_id',(SELECT id FROM plan1),
  'workplace_id',:'WA','scope','Tesis geneli, revize','prepared_on',current_date::text,
  'valid_until',(current_date+365)::text,
  'team',jsonb_build_array(jsonb_build_object('full_name','Yeni Koordinator','role','coordinator')),
  'review_note','Isveren yazili talimati'));
SELECT pg_temp.expect((SELECT scope||'|'||prepared_on::text||'|'||coalesce(valid_until::text,'NULL')
    ||'|'||team_snapshot::text FROM private_isg.emergency_plan_versions
  WHERE plan_id=(SELECT id FROM plan1) AND version=1),
  (SELECT scope||'|'||prepared_on::text||'|'||coalesce(valid_until::text,'NULL')||'|'||team_snapshot::text
   FROM before_renewal),
  'renewing rewrites nothing in the version before it');
SELECT pg_temp.expect((SELECT state FROM private_isg.emergency_plan_versions
  WHERE plan_id=(SELECT id FROM plan1) AND version=1),'superseded','the old version is superseded, not deleted');
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.emergency_plan_versions
  WHERE plan_id=(SELECT id FROM plan1) AND state='active'),'1','and only one version is active at a time');
SELECT pg_temp.expect((SELECT public.isg_emergency_plans_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM plan1),NULL,NULL)
  ->'row'->>'versions_total'),'2','the history holds both versions');
SELECT pg_temp.expect((SELECT public.isg_emergency_plans_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM plan1),NULL,NULL)
  ->'row'->'versions'->1->>'team_size'),'2','and the older one still carries its own team');
SELECT pg_temp.expect((SELECT public.isg_emergency_plans_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM plan1),NULL,NULL)
  ->'row'->>'team_size'),'1','while the active one carries the team it was renewed with');

-- 9. A renewal cannot be aimed at a plan that is not this company's.
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,jsonb_build_object(
  'plan_id','99999999-9999-4999-a999-999999999999','workplace_id',%L,'scope','X',
  'prepared_on',current_date::text,'team',pg_temp.team('fire')))$q$,:'CA',:'WA'),
  'ACCESS_DENIED','a renewal aimed at an unknown plan is refused');

-- 10. The contact is optional and nothing else rides into the snapshot.
SELECT pg_temp.expect((SELECT team_snapshot->1->>'contact' FROM private_isg.emergency_plan_versions
  WHERE plan_id=(SELECT id FROM plan1) AND version=1),NULL,'an entry with no contact stores none');
SELECT pg_temp.expect((SELECT (SELECT count(*) FROM jsonb_object_keys(team_snapshot->0))::text
  FROM private_isg.emergency_plan_versions WHERE plan_id=(SELECT id FROM plan1) AND version=1),
  '3','and a full entry stores exactly name, role and contact');

-- 11. The tally can never disagree with the list it counts.
SELECT pg_temp.expect(
  (SELECT sum((value)::int)::text FROM jsonb_each_text(
    public.isg_emergency_plans_read_v1(NULL,'list',NULL,NULL,NULL,NULL,100,0)->'counts')),
  (SELECT public.isg_emergency_plans_read_v1(NULL,'list',NULL,NULL,NULL,NULL,100,0)->>'total'),
  'the account counts add up to the rows they count');
SELECT pg_temp.expect((SELECT public.isg_emergency_plans_read_v1(NULL,'list',NULL,NULL,NULL,NULL,100,0)
  ->>'compliance_verdict'),NULL,'the list states no compliance verdict');
SELECT pg_temp.expect((SELECT public.isg_emergency_plans_read_v1(NULL,'list',NULL,'expired',NULL,NULL,100,0)
  ->>'total'),'1','the expired filter agrees with its counter');
-- Only the active version of each plan is a row.
SELECT pg_temp.expect((SELECT public.isg_emergency_plans_read_v1(NULL,'list',NULL,NULL,NULL,NULL,100,0)->>'total'),
  (SELECT count(DISTINCT plan_id)::text FROM private_isg.emergency_plan_versions),
  'one row per plan, never one per version');

-- 12. The same mutation id replays instead of writing twice.
SELECT pg_temp.expect((public.isg_emergency_plans_mutate_v1(:'CA','publish_plan',
  '00000000-0000-0000-0000-000000009001','00000000-0000-0000-0000-000000000091',
  jsonb_build_object('workplace_id',:'WA','scope','Tekrar','prepared_on',current_date::text,
    'team',pg_temp.team('other')))->>'replayed'),'false','first save writes');
SELECT pg_temp.expect((public.isg_emergency_plans_mutate_v1(:'CA','publish_plan',
  '00000000-0000-0000-0000-000000009001','00000000-0000-0000-0000-000000000091',
  jsonb_build_object('workplace_id',:'WA','scope','Tekrar','prepared_on',current_date::text,
    'team',pg_temp.team('other')))->>'replayed'),'true','the same mutation replays');
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.emergency_plan_versions WHERE scope='Tekrar'),
  '1','and writes only once');
SELECT pg_temp.expect_refusal(format($q$SELECT public.isg_emergency_plans_mutate_v1(%L,'publish_plan',
  '00000000-0000-0000-0000-000000009001','00000000-0000-0000-0000-000000000091',
  jsonb_build_object('workplace_id',%L,'scope','Baska','prepared_on',current_date::text,
    'team',pg_temp.team('other')))$q$,:'CA',:'WA'),
  'IDEMPOTENCY_CONFLICT','the same id with a different body is refused');

-- 13. Closing the module closes this module and nothing else.
UPDATE private_isg.module_registry SET read_enabled=false,write_enabled=false WHERE module='emergency_plan';
SELECT pg_temp.expect_refusal(format('SELECT public.isg_emergency_plans_read_v1(%L,''list'',NULL,NULL,NULL,NULL,10,0)',:'CA'),
  'MODULE_UNAVAILABLE','a closed module refuses');
UPDATE private_isg.module_registry SET read_enabled=true,write_enabled=true WHERE module='emergency_plan';

-- 14. No table grant reaches a client role, and the wrappers are the only way in.
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.role_table_grants
  WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role')),
  '0','no client role holds a table grant in private_isg');
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.routine_privileges
  WHERE routine_schema='public' AND grantee='authenticated' AND routine_name LIKE 'isg_emergency%'),
  '2','exactly the two public wrappers are callable');
SELECT 'ALL EMERGENCY PLAN CHECKS PASSED' AS result;
