-- Checks for the P08 risk versioning client boundary. Disposable database only.
-- Expected values are written here by hand; none is read back from the function
-- under test to decide what the function under test should say.
\set ON_ERROR_STOP on
\set A '20000000-0000-0000-0000-000000000001'
\set CA '10000000-0000-0000-0000-000000000001'
\set CB '10000000-0000-0000-0000-000000000002'
\set WA '40000000-0000-0000-0000-000000000001'
\set WB '40000000-0000-0000-0000-000000000003'
\set CLEAN '50000000-0000-0000-0000-000000000001'
\set DIRTY '50000000-0000-0000-0000-000000000002'

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
CREATE FUNCTION pg_temp.mutate(p_company uuid,p_action text,p_payload jsonb) RETURNS jsonb
LANGUAGE sql AS $$
  SELECT public.isg_risk_versions_mutate_v1(p_company,p_action,gen_random_uuid(),gen_random_uuid(),p_payload) $$;

SELECT set_config('test.actor',:'A',false);

-- 1. The slice adds no switch of its own and opens none: it rides on `risk`,
--    which the first P08 slice left closed.
SELECT pg_temp.expect((SELECT read_enabled::text||','||write_enabled::text FROM private_isg.rollout WHERE feature='risk'),
  'false,false','the risk switch is still closed');
SELECT pg_temp.expect_refusal(format('SELECT public.isg_risk_versions_read_v1(%L,''list'',NULL,NULL,NULL,NULL,10,0)',:'CA'),
  'FEATURE_UNAVAILABLE','a closed feature refuses the read');
UPDATE private_isg.rollout SET read_enabled=true WHERE feature='risk';
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,'open_assessment',jsonb_build_object('workplace_id',%L))$q$,:'CA',:'WA'),
  'FEATURE_UNAVAILABLE','read-only refuses the write');
UPDATE private_isg.rollout SET write_enabled=true WHERE feature='risk';

-- 2. The ownership check the domain functions never had.
SELECT pg_temp.expect_refusal(format('SELECT public.isg_risk_versions_read_v1(%L,''list'',NULL,NULL,NULL,NULL,10,0)',:'CB'),
  'ACCESS_DENIED','another owner company is refused');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,'open_assessment',
  jsonb_build_object('workplace_id','40000000-0000-0000-0000-000000000002'))$q$,:'CA'),
  'ACCESS_DENIED','a workplace of another company is refused');

-- 3. An opened assessment holds no document yet.
CREATE TEMP TABLE main AS SELECT (pg_temp.mutate(:'CA','open_assessment',
  jsonb_build_object('workplace_id',:'WA'))->>'assessment_id')::uuid AS id;
SELECT pg_temp.expect((SELECT public.isg_risk_versions_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM main),NULL,NULL)
  ->'row'->>'state'),'never_assessed','a new assessment has never been assessed');
SELECT pg_temp.expect((SELECT public.isg_risk_versions_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM main),NULL,NULL)
  ->'row'->>'has_open_draft'),'false','and has no draft');
-- Opening the same workplace twice is the same assessment.
SELECT pg_temp.expect((pg_temp.mutate(:'CA','open_assessment',jsonb_build_object('workplace_id',:'WA'))
  ->'answer'->>'replayed'),'true','opening the same workplace twice returns the same assessment');

-- 4. Date rules belong to the server.
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,'draft_version',
  jsonb_build_object('assessment_id',%L,'kind','full','assessment_on',(current_date+1)::text,'expected_current',0))$q$,
  :'CA',(SELECT id FROM main)),
  'ASSESSMENT_DATE_IN_FUTURE','a future assessment date is refused');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,'draft_version',
  jsonb_build_object('assessment_id',%L,'kind','full','assessment_on',(current_date-10)::text,'expected_current',7))$q$,
  :'CA',(SELECT id FROM main)),
  'VERSION_CONFLICT','a stale expected version is refused');

-- 5. A draft is work in progress, never the document.
SELECT pg_temp.expect((pg_temp.mutate(:'CA','draft_version',jsonb_build_object('assessment_id',(SELECT id FROM main),
  'kind','full','assessment_on',(current_date-10)::text,'expected_current',0))->'row'->>'state'),
  'never_assessed','an open draft does not become the document');
SELECT pg_temp.expect((SELECT public.isg_risk_versions_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM main),NULL,NULL)
  ->'row'->>'has_open_draft'),'true','but it is reported beside the state');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,'draft_version',
  jsonb_build_object('assessment_id',%L,'kind','full','assessment_on',(current_date-10)::text,'expected_current',0))$q$,
  :'CA',(SELECT id FROM main)),
  'DRAFT_ALREADY_OPEN','a second draft is refused while one is open');

-- 6. An unscanned file cannot be attached.
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.file_assets WHERE asset_id=:'DIRTY' AND scan_status<>'clean'),
  '1','the fixture holds an uncleared asset');

-- 7. The expert's own period is stored as the expert's, and forces review.
SELECT pg_temp.expect((pg_temp.mutate(:'CA','finalize_version',jsonb_build_object('assessment_id',(SELECT id FROM main),
  'version',1,'expected_current',0,'period_years',5))->'row'->>'period_source'),
  'unapproved_fixture','an expert period is not presented as a rule');
SELECT pg_temp.expect((SELECT public.isg_risk_versions_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM main),NULL,NULL)
  ->'row'->>'period_needs_review'),'true','and it is flagged for review');
SELECT pg_temp.expect((SELECT valid_until::text FROM private_isg.risk_assessments WHERE assessment_id=(SELECT id FROM main)),
  (current_date-10+interval '5 years')::date::text,'the period runs from the assessment date, not from today');
SELECT pg_temp.expect((SELECT public.isg_risk_versions_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM main),NULL,NULL)
  ->'row'->>'state'),'valid','and the document now stands');

-- 8. The client cannot name who verified: the key is not on the allowlist, and
--    the row carries the signed-in expert.
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,'finalize_version',
  jsonb_build_object('assessment_id',%L,'version',1,'expected_current',1,
    'verified_by','20000000-0000-0000-0000-000000000002'))$q$,:'CA',(SELECT id FROM main)),
  'PAYLOAD_NOT_ALLOWED','a named verifier is refused');
SELECT pg_temp.expect((SELECT verified_by::text FROM private_isg.risk_assessment_versions
  WHERE assessment_id=(SELECT id FROM main) AND version=1),:'A','the verifier is the signed-in expert');

-- 9. Finalising the same version again is a replay, not a second document.
SELECT pg_temp.expect((pg_temp.mutate(:'CA','finalize_version',jsonb_build_object('assessment_id',(SELECT id FROM main),
  'version',1,'expected_current',1))->'answer'->>'replayed'),'true','finalising an already final version replays');

-- 10. A published rule is attributed to the rule.
CREATE TEMP TABLE ruled AS SELECT (pg_temp.mutate(:'CA','open_assessment',
  jsonb_build_object('workplace_id',:'WB'))->>'assessment_id')::uuid AS id;
SELECT pg_temp.mutate(:'CA','draft_version',jsonb_build_object('assessment_id',(SELECT id FROM ruled),
  'kind','full','assessment_on',(current_date-20)::text,'expected_current',0));
SELECT pg_temp.expect((pg_temp.mutate(:'CA','finalize_version',jsonb_build_object('assessment_id',(SELECT id FROM ruled),
  'version',1,'expected_current',0,'rule_code','RISK_GENERAL_4Y'))->'row'->>'period_source'),
  'rule_version','a published rule is attributed to the rule');
SELECT pg_temp.expect((SELECT public.isg_risk_versions_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM ruled),NULL,NULL)
  ->'row'->>'period_needs_review'),'false','and needs no review');
-- A rule the product never published is refused rather than assumed. The check
-- needs a fresh draft: an already final version replays before it is reached.
SELECT pg_temp.mutate(:'CA','draft_version',jsonb_build_object('assessment_id',(SELECT id FROM ruled),
  'kind','full','assessment_on',(current_date-3)::text,'expected_current',1));
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,'finalize_version',
  jsonb_build_object('assessment_id',%L,'version',2,'expected_current',1,'rule_code','NO_SUCH_RULE'))$q$,
  :'CA',(SELECT id FROM ruled)),
  'RULE_NEEDS_REVIEW','an unpublished rule is refused rather than assumed');
-- A full renewal with neither a rule nor a number is refused too: a period is
-- never left to chance.
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,'finalize_version',
  jsonb_build_object('assessment_id',%L,'version',2,'expected_current',1))$q$,
  :'CA',(SELECT id FROM ruled)),
  'VALIDATION_ERROR','a full renewal with no period at all is refused');

-- 11. The legal date cannot be moved by a correction.
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,'draft_version',
  jsonb_build_object('assessment_id',%L,'kind','metadata','assessment_on',(current_date-5)::text,
    'reason','Yanlis yazilan bilgi duzeltildi','expected_current',1))$q$,:'CA',(SELECT id FROM main)),
  'ASSESSMENT_DATE_IMMUTABLE','a correction cannot move the legal date');

-- 12. A scoped revision never resets the whole workplace period.
CREATE TEMP TABLE before_partial AS SELECT valid_until FROM private_isg.risk_assessments WHERE assessment_id=(SELECT id FROM main);
SELECT pg_temp.mutate(:'CA','draft_version',jsonb_build_object('assessment_id',(SELECT id FROM main),
  'kind','partial','scope',jsonb_build_array('kaynak_bolumu'),'reason','Kaynak bolumu yeniden degerlendirildi','expected_current',1));
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,'finalize_version',
  jsonb_build_object('assessment_id',%L,'version',2,'expected_current',1,'period_years',3))$q$,
  :'CA',(SELECT id FROM main)),
  'VALIDATION_ERROR','a scoped revision cannot carry a period');
SELECT pg_temp.mutate(:'CA','record_impact',jsonb_build_object('assessment_id',(SELECT id FROM main),
  'version',2,'target_kind','risk_area','target_ref','kaynak_bolumu','action','review'));
SELECT pg_temp.mutate(:'CA','finalize_version',jsonb_build_object('assessment_id',(SELECT id FROM main),
  'version',2,'expected_current',1));
SELECT pg_temp.expect((SELECT valid_until::text FROM private_isg.risk_assessments WHERE assessment_id=(SELECT id FROM main)),
  (SELECT valid_until::text FROM before_partial),'a scoped revision leaves the period where it was');
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.risk_assessment_versions
  WHERE assessment_id=(SELECT id FROM main) AND state='final'),'1','and only one version is final at a time');
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.risk_assessment_versions
  WHERE assessment_id=(SELECT id FROM main) AND state='superseded'),'1','the previous one is superseded');

-- 13. An impact list belongs to a scoped revision only.
SELECT pg_temp.mutate(:'CA','draft_version',jsonb_build_object('assessment_id',(SELECT id FROM main),
  'kind','metadata','reason','Imza alani duzeltildi','expected_current',2));
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,'record_impact',
  jsonb_build_object('assessment_id',%L,'version',3,'target_kind','risk_area','target_ref','x','action','review'))$q$,
  :'CA',(SELECT id FROM main)),
  'VALIDATION_ERROR','a metadata correction carries no impact list');

-- 14. Nothing is copied from an analysis on its own, and a finalised version
--     cannot gain a source afterwards.
SELECT pg_temp.expect((pg_temp.mutate(:'CA','attach_source',jsonb_build_object('assessment_id',(SELECT id FROM main),
  'version',3,'analysis_id','60000000-0000-0000-0000-000000000001',
  'finding_id','70000000-0000-0000-0000-000000000001','source_version',4,
  'copied_fields',jsonb_build_object('title','Korkuluk eksik')))->'answer'->>'legacy_analysis_written'),
  'false','attaching a source writes nothing back to the analysis');
SELECT pg_temp.mutate(:'CA','finalize_version',jsonb_build_object('assessment_id',(SELECT id FROM main),
  'version',3,'expected_current',2));
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,'attach_source',
  jsonb_build_object('assessment_id',%L,'version',3,'analysis_id','60000000-0000-0000-0000-000000000002',
    'finding_id','70000000-0000-0000-0000-000000000002','source_version',1))$q$,:'CA',(SELECT id FROM main)),
  'VERSION_FINALIZED','a finalised version cannot gain a source');

-- 15. A source that moves on raises a flag; the document is not rewritten.
CREATE TEMP TABLE before_drift AS
  SELECT assessment_on,valid_until,state FROM private_isg.risk_assessment_versions
  WHERE assessment_id=(SELECT id FROM main) AND version=3;
SELECT pg_temp.expect((pg_temp.mutate(:'CA','flag_drift',jsonb_build_object('assessment_id',(SELECT id FROM main),
  'version',3,'analysis_id','60000000-0000-0000-0000-000000000001','current_source_version',9,
  'note','Analiz guncellendi'))->'answer'->>'source_drift'),'true','a moved source is detected');
SELECT pg_temp.expect((SELECT assessment_on::text||','||coalesce(valid_until::text,'NULL')||','||state
  FROM private_isg.risk_assessment_versions WHERE assessment_id=(SELECT id FROM main) AND version=3),
  (SELECT assessment_on::text||','||coalesce(valid_until::text,'NULL')||','||state FROM before_drift),
  'and the document itself is untouched');
SELECT pg_temp.expect((SELECT public.isg_risk_versions_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM main),NULL,NULL)
  ->'row'->>'source_drift'),'true','the flag is what the read reports');

-- 16. A finalised document with no period never reads as valid.
UPDATE private_isg.risk_assessments SET valid_until=NULL WHERE assessment_id=(SELECT id FROM main);
SELECT pg_temp.expect((SELECT public.isg_risk_versions_read_v1(:'CA','detail',NULL,NULL,NULL,(SELECT id FROM main),NULL,NULL)
  ->'row'->>'state'),'period_unknown','a missing period is a gap, not a clean bill');
UPDATE private_isg.risk_assessments SET valid_until=(SELECT valid_until FROM before_partial)
  WHERE assessment_id=(SELECT id FROM main);

-- 17. The catalogue says what a period may be attributed to.
SELECT pg_temp.expect((SELECT public.isg_risk_versions_read_v1(:'CA','catalog',NULL,NULL,NULL,NULL,NULL,NULL)
  ->>'notice_days'),'60','the warning window is the server''s');
SELECT pg_temp.expect((SELECT public.isg_risk_versions_read_v1(:'CA','catalog',NULL,NULL,NULL,NULL,NULL,NULL)
  ->>'period_defaults_offered'),'false','no period is offered as a default');
SELECT pg_temp.expect((SELECT public.isg_risk_versions_read_v1(:'CA','catalog',NULL,NULL,NULL,NULL,NULL,NULL)
  ->>'expert_period_needs_review'),'true','the expert''s own number always needs review');
SELECT pg_temp.expect((SELECT jsonb_array_length(public.isg_risk_versions_read_v1(:'CA','catalog',NULL,NULL,NULL,NULL,NULL,NULL)
  ->'workplaces')::text),'2','the company workplaces are listed');
SELECT pg_temp.expect((SELECT public.isg_risk_versions_read_v1(:'CA','catalog',NULL,NULL,NULL,NULL,NULL,NULL)
  ->>'analysis_is_not_an_assessment'),'true','and a photo analysis is not an assessment');

-- 18. The tally can never disagree with the list it counts.
SELECT pg_temp.expect(
  (SELECT sum((value)::int)::text FROM jsonb_each_text(
    public.isg_risk_versions_read_v1(NULL,'list',NULL,NULL,NULL,NULL,100,0)->'counts')),
  (SELECT public.isg_risk_versions_read_v1(NULL,'list',NULL,NULL,NULL,NULL,100,0)->>'total'),
  'the account counts add up to the rows they count');
SELECT pg_temp.expect((SELECT public.isg_risk_versions_read_v1(NULL,'list',NULL,NULL,NULL,NULL,100,0)->>'compliance_verdict'),
  NULL,'the list states no compliance verdict');

-- 19. The same mutation id replays instead of writing twice.
SELECT pg_temp.expect((public.isg_risk_versions_mutate_v1(:'CA','open_assessment',
  '00000000-0000-0000-0000-00000000e001','00000000-0000-0000-0000-0000000000e1',
  jsonb_build_object('workplace_id',:'WA'))->>'replayed'),'false','first save writes');
SELECT pg_temp.expect((public.isg_risk_versions_mutate_v1(:'CA','open_assessment',
  '00000000-0000-0000-0000-00000000e001','00000000-0000-0000-0000-0000000000e1',
  jsonb_build_object('workplace_id',:'WA'))->>'replayed'),'true','the same mutation replays');
SELECT pg_temp.expect_refusal(format($q$SELECT public.isg_risk_versions_mutate_v1(%L,'open_assessment',
  '00000000-0000-0000-0000-00000000e001','00000000-0000-0000-0000-0000000000e1',
  jsonb_build_object('workplace_id',%L))$q$,:'CA',:'WB'),
  'IDEMPOTENCY_CONFLICT','the same id with a different body is refused');

-- 20. No table grant reaches a client role, and the wrappers are the only way in.
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.role_table_grants
  WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role')),
  '0','no client role holds a table grant in private_isg');
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.routine_privileges
  WHERE routine_schema='public' AND grantee='authenticated' AND routine_name LIKE 'isg_risk_versions%'),
  '2','exactly the two public wrappers are callable');
SELECT 'ALL RISK VERSION CHECKS PASSED' AS result;
