-- vNext v12 separates visible defects from critical-equipment assurance.
-- Critical process tanks and bridge cranes can now produce truthful,
-- numerically scored integrity/control-verification findings without claiming
-- that a record is missing or a periodic inspection is overdue. The public
-- mobile request/finding schema and provider-call count remain unchanged.

do $$
begin
  update private.analysis_engine_configs
  set schema_version = 'hazard-fact-v3.3',
      prompt_version = 'vnext-photo-expert-v12',
      policy_version = 'semantic-risk-v12',
      control_catalog_version = 'controls-v8',
      config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
        'assessment_basis_contract_version', 1,
        'critical_asset_assurance_version', 1,
        'process_vessel_assurance_version', 1,
        'crane_periodic_control_assurance_version', 1,
        'generic_crane_motion_guard_version', 1,
        'uncertainty_language_guard_version', 2,
        'root_cause_qualification_version', 2,
        'approved_reference_renderer_version', 3,
        'mechanism_control_mapping_version', 8,
        'quality_trace_stage_version', 5
      ),
      updated_at = now()
  where engine_version = 'vnext-v3'
    and is_active = true;

  if not found then
    raise exception 'active vnext-v3 engine configuration not found';
  end if;
end;
$$;
