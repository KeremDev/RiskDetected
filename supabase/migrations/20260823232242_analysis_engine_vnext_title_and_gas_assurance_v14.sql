-- vNext v14: exact assurance titles, report-level assurance deduplication,
-- isolated tank-part guard, and LNG/LPG/Ex equipment assurance coverage.
update private.analysis_engine_configs
set
  prompt_version = 'vnext-photo-expert-v14',
  policy_version = 'semantic-risk-v14',
  control_catalog_version = 'controls-v10',
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'asset_assurance_catalog_version', 'asset-assurance-v3',
    'equipment_assurance_catalog_version', 3,
    'assurance_exact_title_mapping_version', 1,
    'assurance_cross_photo_dedup_version', 1,
    'title_photo_suffix_removed', true,
    'detached_tank_part_guard_version', 1,
    'uncertainty_language_guard_version', 3,
    'lng_storage_assurance_version', 1,
    'lpg_storage_assurance_version', 1,
    'hazardous_area_ex_assurance_version', 1,
    'mechanism_control_mapping_version', 10,
    'quality_trace_stage_version', 7
  ),
  updated_at = now()
where engine_version = 'vnext-v3'
  and is_active = true;
