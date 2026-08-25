-- vNext quality renderer/policy v4.
--
-- No public schema or mobile contract changes. The active clean-room engine
-- keeps HazardFactV3 while versioning the prompt, deterministic scoring guard,
-- public-copy renderer and control/reference catalog used by future runs.

do $$
begin
  update private.analysis_engine_configs
  set prompt_version = 'vnext-photo-expert-v4',
      policy_version = 'semantic-risk-v4',
      control_catalog_version = 'controls-v4',
      config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
        'public_copy_renderer_version', 4,
        'visual_frequency_ceiling_enabled', true,
        'single_preventive_measure_enabled', true,
        'approved_reference_renderer_version', 1
      ),
      updated_at = now()
  where engine_version = 'vnext-v3'
    and is_active = true;

  if not found then
    raise exception 'active vnext-v3 engine configuration not found';
  end if;
end;
$$;
