-- Deterministic consistency hardening for repeated-image analyses. This keeps
-- the v3.4 provider contract while advancing prompt, scoring, public copy,
-- taxonomy, asset identity and targeted reconciliation policies.
update private.analysis_engine_configs
set
  prompt_version = 'vnext-photo-expert-v22',
  policy_version = 'semantic-risk-v23',
  control_catalog_version = 'controls-v18',
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'asset_assurance_catalog_version', 'asset-assurance-v6',
    'finding_taxonomy_version', 'finding-taxonomy-v3',
    'public_spatial_address_policy_version', 3,
    'score_stability_policy_version', 3,
    'asset_assurance_identity_gate_version', 2,
    'assurance_corrective_copy_version', 2,
    'equipment_identity_count_version', 2,
    'targeted_primary_reconciliation_version', 2,
    'component_coverage_audit_version', 2,
    'observed_before_assurance_order_version', 1,
    'storage_stacking_probability_policy_version', 1,
    'incomplete_guardrail_severity_policy_version', 1,
    'quality_trace_stage_version', 15
  ),
  updated_at = now()
where engine_version = 'vnext-v3'
  and is_active = true;
