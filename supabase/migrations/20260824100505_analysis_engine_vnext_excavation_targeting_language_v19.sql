-- vNext v19: close the bounded multi-hook verification path, distinguish an
-- active excavation work area from an explicit slope face, and tighten
-- deterministic frequency, field-verification, root-cause and inventory
-- language policies without changing the public UI contract.
update private.analysis_engine_configs
set
  prompt_version = 'vnext-photo-expert-v19',
  policy_version = 'semantic-risk-v19',
  control_catalog_version = 'controls-v14',
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'critical_hardware_targeting_version', 3,
    'targeted_geometry_confirmation_version', 2,
    'excavation_slope_context_version', 2,
    'active_excavation_frequency_policy_version', 1,
    'site_stability_field_verification_version', 1,
    'inventory_safety_claim_filter_version', 3,
    'root_cause_claim_policy_version', 3,
    'mechanism_control_mapping_version', 14,
    'quality_trace_stage_version', 11
  ),
  updated_at = now()
where engine_version = 'vnext-v3'
  and is_active = true;
