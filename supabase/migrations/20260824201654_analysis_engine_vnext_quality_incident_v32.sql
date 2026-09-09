-- Remediate the 2026-08-24 vNext quality incident. This activation keeps the
-- hazard-fact v3.5 wire contract, score tables, subscription compute profiles
-- and client UI unchanged. It versions the structured critical-evidence gate,
-- consolidated equipment assurance, all-photo evidence-triggered high-hazard
-- coverage, safe JSON syntax recovery and durable technical retry checkpoint.

update private.analysis_engine_configs
set
  prompt_version = 'vnext-photo-expert-v26',
  policy_version = 'semantic-risk-v28',
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'structured_visible_barrier_evidence_version', 1,
    'high_consequence_rejection_guard_version', 1,
    'evidence_rejection_ratio_alert_version', 1,
    'evidence_rejection_ratio_alert_threshold', 0.5,
    'asset_assurance_catalog_version', 'asset-assurance-v8',
    'asset_assurance_single_asset_version', 1,
    'finding_taxonomy_version', 'finding-taxonomy-v4',
    'crane_taxonomy_version', 1,
    'scaffold_entity_relationship_version', 1,
    'high_hazard_critical_coverage_enabled', true,
    'high_hazard_critical_coverage_version', 2,
    'provider_json_syntax_repair_version', 1,
    'provider_schema_technical_retry_enabled', true,
    'provider_retry_checkpoint_version', 1,
    'public_copy_renderer_version', 10,
    'assurance_public_copy_version', 4,
    'quality_trace_stage_version', 19
  ),
  updated_at = now()
where engine_version = 'vnext-v3'
  and is_active = true;

do $verify_vnext_quality_incident_v32$
declare
  v_matching integer;
begin
  select count(*) into v_matching
  from private.analysis_engine_configs
  where engine_version = 'vnext-v3'
    and is_active = true
    and schema_version = 'hazard-fact-v3.5'
    and prompt_version = 'vnext-photo-expert-v26'
    and policy_version = 'semantic-risk-v28'
    and control_catalog_version = 'controls-v18'
    and config->>'sector_profile_version' = 'sector-profile-v2'
    and config->>'structured_visible_barrier_evidence_version' = '1'
    and config->>'high_consequence_rejection_guard_version' = '1'
    and config->>'evidence_rejection_ratio_alert_version' = '1'
    and config->>'evidence_rejection_ratio_alert_threshold' = '0.5'
    and config->>'asset_assurance_catalog_version' = 'asset-assurance-v8'
    and config->>'asset_assurance_single_asset_version' = '1'
    and config->>'finding_taxonomy_version' = 'finding-taxonomy-v4'
    and config->>'crane_taxonomy_version' = '1'
    and config->>'scaffold_entity_relationship_version' = '1'
    and config->>'high_hazard_critical_coverage_enabled' = 'true'
    and config->>'high_hazard_critical_coverage_version' = '2'
    and config->>'provider_json_syntax_repair_version' = '1'
    and config->>'provider_schema_technical_retry_enabled' = 'true'
    and config->>'provider_retry_checkpoint_version' = '1'
    and config->>'public_copy_renderer_version' = '10'
    and config->>'assurance_public_copy_version' = '4'
    and config->>'quality_trace_stage_version' = '19';

  if v_matching < 1 then
    raise exception 'vNext quality incident policy v32 did not apply';
  end if;
end;
$verify_vnext_quality_incident_v32$;
