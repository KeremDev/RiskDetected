-- Checks for the P10 İSG-KATİP contract client boundary. Disposable database
-- only. Expected values are written here by hand; none is read back from the
-- function under test to decide what the function under test should say.
\set ON_ERROR_STOP on
\set A '20000000-0000-0000-0000-000000000001'
\set CA '10000000-0000-0000-0000-000000000001'
\set CB '10000000-0000-0000-0000-000000000002'
\set WA '40000000-0000-0000-0000-000000000001'
\set WB '40000000-0000-0000-0000-000000000003'

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
CREATE FUNCTION pg_temp.katip(p_company uuid,p_action text,p_payload jsonb) RETURNS jsonb
LANGUAGE sql AS $$
  SELECT public.isg_katip_mutate_v1(p_company,p_action,gen_random_uuid(),gen_random_uuid(),p_payload) $$;

SELECT set_config('test.actor',:'A',false);

-- 1. The slice adds no switch of its own and opens none.
SELECT pg_temp.expect_refusal(format('SELECT public.isg_katip_read_v1(%L,''list'',NULL,NULL,NULL,NULL,10,0)',:'CA'),
  'FEATURE_UNAVAILABLE','a closed feature refuses ahead of the module');
UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='modules';
SELECT pg_temp.expect_refusal(format('SELECT public.isg_katip_read_v1(%L,''list'',NULL,NULL,NULL,NULL,10,0)',:'CA'),
  'MODULE_UNAVAILABLE','a closed module refuses on its own');
UPDATE private_isg.module_registry SET read_enabled=true,write_enabled=true WHERE module='katip_contract';

-- 2. The ownership check the core function never had.
SELECT pg_temp.expect_refusal(format('SELECT public.isg_katip_read_v1(%L,''list'',NULL,NULL,NULL,NULL,10,0)',:'CB'),
  'ACCESS_DENIED','another owner company is refused');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.katip(%L,'record_contract',jsonb_build_object(
  'workplace_id','40000000-0000-0000-0000-000000000002','counterparty','OSGB','expert_contact','Uzman',
  'scope','Tam kapsam','starts_on',current_date::text))$q$,:'CA'),
  'ACCESS_DENIED','a workplace of another company is refused');

-- 3. The product never touches the official system, and takes no credential.
SELECT pg_temp.expect((SELECT public.isg_katip_read_v1(:'CA','catalog',NULL,NULL,NULL,NULL,NULL,NULL)
  ->>'official_integration'),'false','the catalogue states there is no integration');
SELECT pg_temp.expect((SELECT public.isg_katip_read_v1(:'CA','catalog',NULL,NULL,NULL,NULL,NULL,NULL)
  ->>'official_status_checked'),'false','and that no official status was checked');
SELECT pg_temp.expect((SELECT public.isg_katip_read_v1(:'CA','catalog',NULL,NULL,NULL,NULL,NULL,NULL)
  ->>'credential_collection'),'false','and that no credential is collected');
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.columns
  WHERE table_schema='private_isg' AND table_name='katip_contracts'
    AND (column_name ILIKE '%password%' OR column_name ILIKE '%credential%'
      OR column_name ILIKE '%token%' OR column_name ILIKE '%session%')),
  '0','the schema has nowhere to put a credential');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.katip(%L,'record_contract',jsonb_build_object(
  'workplace_id',%L,'counterparty','OSGB','expert_contact','Uzman','scope','Tam kapsam',
  'starts_on',current_date::text,'official_integration',true))$q$,:'CA',:'WA'),
  'PAYLOAD_NOT_ALLOWED','the integration flag cannot be raised by the client');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.katip(%L,'record_contract',jsonb_build_object(
  'workplace_id',%L,'counterparty','OSGB','expert_contact','Uzman','scope','Tam kapsam',
  'starts_on',current_date::text,'katip_password','gizli'))$q$,:'CA',:'WA'),
  'PAYLOAD_NOT_ALLOWED','and no credential can be sent either');

-- 4. An open ended contract is its own state, not a missing end date.
CREATE TEMP TABLE openended AS SELECT (pg_temp.katip(:'CA','record_contract',jsonb_build_object(
  'workplace_id',:'WA','counterparty','A OSGB','expert_contact','Uzman Bir','scope','Tam kapsam',
  'starts_on',(current_date-100)::text,'declared_monthly_minutes',600,
  'declared_note','Sozlesmede aylik 10 saat yaziyor','contract_location','Sozlesme klasoru'))
  ->>'contract_id')::uuid AS id;
SELECT pg_temp.expect((SELECT public.isg_katip_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM openended),NULL,NULL)
  ->'row'->>'term_state'),'open_ended','a contract with no end date is open ended');
SELECT pg_temp.expect((SELECT public.isg_katip_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM openended),NULL,NULL)
  ->'row'->>'state'),'active','and it never expires');

-- 5. What the contract declares is stored; whether it is enough is not known.
SELECT pg_temp.expect((SELECT public.isg_katip_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM openended),NULL,NULL)
  ->'row'->>'declared_monthly_minutes'),'600','the declared service time is on the record');
SELECT pg_temp.expect((SELECT public.isg_katip_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM openended),NULL,NULL)
  ->'row'->>'required_service_time_known'),'false','and the required amount is stated as unknown');
SELECT pg_temp.expect((SELECT public.isg_katip_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM openended),NULL,NULL)
  ->'row'->>'official_submission_made'),'false','the row says nothing was filed officially');
SELECT pg_temp.expect((SELECT public.isg_katip_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM openended),NULL,NULL)
  ->'row'->>'contract_stored'),'false','and that the document itself is not held here');
SELECT pg_temp.expect((SELECT public.isg_katip_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM openended),NULL,NULL)
  ->'row'->>'contract_location'),'Sozlesme klasoru','only where it is');

-- 6. The states a fixed term contract moves through. The window is 30 days.
CREATE TEMP TABLE soon AS SELECT (pg_temp.katip(:'CA','record_contract',jsonb_build_object(
  'workplace_id',:'WA','counterparty','B OSGB','expert_contact','Uzman Iki','scope','Kismi kapsam',
  'starts_on',(current_date-300)::text,'ends_before',(current_date+30)::text))->>'contract_id')::uuid AS id;
SELECT pg_temp.expect((SELECT public.isg_katip_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM soon),NULL,NULL)
  ->'row'->>'state'),'expiring','the last day of the window is expiring');
SELECT pg_temp.expect((SELECT public.isg_katip_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM soon),NULL,NULL)
  ->'row'->>'term_state'),'fixed_term','and a contract with an end date is fixed term');
CREATE TEMP TABLE gone AS SELECT (pg_temp.katip(:'CA','record_contract',jsonb_build_object(
  'workplace_id',:'WA','counterparty','C OSGB','expert_contact','Uzman Uc','scope','Eski kapsam',
  'starts_on',(current_date-400)::text,'ends_before',(current_date-1)::text))->>'contract_id')::uuid AS id;
SELECT pg_temp.expect((SELECT public.isg_katip_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM gone),NULL,NULL)
  ->'row'->>'state'),'expired','yesterday is expired');
CREATE TEMP TABLE later AS SELECT (pg_temp.katip(:'CA','record_contract',jsonb_build_object(
  'workplace_id',:'WB','counterparty','D OSGB','expert_contact','Uzman Dort','scope','Yeni kapsam',
  'starts_on',(current_date+10)::text))->>'contract_id')::uuid AS id;
SELECT pg_temp.expect((SELECT public.isg_katip_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM later),NULL,NULL)
  ->'row'->>'state'),'upcoming','a contract that starts later is upcoming');

-- 7. Ending a contract, and correcting the date.
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.katip(%L,'end_contract',jsonb_build_object(
  'contract_id',%L,'ends_before',(current_date-200)::text))$q$,:'CA',(SELECT id FROM openended)),
  'ENDS_BEFORE_START','an end before the start is refused');
SELECT pg_temp.expect((pg_temp.katip(:'CA','end_contract',jsonb_build_object(
  'contract_id',(SELECT id FROM openended),'ends_before',(current_date-1)::text))->'row'->>'term_state'),
  'fixed_term','ending an open ended contract makes it fixed term');
SELECT pg_temp.expect((SELECT public.isg_katip_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM openended),NULL,NULL)
  ->'row'->>'state'),'expired','and it is expired from that day');
SELECT pg_temp.expect((pg_temp.katip(:'CA','end_contract',jsonb_build_object(
  'contract_id',(SELECT id FROM openended),'ends_before',(current_date-1)::text))->'answer'->>'replayed'),
  'true','ending it again with the same date replays');
SELECT pg_temp.expect((pg_temp.katip(:'CA','end_contract',jsonb_build_object(
  'contract_id',(SELECT id FROM openended),'ends_before',(current_date-5)::text))->'row'->>'ends_before'),
  (current_date-5)::text,'a mistyped end date can be corrected');

-- 8. An archived contract is closed.
SELECT pg_temp.expect((pg_temp.katip(:'CA','archive_contract',jsonb_build_object(
  'contract_id',(SELECT id FROM gone)))->'row'->>'state'),'archived','archiving closes the contract');
SELECT pg_temp.expect((pg_temp.katip(:'CA','archive_contract',jsonb_build_object(
  'contract_id',(SELECT id FROM gone)))->'answer'->>'replayed'),'true','archiving twice is the same answer');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.katip(%L,'end_contract',jsonb_build_object(
  'contract_id',%L,'ends_before',current_date::text))$q$,:'CA',(SELECT id FROM gone)),
  'CONTRACT_ARCHIVED','an archived contract is not re-dated');

-- 9. The same counterparty, scope and start is one contract, not two.
SELECT pg_temp.expect((pg_temp.katip(:'CA','record_contract',jsonb_build_object(
  'workplace_id',:'WA','counterparty','B OSGB','expert_contact','Baska Uzman','scope','Kismi kapsam',
  'starts_on',(current_date-300)::text))->'answer'->>'replayed'),
  'true','the same counterparty, scope and start returns the same contract');
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.katip_contracts WHERE counterparty='B OSGB'),
  '1','and writes only once');

-- 10. A contract of another company cannot be archived.
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000002',false);
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.katip(%L,'archive_contract',jsonb_build_object(
  'contract_id',%L))$q$,:'CB',(SELECT id FROM soon)),
  'ACCESS_DENIED','a contract outside the company is refused');
SELECT set_config('test.actor',:'A',false);

-- 11. The tally can never disagree with the list it counts.
SELECT pg_temp.expect(
  (SELECT sum((value)::int)::text FROM jsonb_each_text(
    public.isg_katip_read_v1(NULL,'list',NULL,NULL,NULL,NULL,100,0)->'counts')),
  (SELECT public.isg_katip_read_v1(NULL,'list',NULL,NULL,NULL,NULL,100,0)->>'total'),
  'the account counts add up to the rows they count');
SELECT pg_temp.expect((SELECT public.isg_katip_read_v1(NULL,'list',NULL,'archived',NULL,NULL,100,0)->>'total'),
  '1','the archived filter agrees with its counter');
SELECT pg_temp.expect((SELECT public.isg_katip_read_v1(NULL,'list',NULL,'current',NULL,NULL,100,0)->>'total'),
  '1','the current counter holds the upcoming one');
SELECT pg_temp.expect((SELECT public.isg_katip_read_v1(NULL,'list',NULL,NULL,NULL,NULL,100,0)
  ->>'official_integration'),'false','the list repeats that there is no integration');
SELECT pg_temp.expect((SELECT public.isg_katip_read_v1(NULL,'list',NULL,NULL,NULL,NULL,100,0)
  ->>'compliance_verdict'),NULL,'and states no compliance verdict');

-- 12. The same mutation id replays instead of writing twice.
SELECT pg_temp.expect((public.isg_katip_mutate_v1(:'CA','record_contract',
  '00000000-0000-0000-0000-00000000d001','00000000-0000-0000-0000-0000000000d1',
  jsonb_build_object('workplace_id',:'WA','counterparty','E OSGB','expert_contact','Uzman Bes',
    'scope','Tekrar kapsam','starts_on',current_date::text))->>'replayed'),'false','first save writes');
SELECT pg_temp.expect((public.isg_katip_mutate_v1(:'CA','record_contract',
  '00000000-0000-0000-0000-00000000d001','00000000-0000-0000-0000-0000000000d1',
  jsonb_build_object('workplace_id',:'WA','counterparty','E OSGB','expert_contact','Uzman Bes',
    'scope','Tekrar kapsam','starts_on',current_date::text))->>'replayed'),'true','the same mutation replays');
SELECT pg_temp.expect_refusal(format($q$SELECT public.isg_katip_mutate_v1(%L,'record_contract',
  '00000000-0000-0000-0000-00000000d001','00000000-0000-0000-0000-0000000000d1',
  jsonb_build_object('workplace_id',%L,'counterparty','F OSGB','expert_contact','Uzman Alti',
    'scope','Baska kapsam','starts_on',current_date::text))$q$,:'CA',:'WA'),
  'IDEMPOTENCY_CONFLICT','the same id with a different body is refused');
-- Every write envelope repeats it, not only the read.
SELECT pg_temp.expect((public.isg_katip_mutate_v1(:'CA','record_contract',
  '00000000-0000-0000-0000-00000000d001','00000000-0000-0000-0000-0000000000d1',
  jsonb_build_object('workplace_id',:'WA','counterparty','E OSGB','expert_contact','Uzman Bes',
    'scope','Tekrar kapsam','starts_on',current_date::text))->>'official_submission_made'),
  'false','every write answer says nothing was filed officially');

-- 13. No table grant reaches a client role, and the wrappers are the only way in.
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.role_table_grants
  WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role')),
  '0','no client role holds a table grant in private_isg');
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.routine_privileges
  WHERE routine_schema='public' AND grantee='authenticated' AND routine_name LIKE 'isg_katip%'),
  '2','exactly the two public wrappers are callable');
SELECT 'ALL KATIP CONTRACT CHECKS PASSED' AS result;
