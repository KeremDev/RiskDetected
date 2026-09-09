-- vNext v15: accept directly visible safety-barrier geometry, reject bare
-- process-vent openings as scored defects, correct mechanism/control/category
-- routing, narrow same-photo equivalent-component merging, and lower the
-- bounded Gemini reasoning/targeted budgets.
update private.analysis_engine_configs
set
  prompt_version = 'vnext-photo-expert-v15',
  policy_version = 'semantic-risk-v15',
  control_catalog_version = 'controls-v11',
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'asset_assurance_catalog_version', 'asset-assurance-v4',
    'equipment_assurance_catalog_version', 4,
    'gemini_thinking_budget', 3072,
    'technical_retry_gemini_thinking_budget', 2048,
    'targeted_gemini_thinking_budget', 1024,
    'targeted_max_provider_output_tokens', 4096,
    'visible_safety_barrier_evidence_version', 2,
    'process_vent_design_guard_version', 1,
    'same_photo_equivalent_condition_merge_version', 1,
    'mechanism_control_mapping_version', 11,
    'heavy_component_storage_control_version', 1,
    'electrical_category_precedence_version', 1,
    'generic_process_line_reference_version', 1,
    'technical_reference_scope_version', 1,
    'targeted_signal_gate_version', 4,
    'provider_token_budget_policy_version', 2,
    'quality_trace_stage_version', 8
  ),
  updated_at = now()
where engine_version = 'vnext-v3'
  and is_active = true;
