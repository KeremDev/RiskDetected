-- Checks for the P10 PPE handover client boundary. Disposable database only.
-- Expected values are written here by hand; none is read back from the function
-- under test to decide what the function under test should say.
\set ON_ERROR_STOP on
\set A '20000000-0000-0000-0000-000000000001'
\set CA '10000000-0000-0000-0000-000000000001'
\set CB '10000000-0000-0000-0000-000000000002'
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
CREATE FUNCTION pg_temp.ppe(p_company uuid,p_action text,p_payload jsonb) RETURNS jsonb
LANGUAGE sql AS $$
  SELECT public.isg_ppe_mutate_v1(p_company,p_action,gen_random_uuid(),gen_random_uuid(),p_payload) $$;

SELECT set_config('test.actor',:'A',false);

-- 1. The slice adds no switch of its own and opens none.
SELECT pg_temp.expect((SELECT read_enabled::text FROM private_isg.rollout WHERE feature='modules'),
  'false','the modules feature is still closed');
SELECT pg_temp.expect_refusal(format('SELECT public.isg_ppe_read_v1(%L,''list'',NULL,NULL,NULL,NULL,10,0)',:'CA'),
  'FEATURE_UNAVAILABLE','a closed feature refuses ahead of the module');
UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='modules';
SELECT pg_temp.expect_refusal(format('SELECT public.isg_ppe_read_v1(%L,''list'',NULL,NULL,NULL,NULL,10,0)',:'CA'),
  'MODULE_UNAVAILABLE','a closed module refuses on its own');
UPDATE private_isg.module_registry SET read_enabled=true,write_enabled=true WHERE module='ppe';

-- 2. The ownership check the core functions never had.
SELECT pg_temp.expect_refusal(format('SELECT public.isg_ppe_read_v1(%L,''list'',NULL,NULL,NULL,NULL,10,0)',:'CB'),
  'ACCESS_DENIED','another owner company is refused');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.ppe(%L,'record_handover',jsonb_build_object(
  'employee_id',%L,'item','Baret','quantity',1,'unit','piece','handed_on',current_date::text))$q$,
  :'CA',:'OUTSIDER'),
  'ACCESS_DENIED','an employee of another company is refused');

-- 3. The product never claims to hold a signed form.
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.ppe(%L,'record_handover',jsonb_build_object(
  'employee_id',%L,'item','Baret','quantity',1,'unit','piece','handed_on',current_date::text,
  'signed_copy',true))$q$,:'CA',:'E1'),
  'PAYLOAD_NOT_ALLOWED','the signed copy flag cannot be set by the client');
SELECT pg_temp.expect((SELECT public.isg_ppe_read_v1(:'CA','catalog',NULL,NULL,NULL,NULL,NULL,NULL)
  ->>'signed_copy_storage_available'),'false','and the catalogue says no file is stored here');
SELECT pg_temp.expect((SELECT public.isg_ppe_read_v1(:'CA','catalog',NULL,NULL,NULL,NULL,NULL,NULL)
  ->>'item_catalogue_offered'),'false','no fixed equipment list is offered either');

-- 4. Nothing was handed over on a day that has not happened.
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.ppe(%L,'record_handover',jsonb_build_object(
  'employee_id',%L,'item','Baret','quantity',1,'unit','piece','handed_on',(current_date+1)::text))$q$,
  :'CA',:'E1'),
  'HANDED_IN_THE_FUTURE','a handover dated tomorrow is refused');

-- 5. A handover is recorded, and what is still out is counted, not stored.
CREATE TEMP TABLE gloves AS SELECT (pg_temp.ppe(:'CA','record_handover',jsonb_build_object(
  'employee_id',:'E1','item','Eldiven','quantity',10,'unit','pair','handed_on',(current_date-10)::text,
  'signed_copy_location','Personel dosyasi, klasor 3'))->>'handover_id')::uuid AS id;
SELECT pg_temp.expect((SELECT public.isg_ppe_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM gloves),NULL,NULL)
  ->'row'->>'state'),'outstanding','nothing back yet means it is all still out');
SELECT pg_temp.expect((SELECT public.isg_ppe_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM gloves),NULL,NULL)
  ->'row'->>'outstanding'),'10.000','and the outstanding amount is the whole handover');
SELECT pg_temp.expect((SELECT signed_copy::text FROM private_isg.ppe_handovers WHERE handover_id=(SELECT id FROM gloves)),
  'false','the signed copy flag is false on the row');
SELECT pg_temp.expect((SELECT public.isg_ppe_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM gloves),NULL,NULL)
  ->'row'->>'signed_copy_location'),'Personel dosyasi, klasor 3','but where the form is kept was recorded');
SELECT pg_temp.expect((SELECT public.isg_ppe_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM gloves),NULL,NULL)
  ->'row'->>'signed_copy_stored'),'false','and the read says the file is not held here');

-- 6. Nothing comes back before it went out, and no more than went out.
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.ppe(%L,'record_return',jsonb_build_object(
  'handover_id',%L,'quantity',1,'returned_on',(current_date-20)::text,'condition','reusable'))$q$,
  :'CA',(SELECT id FROM gloves)),
  'RETURN_BEFORE_HANDOVER','a return before the handover is refused');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.ppe(%L,'record_return',jsonb_build_object(
  'handover_id',%L,'quantity',11,'returned_on',current_date::text,'condition','reusable'))$q$,
  :'CA',(SELECT id FROM gloves)),
  'RETURN_EXCEEDS_HANDOVER','more coming back than went out is refused');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.ppe(%L,'record_return',jsonb_build_object(
  'handover_id',%L,'quantity',1,'returned_on',(current_date+1)::text,'condition','reusable'))$q$,
  :'CA',(SELECT id FROM gloves)),
  'RETURNED_IN_THE_FUTURE','a return dated tomorrow is refused');

-- 7. Partial and full returns move the state, and the sum never exceeds.
SELECT pg_temp.expect((pg_temp.ppe(:'CA','record_return',jsonb_build_object('handover_id',(SELECT id FROM gloves),
  'quantity',4,'returned_on',(current_date-2)::text,'condition','worn'))->'row'->>'state'),
  'partial','some back makes it partial');
SELECT pg_temp.expect((SELECT public.isg_ppe_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM gloves),NULL,NULL)
  ->'row'->>'outstanding'),'6.000','and six are still out');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.ppe(%L,'record_return',jsonb_build_object(
  'handover_id',%L,'quantity',7,'returned_on',current_date::text,'condition','reusable'))$q$,
  :'CA',(SELECT id FROM gloves)),
  'RETURN_EXCEEDS_HANDOVER','the second return cannot push the total over either');
SELECT pg_temp.expect((pg_temp.ppe(:'CA','record_return',jsonb_build_object('handover_id',(SELECT id FROM gloves),
  'quantity',6,'returned_on',current_date::text,'condition','lost','note','Sahada kayboldu'))
  ->'row'->>'state'),'closed','everything back closes the handover');
SELECT pg_temp.expect((SELECT public.isg_ppe_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM gloves),NULL,NULL)
  ->'row'->>'lost_quantity'),'6.000','and what was lost is reported on its own');

-- 8. A mistaken return can be taken back, and the count corrects itself.
CREATE TEMP TABLE wrong AS SELECT ((public.isg_ppe_read_v1(:'CA','detail',NULL,NULL,NULL,
  (SELECT id FROM gloves),NULL,NULL)->'row'->'returns'->0->>'id'))::uuid AS id;
SELECT pg_temp.expect((pg_temp.ppe(:'CA','remove_return',jsonb_build_object(
  'handover_id',(SELECT id FROM gloves),'return_id',(SELECT id FROM wrong)))->'row'->>'state'),
  'partial','taking a return back reopens the handover');
SELECT pg_temp.expect((SELECT public.isg_ppe_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM gloves),NULL,NULL)
  ->'row'->>'outstanding'),'6.000','and the outstanding amount is recounted, not patched');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.ppe(%L,'remove_return',jsonb_build_object(
  'handover_id',%L,'return_id','99999999-9999-4999-a999-999999999999'))$q$,
  :'CA',(SELECT id FROM gloves)),
  'ACCESS_DENIED','a return that is not on this handover cannot be removed');

-- 9. The same external reference is one handover, not two.
SELECT pg_temp.expect((pg_temp.ppe(:'CA','record_handover',jsonb_build_object(
  'employee_id',:'E2','item','Baret','quantity',1,'unit','piece','handed_on',current_date::text,
  'external_ref','ZIM-2026-001'))->'answer'->>'replayed'),'false','a new reference writes');
SELECT pg_temp.expect((pg_temp.ppe(:'CA','record_handover',jsonb_build_object(
  'employee_id',:'E2','item','Baret','quantity',1,'unit','piece','handed_on',current_date::text,
  'external_ref','ZIM-2026-001'))->'answer'->>'replayed'),'true','the same reference returns the same handover');
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.ppe_handovers WHERE external_ref='ZIM-2026-001'),
  '1','and writes only once');

-- 10. A return cannot be filed against another company's handover.
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000002',false);
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.ppe(%L,'record_return',jsonb_build_object(
  'handover_id',%L,'quantity',1,'returned_on',current_date::text,'condition','reusable'))$q$,
  :'CB',(SELECT id FROM gloves)),
  'ACCESS_DENIED','a handover outside the company is refused');
SELECT set_config('test.actor',:'A',false);

-- 11. The tally can never disagree with the list it counts.
SELECT pg_temp.expect(
  (SELECT sum((value)::int)::text FROM jsonb_each_text(
    public.isg_ppe_read_v1(NULL,'list',NULL,NULL,NULL,NULL,100,0)->'counts')),
  (SELECT public.isg_ppe_read_v1(NULL,'list',NULL,NULL,NULL,NULL,100,0)->>'total'),
  'the account counts add up to the rows they count');
SELECT pg_temp.expect((SELECT public.isg_ppe_read_v1(NULL,'list',NULL,'partial',NULL,NULL,100,0)->>'total'),
  '1','the partial filter agrees with its counter');
SELECT pg_temp.expect((SELECT public.isg_ppe_read_v1(NULL,'list',NULL,NULL,NULL,NULL,100,0)
  ->>'compliance_verdict'),NULL,'the list states no compliance verdict');
-- One row per handover, never one per return.
SELECT pg_temp.expect((SELECT public.isg_ppe_read_v1(NULL,'list',NULL,NULL,NULL,NULL,100,0)->>'total'),
  (SELECT count(*)::text FROM private_isg.ppe_handovers),'one row per handover, never one per return');

-- 12. The same mutation id replays instead of writing twice.
SELECT pg_temp.expect((public.isg_ppe_mutate_v1(:'CA','record_handover',
  '00000000-0000-0000-0000-00000000b001','00000000-0000-0000-0000-0000000000b1',
  jsonb_build_object('employee_id',:'E1','item','Gozluk','quantity',2,'unit','piece',
    'handed_on',current_date::text))->>'replayed'),'false','first save writes');
SELECT pg_temp.expect((public.isg_ppe_mutate_v1(:'CA','record_handover',
  '00000000-0000-0000-0000-00000000b001','00000000-0000-0000-0000-0000000000b1',
  jsonb_build_object('employee_id',:'E1','item','Gozluk','quantity',2,'unit','piece',
    'handed_on',current_date::text))->>'replayed'),'true','the same mutation replays');
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.ppe_handovers WHERE item='Gozluk'),
  '1','and writes only once');
SELECT pg_temp.expect_refusal(format($q$SELECT public.isg_ppe_mutate_v1(%L,'record_handover',
  '00000000-0000-0000-0000-00000000b001','00000000-0000-0000-0000-0000000000b1',
  jsonb_build_object('employee_id',%L,'item','Gozluk','quantity',3,'unit','piece',
    'handed_on',current_date::text))$q$,:'CA',:'E1'),
  'IDEMPOTENCY_CONFLICT','the same id with a different body is refused');

-- 13. No table grant reaches a client role, and the wrappers are the only way in.
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.role_table_grants
  WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role')),
  '0','no client role holds a table grant in private_isg');
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.routine_privileges
  WHERE routine_schema='public' AND grantee='authenticated' AND routine_name LIKE 'isg_ppe%'),
  '2','exactly the two public wrappers are callable');
SELECT 'ALL PPE HANDOVER CHECKS PASSED' AS result;
