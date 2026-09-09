-- vNext v18: preserve rejected critical-component candidates in coverage,
-- allow one bounded close inspection for up to two equivalent critical
-- hardware targets, and tighten identity-driven assurance/counting and
-- mechanism-specific controls without changing the public UI contract.
update private.analysis_engine_configs
set
  prompt_version = 'vnext-photo-expert-v18',
  policy_version = 'semantic-risk-v18',
  control_catalog_version = 'controls-v13',
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'generic_visual_hazard_gate_version', 2,
    'critical_hardware_targeting_version', 2,
    'targeted_equivalent_region_limit', 2,
    'targeted_decision_trace_version', 1,
    'rejected_fact_coverage_version', 1,
    'asset_assurance_identity_gate_version', 1,
    'asset_assurance_catalog_version', 'asset-assurance-v5',
    'equipment_identity_count_version', 1,
    'inventory_safety_claim_filter_version', 2,
    'root_cause_claim_policy_version', 2,
    'finding_taxonomy_version', 'finding-taxonomy-v2',
    'mechanism_control_mapping_version', 13,
    'quality_trace_stage_version', 11
  ),
  updated_at = now()
where engine_version = 'vnext-v3'
  and is_active = true;
