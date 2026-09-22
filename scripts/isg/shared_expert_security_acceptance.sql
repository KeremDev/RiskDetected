-- Execute after JWT test claims inside BEGIN/ROLLBACK; RESET ROLE needs admin runner.
CREATE TEMP TABLE expert_security_results(test text,passed boolean);
GRANT SELECT,INSERT ON expert_security_results TO authenticated;
RESET ROLE;
UPDATE private_isg.company_assignments SET ends_at=clock_timestamp()-interval '1 second'
 WHERE workspace_id=current_setting('isg.test_workspace')::uuid AND membership_id IN
 (SELECT id FROM private_isg.workspace_memberships WHERE user_id='0eda5735-1e03-4d2f-9441-051ebc16c75f')
 AND starts_at<clock_timestamp()-interval '1 second';
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN
 r:=public.isg_expert_rpc_v1(current_setting('isg.test_workspace')::uuid,'isg_expert_companies_v1','{}')->'payload';
 IF jsonb_array_length(r->'rows')<>0 THEN RAISE EXCEPTION 'REVOKED_COMPANY_VISIBLE'; END IF;
 BEGIN
  PERFORM public.isg_expert_rpc_v1(current_setting('isg.test_workspace')::uuid,'isg_personnel_read_v1',
   '{"p_company":"81dc715a-cdee-42f1-ab75-f653adb3283f","p_kind":"employees","p_query":"","p_archived":false,"p_after":null,"p_id":null}');
  RAISE EXCEPTION 'REVOKED_READ_ALLOWED';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM NOT IN ('ACCESS_DENIED','ASSIGNMENT_REQUIRED') THEN RAISE; END IF; END;
 INSERT INTO expert_security_results VALUES('revoked assignment removed from list and denied direct read',true);
END $$;
RESET ROLE;
UPDATE private_isg.workspace_memberships SET status='suspended',is_practicing_expert=false,suspended_at=clock_timestamp()
 WHERE workspace_id=current_setting('isg.test_workspace')::uuid AND user_id='0eda5735-1e03-4d2f-9441-051ebc16c75f';
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 BEGIN
  PERFORM public.isg_expert_rpc_v1(current_setting('isg.test_workspace')::uuid,'isg_expert_companies_v1','{}');
  RAISE EXCEPTION 'SUSPENDED_ALLOWED';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'ACCESS_DENIED' THEN RAISE; END IF; END;
 IF nullif(current_setting('private_isg.expert_workspace',true),'') IS NOT NULL THEN RAISE EXCEPTION 'TENANT_CONTEXT_LEAK'; END IF;
 INSERT INTO expert_security_results VALUES('suspended membership denied and context cleared',true);
END $$;
SELECT * FROM expert_security_results;
