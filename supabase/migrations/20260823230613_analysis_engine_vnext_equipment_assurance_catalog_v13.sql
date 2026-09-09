-- vNext v13: broaden truthful equipment-assurance coverage without changing
-- the evidence threshold for visible-defect claims or adding provider calls.
update private.analysis_engine_configs
set
  prompt_version = 'vnext-photo-expert-v13',
  policy_version = 'semantic-risk-v13',
  control_catalog_version = 'controls-v9',
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'asset_assurance_catalog_version', 'asset-assurance-v2',
    'equipment_assurance_catalog_version', 2,
    'critical_asset_assurance_version', 2,
    'process_vessel_assurance_version', 2,
    'api_tank_reference_policy_version', 1,
    'ndt_method_selection_policy_version', 1,
    'scene_inventory_equipment_taxonomy_version', 1,
    'mechanism_control_mapping_version', 9,
    'quality_trace_stage_version', 6,
    'max_asset_assurance_findings_per_photo', 8
  ),
  updated_at = now()
where engine_version = 'vnext-v3'
  and is_active = true;
