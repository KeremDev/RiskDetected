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
      'p05_pilot_grants',
      'p05_pilot_accounts','p05_pilot_company_origins','p05_company_profiles',
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
      'checklist_runs','checklist_run_items','nonconformity_reconciliations',
      'module_registry','emergency_plan_versions','drill_records','equipment_items','equipment_inspection_rules',
      'equipment_inspections','appointments','ppe_handovers','ppe_returns',
      'katip_contracts','annual_work_plans','annual_work_plan_items','annual_training_plans','board_meetings',
      'board_decisions','work_permit_forms','site_visits','site_visit_observations','notebook_archive_entries',
      'document_templates','document_template_versions','documents','document_number_sequences','document_versions',
      'export_jobs','import_batches','import_rows','import_checkpoints',
      'notification_purposes','notification_consents','producer_ownership','notification_episodes',
      'notification_jobs','delivery_attempts','notification_device_permissions',
      'nonconformity_receipts',
      'personal_notes','note_conflicts','note_items','note_tags','note_tag_links','personal_reminders','note_mutation_receipts',
      'reminder_occurrences','device_delivery_claims',
      'billing_lifecycle_evidence','billing_lifecycle_projection','benefit_definitions','benefit_state_edges',
      'benefit_instances','store_offer_mappings','discount_quotes','checkout_intents','benefit_settlements',
      'settlement_adjustments','billing_reconciliation_jobs',
      'campaign_definitions','campaign_versions','referral_codes','referral_claims','qualification_events',
      'campaign_budgets','budget_reservations','winback_episodes','winback_contacts','suppression_records',
      'eligibility_checks',
      'funnel_stages','telemetry_event_kinds','support_chains','technical_events','telemetry_queue_reports',
      'attribution_records','admin_scopes','admin_sessions','admin_audit_entries','admin_actions',
      'admin_exports','admin_operation_state','funnel_progress',
      'score_policy_versions','score_processes','score_subject_states','score_snapshots','score_contributions',
      'score_critical_findings','score_oracle_fixtures','score_simulations','portfolio_projections',
      'portfolio_entries']);
    // This fresh, tiny fixture has no representative query workload. Keep the
    // explicitly reviewed FK-covering indexes: zero scans here is not removal evidence.
    const reviewedFKIndexes=new Set([
      'nonconformity_receipts_nonconformity_receipt_company_idx',
      'p05_pilot_grants_p05_pilot_company_idx',
      'portfolio_entries_portfolio_entry_company_idx','portfolio_entries_portfolio_entry_snapshot_idx',
      'portfolio_projections_portfolio_projection_policy_idx','score_contributions_score_contribution_process_idx',
      'score_simulations_score_simulation_from_idx','score_simulations_score_simulation_to_idx',
      'score_snapshots_score_snapshot_superseded_idx',
      'admin_actions_admin_action_audit_idx','admin_actions_admin_action_scope_idx',
      'admin_actions_admin_action_session_idx','admin_audit_entries_admin_audit_scope_idx',
      'admin_audit_entries_admin_audit_session_idx','admin_sessions_admin_session_user_idx',
      'funnel_progress_funnel_progress_stage_idx','support_chains_support_chain_owner_idx',
      'support_chains_support_chain_stage_idx','technical_events_technical_event_chain_idx',
      'technical_events_technical_event_stage_idx','telemetry_queue_reports_telemetry_queue_owner_idx',
      'budget_reservations_budget_reservation_subject_idx','campaign_versions_campaign_version_campaign_idx',
      'campaign_versions_campaign_version_invitee_reward_idx','campaign_versions_campaign_version_inviter_reward_idx',
      'campaign_versions_campaign_version_winback_reward_idx','eligibility_checks_eligibility_check_owner_idx',
      'eligibility_checks_eligibility_check_campaign_idx','referral_claims_referral_claim_inviter_idx',
      'referral_claims_referral_claim_invitee_idx','referral_codes_referral_code_campaign_idx',
      'referral_claims_referral_claim_qualified_version_idx',
      'suppression_records_suppression_episode_idx','suppression_records_suppression_campaign_idx',
      'winback_episodes_winback_episode_campaign_idx','winback_episodes_winback_episode_version_idx',
      'winback_episodes_winback_episode_owner_idx',
      'benefit_instances_benefit_instance_definition_idx','benefit_settlements_benefit_settlement_evidence_idx',
      'benefit_settlements_benefit_settlement_instance_idx','billing_lifecycle_evidence_billing_evidence_owner_idx',
      'billing_lifecycle_evidence_billing_evidence_review_idx','billing_lifecycle_projection_billing_projection_evidence_idx',
      'billing_lifecycle_projection_billing_projection_review_idx','discount_quotes_discount_quote_instance_idx',
      'discount_quotes_discount_quote_mapping_idx','discount_quotes_discount_quote_owner_idx',
      'settlement_adjustments_settlement_adjustment_idx','store_offer_mappings_store_offer_definition_idx',
      'notification_device_permissions_notification_device_owner_idx','notification_device_permissions_notification_device_session_idx',
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
      'emergency_plan_versions_emergency_plan_scope_idx','emergency_plan_versions_emergency_plan_owner_idx',
      'emergency_plan_versions_emergency_plan_asset_idx','drill_records_drill_scope_idx','drill_records_drill_plan_idx',
      'equipment_items_equipment_scope_idx','equipment_items_equipment_owner_idx','equipment_inspections_inspection_asset_idx',
      'appointments_appointment_employee_idx','appointments_appointment_scope_idx','appointments_appointment_asset_idx',
      'ppe_handovers_ppe_asset_idx',
      'katip_contracts_katip_scope_idx','katip_contracts_katip_asset_idx','katip_contracts_katip_owner_idx',
      'annual_work_plans_work_plan_owner_idx','annual_work_plan_items_work_plan_item_carry_idx',
      'annual_work_plan_items_work_plan_item_state_idx',
      'annual_training_plans_training_plan_owner_idx','annual_training_plans_training_plan_realised_idx',
      'board_meetings_board_scope_idx','board_meetings_board_owner_idx','board_meetings_board_asset_idx',
      'work_permit_forms_permit_scope_idx','work_permit_forms_permit_owner_idx','work_permit_forms_permit_asset_idx',
      'site_visits_visit_owner_idx','site_visits_visit_scope_idx',
      'site_visit_observations_observation_asset_idx','site_visit_observations_observation_nonconformity_idx',
      'notebook_archive_entries_notebook_scope_idx','notebook_archive_entries_notebook_owner_idx',
      'notebook_archive_entries_notebook_asset_idx',
      'documents_document_owner_idx','documents_document_template_idx','documents_document_scope_idx',
      'document_versions_document_version_finalizer_idx','document_template_versions_document_template_approver_idx',
      'export_jobs_export_state_idx','export_jobs_export_asset_idx',
      'import_batches_import_asset_idx','import_batches_import_owner_idx','import_rows_import_row_status_idx',
      'notification_consents_consent_owner_idx','notification_consents_consent_purpose_idx',
      'notification_episodes_episode_company_idx','notification_episodes_episode_purpose_idx',
      'notification_episodes_notification_episode_company_owner_idx',
      'notification_episodes_episode_owner_idx','delivery_attempts_attempt_job_idx',
      'personal_notes_note_owner_idx','note_conflicts_note_conflict_idx','note_items_note_item_idx',
      'note_tags_note_tag_owner_idx','note_tag_links_note_tag_link_idx',
      'p05_company_profiles_p05_company_profile_responsible','p05_company_profiles_p05_company_profile_owner',
      'personal_reminders_reminder_owner_idx','personal_reminders_reminder_note_idx',
      'reminder_occurrences_occurrence_due_idx',
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
