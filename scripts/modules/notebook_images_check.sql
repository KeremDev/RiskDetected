BEGIN;
SELECT set_config('test.actor','20000000-0000-0000-0000-000000000001',true);
SELECT set_config('test.pilot','true',true);
SELECT set_config('test.pilot_write','true',true);
UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true;
UPDATE private_isg.module_registry SET read_enabled=true,write_enabled=true;
INSERT INTO private_isg.file_assets VALUES
 ('50000000-0000-0000-0000-000000000021','20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','image/png','clean'),
 ('50000000-0000-0000-0000-000000000022','20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','application/pdf','clean'),
 ('50000000-0000-0000-0000-000000000023','20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','image/jpeg','clean');
INSERT INTO private_isg.file_library_entries(asset_id,owner_id,company_id) SELECT asset_id,owner_id,company_id FROM private_isg.file_assets;
DO $$ DECLARE payload jsonb:='{"kind":"approved_notebook","values":{"title":"Defter sayfası","note":"Saha tespiti","asset_id":"50000000-0000-0000-0000-000000000021"}}';
 op uuid:=gen_random_uuid(); mutation uuid:=gen_random_uuid(); r jsonb; bad text; changed jsonb; BEGIN
 r:=public.isg_pilot_process_mutate_v1('10000000-0000-0000-0000-000000000001','save',op,mutation,payload);
 IF r IS DISTINCT FROM public.isg_pilot_process_mutate_v1('10000000-0000-0000-0000-000000000001','save',op,mutation,payload) THEN RAISE EXCEPTION 'notebook duplicate'; END IF;
 IF jsonb_array_length(public.isg_pilot_process_read_v1('approved_notebook','10000000-0000-0000-0000-000000000001',null,null,null,0)->'rows')<>1 THEN RAISE EXCEPTION 'notebook list'; END IF;
 PERFORM public.isg_pilot_process_attachment_v1('approved_notebook',(r->>'id')::uuid,'asset_id');
 IF r->'values' ? 'due_on' OR r->'values' ? 'valid_until' THEN RAISE EXCEPTION 'unexpected validity'; END IF;
 FOREACH bad IN ARRAY ARRAY['50000000-0000-0000-0000-000000000022','50000000-0000-0000-0000-000000000023'] LOOP
  BEGIN PERFORM public.isg_pilot_process_mutate_v1('10000000-0000-0000-0000-000000000001','save',gen_random_uuid(),gen_random_uuid(),jsonb_set(payload,'{values,asset_id}',to_jsonb(bad))); RAISE EXCEPTION 'bad image accepted';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'ACCESS_DENIED' THEN RAISE; END IF; END;
 END LOOP;
 BEGIN PERFORM public.isg_pilot_process_mutate_v1('10000000-0000-0000-0000-000000000001','save',gen_random_uuid(),gen_random_uuid(),jsonb_set(payload,'{values,asset_id}','null')); RAISE EXCEPTION 'missing image accepted';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'VALIDATION_ERROR' THEN RAISE; END IF; END;
 changed:=public.isg_pilot_process_mutate_v1('10000000-0000-0000-0000-000000000001','save',gen_random_uuid(),gen_random_uuid(),jsonb_build_object('kind','approved_notebook','id',r->>'id','expected',r->>'expected','values',jsonb_build_object('title','Yeni başlık','note','Not güncellendi')));
 IF changed->'values'->>'asset_id'<>r->'values'->>'asset_id' THEN RAISE EXCEPTION 'image lost on note update'; END IF;
 IF NOT EXISTS(SELECT 1 FROM private_isg.process_record_history WHERE kind='approved_notebook' AND record_id=(r->>'id')::uuid) THEN RAISE EXCEPTION 'history lost'; END IF;
 PERFORM set_config('test.actor','20000000-0000-0000-0000-000000000002',true);
 BEGIN PERFORM public.isg_pilot_process_read_v1('approved_notebook',null,(r->>'id')::uuid,null,null,0);RAISE EXCEPTION 'notebook owner leak';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'ACCESS_DENIED' THEN RAISE; END IF; END;
 PERFORM set_config('test.actor','20000000-0000-0000-0000-000000000001',true);
 PERFORM public.isg_pilot_process_mutate_v1('10000000-0000-0000-0000-000000000001','delete',gen_random_uuid(),gen_random_uuid(),jsonb_build_object('kind','approved_notebook','id',changed->>'id','expected',changed->>'expected'));
 IF jsonb_array_length(public.isg_pilot_process_read_v1('approved_notebook',null,null,null,null,0)->'rows')<>0 THEN RAISE EXCEPTION 'deleted image still listed'; END IF;
 PERFORM set_config('test.pilot','false',true);
 BEGIN PERFORM public.isg_pilot_process_read_v1('approved_notebook',null,null,null,null,0);RAISE EXCEPTION 'nonpilot notebook';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'FEATURE_UNAVAILABLE' THEN RAISE; END IF; END;
 RAISE NOTICE 'ok notebook image-only/create/read/replay/edit/history/delete/owner/pilot/no expiry';
END $$;
ROLLBACK;
