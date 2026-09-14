-- Checks for the Evrak Takibi pilot bundle. Disposable database only.
-- Every expected value is written here by hand; none is read back from the
-- function under test to decide what the function under test should say.
\set ON_ERROR_STOP on
\set A '20000000-0000-0000-0000-000000000001'
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
-- One obligation per test, so no test can be judged against another's rows.
CREATE FUNCTION pg_temp.own(p_company uuid,p_title text,p_validity integer,p_notice integer) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE answer jsonb;
BEGIN
  answer:=public.isg_document_tracking_mutate_v1(p_company,'add_obligation',gen_random_uuid(),gen_random_uuid(),
    jsonb_strip_nulls(jsonb_build_object('kind_code','other','title',p_title,
      'validity_days',p_validity,'notice_days',p_notice)));
  RETURN (answer->'row'->>'id')::uuid;
END $$;

-- 1. The switch this bundle opened, and nothing else.
SELECT pg_temp.expect((SELECT read_enabled::text||','||write_enabled::text FROM private_isg.rollout WHERE feature='document_tracking'),
  'true,true','document_tracking is open');
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.rollout),'3','no other feature row was added');

-- 2. Nobody reaches the module without being on the pilot list.
SELECT set_config('test.actor',:'A',false); SELECT set_config('test.pilot','false',false);
SELECT pg_temp.expect_refusal(format('SELECT public.isg_document_tracking_read_v1(%L,''list'',NULL,NULL,NULL,NULL)',:'CA'),
  'FEATURE_UNAVAILABLE','non-pilot account refused for a company read');
SELECT pg_temp.expect_refusal('SELECT public.isg_document_portfolio_v1(NULL,NULL,NULL,NULL,10,0)',
  'FEATURE_UNAVAILABLE','non-pilot account refused for the portfolio read');

-- 3. A pilot account still cannot reach another account's company.
SELECT set_config('test.pilot','true',false);
SELECT pg_temp.expect_refusal(format('SELECT public.isg_document_tracking_read_v1(%L,''list'',NULL,NULL,NULL,NULL)',:'CB'),
  'FEATURE_UNAVAILABLE','pilot account refused another owner company');

-- 4. No health record can be tracked, and there is no column for a file.
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.document_obligation_kinds
  WHERE kind_code ILIKE '%health%' OR kind_code ILIKE '%medical%' OR kind_code ILIKE '%saglik%'),
  '0','the kind catalogue holds no health code');
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.columns
  WHERE table_schema='private_isg' AND table_name IN ('document_obligations','document_obligation_records')
    AND column_name IN ('asset_id','evidence_asset_id','file_id','storage_path')),
  '0','no table here has a column for a file');
SELECT pg_temp.expect((SELECT public.isg_document_tracking_read_v1(:'CA','kinds',NULL,NULL,NULL,NULL)->>'health_records_tracked'),
  'false','and the catalogue read says so');
SELECT pg_temp.expect_refusal(format($q$SELECT public.isg_document_tracking_mutate_v1(%L,'add_obligation',gen_random_uuid(),
  gen_random_uuid(),jsonb_build_object('kind_code','health_report','title','Saglik'))$q$,:'CA'),
  'insert or update on table "document_obligations" violates foreign key constraint "document_obligations_kind_code_fkey"',
  'an unknown kind has nothing to arrive under');

-- 5. Calling an obligation legal demands the reference relied upon.
SELECT pg_temp.expect_refusal(format($q$SELECT public.isg_document_tracking_mutate_v1(%L,'add_obligation',gen_random_uuid(),
  gen_random_uuid(),jsonb_build_object('kind_code','other','title','Dayanaksiz','basis','legal'))$q$,:'CA'),
  'new row for relation "document_obligations" violates check constraint "document_obligations_check"',
  'a legal basis without its reference is refused');

-- 6. An obligation with no copy is missing, never valid.
SELECT pg_temp.expect((SELECT public.isg_document_tracking_read_v1(:'CA','detail',NULL,NULL,NULL,
  pg_temp.own(:'CA','Kopyasiz',365,30))->'row'->>'status'),'missing','no copy means missing');

-- 7. The status the dates produce, at each boundary. Notice window is 30 days.
SELECT pg_temp.expect((SELECT public.isg_document_tracking_mutate_v1(:'CA','record_copy',gen_random_uuid(),gen_random_uuid(),
  jsonb_build_object('obligation_id',pg_temp.own(:'CA','Gecerli',365,30),
    'issued_on',(current_date-10)::text,'valid_until',(current_date+90)::text))->'row'->>'status'),
  'valid','a copy good for 90 more days is valid');
SELECT pg_temp.expect((SELECT public.isg_document_tracking_mutate_v1(:'CA','record_copy',gen_random_uuid(),gen_random_uuid(),
  jsonb_build_object('obligation_id',pg_temp.own(:'CA','Yaklasan',365,30),
    'issued_on',(current_date-10)::text,'valid_until',(current_date+30)::text))->'row'->>'status'),
  'due_soon','the last day of the notice window is due_soon');
SELECT pg_temp.expect((SELECT public.isg_document_tracking_mutate_v1(:'CA','record_copy',gen_random_uuid(),gen_random_uuid(),
  jsonb_build_object('obligation_id',pg_temp.own(:'CA','Sinir',365,30),
    'issued_on',(current_date-10)::text,'valid_until',(current_date+31)::text))->'row'->>'status'),
  'valid','one day past the window is still valid');
SELECT pg_temp.expect((SELECT public.isg_document_tracking_mutate_v1(:'CA','record_copy',gen_random_uuid(),gen_random_uuid(),
  jsonb_build_object('obligation_id',pg_temp.own(:'CA','Dolmus',365,30),
    'issued_on',(current_date-400)::text,'valid_until',(current_date-1)::text))->'row'->>'status'),
  'expired','yesterday is expired');

-- 8. The obligation's own period fills the end date when none is given, and an
--    obligation with no period produces a copy that simply stands.
SELECT pg_temp.expect((SELECT (public.isg_document_tracking_mutate_v1(:'CA','record_copy',gen_random_uuid(),gen_random_uuid(),
  jsonb_build_object('obligation_id',pg_temp.own(:'CA','Suresinden',100,30),
    'issued_on',(current_date-10)::text))->'row'->'records'->0->>'valid_until')),
  (current_date+90)::text,'the obligation period fills the end date');
SELECT pg_temp.expect((SELECT public.isg_document_tracking_mutate_v1(:'CA','record_copy',gen_random_uuid(),gen_random_uuid(),
  jsonb_build_object('obligation_id',pg_temp.own(:'CA','Suresiz',NULL,30),
    'issued_on',(current_date-10)::text))->'row'->>'status'),
  'valid','an obligation with no period produces a copy that does not expire');

-- 9. Concurrent editing is refused, not silently merged.
CREATE TEMP TABLE versioned AS SELECT pg_temp.own(:'CA','Surumlu',365,30) AS id;
SELECT pg_temp.expect_refusal(format($q$SELECT public.isg_document_tracking_mutate_v1(%L,'update_obligation',gen_random_uuid(),
  gen_random_uuid(),jsonb_build_object('obligation_id',%L,'expected_version',99,'title','Yeni'))$q$,
  :'CA',(SELECT id FROM versioned)),
  'VERSION_CONFLICT','a stale version is refused');
SELECT pg_temp.expect((SELECT public.isg_document_tracking_mutate_v1(:'CA','update_obligation',gen_random_uuid(),gen_random_uuid(),
  jsonb_build_object('obligation_id',(SELECT id FROM versioned),'expected_version',1,'title','Duzeltilmis'))->'row'->>'title'),
  'Duzeltilmis','the current version is accepted');

-- 10. Archiving takes the row off the board without deleting its history.
CREATE TEMP TABLE archived AS SELECT pg_temp.own(:'CA','Arsivlenecek',365,30) AS id;
SELECT public.isg_document_tracking_mutate_v1(:'CA','archive_obligation',gen_random_uuid(),gen_random_uuid(),
  jsonb_build_object('obligation_id',(SELECT id FROM archived),'expected_version',1));
SELECT pg_temp.expect((SELECT count(*)::text FROM jsonb_array_elements(
  public.isg_document_tracking_read_v1(:'CA','list',NULL,NULL,NULL,NULL)->'rows') AS e
  WHERE e->>'id'=(SELECT id::text FROM archived)),'0','an archived obligation leaves the board');
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.document_obligations
  WHERE obligation_id=(SELECT id FROM archived)),'1','but the row is kept');
SELECT pg_temp.expect_refusal(format($q$SELECT public.isg_document_tracking_mutate_v1(%L,'record_copy',gen_random_uuid(),
  gen_random_uuid(),jsonb_build_object('obligation_id',%L,'issued_on',current_date::text))$q$,
  :'CA',(SELECT id FROM archived)),
  'OBLIGATION_ARCHIVED','and no copy can be filed against it');

-- 11. A copy can be removed, and the status goes back to what it was.
CREATE TEMP TABLE removable AS SELECT pg_temp.own(:'CA','Silinecek',365,30) AS id;
CREATE TEMP TABLE removable_record AS
  SELECT (public.isg_document_tracking_mutate_v1(:'CA','record_copy',gen_random_uuid(),gen_random_uuid(),
    jsonb_build_object('obligation_id',(SELECT id FROM removable),'issued_on',current_date::text))
    ->'row'->'records'->0->>'id')::uuid AS id;
SELECT pg_temp.expect((SELECT public.isg_document_tracking_mutate_v1(:'CA','remove_copy',gen_random_uuid(),gen_random_uuid(),
  jsonb_build_object('obligation_id',(SELECT id FROM removable),'record_id',(SELECT id FROM removable_record)))
  ->'row'->>'status'),'missing','removing the only copy makes the obligation missing again');

-- 12. The same mutation id replays instead of writing twice.
SELECT pg_temp.expect((public.isg_document_tracking_mutate_v1(:'CA','add_obligation',
  '00000000-0000-0000-0000-00000000d001','00000000-0000-0000-0000-0000000000d1',
  jsonb_build_object('kind_code','other','title','Tek Kayit'))->>'replayed'),'false','first save writes');
SELECT pg_temp.expect((public.isg_document_tracking_mutate_v1(:'CA','add_obligation',
  '00000000-0000-0000-0000-00000000d001','00000000-0000-0000-0000-0000000000d1',
  jsonb_build_object('kind_code','other','title','Tek Kayit'))->>'replayed'),'true','the same mutation replays');
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.document_obligations WHERE title='Tek Kayit'),
  '1','and writes only once');
SELECT pg_temp.expect_refusal(format($q$SELECT public.isg_document_tracking_mutate_v1(%L,'add_obligation',
  '00000000-0000-0000-0000-00000000d001','00000000-0000-0000-0000-0000000000d1',
  jsonb_build_object('kind_code','other','title','Baska Kayit'))$q$,:'CA'),
  'IDEMPOTENCY_CONFLICT','the same id with a different body is refused');

-- 13. The tally can never disagree with the list it is counting.
SELECT pg_temp.expect(
  (SELECT sum((value)::int)::text FROM jsonb_each_text(
    public.isg_document_tracking_read_v1(:'CA','list',NULL,NULL,NULL,NULL)->'counts')),
  (SELECT jsonb_array_length(public.isg_document_tracking_read_v1(:'CA','list',NULL,NULL,NULL,NULL)->'rows')::text),
  'the company counts add up to the rows they count');
SELECT pg_temp.expect((SELECT public.isg_document_tracking_read_v1(:'CA','list',NULL,NULL,NULL,NULL)->>'compliance_verdict'),
  NULL,'the list states no compliance verdict');
SELECT pg_temp.expect((SELECT public.isg_document_tracking_read_v1(:'CA','list',NULL,NULL,NULL,NULL)->>'file_storage_available'),
  'false','and never claims a file is held here');

-- 14. The portfolio answers the whole account from one aggregate.
SELECT pg_temp.expect((SELECT public.isg_document_portfolio_v1(NULL,NULL,NULL,NULL,100,0)->>'total'),
  (SELECT count(*)::text FROM private_isg.document_obligations WHERE owner_id=:'A' AND NOT is_archived),
  'the portfolio total matches the live obligations');
SELECT pg_temp.expect((SELECT public.isg_document_portfolio_v1(NULL,'missing',NULL,NULL,100,0)->>'total'),
  (SELECT count(*)::text FROM jsonb_array_elements(
    public.isg_document_tracking_read_v1(:'CA','list',NULL,'missing',NULL,NULL)->'rows')),
  'and its missing filter agrees with the company list');
SELECT pg_temp.expect((SELECT public.isg_document_portfolio_v1(NULL,NULL,NULL,NULL,100,0)->>'file_storage_available'),
  'false','the portfolio never claims a file is held here either');
SELECT pg_temp.expect((SELECT public.isg_document_portfolio_v1(NULL,NULL,NULL,NULL,100,0)->>'compliance_verdict'),
  NULL,'and states no compliance verdict');
SELECT pg_temp.expect((SELECT jsonb_array_length(public.isg_document_portfolio_v1(NULL,NULL,NULL,NULL,5,0)->'rows')::text),
  '5','the server owns the page size');
SELECT pg_temp.expect((SELECT public.isg_document_portfolio_v1(NULL,NULL,NULL,NULL,5,0)->>'has_more'),
  'true','and says when there is more');

-- 15. Closing the feature closes the module, reads and writes alike.
UPDATE private_isg.rollout SET write_enabled=false WHERE feature='document_tracking';
SELECT pg_temp.expect_refusal(format($q$SELECT public.isg_document_tracking_mutate_v1(%L,'add_obligation',gen_random_uuid(),
  gen_random_uuid(),jsonb_build_object('kind_code','other','title','Kapali'))$q$,:'CA'),
  'FEATURE_UNAVAILABLE','a read-only feature refuses the write');
SELECT pg_temp.expect((SELECT public.isg_document_tracking_read_v1(:'CA','list',NULL,NULL,NULL,NULL)->>'kind'),
  'list','while the read still answers');
UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature='document_tracking';
SELECT pg_temp.expect_refusal(format('SELECT public.isg_document_tracking_read_v1(%L,''list'',NULL,NULL,NULL,NULL)',:'CA'),
  'FEATURE_UNAVAILABLE','a closed feature refuses the read');
SELECT pg_temp.expect_refusal('SELECT public.isg_document_portfolio_v1(NULL,NULL,NULL,NULL,10,0)',
  'FEATURE_UNAVAILABLE','and the portfolio with it');
UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='document_tracking';

-- 16. No table grant reaches a client role, and the wrappers are the only way in.
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.role_table_grants
  WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role')),
  '0','no client role holds a table grant in private_isg');
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.routine_privileges
  WHERE routine_schema='public' AND grantee='authenticated'
    AND routine_name IN ('isg_document_tracking_read_v1','isg_document_tracking_mutate_v1','isg_document_portfolio_v1')),
  '3','exactly the three public wrappers are callable');
SELECT 'ALL PILOT DOCUMENT TRACKING CHECKS PASSED' AS result;
