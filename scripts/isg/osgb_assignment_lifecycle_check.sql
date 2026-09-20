-- A scheduled finite primary interval must not allow another primary expert.
DO $$ DECLARE c uuid := (SELECT value::uuid FROM company_test_state WHERE key='company');
  a jsonb; b jsonb; r jsonb; start_time timestamptz := clock_timestamp()+interval '2 days';
BEGIN
  a:=public.isg_workspace_assignment_mutate_v1(gen_random_uuid(),
    '41000000-0000-4000-8000-000000000001',c,NULL,
    '42000000-0000-4000-8000-000000000002',0,'create','primary',start_time,
    start_time+interval '2 days','planned primary');
  BEGIN
    PERFORM public.isg_workspace_assignment_mutate_v1(gen_random_uuid(),
      '41000000-0000-4000-8000-000000000001',c,NULL,
      '42000000-0000-4000-8000-000000000003',0,'create','primary',start_time,
      start_time+interval '1 day','overlapping primary');
    RAISE EXCEPTION 'EXPECTED_PRIMARY_OVERLAP';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'ASSIGNMENT_OVERLAP' THEN RAISE; END IF; END;
  -- Cancel before the effective date: preserve history as an empty interval.
  b:=public.isg_workspace_assignment_mutate_v1(gen_random_uuid(),
    '41000000-0000-4000-8000-000000000001',c,(a->>'assignment_id')::uuid,
    NULL,0,'end',NULL,NULL,clock_timestamp(),'cancel before start');
  IF b->>'ends_at' IS DISTINCT FROM b->>'starts_at' OR b->>'version'<>'1' THEN
    RAISE EXCEPTION 'future cancellation failed'; END IF;
  r:=public.isg_workspace_assignment_list_v1('41000000-0000-4000-8000-000000000001',c,'future',NULL,100);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(r->'rows') x WHERE x->>'assignment_id'=a->>'assignment_id') THEN
    RAISE EXCEPTION 'cancelled assignment still planned'; END IF;
  r:=public.isg_workspace_assignment_list_v1('41000000-0000-4000-8000-000000000001',c,'ended',NULL,100);
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'rows') x WHERE x->>'assignment_id'=a->>'assignment_id') THEN
    RAISE EXCEPTION 'cancelled assignment missing from history'; END IF;
  -- A finite current assignment can be ended early, without extending it.
  a:=public.isg_workspace_assignment_mutate_v1(gen_random_uuid(),
    '41000000-0000-4000-8000-000000000001',c,NULL,
    '42000000-0000-4000-8000-000000000003',0,'create','support',clock_timestamp()-interval '1 hour',
    clock_timestamp()+interval '1 day','finite current');
  b:=public.isg_workspace_assignment_mutate_v1(gen_random_uuid(),
    '41000000-0000-4000-8000-000000000001',c,(a->>'assignment_id')::uuid,
    NULL,0,'end',NULL,NULL,clock_timestamp(),'end finite assignment');
  IF (b->>'ends_at')::timestamptz >= (a->>'ends_at')::timestamptz THEN
    RAISE EXCEPTION 'finite assignment was not shortened'; END IF;
  BEGIN
    PERFORM public.isg_workspace_assignment_mutate_v1(gen_random_uuid(),
      '41000000-0000-4000-8000-000000000001',c,(b->>'assignment_id')::uuid,
      NULL,1,'end',NULL,NULL,clock_timestamp()+interval '1 day','try to extend ended access');
    RAISE EXCEPTION 'EXPECTED_CLOSED_ASSIGNMENT_CONFLICT';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'ASSIGNMENT_CONFLICT' THEN RAISE; END IF; END;
  BEGIN
    PERFORM public.isg_workspace_assignment_list_v1('41000000-0000-4000-8000-000000000001',c,'all',NULL,NULL);
    RAISE EXCEPTION 'EXPECTED_NULL_LIMIT_REJECTION';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'VALIDATION_ERROR' THEN RAISE; END IF; END;
  BEGIN
    PERFORM public.isg_workspace_assignment_list_v1('41000000-0000-4000-8000-000000000001',c,NULL,NULL,100);
    RAISE EXCEPTION 'EXPECTED_NULL_STATUS_REJECTION';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'VALIDATION_ERROR' THEN RAISE; END IF; END;
  BEGIN
    PERFORM public.isg_workspace_company_list_v1('41000000-0000-4000-8000-000000000001',NULL,NULL);
    RAISE EXCEPTION 'EXPECTED_NULL_COMPANY_LIMIT_REJECTION';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'VALIDATION_ERROR' THEN RAISE; END IF; END;
  RAISE NOTICE 'ok assignment finite primary overlap, future cancellation and early termination';
END $$;
