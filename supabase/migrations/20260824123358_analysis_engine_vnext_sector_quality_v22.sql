-- Sector Profile v2 quality hardening. The provider schema and prompt remain
-- v3.4/v21; deterministic evidence, targeting, control and public-copy policy
-- behavior moves forward independently.
update private.analysis_engine_configs
set
  policy_version = 'semantic-risk-v22',
  control_catalog_version = 'controls-v17',
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'sector_module_contract_version', 2,
    'sector_component_coverage_version', 2,
    'sector_target_priority_version', 2,
    'targeted_rejection_trace_version', 2,
    'sector_negative_validator_version', 2,
    'sector_control_preference_enforcement_version', 1,
    'public_spatial_address_policy_version', 2,
    'quality_trace_stage_version', 14
  ),
  updated_at = now()
where engine_version = 'vnext-v3'
  and is_active = true;
