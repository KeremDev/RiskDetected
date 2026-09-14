SET test.actor='20000000-0000-0000-0000-000000000001';
DO $$ DECLARE r jsonb; BEGIN
 r:=public.isg_statistics_v1(NULL,6);
 ASSERT (r->>'analyses')::int=252,'all analyses, including unassigned, no 200 cap';
 ASSERT (r->>'trainings')::int=1,'multi company training counted once';
 ASSERT (r->>'trained_people')::int=1 AND (r->>'training_enrollments')::int=1;
 ASSERT r->'findings'='null' AND r->'documents'='null','unavailable never zero';
 ASSERT jsonb_array_length(r->'series')=6,'empty months included';
 r:=public.isg_statistics_v1('10000000-0000-0000-0000-000000000001',1);
 ASSERT (r->>'analyses')::int=251 AND (r->>'company_count')::int=1,'company filters unassigned';
 BEGIN PERFORM public.isg_statistics_v1('10000000-0000-0000-0000-000000000002',6); RAISE EXCEPTION 'foreign company accepted';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM NOT IN ('ACCESS_DENIED','FEATURE_UNAVAILABLE') THEN RAISE; END IF; END;
 BEGIN PERFORM public.isg_statistics_v1(NULL,0); RAISE EXCEPTION 'bad months accepted'; EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'VALIDATION_ERROR' THEN RAISE; END IF; END;
 ASSERT NOT has_function_privilege('anon','public.isg_statistics_v1(uuid,integer)','execute');
 END $$;
CREATE TABLE private_isg.rollout(feature text,read_enabled boolean);
INSERT INTO private_isg.rollout VALUES ('nonconformity',true);
CREATE FUNCTION private_isg.require_nonconformity_company(uuid,boolean) RETURNS uuid LANGUAGE sql AS $$ SELECT private_isg.require_company($1,$2) $$;
CREATE TABLE private_isg.nonconformities(owner_id uuid,company_id uuid,state text,opened_on date,due_on date,closed_on date,severity text,record_kind text);
INSERT INTO private_isg.nonconformities SELECT '20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','open',current_date,current_date-1,NULL,'high','nonconformity' FROM generate_series(1,205);
INSERT INTO private_isg.nonconformities VALUES
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','closed',current_date-4,current_date-1,current_date,'low','nonconformity'),
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','open',current_date,current_date-1,NULL,'critical','improvement'),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','open',current_date,current_date-1,NULL,'critical','nonconformity');
CREATE FUNCTION private_isg.read_document_portfolio(text,text,uuid,text[],integer,integer) RETURNS jsonb LANGUAGE sql AS $$
 SELECT '{"companies":[{"id":"10000000-0000-0000-0000-000000000001","counts":{"valid":4,"missing":2}},{"id":"10000000-0000-0000-0000-000000000002","counts":{"valid":999}}]}'::jsonb $$;
DO $$ DECLARE r jsonb; BEGIN
 r:=public.isg_statistics_v1(NULL,6);
 ASSERT (r#>>'{findings,open}')::int=205 AND (r#>>'{findings,overdue}')::int=205,'all actionable rows';
 ASSERT (r#>>'{findings,closed}')::int=1 AND (r#>>'{findings,severity,critical}')::int=0,'closed and improvement separate';
 ASSERT (r#>>'{documents,valid}')::int=4 AND (r#>>'{documents,missing}')::int=2,'document company ownership';
 PERFORM set_config('test.expired','true',true);
 BEGIN PERFORM public.isg_statistics_v1(NULL,6); RAISE EXCEPTION 'expired accepted'; EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'FEATURE_UNAVAILABLE' THEN RAISE; END IF; END;
 END $$;
SELECT 'PASS statistics SQL assertions';
BEGIN;
DO $$ DECLARE r jsonb; boundary timestamptz:=(date_trunc('month',now() AT TIME ZONE 'Europe/Istanbul')) AT TIME ZONE 'Europe/Istanbul'; BEGIN
 INSERT INTO public.analyses(user_id,company_id,kind,status,completed_at,created_at) VALUES
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','photo','completed',boundary,boundary),
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','photo','completed',boundary-interval '1 second',boundary-interval '1 second');
 r:=public.isg_statistics_v1('10000000-0000-0000-0000-000000000003',1);
 ASSERT (r->>'analyses')::int=1,'Istanbul month lower boundary inclusive';
 r:=public.isg_statistics_v1('10000000-0000-0000-0000-000000000003',6);
 ASSERT (r->>'analyses')::int=2,'prior local month preserved';
 UPDATE private_isg.pilot_training_sessions SET deleted_at=now();
 r:=public.isg_statistics_v1(NULL,6);
 ASSERT (r->>'trainings')::int=0,'deleted sessions excluded';
 UPDATE public.companies SET is_archived=true WHERE id='10000000-0000-0000-0000-000000000003';
 r:=public.isg_statistics_v1(NULL,6);
 ASSERT (r->>'company_count')::int=1 AND (r->>'analyses')::int=252,'archived company excluded';
END $$;
ROLLBACK;
SELECT 'PASS local month boundaries, deleted sessions and archived companies';
