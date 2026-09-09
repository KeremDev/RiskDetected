-- vNext v16: consolidate duplicate scene-area findings, absorb overlapping
-- drive assurance into confirmed observed conditions, reject generic visual
-- hazard inference, separate assurance scores from active totals, and stop
-- reducing residual risk before control implementation is confirmed.
update private.analysis_engine_configs
set
  prompt_version = 'vnext-photo-expert-v16',
  policy_version = 'semantic-risk-v16',
  control_catalog_version = 'controls-v12',
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'asset_assurance_catalog_version', 'asset-assurance-v4',
    'equipment_assurance_catalog_version', 4,
    'visible_safety_barrier_evidence_version', 3,
    'same_scene_area_condition_merge_version', 1,
    'observed_assurance_absorption_version', 1,
    'generic_visual_hazard_gate_version', 1,
    'visible_inherent_probability_policy_version', 2,
    'mechanism_severity_cap_version', 1,
    'analysis_total_assurance_split_version', 1,
    'residual_control_confirmation_policy_version', 1,
    'assurance_corrective_copy_version', 1,
    'mechanism_control_mapping_version', 12,
    'quality_trace_stage_version', 9
  ),
  updated_at = now()
where engine_version = 'vnext-v3'
  and is_active = true;
