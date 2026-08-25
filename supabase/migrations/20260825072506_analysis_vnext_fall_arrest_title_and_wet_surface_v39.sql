-- Title and grouping repairs. The prompt is untouched, so the pinned bundle
-- hash stays on v31 and the verification block asserts it did not move.
--
--   * The accepted fall-arrest finding was published as "Korkuluk sisteminde
--     ara korkuluk eksikliği": its cue names the collective protection that is
--     also absent, and the guardrail branch matched that word.
--   * A water-puddle fact and a scattered-material fact shared the
--     housekeeping title, because equipment_family arrived as the module id
--     "egress_housekeeping".
--   * The equipment-group resolver found "ppe" inside "wet_slippery_surface"
--     and filed a puddle as personal protective equipment.

update private.analysis_engine_configs
set
  config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
    'finding_title_policy_version', 3,
    'public_copy_renderer_version', 13,
    'equipment_group_taxonomy_version', 2,
    'wet_surface_title_policy_version', 1,
    'fall_arrest_title_policy_version', 1,
    'quality_trace_stage_version', 25
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
    or v_config.prompt_version <> 'vnext-photo-expert-v31'
    or v_config.config->>'prompt_bundle_sha256'
      <> '508f42409ea2929e0c43fce6d6b4ea8bfcad7c321a05f2d0f15b8939bc9cf144'
    or (v_config.config->>'finding_title_policy_version')::int <> 3
    or (v_config.config->>'equipment_group_taxonomy_version')::int <> 2
  then
    raise exception 'vNext title policy v3 activation verification failed';
  end if;
end;
$$;
