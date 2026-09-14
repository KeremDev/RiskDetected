BEGIN;
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',true);
UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='nonconformity';
DO $$ DECLARE r jsonb; c uuid:='10000000-0000-0000-0000-000000000001'; id_ uuid; BEGIN
r:=public.isg_nonconformity_mutate_v1(c,'open_detailed',gen_random_uuid(),gen_random_uuid(),'{"workplace_id":"40000000-0000-0000-0000-000000000001","title":"Koruyucu eksik","severity":"high","description":"Saha gözlemi","risk_method":"fine_kinney","fk_probability":3,"fk_frequency":3,"fk_severity":7}');
id_:=(r->'row'->>'id')::uuid;
IF (r->'row'->'detail'->>'risk_score')::numeric<>63 THEN RAISE EXCEPTION 'Score wrong'; END IF;
IF public.isg_nonconformity_read_v1(c,'detail',NULL,NULL,NULL,id_)->'row' IS DISTINCT FROM r->'row' THEN RAISE EXCEPTION 'Detail mismatch'; END IF;
PERFORM public.isg_nonconformity_read_v1(c,'list',NULL,NULL,NULL,NULL);
RAISE NOTICE 'ok live-compatible nonconformity detailed create/list/read';
PERFORM set_config('test.actor','20000000-0000-0000-0000-000000000002',true);
BEGIN PERFORM public.isg_nonconformity_read_v1(c,'detail',NULL,NULL,NULL,id_);RAISE EXCEPTION 'Scope leaked'; EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'ACCESS_DENIED' THEN RAISE;END IF; END;
RAISE NOTICE 'ok nonconformity owner isolation';
END $$;
ROLLBACK;
