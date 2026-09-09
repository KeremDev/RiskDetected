-- vNext v10 keeps the mobile contract unchanged while upgrading the private
-- model/renderer contract. The runtime reads this row at analysis start so
-- every run records the exact narrative, scoring and control policy versions.
update private.analysis_engine_configs
set schema_version = 'hazard-fact-v3.2',
    prompt_version = 'vnext-photo-expert-v10',
    policy_version = 'semantic-risk-v10',
    control_catalog_version = 'controls-v6',
    config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
      'public_copy_renderer_version', 6,
      'mechanism_control_mapping_version', 6,
      'expert_narrative_contract_version', 1,
      'root_cause_qualification_version', 1,
      'title_collision_disambiguation_version', 1,
      'component_coverage_mechanism_guard_version', 1,
      'direct_semantic_score_mapping_version', 1,
      'provider_frequency_enum_version', 2,
      'semantic_severity_ceiling_version', 0,
      'score_stability_policy_version', 2
    ),
    updated_at = now()
where engine_version = 'vnext-v3';
