import {spawn} from 'node:child_process';
import {createServer} from 'node:net';
import {mkdtempSync,chmodSync,rmdirSync} from 'node:fs';
import {randomBytes} from 'node:crypto';

/** CLI gets only a private Unix socket into our owned network=none test container.
 * No TCP listener, published port, Docker mount, production URL or persistent secret.
 */
export async function probePersonnelAdvisors({synthetic,sql,guard,names,pass,onFindings=()=>{}}) {
  if(synthetic!==true)throw Error('AUTH_RESTORE_ADVISOR_SYNTHETIC_REQUIRED');
  guard('client');guard('db');
  const password=randomBytes(32).toString('hex');
  sql(`CREATE ROLE isg_local_advisor LOGIN PASSWORD '${password}'; ALTER ROLE isg_local_advisor SET default_transaction_read_only=on; GRANT pg_read_all_stats TO isg_local_advisor;`);
  const directory=mkdtempSync('/tmp/isg-advisor-');chmodSync(directory,0o700);
  const socket=directory+'/.s.PGSQL.5432',children=new Set(),connections=new Set();
  const bridge="const net=require('node:net');const s=net.connect({host:'127.0.0.1',port:5432});process.stdin.pipe(s);s.pipe(process.stdout);s.on('error',()=>process.exit(1));s.on('close',()=>process.exit(0));";
  const server=createServer(connection=>{
    try{guard('client');guard('db');}catch{connection.destroy();return;}
    connections.add(connection);
    const child=spawn('docker',['exec','-i',names.client,'node','-e',bridge],{stdio:['pipe','pipe','ignore'],timeout:45000});
    children.add(child);connection.pipe(child.stdin);child.stdout.pipe(connection);
    child.stdin.on('error',()=>connection.destroy());child.on('error',()=>connection.destroy());
    child.on('close',()=>{children.delete(child);connection.destroy();});
    connection.on('error',()=>child.kill());connection.on('close',()=>{connections.delete(connection);child.kill();});
  });
  try {
    await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(socket,resolve);});chmodSync(socket,0o600);
    const url=`postgresql://isg_local_advisor:${password}@localhost:5432/postgres?host=${encodeURIComponent(directory)}&sslmode=disable`;
    const result=await new Promise(resolve=>{
      const child=spawn('supabase',['db','advisors','--db-url',url,'--type','all','--level','info','--fail-on','none','--output','json'],{stdio:['ignore','pipe','pipe'],timeout:45000});
      let stdout='',stderr='';child.stdout.on('data',b=>{if(stdout.length<4*1024*1024)stdout+=b;else child.kill();});
      child.stderr.on('data',b=>{if(stderr.length<4096)stderr+=b;});child.on('error',()=>resolve({ok:false}));child.on('close',code=>resolve({ok:code===0,stdout,stderr}));
    });
    if(!result.ok)throw Error('AUTH_RESTORE_ADVISOR_CLI_FAILED: '+(result.stderr??'').replaceAll(password,'[redacted]').replace(/postgres(?:ql)?:\/\/\S+/g,'[local database]').slice(-1500));
    let parsed;try{parsed=JSON.parse(result.stdout);}catch{throw Error('AUTH_RESTORE_ADVISOR_OUTPUT_INVALID');}
    const findings=Array.isArray(parsed)?parsed:parsed.lints??parsed.advisors;
    if(!Array.isArray(findings))throw Error('AUTH_RESTORE_ADVISOR_OUTPUT_INVALID');
    const relevant=findings.filter(f=>JSON.stringify(f).includes('private_isg')||JSON.stringify(f).includes('isg_workspace_')||JSON.stringify(f).includes('isg_personnel_')||JSON.stringify(f).includes('isg_directory_')||JSON.stringify(f).includes('isg_context_')||JSON.stringify(f).includes('companies_id_user_isg_unique'));
    onFindings({total_findings:findings.length,relevant_findings:relevant});
    pass('personnel_advisor_cli_completed',true);
    pass('personnel_advisor_new_schema_no_errors',!relevant.some(f=>String(f.level).toUpperCase()==='ERROR'));
    // Deliberate default-deny tables, with no client grants, are not missing policies.
    const denyTables=new Set(['rollout','workplaces','departments','employees','personnel_receipts','personnel_audit','personnel_outbox','workplace_initializations','job_roles','contractor_organizations','contractor_engagements','workplace_context_versions','employee_assignments','directory_events','directory_outbox',
      // P01/P03 ledgers: private by construction, worker/owner only, zero client grant.
      'consumer_registry','event_deliveries','consumer_receipts','dispatch_dead_letters','dispatch_reconciliations',
      'quota_definitions','legacy_entitlement_floors','quota_reservations','quota_settlements','quota_shadow_observations',
      'file_purposes','upload_intents','file_assets','file_derivatives','file_scan_results',
      'legal_sources','rule_versions','rule_simulations','applicability_decisions','requirement_instances',
      'requirement_schedules','rule_reconciliations',
      'training_catalogs','training_catalog_versions','training_topic_groups','training_class_rules',
      'company_curriculum_versions','training_plans','training_sessions','training_enrolments',
      'attendance_intervals','assessment_attempts','training_completions','external_credentials',
      'risk_assessments','risk_assessment_versions','risk_source_links','revision_impacts','risk_file_variants',
      'nonconformity_state_edges','nonconformities','nonconformity_transitions','nonconformity_actions',
      'verification_records','checklist_templates','checklist_template_versions','checklist_template_items',
      'checklist_runs','checklist_run_items','nonconformity_reconciliations']);
    // This fresh, tiny fixture has no representative query workload. Keep the
    // explicitly reviewed FK-covering indexes: zero scans here is not removal evidence.
    const reviewedFKIndexes=new Set([
      'departments_department_parent_scope_idx','employees_employee_employer_scope_idx',
      'job_roles_job_owner_idx','contractor_organizations_contractor_owner_idx',
      'contractor_engagements_engagement_owner_idx','contractor_engagements_engagement_organization_idx','contractor_engagements_engagement_workplace_idx',
      'workplace_context_versions_context_owner_idx','workplace_context_versions_context_workplace_idx',
      'employee_assignments_assignment_owner_idx','employee_assignments_assignment_employee_idx','employee_assignments_assignment_department_idx','employee_assignments_assignment_job_idx','employee_assignments_assignment_employer_idx',
      'directory_events_directory_event_owner_idx',
      'event_deliveries_dispatch_claimable_idx','quota_reservations_quota_reservation_company_idx',
      'quota_reservations_quota_reservation_kind_idx','quota_shadow_observations_quota_shadow_owner_idx',
      'upload_intents_upload_intent_purpose_idx','upload_intents_upload_intent_company_idx','upload_intents_upload_intent_reservation_idx',
      'file_assets_file_asset_owner_idx','file_assets_file_asset_purpose_idx','file_assets_file_asset_company_idx',
      'rule_versions_rule_version_source_idx','rule_versions_rule_version_approver_idx',
      'applicability_decisions_decision_scope_idx','legal_sources_legal_source_verifier_idx',
      'company_curriculum_versions_curriculum_scope_idx','company_curriculum_versions_curriculum_owner_idx',
      'training_plans_plan_scope_idx','training_plans_plan_curriculum_idx','training_plans_plan_requirement_idx',
      'training_completions_completion_employee_idx','training_completions_completion_validity_idx',
      'external_credentials_credential_asset_idx',
      'training_catalog_versions_catalog_version_source_idx','training_catalog_versions_catalog_version_approver_idx',
      'risk_assessments_risk_assessment_owner_idx','risk_assessment_versions_risk_version_state_idx',
      'risk_assessment_versions_risk_version_asset_idx','risk_assessment_versions_risk_version_verifier_idx',
      'risk_file_variants_risk_variant_asset_idx',
      'nonconformities_nonconformity_scope_idx','nonconformities_nonconformity_owner_idx','nonconformities_nonconformity_due_idx',
      'nonconformity_transitions_transition_actor_idx','nonconformity_actions_action_scope_idx',
      'verification_records_verification_verifier_idx','verification_records_verification_asset_idx',
      'checklist_runs_checklist_run_scope_idx','checklist_runs_checklist_run_owner_idx','checklist_runs_checklist_run_template_idx',
      'checklist_run_items_checklist_item_asset_idx','checklist_run_items_checklist_item_nonconformity_idx',
      'checklist_template_versions_checklist_version_approver_idx',
    ].map(key=>'unused_index_private_isg_'+key));
    pass('personnel_advisor_no_unreviewed_findings',relevant.every(f=>f.level==='INFO'&&f.metadata?.schema==='private_isg'&&
      ((f.name==='rls_enabled_no_policy'&&denyTables.has(f.metadata?.name))||(f.name==='unused_index'&&reviewedFKIndexes.has(f.cache_key)))));
    return {cli:true,read_only_role:true,private_unix_socket:true,full_schema_restore:false,
      total_findings:findings.length,relevant_findings:relevant,reviewed_unused_fk_index_reason:'Fresh synthetic database; retain explicit FK coverage. This is not production performance evidence.'};
  } finally {
    for(const connection of connections)connection.destroy();
    for(const child of children)child.kill();
    await new Promise(resolve=>server.close(resolve));
    rmdirSync(directory);
  }
}
