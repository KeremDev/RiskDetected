-- vNext v17: keep field-verification semantics independent from score-policy
-- normalization, allow one evidence-gated critical-hardware geometry
-- reinspection, and persist closed stable finding/equipment taxonomy codes.
update private.analysis_engine_configs
set
  prompt_version = 'vnext-photo-expert-v17',
  policy_version = 'semantic-risk-v17',
  control_catalog_version = 'controls-v12',
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'field_verification_semantics_version', 2,
    'critical_hardware_targeting_version', 1,
    'finding_taxonomy_version', 'finding-taxonomy-v1',
    'equipment_group_taxonomy_version', 1,
    'quality_trace_stage_version', 10
  ),
  updated_at = now()
where engine_version = 'vnext-v3'
  and is_active = true;
