-- Activates prompt bundle v30.
--
-- Four defects from the 2026-08-25 06:03 construction analysis:
--   * equipment_family arrived as module ids ("scaffold_and_ladder") and
--     components as diacritic-stripped snake_case, and one reached a published
--     title as "... - Scaffold and ladder".
--   * a scaffold mid-rail fact inherited the slab-edge total-absence title.
--   * all five findings carried needs_field_verification, because the sector
--     frequency prior forced it, against the model's own "Görsel kanıt
--     yeterlidir".
--   * uncapped starter bars published at FK 42: severity clipped to 7 by the
--     sharp_edge_contact cap and probability floored at 1 by the
--     inherent-hazard rule.

update private.analysis_engine_configs
set
  prompt_version = 'vnext-photo-expert-v30',
  policy_version = 'semantic-risk-v29',
  control_catalog_version = 'controls-v19',
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'prompt_bundle_policy_version', 'prompt-bundle-sha256-v1',
    'prompt_bundle_sha256',
      'e064c5c6b0da56fba6f7c1e53a715cdfdf8b798981e88d394dacecd9a5ef080b',
    'structured_identifier_label_guard_version', 1,
    'title_total_absence_policy_version', 2,
    'field_verification_semantics_version', 3,
    'impalement_score_policy_version', 1,
    'mechanism_severity_cap_version', 2,
    'public_copy_renderer_version', 12,
    'quality_trace_stage_version', 23
  ),
  updated_at = now()
where engine_version = 'vnext-v3'
  and is_active = true;

do $$
declare
  v_config private.analysis_engine_configs%rowtype;
begin
  select * into v_config
  from private.analysis_engine_configs
  where engine_version = 'vnext-v3' and is_active = true;

  if not found
    or v_config.prompt_version <> 'vnext-photo-expert-v30'
    or v_config.control_catalog_version <> 'controls-v19'
    or v_config.config->>'prompt_bundle_sha256'
      <> 'e064c5c6b0da56fba6f7c1e53a715cdfdf8b798981e88d394dacecd9a5ef080b'
    or coalesce(
      (v_config.config->>'prompt_bundle_integrity_enabled')::boolean,
      false
    ) is not true
    or v_config.config #>> '{compute_profiles,premium,max_provider_output_tokens}'
      <> '12288'
  then
    raise exception 'vNext v30 activation verification failed';
  end if;
end;
$$;
