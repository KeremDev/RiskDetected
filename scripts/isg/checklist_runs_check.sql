-- Checks for the P09 checklist client boundary. Disposable database only.
-- Expected values are written here by hand; none is read back from the function
-- under test to decide what the function under test should say.
\set ON_ERROR_STOP on
\set A '20000000-0000-0000-0000-000000000001'
\set B '20000000-0000-0000-0000-000000000002'
\set CA '10000000-0000-0000-0000-000000000001'
\set CB '10000000-0000-0000-0000-000000000002'
\set WA '40000000-0000-0000-0000-000000000001'

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
  SELECT public.isg_checklists_mutate_v1(p_company,p_action,gen_random_uuid(),gen_random_uuid(),p_payload) $$;

SELECT set_config('test.actor',:'A',false);

-- 1. The slice adds no switch of its own and opens none.
SELECT pg_temp.expect((SELECT read_enabled::text||','||write_enabled::text FROM private_isg.rollout WHERE feature='nonconformity'),
  'false,false','the nonconformity switch is still closed');
SELECT pg_temp.expect_refusal(format('SELECT public.isg_checklists_read_v1(%L,''list'',NULL,NULL,NULL,NULL,NULL,10,0)',:'CA'),
  'FEATURE_UNAVAILABLE','a closed feature refuses the read');
UPDATE private_isg.rollout SET read_enabled=true WHERE feature='nonconformity';
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,'draft_template',jsonb_build_object('title','Liste'))$q$,:'CA'),
  'FEATURE_UNAVAILABLE','read-only refuses the write');
UPDATE private_isg.rollout SET write_enabled=true WHERE feature='nonconformity';

-- 2. The product ships no question list, and says so rather than looking empty.
SELECT pg_temp.expect((SELECT public.isg_checklists_read_v1(:'CA','catalog',NULL,NULL,NULL,NULL,NULL,NULL,NULL)
  ->>'product_templates_offered'),'false','the product offers no ready-made list');
SELECT pg_temp.expect((SELECT jsonb_array_length(public.isg_checklists_read_v1(:'CA','catalog',NULL,NULL,NULL,NULL,NULL,NULL,NULL)
  ->'templates')::text),'0','and none is published to start from');
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.checklist_templates),'0','no template is seeded at all');

-- 3. The ownership check the core functions never had.
SELECT pg_temp.expect_refusal(format('SELECT public.isg_checklists_read_v1(%L,''list'',NULL,NULL,NULL,NULL,NULL,10,0)',:'CB'),
  'ACCESS_DENIED','another owner company is refused');

-- 4. Authoring: a template, one open draft, and a code that cannot collide.
CREATE TEMP TABLE mine AS SELECT (pg_temp.mutate(:'CA','draft_template',
  jsonb_build_object('title','Yüksekte Çalışma'))->'answer'->>'template_code') AS code;
SELECT pg_temp.expect((SELECT owner_id::text FROM private_isg.checklist_templates WHERE template_code=(SELECT code FROM mine)),
  :'A','a template the expert wrote belongs to the expert');
SELECT pg_temp.expect((pg_temp.mutate(:'CA','draft_template',jsonb_build_object('title','Yüksekte Çalışma'))
  ->'answer'->>'replayed'),'true','a second call returns the draft that is already open');
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.checklist_template_versions
  WHERE template_code=(SELECT code FROM mine)),'1','and writes only one version');

-- 5. Another account writing the same title gets its own code and cannot see
--    the first expert's list.
SELECT set_config('test.actor',:'B',false);
CREATE TEMP TABLE theirs AS SELECT (pg_temp.mutate(:'CB','draft_template',
  jsonb_build_object('title','Yüksekte Çalışma'))->'answer'->>'template_code') AS code;
SELECT pg_temp.expect((SELECT CASE WHEN (SELECT code FROM mine)=(SELECT code FROM theirs) THEN 'same' ELSE 'different' END),
  'different','the same title in two accounts is two codes');
SELECT pg_temp.expect((SELECT jsonb_array_length(public.isg_checklists_read_v1(:'CB','templates',NULL,NULL,NULL,NULL,NULL,NULL,NULL)
  ->'rows')::text),'1','each account sees only its own lists');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,'set_item',jsonb_build_object(
  'template_code',%L,'version',1,'item_code','a1','prompt','Sızma testi','position',1))$q$,
  :'CB',(SELECT code FROM mine)),
  'ACCESS_DENIED','and cannot edit the other account''s list');
SELECT set_config('test.actor',:'A',false);

-- 6. Publishing demands questions and a note, and the approver is not the
--    client's to name.
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,'publish_template',
  jsonb_build_object('template_code',%L,'version',1,'approval_note','Kendi listem'))$q$,:'CA',(SELECT code FROM mine)),
  'VALIDATION_ERROR','an empty list cannot be published');
SELECT pg_temp.mutate(:'CA','set_item',jsonb_build_object('template_code',(SELECT code FROM mine),
  'version',1,'item_code','korkuluk','prompt','Korkuluk var mi?','position',1));
SELECT pg_temp.mutate(:'CA','set_item',jsonb_build_object('template_code',(SELECT code FROM mine),
  'version',1,'item_code','emniyet_kemeri','prompt','Emniyet kemeri kullaniliyor mu?','position',2,
  'allows_not_applicable',false));
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,'publish_template',
  jsonb_build_object('template_code',%L,'version',1,'approver','%s'))$q$,:'CA',(SELECT code FROM mine),:'B'),
  'PAYLOAD_NOT_ALLOWED','a named approver is refused');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,'publish_template',
  jsonb_build_object('template_code',%L,'version',1))$q$,:'CA',(SELECT code FROM mine)),
  'VALIDATION_ERROR','publishing with no note is refused');
SELECT pg_temp.expect((pg_temp.mutate(:'CA','publish_template',jsonb_build_object('template_code',(SELECT code FROM mine),
  'version',1,'approval_note','Kendi hazirladigim liste'))->'answer'->>'status'),
  'published','a list with questions and a note publishes');
SELECT pg_temp.expect((SELECT approved_by::text FROM private_isg.checklist_template_versions
  WHERE template_code=(SELECT code FROM mine) AND version=1),:'A','the approver is the signed-in expert');
SELECT pg_temp.expect((SELECT public.isg_checklists_read_v1(:'CA','templates',NULL,NULL,NULL,NULL,NULL,NULL,NULL)
  ->>'approval_is_self_declared'),'true','and the read says that approval is the expert''s own');

-- 7. A published version is never edited.
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,'set_item',jsonb_build_object(
  'template_code',%L,'version',1,'item_code','korkuluk','prompt','Degisti','position',1))$q$,
  :'CA',(SELECT code FROM mine)),
  'TEMPLATE_PUBLISHED','a published question cannot be rewritten');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,'remove_item',jsonb_build_object(
  'template_code',%L,'version',1,'item_code','korkuluk'))$q$,:'CA',(SELECT code FROM mine)),
  'TEMPLATE_PUBLISHED','nor removed');

-- 8. A run pins the version it was filled against.
CREATE TEMP TABLE run1 AS SELECT (pg_temp.mutate(:'CA','start_run',jsonb_build_object(
  'workplace_id',:'WA','template_code',(SELECT code FROM mine)))->>'run_id')::uuid AS id;
SELECT pg_temp.expect((SELECT template_version::text FROM private_isg.checklist_runs WHERE run_id=(SELECT id FROM run1)),
  '1','the run pins the published version');
-- A second version with a different question, published afterwards.
SELECT pg_temp.mutate(:'CA','draft_template',jsonb_build_object('title','Yüksekte Çalışma'));
SELECT pg_temp.mutate(:'CA','set_item',jsonb_build_object('template_code',(SELECT code FROM mine),
  'version',2,'item_code','yeni_soru','prompt','Yeni eklenen soru','position',3));
SELECT pg_temp.mutate(:'CA','publish_template',jsonb_build_object('template_code',(SELECT code FROM mine),
  'version',2,'approval_note','Ikinci surum'));
SELECT pg_temp.expect((SELECT public.isg_checklists_read_v1(:'CA','detail',NULL,NULL,NULL,NULL,(SELECT id FROM run1),NULL,NULL)
  ->'row'->>'expected'),'2','publishing a newer list does not change what the run asks');
SELECT pg_temp.expect((SELECT status FROM private_isg.checklist_template_versions
  WHERE template_code=(SELECT code FROM mine) AND version=1),'superseded','the old version is superseded, not deleted');
-- The new draft started from what was published rather than from nothing.
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.checklist_template_items
  WHERE template_code=(SELECT code FROM mine) AND version=2),'3','a new version starts from the published one');

-- 9. "Not applicable" is only accepted where the list allows it.
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,'record_item',jsonb_build_object(
  'run_id',%L,'item_code','emniyet_kemeri','result','not_applicable'))$q$,:'CA',(SELECT id FROM run1)),
  'VALIDATION_ERROR','not applicable is refused where the list forbids it');

-- 10. A failing answer never becomes a record on its own.
SELECT pg_temp.mutate(:'CA','record_item',jsonb_build_object('run_id',(SELECT id FROM run1),
  'item_code','korkuluk','result','nonconform','note','Korkuluk yok'));
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.nonconformities),
  '0','a failing answer alone opens nothing');
SELECT pg_temp.expect((SELECT public.isg_checklists_read_v1(:'CA','detail',NULL,NULL,NULL,NULL,(SELECT id FROM run1),NULL,NULL)
  ->'row'->>'nonconformities_opened'),'0','and the run says none was opened');
SELECT pg_temp.expect((SELECT public.isg_checklists_read_v1(:'CA','detail',NULL,NULL,NULL,NULL,(SELECT id FROM run1),NULL,NULL)
  ->'row'->>'auto_nonconformity'),'false','the read states it never converts on its own');

-- 11. A run cannot be submitted while a question is unanswered.
SELECT pg_temp.expect((SELECT public.isg_checklists_read_v1(:'CA','detail',NULL,NULL,NULL,NULL,(SELECT id FROM run1),NULL,NULL)
  ->'row'->>'remaining'),'1','one of the two questions is still open');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,'submit_run',jsonb_build_object('run_id',%L))$q$,
  :'CA',(SELECT id FROM run1)),
  'RUN_INCOMPLETE','an unanswered question blocks submission');

-- 12. Opening a record is a separate, explicit act.
SELECT pg_temp.mutate(:'CA','record_item',jsonb_build_object('run_id',(SELECT id FROM run1),
  'item_code','emniyet_kemeri','result','nonconform','open_nonconformity',true,'severity','high'));
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.nonconformities),
  '1','asking for a record opens exactly one');
SELECT pg_temp.expect((SELECT source_kind FROM private_isg.nonconformities),'checklist',
  'and it knows the checklist is where it came from');
-- Answering the same failing question again reuses the record it made.
SELECT pg_temp.expect((pg_temp.mutate(:'CA','record_item',jsonb_build_object('run_id',(SELECT id FROM run1),
  'item_code','emniyet_kemeri','result','nonconform','open_nonconformity',true,'severity','high'))
  ->'answer'->>'replayed'),'true','answering the same failing question again reuses the record');
SELECT pg_temp.expect((SELECT count(*)::text FROM private_isg.nonconformities),'1','and opens no second one');

-- 13. Once every question is answered the run can be submitted.
SELECT pg_temp.expect((SELECT public.isg_checklists_read_v1(:'CA','detail',NULL,NULL,NULL,NULL,(SELECT id FROM run1),NULL,NULL)
  ->'row'->>'remaining'),'0','once every question is answered nothing remains');
SELECT pg_temp.expect((pg_temp.mutate(:'CA','submit_run',jsonb_build_object('run_id',(SELECT id FROM run1)))
  ->'answer'->>'state'),'submitted','and the run submits');

-- 14. A submitted run is the record of what was checked.
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,'record_item',jsonb_build_object(
  'run_id',%L,'item_code','korkuluk','result','conform'))$q$,:'CA',(SELECT id FROM run1)),
  'RUN_SUBMITTED','no answer changes after submission');
SELECT pg_temp.expect_refusal(format($q$SELECT pg_temp.mutate(%L,'cancel_run',jsonb_build_object('run_id',%L))$q$,
  :'CA',(SELECT id FROM run1)),
  'RUN_SUBMITTED','and it is not withdrawn either');

-- 15. An open run can be cancelled.
CREATE TEMP TABLE run2 AS SELECT (pg_temp.mutate(:'CA','start_run',jsonb_build_object(
  'workplace_id',:'WA','template_code',(SELECT code FROM mine)))->>'run_id')::uuid AS id;
SELECT pg_temp.expect((pg_temp.mutate(:'CA','cancel_run',jsonb_build_object('run_id',(SELECT id FROM run2)))
  ->'answer'->>'state'),'cancelled','an open run can be cancelled');
SELECT pg_temp.expect((pg_temp.mutate(:'CA','cancel_run',jsonb_build_object('run_id',(SELECT id FROM run2)))
  ->'answer'->>'replayed'),'true','and cancelling twice is the same answer');

-- 16. The tally can never disagree with the list it counts.
SELECT pg_temp.expect(
  (SELECT sum((value)::int)::text FROM jsonb_each_text(
    public.isg_checklists_read_v1(NULL,'list',NULL,NULL,NULL,NULL,NULL,100,0)->'counts')),
  (SELECT public.isg_checklists_read_v1(NULL,'list',NULL,NULL,NULL,NULL,NULL,100,0)->>'total'),
  'the account counts add up to the rows they count');
SELECT pg_temp.expect((SELECT public.isg_checklists_read_v1(NULL,'list',NULL,NULL,NULL,NULL,NULL,100,0)
  ->>'compliance_verdict'),NULL,'the list states no compliance verdict');
SELECT pg_temp.expect((SELECT public.isg_checklists_read_v1(NULL,'list',NULL,'submitted',NULL,NULL,NULL,100,0)
  ->>'total'),'1','the submitted filter agrees with its counter');

-- 17. The same mutation id replays instead of writing twice.
SELECT pg_temp.expect((public.isg_checklists_mutate_v1(:'CA','start_run',
  '00000000-0000-0000-0000-00000000f001','00000000-0000-0000-0000-0000000000f1',
  jsonb_build_object('workplace_id',:'WA','template_code',(SELECT code FROM mine)))->>'replayed'),
  'false','first save writes');
SELECT pg_temp.expect((public.isg_checklists_mutate_v1(:'CA','start_run',
  '00000000-0000-0000-0000-00000000f001','00000000-0000-0000-0000-0000000000f1',
  jsonb_build_object('workplace_id',:'WA','template_code',(SELECT code FROM mine)))->>'replayed'),
  'true','the same mutation replays');
SELECT pg_temp.expect_refusal(format($q$SELECT public.isg_checklists_mutate_v1(%L,'start_run',
  '00000000-0000-0000-0000-00000000f001','00000000-0000-0000-0000-0000000000f1',
  jsonb_build_object('workplace_id',%L,'template_code',%L,'started_on',(current_date-1)::text))$q$,
  :'CA',:'WA',(SELECT code FROM mine)),
  'IDEMPOTENCY_CONFLICT','the same id with a different body is refused');

-- 18. No table grant reaches a client role, and the wrappers are the only way in.
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.role_table_grants
  WHERE table_schema='private_isg' AND grantee IN ('anon','authenticated','service_role')),
  '0','no client role holds a table grant in private_isg');
SELECT pg_temp.expect((SELECT count(*)::text FROM information_schema.routine_privileges
  WHERE routine_schema='public' AND grantee='authenticated' AND routine_name LIKE 'isg_checklists%'),
  '2','exactly the two public wrappers are callable');
SELECT 'ALL CHECKLIST RUN CHECKS PASSED' AS result;
