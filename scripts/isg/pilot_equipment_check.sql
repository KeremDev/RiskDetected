-- Checks for the Periyodik Kontroller pilot bundle. Disposable database only.
-- Every expected value is written here by hand; none is read back from the
-- function under test to decide what the function under test should say.
\set ON_ERROR_STOP on
\set A '20000000-0000-0000-0000-000000000001'
\set B '20000000-0000-0000-0000-000000000002'
\set CA '10000000-0000-0000-0000-000000000001'
\set CB '10000000-0000-0000-0000-000000000002'
\set WA '40000000-0000-0000-0000-000000000001'

CREATE FUNCTION pg_temp.expect_refusal(sql text,want text,label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE sql;
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

-- 1. The switches this bundle opened are the ones it claims to open.
SELECT pg_temp.expect((SELECT read_enabled::text||','||write_enabled::text FROM private_isg.rollout WHERE feature='modules'),
  'true,true','rollout modules open');
SELECT pg_temp.expect((SELECT read_enabled::text||','||write_enabled::text FROM private_isg.module_registry WHERE module='equipment'),
  'true,true','module equipment open');
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.module_registry WHERE read_enabled),
  '1','only equipment is open');

-- 2. Nobody reaches the module without being on the pilot list.
SELECT set_config('test.actor',:'A',false); SELECT set_config('test.pilot','false',false);
SELECT pg_temp.expect_refusal(format('SELECT public.isg_equipment_checks_read_v1(%L,''list'',NULL,NULL,NULL,NULL,NULL,10,0)',:'CA'),
  'FEATURE_UNAVAILABLE','non-pilot account refused for a company read');
SELECT pg_temp.expect_refusal('SELECT public.isg_equipment_checks_read_v1(NULL,''list'',NULL,NULL,NULL,NULL,NULL,10,0)',
  'FEATURE_UNAVAILABLE','non-pilot account refused for the account read');

-- 3. A pilot account still cannot reach another account's company.
SELECT set_config('test.pilot','true',false);
SELECT pg_temp.expect_refusal(format('SELECT public.isg_equipment_checks_read_v1(%L,''list'',NULL,NULL,NULL,NULL,NULL,10,0)',:'CB'),
  'FEATURE_UNAVAILABLE','pilot account refused another owner company');

-- 4. Registering materialises the type default as a visible, reviewable rule.
SELECT public.isg_equipment_checks_mutate_v1(:'CA','register_equipment',gen_random_uuid(),
  '00000000-0000-0000-0000-0000000000a1',
  jsonb_build_object('workplace_id',:'WA','equipment_type','forklift','serial_tag','FL-1'));
SELECT pg_temp.expect((SELECT period_months::text||','||period_source||','||needs_review::text
  FROM private_isg.equipment_inspection_rules WHERE company_id=:'CA' AND equipment_type='forklift'),
  '12,regulation_default,true','default period is materialised and flagged for review');
SELECT pg_temp.expect((SELECT length(exception_note)>=20 FROM private_isg.equipment_inspection_rules
  WHERE company_id=:'CA' AND equipment_type='forklift')::text,'true','the default carries its basis note');

-- 5. A report with no date given takes the period's answer, marked as such.
SELECT public.isg_equipment_checks_mutate_v1(:'CA','record_inspection',gen_random_uuid(),
  '00000000-0000-0000-0000-0000000000a2',
  jsonb_build_object('equipment_id',(SELECT equipment_id FROM private_isg.equipment_items WHERE serial_tag='FL-1'),
    'performed_on','2026-03-10','result','pass','inspector','Kontrol Eden'));
SELECT pg_temp.expect((SELECT next_due_on::text||','||due_source FROM private_isg.equipment_inspections
  WHERE performed_on='2026-03-10'),'2027-03-10,period','12 months after the report, reported as the period answer');

-- 6. The expert's own date is stored as the expert's, not the period's.
SELECT public.isg_equipment_checks_mutate_v1(:'CA','register_equipment',gen_random_uuid(),
  '00000000-0000-0000-0000-0000000000a3',
  jsonb_build_object('workplace_id',:'WA','equipment_type','crane','serial_tag','CR-1'));
SELECT public.isg_equipment_checks_mutate_v1(:'CA','record_inspection',gen_random_uuid(),
  '00000000-0000-0000-0000-0000000000a4',
  jsonb_build_object('equipment_id',(SELECT equipment_id FROM private_isg.equipment_items WHERE serial_tag='CR-1'),
    'performed_on','2026-03-10','result','pass','next_due_on','2026-09-10'));
SELECT pg_temp.expect((SELECT next_due_on::text||','||due_source FROM private_isg.equipment_inspections i
  JOIN private_isg.equipment_items e USING(equipment_id) WHERE e.serial_tag='CR-1'),
  '2026-09-10,expert','the expert date is attributed to the expert');

-- 7. A type the product has no default for keeps no period and no date.
SELECT public.isg_equipment_checks_mutate_v1(:'CA','register_equipment',gen_random_uuid(),
  '00000000-0000-0000-0000-0000000000a5',
  jsonb_build_object('workplace_id',:'WA','equipment_type','custom_rig','serial_tag','CX-1'));
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.equipment_inspection_rules
  WHERE company_id=:'CA' AND equipment_type='custom_rig'),'0','an unknown type borrows no period');
SELECT public.isg_equipment_checks_mutate_v1(:'CA','record_inspection',gen_random_uuid(),
  '00000000-0000-0000-0000-0000000000a6',
  jsonb_build_object('equipment_id',(SELECT equipment_id FROM private_isg.equipment_items WHERE serial_tag='CX-1'),
    'performed_on','2026-03-10','result','pass'));
SELECT pg_temp.expect((SELECT coalesce(next_due_on::text,'NULL')||','||coalesce(due_source,'NULL')
  FROM private_isg.equipment_inspections i JOIN private_isg.equipment_items e USING(equipment_id)
  WHERE e.serial_tag='CX-1'),'NULL,NULL','no period means no invented due date');
SELECT pg_temp.expect((SELECT public.isg_equipment_checks_read_v1(:'CA','detail',NULL,NULL,NULL,NULL,
  (SELECT equipment_id FROM private_isg.equipment_items WHERE serial_tag='CX-1'),10,0)->'row'->>'state'),
  'period_unknown','and the row says the period is unknown, not that it is valid');

-- 8. PILOT DIVERGENCE 2: an evidence reference is refused, never stored unbacked.
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.columns
  WHERE table_schema='private_isg' AND table_name='equipment_inspections' AND column_name='evidence_asset_id'),
  '0','there is no column for an asset this pilot cannot clear');
SELECT pg_temp.expect_refusal(format($q$SELECT public.isg_equipment_checks_mutate_v1(%L,'record_inspection',gen_random_uuid(),
  '00000000-0000-0000-0000-0000000000a7',
  jsonb_build_object('equipment_id',(SELECT equipment_id FROM private_isg.equipment_items WHERE serial_tag='FL-1'),
    'performed_on','2026-04-01','result','pass','evidence_asset_id',gen_random_uuid()))$q$,:'CA'),
  'VALIDATION_ERROR','a non-null evidence reference is refused');
-- A null one is accepted, because that is what the client always sends.
SELECT public.isg_equipment_checks_mutate_v1(:'CA','record_inspection',gen_random_uuid(),
  '00000000-0000-0000-0000-0000000000a8',
  jsonb_build_object('equipment_id',(SELECT equipment_id FROM private_isg.equipment_items WHERE serial_tag='FL-1'),
    'performed_on','2026-04-01','result','pass','evidence_asset_id',NULL));
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.equipment_inspections WHERE performed_on='2026-04-01'),
  '1','a null evidence key does not block the save');

-- 9. The KATİP mark is stored and moves nothing.
SELECT public.isg_equipment_checks_mutate_v1(:'CA','register_equipment',gen_random_uuid(),
  '00000000-0000-0000-0000-0000000000b1',
  jsonb_build_object('workplace_id',:'WA','equipment_type','boiler','serial_tag','BO-1'));
SELECT public.isg_equipment_checks_mutate_v1(:'CA','record_inspection',gen_random_uuid(),
  '00000000-0000-0000-0000-0000000000b2',
  jsonb_build_object('equipment_id',(SELECT equipment_id FROM private_isg.equipment_items WHERE serial_tag='BO-1'),
    'performed_on','2026-03-10','result','pass','katip_declared',true,'katip_note','Atama yapildi'));
CREATE TEMP TABLE katip_before AS SELECT public.isg_equipment_checks_read_v1(:'CA','detail',NULL,NULL,NULL,NULL,
  (SELECT equipment_id FROM private_isg.equipment_items WHERE serial_tag='BO-1'),10,0) AS doc;
SELECT pg_temp.expect((SELECT doc->'row'->>'state' FROM katip_before),'valid','a ticked report is still just valid');
SELECT pg_temp.expect((SELECT doc->'row'->'inspections'->0->>'katip_assignment_declared' FROM katip_before),'true','the tick is stored');
SELECT pg_temp.expect((SELECT doc->'row'->>'katip_official_verification' FROM katip_before),'false',
  'and the read never claims the official system was checked');
-- Untick it: the row, its state and the board counts must not move.
SELECT public.isg_equipment_checks_mutate_v1(:'CA','update_inspection',gen_random_uuid(),
  '00000000-0000-0000-0000-0000000000b3',
  jsonb_build_object('equipment_id',(SELECT equipment_id FROM private_isg.equipment_items WHERE serial_tag='BO-1'),
    'inspection_id',(SELECT i.inspection_id FROM private_isg.equipment_inspections i
       JOIN private_isg.equipment_items e USING(equipment_id) WHERE e.serial_tag='BO-1'),
    'katip_declared',false));
-- Everything the board is decided by must be byte-identical before and after.
SELECT pg_temp.expect((SELECT (public.isg_equipment_checks_read_v1(:'CA','detail',NULL,NULL,NULL,NULL,
  (SELECT equipment_id FROM private_isg.equipment_items WHERE serial_tag='BO-1'),10,0)->'row')
  - 'katip_assignment_declared' - 'katip_declared_note' - 'inspections'
  = (SELECT (doc->'row') - 'katip_assignment_declared' - 'katip_declared_note' - 'inspections' FROM katip_before))::text,
  'true','unticking KATIP moves nothing the board reads');
SELECT pg_temp.expect((SELECT public.isg_equipment_checks_read_v1(:'CA','detail',NULL,NULL,NULL,NULL,
  (SELECT equipment_id FROM private_isg.equipment_items WHERE serial_tag='BO-1'),10,0)->'row'->>'state'),
  'valid','unticking KATIP does not change the state');
SELECT pg_temp.expect((SELECT coalesce(katip_declared_note,'NULL') FROM private_isg.equipment_inspections i
  JOIN private_isg.equipment_items e USING(equipment_id) WHERE e.serial_tag='BO-1'),
  'NULL','unticking clears the note it explained');

-- 10. A filed report can be corrected, but not rewritten.
SELECT pg_temp.expect_refusal(format($q$SELECT public.isg_equipment_checks_mutate_v1(%L,'update_inspection',gen_random_uuid(),
  '00000000-0000-0000-0000-0000000000b4',
  jsonb_build_object('equipment_id',(SELECT equipment_id FROM private_isg.equipment_items WHERE serial_tag='BO-1'),
    'inspection_id',(SELECT i.inspection_id FROM private_isg.equipment_inspections i
      JOIN private_isg.equipment_items e USING(equipment_id) WHERE e.serial_tag='BO-1'),
    'performed_on','2026-05-05'))$q$,:'CA'),
  'PAYLOAD_NOT_ALLOWED','the check date cannot be edited');
SELECT pg_temp.expect_refusal(format($q$SELECT public.isg_equipment_checks_mutate_v1(%L,'update_inspection',gen_random_uuid(),
  '00000000-0000-0000-0000-0000000000b5',
  jsonb_build_object('equipment_id',(SELECT equipment_id FROM private_isg.equipment_items WHERE serial_tag='BO-1'),
    'inspection_id',(SELECT i.inspection_id FROM private_isg.equipment_inspections i
      JOIN private_isg.equipment_items e USING(equipment_id) WHERE e.serial_tag='BO-1'),
    'result','fail'))$q$,:'CA'),
  'PAYLOAD_NOT_ALLOWED','the result cannot be edited');
SELECT public.isg_equipment_checks_mutate_v1(:'CA','update_inspection',gen_random_uuid(),
  '00000000-0000-0000-0000-0000000000b6',
  jsonb_build_object('equipment_id',(SELECT equipment_id FROM private_isg.equipment_items WHERE serial_tag='BO-1'),
    'inspection_id',(SELECT i.inspection_id FROM private_isg.equipment_inspections i
      JOIN private_isg.equipment_items e USING(equipment_id) WHERE e.serial_tag='BO-1'),
    'inspector','Duzeltilmis Ad','next_due_on','2027-01-15'));
SELECT pg_temp.expect((SELECT inspector||','||next_due_on::text||','||due_source
  FROM private_isg.equipment_inspections i JOIN private_isg.equipment_items e USING(equipment_id)
  WHERE e.serial_tag='BO-1'),'Duzeltilmis Ad,2027-01-15,expert','a correction lands and is attributed');
-- Correcting back onto the period's own answer reads as the period again.
SELECT public.isg_equipment_checks_mutate_v1(:'CA','update_inspection',gen_random_uuid(),
  '00000000-0000-0000-0000-0000000000b7',
  jsonb_build_object('equipment_id',(SELECT equipment_id FROM private_isg.equipment_items WHERE serial_tag='BO-1'),
    'inspection_id',(SELECT i.inspection_id FROM private_isg.equipment_inspections i
      JOIN private_isg.equipment_items e USING(equipment_id) WHERE e.serial_tag='BO-1'),
    'next_due_on','2027-03-10'));
SELECT pg_temp.expect((SELECT due_source FROM private_isg.equipment_inspections i
  JOIN private_isg.equipment_items e USING(equipment_id) WHERE e.serial_tag='BO-1'),
  'period','a corrected date back on the period reads as the period answer');

-- 11. The same mutation id replays instead of writing twice.
SELECT pg_temp.expect((public.isg_equipment_checks_mutate_v1(:'CA','register_equipment',
  '00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000000000c1',
  jsonb_build_object('workplace_id',:'WA','equipment_type','ladder','serial_tag','LD-1'))->>'replayed'),
  'false','first save writes');
SELECT pg_temp.expect((public.isg_equipment_checks_mutate_v1(:'CA','register_equipment',
  '00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000000000c1',
  jsonb_build_object('workplace_id',:'WA','equipment_type','ladder','serial_tag','LD-1'))->>'replayed'),
  'true','the same mutation replays');
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.equipment_items WHERE serial_tag='LD-1'),
  '1','and writes only once');
SELECT pg_temp.expect_refusal(format($q$SELECT public.isg_equipment_checks_mutate_v1(%L,'register_equipment',
  '00000000-0000-0000-0000-00000000c001','00000000-0000-0000-0000-0000000000c1',
  jsonb_build_object('workplace_id',%L,'equipment_type','ladder','serial_tag','LD-2'))$q$,:'CA',:'WA'),
  'IDEMPOTENCY_CONFLICT','the same id with a different body is refused');

-- 12. Closing the module switch closes the module and nothing else.
UPDATE private_isg.module_registry SET read_enabled=false,write_enabled=false WHERE module='equipment';
SELECT pg_temp.expect_refusal(format('SELECT public.isg_equipment_checks_read_v1(%L,''list'',NULL,NULL,NULL,NULL,NULL,10,0)',:'CA'),
  'MODULE_UNAVAILABLE','a closed module refuses');
UPDATE private_isg.module_registry SET read_enabled=true,write_enabled=true WHERE module='equipment';
UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='modules';
SELECT pg_temp.expect_refusal(format('SELECT public.isg_equipment_checks_read_v1(%L,''list'',NULL,NULL,NULL,NULL,NULL,10,0)',:'CA'),
  'FEATURE_UNAVAILABLE','a closed feature refuses ahead of the module');
UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='modules';

-- 13. No table grant reaches a client role, and the two wrappers are the only way in.
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.role_table_grants
  WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role')),
  '0','no client role holds a table grant in private_isg');
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.routine_privileges
  WHERE routine_schema='public' AND grantee='authenticated' AND routine_name LIKE 'isg_equipment%'),
  '2','exactly the two public wrappers are callable');
-- 14. The catalogue the client opens the page with.
SELECT pg_temp.expect((SELECT jsonb_array_length(public.isg_equipment_checks_read_v1(:'CA','catalog',
  NULL,NULL,NULL,NULL,NULL,NULL,NULL)->'suggestions')::text),'20','every suggested type is offered');
SELECT pg_temp.expect((SELECT public.isg_equipment_checks_read_v1(:'CA','catalog',
  NULL,NULL,NULL,NULL,NULL,NULL,NULL)->'suggestions'->0->>'default_period_months'),'12',
  'and each arrives with its default period');
SELECT pg_temp.expect((SELECT public.isg_equipment_checks_read_v1(:'CA','catalog',
  NULL,NULL,NULL,NULL,NULL,NULL,NULL)->>'period_default_needs_review'),'true',
  'the default is offered as something to confirm, not as a determination');
SELECT pg_temp.expect((SELECT public.isg_equipment_checks_read_v1(:'CA','catalog',
  NULL,NULL,NULL,NULL,NULL,NULL,NULL)->'workplaces'->0->>'name'),'Merkez',
  'the company workplaces are listed for the register form');
SELECT pg_temp.expect((SELECT public.isg_equipment_checks_read_v1(:'CA','catalog',
  NULL,NULL,NULL,NULL,NULL,NULL,NULL)->>'health_records_tracked'),'false',
  'and the catalogue says no person is tracked here');

-- 15. The account-wide board a pilot account opens the module on.
SELECT pg_temp.expect((SELECT public.isg_equipment_checks_read_v1(NULL,'list',
  NULL,NULL,NULL,NULL,NULL,50,0)->>'total'),'5','the board counts every item the account owns');
SELECT pg_temp.expect((SELECT public.isg_equipment_checks_read_v1(NULL,'list',
  NULL,'overdue',NULL,NULL,NULL,50,0)->>'total'),'1','and the overdue filter agrees with its counter');

SELECT 'ALL PILOT EQUIPMENT CHECKS PASSED' AS result;
