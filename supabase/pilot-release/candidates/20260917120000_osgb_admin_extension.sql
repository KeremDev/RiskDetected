-- OSGB commands on the existing P16 admin authority. NOT DEPLOYED.
-- No second role/session system is introduced: every command uses the existing
-- AAL2 session, scope, simulate-first, admin-write-pause and immutable audit path.
SET LOCAL lock_timeout='1s';
SET LOCAL statement_timeout='20s';

INSERT INTO private_isg.workspace_rollout(feature) VALUES('workspace_admin');
INSERT INTO private_isg.admin_scopes(scope_key,note) VALUES
  ('osgb.read','read aggregate OSGB workspace health'),
  ('osgb.support','perform allowlisted member and reconciliation support commands'),
  ('osgb.billing','perform allowlisted OSGB trial and credit support commands');

ALTER TABLE private_isg.admin_actions DROP CONSTRAINT admin_actions_action_kind_check;
ALTER TABLE private_isg.admin_actions ADD CONSTRAINT admin_actions_action_kind_check
  CHECK(action_kind IN ('campaign_pause','campaign_publish','budget_change','rollout_switch',
    'benefit_review','export_request','osgb_trial_grant','osgb_credit_grant',
    'osgb_member_suspend','osgb_reconcile_request'));

CREATE TABLE private_isg.workspace_admin_commands (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  action_id uuid NOT NULL UNIQUE REFERENCES private_isg.admin_actions(action_id) ON DELETE RESTRICT,
  workspace_id uuid NOT NULL REFERENCES private_isg.workspaces(id) ON DELETE RESTRICT,
  command_kind text NOT NULL CHECK(command_kind IN ('osgb_trial_grant','osgb_credit_grant',
    'osgb_member_suspend','osgb_reconcile_request')),
  target_membership_id uuid,
  plan_code text REFERENCES private_isg.workspace_plan_catalog(plan_code),
  credit_units bigint CHECK(credit_units>0),
  expires_at timestamptz,
  expected_version bigint CHECK(expected_version>=0),
  reason text NOT NULL CHECK(octet_length(reason) BETWEEN 3 AND 500),
  state text NOT NULL DEFAULT 'simulated' CHECK(state IN ('simulated','executed')),
  result jsonb,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  executed_at timestamptz,
  FOREIGN KEY(workspace_id,target_membership_id)
    REFERENCES private_isg.workspace_memberships(workspace_id,id) ON DELETE RESTRICT,
  CHECK((command_kind='osgb_trial_grant')=(plan_code IS NOT NULL)),
  CHECK((command_kind='osgb_credit_grant')=(credit_units IS NOT NULL)),
  CHECK((command_kind='osgb_member_suspend')=(target_membership_id IS NOT NULL)),
  CHECK((state='executed')=(executed_at IS NOT NULL AND result IS NOT NULL))
);
CREATE INDEX workspace_admin_command_timeline
  ON private_isg.workspace_admin_commands(workspace_id,created_at,id);
ALTER TABLE private_isg.workspace_admin_commands ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private_isg.workspace_admin_commands FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION private_isg.workspace_admin_scope(p_command text) RETURNS text
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path='' AS $$
  SELECT CASE
    WHEN p_command IN ('osgb_trial_grant','osgb_credit_grant') THEN 'osgb.billing'
    WHEN p_command IN ('osgb_member_suspend','osgb_reconcile_request') THEN 'osgb.support'
  END
$$;

CREATE FUNCTION private_isg.workspace_admin_simulate(p_session uuid,p_command text,p_workspace uuid,
  p_target_membership uuid,p_plan text,p_units bigint,p_expires timestamptz,p_expected bigint,
  p_reason text,p_now timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE scope_key text:=private_isg.workspace_admin_scope(p_command); workspace private_isg.workspaces;
  member private_isg.workspace_memberships; plan private_isg.workspace_plan_catalog;
  clean_reason text; report jsonb; action_result jsonb; command_id uuid;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_admin',true);
  IF scope_key IS NULL OR p_workspace IS NULL OR p_now IS NULL THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  PERFORM private_isg.admin_authorize(p_session,scope_key,false,p_now);
  clean_reason:=private_isg.workspace_text(p_reason,500);
  SELECT * INTO workspace FROM private_isg.workspaces WHERE id=p_workspace AND kind='osgb' FOR SHARE;
  IF workspace.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF p_command='osgb_trial_grant' THEN
    IF p_target_membership IS NOT NULL OR p_units IS NOT NULL OR p_expected IS NOT NULL OR
       p_plan IS NULL OR p_expires IS NULL OR p_expires<=p_now OR p_expires>p_now+interval '90 days' THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    SELECT * INTO plan FROM private_isg.workspace_plan_catalog WHERE plan_code=p_plan AND active FOR SHARE;
    IF plan.plan_code IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='PLAN_NOT_AVAILABLE'; END IF;
    IF EXISTS(SELECT 1 FROM private_isg.workspace_entitlements e WHERE e.workspace_id=p_workspace
      AND e.source_kind='store' AND e.status IN ('active','grace','canceled_active')
      AND (e.valid_until IS NULL OR e.valid_until>p_now)) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACTIVE_STORE_ENTITLEMENT'; END IF;
    report:=jsonb_build_object('workspace_status',workspace.status,'plan_code',plan.plan_code,
      'max_experts',plan.max_experts,'expires_at',p_expires,'economic_source','admin_trial');
  ELSIF p_command='osgb_credit_grant' THEN
    IF p_target_membership IS NOT NULL OR p_plan IS NOT NULL OR p_expires IS NOT NULL OR
       p_expected IS NOT NULL OR p_units IS NULL OR p_units NOT BETWEEN 1 AND 1000000 THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    report:=jsonb_build_object('credit_units',p_units,'source','admin_support',
      'current_wallet_version',(SELECT version FROM private_isg.workspace_wallets WHERE workspace_id=p_workspace));
  ELSIF p_command='osgb_member_suspend' THEN
    IF p_target_membership IS NULL OR p_plan IS NOT NULL OR p_units IS NOT NULL OR p_expires IS NOT NULL OR
       p_expected IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    SELECT * INTO member FROM private_isg.workspace_memberships
      WHERE workspace_id=p_workspace AND id=p_target_membership FOR SHARE;
    IF member.id IS NULL OR member.role='owner' OR member.status<>'active' THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='MEMBERSHIP_CONFLICT'; END IF;
    IF member.version<>p_expected THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    report:=jsonb_build_object('membership_id',member.id,'role',member.role,'status',member.status,
      'version',member.version,'active_assignments',(SELECT count(*) FROM private_isg.company_assignments a
        WHERE a.workspace_id=p_workspace AND a.membership_id=member.id AND a.ends_at IS NULL));
  ELSE
    IF p_target_membership IS NOT NULL OR p_plan IS NOT NULL OR p_units IS NOT NULL OR
       p_expires IS NOT NULL OR p_expected IS NOT NULL THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
    report:=jsonb_build_object('workspace_status',workspace.status,'operation','enqueue_only',
      'store_purchase_created',false);
  END IF;
  action_result:=private_isg.simulate_admin_action(p_session,p_command,scope_key,
    'workspace:'||p_workspace::text,report,p_now);
  INSERT INTO private_isg.workspace_admin_commands(action_id,workspace_id,command_kind,target_membership_id,
    plan_code,credit_units,expires_at,expected_version,reason)
    VALUES((action_result->>'action_id')::uuid,p_workspace,p_command,p_target_membership,p_plan,p_units,
      p_expires,p_expected,clean_reason) RETURNING id INTO command_id;
  RETURN action_result||jsonb_build_object('command_id',command_id,'workspace_id',p_workspace,
    'simulation_report',report);
END $$;

CREATE FUNCTION private_isg.workspace_admin_execute(p_session uuid,p_command uuid,p_now timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE command private_isg.workspace_admin_commands; action private_isg.admin_actions;
  session_row private_isg.admin_sessions; plan private_isg.workspace_plan_catalog;
  member private_isg.workspace_memberships; publish_result jsonb; effect jsonb; v_result jsonb;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_admin',true);
  IF p_command IS NULL OR p_now IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT * INTO command FROM private_isg.workspace_admin_commands WHERE id=p_command FOR UPDATE;
  IF command.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  SELECT * INTO action FROM private_isg.admin_actions WHERE action_id=command.action_id FOR UPDATE;
  IF action.session_id<>p_session THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACCESS_DENIED'; END IF;
  IF command.state='executed' THEN RETURN command.result||jsonb_build_object('replayed',true); END IF;
  SELECT * INTO session_row FROM private_isg.admin_sessions WHERE session_id=p_session;
  publish_result:=private_isg.publish_admin_action(p_session,command.action_id,jsonb_build_object(
    'workspace_id',command.workspace_id,'command_kind',command.command_kind,
    'target_membership_id',command.target_membership_id,'plan_code',command.plan_code,
    'credit_units',command.credit_units,'expires_at',command.expires_at,
    'expected_version',command.expected_version,'reason',command.reason),p_now);
  IF command.command_kind='osgb_trial_grant' THEN
    SELECT * INTO plan FROM private_isg.workspace_plan_catalog WHERE plan_code=command.plan_code AND active FOR SHARE;
    IF EXISTS(SELECT 1 FROM private_isg.workspace_entitlements e WHERE e.workspace_id=command.workspace_id
      AND e.source_kind='store' AND e.status IN ('active','grace','canceled_active')
      AND (e.valid_until IS NULL OR e.valid_until>p_now)) THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='ACTIVE_STORE_ENTITLEMENT'; END IF;
    INSERT INTO private_isg.workspace_entitlements(workspace_id,plan_code,source_kind,status,max_experts,valid_until)
      VALUES(command.workspace_id,plan.plan_code,'admin_trial','active',plan.max_experts,command.expires_at)
    ON CONFLICT(workspace_id) DO UPDATE SET plan_code=EXCLUDED.plan_code,source_binding_id=NULL,
      source_kind='admin_trial',status='active',max_experts=EXCLUDED.max_experts,
      valid_until=EXCLUDED.valid_until,version=private_isg.workspace_entitlements.version+1,
      updated_at=clock_timestamp();
    UPDATE private_isg.workspaces SET status='admin_trial',version=version+1,updated_at=clock_timestamp()
      WHERE id=command.workspace_id;
    effect:=jsonb_build_object('plan_code',plan.plan_code,'max_experts',plan.max_experts,
      'valid_until',command.expires_at,'source_kind','admin_trial');
  ELSIF command.command_kind='osgb_credit_grant' THEN
    effect:=private_isg.workspace_credit_grant(command.id,command.workspace_id,'admin_support',
      'admin-command:'||command.id::text,command.credit_units,session_row.admin_user_id);
  ELSIF command.command_kind='osgb_member_suspend' THEN
    SELECT * INTO member FROM private_isg.workspace_memberships
      WHERE workspace_id=command.workspace_id AND id=command.target_membership_id FOR UPDATE;
    IF member.id IS NULL OR member.role='owner' OR member.status<>'active' THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='MEMBERSHIP_CONFLICT'; END IF;
    IF member.version<>command.expected_version THEN
      RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VERSION_CONFLICT'; END IF;
    UPDATE private_isg.workspace_memberships SET status='suspended',is_practicing_expert=false,
      suspended_at=p_now,ended_at=NULL,permission_revision=permission_revision+1,version=version+1,
      updated_at=clock_timestamp() WHERE id=member.id RETURNING * INTO member;
    INSERT INTO private_isg.workspace_membership_events(workspace_id,membership_id,event_type,actor_user_id,
      to_state,reason,correlation_id) VALUES(command.workspace_id,member.id,'suspended',
      session_row.admin_user_id,private_isg.workspace_member_json(member),command.reason,command.action_id);
    effect:=jsonb_build_object('membership',private_isg.workspace_member_json(member));
  ELSE
    INSERT INTO private_isg.workspace_outbox(workspace_id,event_type,aggregate_type,aggregate_id,
      aggregate_version,payload,correlation_id) VALUES(command.workspace_id,
      'workspace.billing.reconcile_requested.v1','workspace',command.workspace_id,0,
      jsonb_build_object('workspace_id',command.workspace_id,'reason',command.reason),command.action_id);
    effect:=jsonb_build_object('queued',true,'store_purchase_created',false);
  END IF;
  v_result:=jsonb_build_object('schema_version',1,'command_id',command.id,'workspace_id',command.workspace_id,
    'command_kind',command.command_kind,'state','executed','effect',effect,
    'audit_id',publish_result->>'audit_id','audit_written_before_effect',true,'replayed',false);
  UPDATE private_isg.workspace_admin_commands SET state='executed',result=v_result,executed_at=p_now
    WHERE id=command.id;
  RETURN v_result;
END $$;

CREATE FUNCTION private_isg.workspace_admin_overview(p_session uuid,p_limit integer,p_now timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE rows jsonb;
BEGIN
  PERFORM private_isg.workspace_gate('workspace_admin',false);
  PERFORM private_isg.admin_authorize(p_session,'osgb.read',false,p_now);
  IF p_limit NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='VALIDATION_ERROR'; END IF;
  SELECT coalesce(jsonb_agg(row_value ORDER BY name,id),'[]'::jsonb) INTO rows FROM (
    SELECT w.id,w.name,jsonb_build_object('workspace_id',w.id,'name',w.name,'status',w.status,
      'member_count',(SELECT count(*) FROM private_isg.workspace_memberships m WHERE m.workspace_id=w.id AND m.status='active'),
      'company_count',(SELECT count(*) FROM private_isg.workspace_companies c WHERE c.workspace_id=w.id AND c.status='active'),
      'wallet',jsonb_build_object('posted_units',coalesce(wallet.posted_units,0),'reserved_units',coalesce(wallet.reserved_units,0),'debt_units',coalesce(wallet.debt_units,0)),
      'entitlement',CASE WHEN e.workspace_id IS NULL THEN NULL ELSE jsonb_build_object('plan_code',e.plan_code,'source_kind',e.source_kind,'status',e.status,'max_experts',e.max_experts,'valid_until',e.valid_until) END) row_value
    FROM private_isg.workspaces w
    LEFT JOIN private_isg.workspace_wallets wallet ON wallet.workspace_id=w.id
    LEFT JOIN private_isg.workspace_entitlements e ON e.workspace_id=w.id
    WHERE w.kind='osgb' ORDER BY w.name,w.id LIMIT p_limit) q;
  RETURN jsonb_build_object('schema_version',1,'scope','platform','rows',rows);
END $$;

REVOKE ALL ON FUNCTION private_isg.workspace_admin_scope(text),
  private_isg.workspace_admin_simulate(uuid,text,uuid,uuid,text,bigint,timestamptz,bigint,text,timestamptz),
  private_isg.workspace_admin_execute(uuid,uuid,timestamptz),
  private_isg.workspace_admin_overview(uuid,integer,timestamptz)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION private_isg.workspace_admin_simulate(uuid,text,uuid,uuid,text,bigint,timestamptz,bigint,text,timestamptz),
  private_isg.workspace_admin_execute(uuid,uuid,timestamptz),
  private_isg.workspace_admin_overview(uuid,integer,timestamptz)
  TO service_role;
