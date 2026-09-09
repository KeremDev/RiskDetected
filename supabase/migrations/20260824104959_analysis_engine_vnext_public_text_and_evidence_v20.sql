-- vNext v20: make public finding text object-centric, reject unresolved
-- alternative hardware states and unsupported slope/rockfall claims, batch
-- sibling hook signals in one bounded targeted pass, and tighten photo-only
-- root-cause language without changing the public findings schema or UI.
update private.analysis_engine_configs
set
  prompt_version = 'vnext-photo-expert-v20',
  policy_version = 'semantic-risk-v20',
  control_catalog_version = 'controls-v15',
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'critical_hardware_targeting_version', 4,
    'targeted_geometry_confirmation_version', 3,
    'targeted_signal_sibling_batch_version', 1,
    'public_narrative_address_policy_version', 1,
    'finding_title_policy_version', 2,
    'excavation_slope_evidence_policy_version', 3,
    'root_cause_claim_policy_version', 4,
    'mechanism_control_mapping_version', 15,
    'quality_trace_stage_version', 12
  ),
  updated_at = now()
where engine_version = 'vnext-v3'
  and is_active = true;
