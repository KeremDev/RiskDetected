-- Sector Profile v2: activate the typed 15-sector catalogue without changing
-- the public findings/UI contract. Regulation anchors remain data-only.
update private.analysis_engine_configs
set
  schema_version = 'hazard-fact-v3.4',
  prompt_version = 'vnext-photo-expert-v21',
  policy_version = 'semantic-risk-v21',
  control_catalog_version = 'controls-v16',
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'sector_profile_version', 'sector-profile-v2',
    'sector_profile_enabled', true,
    'sector_frequency_prior_enabled', true,
    'sector_control_preferences_enabled', true,
    'sector_negative_rules_enabled', true,
    'sector_regulation_anchors_enabled', false,
    'sector_module_contract_version', 1,
    'sector_frequency_prior_version', 1,
    'sector_component_coverage_version', 1,
    'quality_trace_stage_version', 13
  ),
  updated_at = now()
where engine_version = 'vnext-v3'
  and is_active = true;
