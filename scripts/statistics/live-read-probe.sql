BEGIN;
DO $$ BEGIN
 PERFORM set_config('request.jwt.claims',(SELECT jsonb_build_object('role','authenticated','sub',a.actor_id,'session_id',s.id,'exp',floor(extract(epoch FROM now()+interval '1 hour')))::text
 FROM private_isg.p05_pilot_accounts a JOIN auth.sessions s ON s.user_id=a.actor_id WHERE a.revoked_at IS NULL AND a.expires_at>now() AND (s.not_after IS NULL OR s.not_after>now()) ORDER BY s.created_at DESC LIMIT 1),true);
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; filtered jsonb; n int; c jsonb; BEGIN
 FOREACH n IN ARRAY ARRAY[1,3,6,12] LOOP
  r:=public.isg_statistics_v1(NULL,n);
  ASSERT (r->>'months')::int=n AND jsonb_array_length(r->'series')=n;
  ASSERT (r->>'analyses')::int=(SELECT sum((x->>'analyses')::int) FROM jsonb_array_elements(r->'series') x);
  ASSERT (r->>'trainings')::int=(SELECT sum((x->>'trainings')::int) FROM jsonb_array_elements(r->'series') x);
 END LOOP;
 FOR c IN SELECT value FROM jsonb_array_elements(r->'companies') LOOP
  filtered:=public.isg_statistics_v1((c->>'id')::uuid,6);
  ASSERT (filtered->>'company_id')::uuid=(c->>'id')::uuid;
  ASSERT (filtered->>'company_count')::int=1;
 END LOOP;
 BEGIN PERFORM public.isg_statistics_v1(gen_random_uuid(),6); RAISE EXCEPTION 'unknown company accepted';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM NOT IN ('ACCESS_DENIED','FEATURE_UNAVAILABLE') THEN RAISE; END IF; END;
END $$;
RESET ROLE;
ROLLBACK;
SELECT 'PASS: authenticated statistics read; all periods, companies, totals and unknown-company denial; no data writes' AS result;
