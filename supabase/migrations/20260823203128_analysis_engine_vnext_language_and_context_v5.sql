-- vNext public-language and contextual evidence policy v5.
--
-- No public schema or mobile contract changes. This version records the
-- fluent-copy renderer, enclosed-cab PPE guard and concrete-anomaly gate used
-- for optional targeted reinspection in future analysis runs.

do $$
begin
  update private.analysis_engine_configs
  set prompt_version = 'vnext-photo-expert-v5',
      policy_version = 'semantic-risk-v5',
      config = coalesce(config, '{}'::jsonb) || jsonb_build_object(
        'public_copy_renderer_version', 5,
        'enclosed_cab_ppe_guard_enabled', true,
        'targeted_signal_gate_version', 1
      ),
      updated_at = now()
  where engine_version = 'vnext-v3'
    and is_active = true;

  if not found then
    raise exception 'active vnext-v3 engine configuration not found';
  end if;
end;
$$;
