-- Rollback-only scored source fixture and shared detail projection test.
RESET ROLE;
CREATE TEMP TABLE expert_score_fixture AS
 SELECT a.id analysis,a.company_id,c.id workplace,gen_random_uuid() item,a.workspace_id
 FROM private_isg.workspace_analyses a JOIN private_isg.workplaces c ON c.company_id=a.company_id AND NOT c.is_archived
 WHERE a.workspace_id=current_setting('isg.test_workspace')::uuid LIMIT 1;
INSERT INTO private_isg.workspace_analysis_findings(id,workspace_id,company_id,analysis_id,source_key,ordinal,display_order,item_class,is_scored,title,description,recommended_action,fk_probability,fk_frequency,fk_severity,fk_score,fk_band,m5_probability,m5_severity,m5_score,m5_band)
 SELECT item,workspace_id,company_id,analysis,'qa-score-'||item,999,999,'observed_finding',true,'QA scored source','QA description','QA measure',3,6,15,270,'high',3,4,12,'medium' FROM expert_score_fixture;
GRANT SELECT ON expert_score_fixture TO authenticated;
SET LOCAL ROLE authenticated;
DO $$ DECLARE f record; r jsonb; BEGIN
 SELECT * INTO f FROM expert_score_fixture;
 r:=public.isg_expert_rpc_v1(f.workspace_id,'isg_expert_analysis_v1',jsonb_build_object('p_action','file','p_payload',jsonb_build_object('analysis_id',f.analysis,'item_id',f.item,'item_kind','finding','severity','high','workplace_id',f.workplace,'mutation_id',gen_random_uuid())))->'payload';
 PERFORM set_config('isg.test_filed_score',r->>'nonconformity_id',true);
END $$;
RESET ROLE;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM private_isg.nonconformity_details WHERE nonconformity_id=current_setting('isg.test_filed_score')::uuid AND risk_method IN ('fine_kinney','matrix_5x5') AND risk_score IN (270,12)) THEN RAISE EXCEPTION 'FILED_SCORE_MISSING'; END IF;
END $$;
SELECT 'scored analysis filing preserves editable risk inputs' test,true passed;
