-- Run after shared_expert_acceptance.sql inside BEGIN/ROLLBACK.

CREATE TEMP TABLE expert_analysis_results(test text,passed boolean,detail text);
DO $test$
DECLARE w uuid:=current_setting('isg.test_workspace')::uuid; a uuid; c uuid; item uuid; r jsonb; p jsonb; workplace uuid; detail text; item_kind text;
BEGIN
 r:=public.isg_expert_rpc_v1(w,'isg_expert_analysis_v1','{"p_action":"list","p_payload":{}}')->'payload';
 a:=(r#>>'{rows,0,id}')::uuid; c:=(r#>>'{rows,0,company_id}')::uuid;
 IF a IS NULL THEN RAISE EXCEPTION 'TEST_ANALYSIS_REQUIRED'; END IF;
 BEGIN
 r:=public.isg_expert_rpc_v1(w,'isg_expert_analysis_v1',jsonb_build_object('p_action','detail','p_payload',jsonb_build_object('analysis_id',a)))->'payload';
 IF (r#>>'{analysis,id}')::uuid<>a OR jsonb_array_length(r->'photos')<1 THEN RAISE EXCEPTION 'ANALYSIS_OR_PHOTO_MISSING'; END IF;
 item:=coalesce((r#>>'{risk_findings,0,id}')::uuid,(r#>>'{expert_items,0,id}')::uuid);
 item_kind:=CASE WHEN r#>>'{risk_findings,0,id}' IS NOT NULL OR r#>>'{expert_items,0,kind}'='unscored_finding' THEN 'finding' ELSE 'expert_item' END;
 INSERT INTO expert_analysis_results VALUES('analysis detail and source photos',true,NULL);
 EXCEPTION WHEN OTHERS THEN INSERT INTO expert_analysis_results VALUES('analysis detail and source photos',false,SQLERRM); END;
 BEGIN
 PERFORM public.isg_expert_rpc_v1(w,'isg_expert_analysis_v1',jsonb_build_object('p_action','edit','p_payload',jsonb_build_object('analysis_id',a,'item_id',item,'title','Rollback edited finding')));
 PERFORM public.isg_expert_rpc_v1(w,'isg_expert_analysis_v1',jsonb_build_object('p_action','react','p_payload',jsonb_build_object('analysis_id',a,'item_id',item,'reaction','like')));
 r:=public.isg_expert_rpc_v1(w,'isg_expert_analysis_v1',jsonb_build_object('p_action','detail','p_payload',jsonb_build_object('analysis_id',a)))->'payload';
 IF r#>>ARRAY['feedback',item::text]<>'like' THEN RAISE EXCEPTION 'FEEDBACK_MISSING'; END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements((r->'risk_findings')||(r->'expert_items')) x WHERE x->>'title'='Rollback edited finding') THEN RAISE EXCEPTION 'EDIT_MISSING'; END IF;
 INSERT INTO expert_analysis_results VALUES('analysis edit and feedback',true,NULL);
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS detail=PG_EXCEPTION_CONTEXT; INSERT INTO expert_analysis_results VALUES('analysis edit and feedback',false,SQLERRM||E'\n'||detail); END;
 BEGIN
 r:=public.isg_expert_rpc_v1(w,'isg_nonconformity_read_v1',jsonb_build_object('p_company',c,'p_kind','workplaces','p_query',NULL,'p_state',NULL,'p_after',NULL,'p_id',NULL))->'payload';
 workplace:=(r#>>'{rows,0,id}')::uuid;
 r:=public.isg_expert_rpc_v1(w,'isg_expert_analysis_v1',jsonb_build_object('p_action','file','p_payload',jsonb_build_object('analysis_id',a,'item_id',item,'item_kind',item_kind,'severity','medium','workplace_id',workplace,'mutation_id',gen_random_uuid())))->'payload';
 IF r->>'nonconformity_id' IS NULL THEN RAISE EXCEPTION 'FILING_MISSING'; END IF;
 INSERT INTO expert_analysis_results VALUES('analysis finding into shared nonconformity store',true,NULL);
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS detail=PG_EXCEPTION_CONTEXT; INSERT INTO expert_analysis_results VALUES('analysis finding into shared nonconformity store',false,SQLERRM||E'\n'||detail); END;
 BEGIN
 r:=public.isg_expert_rpc_v1(w,'isg_expert_analysis_v1',jsonb_build_object('p_action','export','p_payload',jsonb_build_object('analysis_id',a,'format','pdf','mutation_id',gen_random_uuid())))->'payload';
 IF r->>'id' IS NULL AND r#>>'{row,id}' IS NULL THEN RAISE EXCEPTION 'EXPORT_MISSING: %',r; END IF;
 INSERT INTO expert_analysis_results VALUES('analysis export queue',true,NULL);
 EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS detail=PG_EXCEPTION_CONTEXT; INSERT INTO expert_analysis_results VALUES('analysis export queue',false,SQLERRM||E'\n'||detail); END;
 BEGIN
 PERFORM public.isg_expert_rpc_v1(w,'isg_expert_analysis_v1',jsonb_build_object('p_action','remove','p_payload',jsonb_build_object('analysis_id',a,'item_id',item)));
 r:=public.isg_expert_rpc_v1(w,'isg_expert_analysis_v1',jsonb_build_object('p_action','detail','p_payload',jsonb_build_object('analysis_id',a)))->'payload';
 IF EXISTS(SELECT 1 FROM jsonb_array_elements((r->'risk_findings')||(r->'expert_items')) x WHERE (x->>'id')::uuid=item) THEN RAISE EXCEPTION 'DELETE_NOT_APPLIED'; END IF;
 INSERT INTO expert_analysis_results VALUES('analysis item delete',true,NULL);
 EXCEPTION WHEN OTHERS THEN INSERT INTO expert_analysis_results VALUES('analysis item delete',false,SQLERRM); END;
END $test$;
SELECT * FROM expert_analysis_results;
