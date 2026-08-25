-- v4 owner pilot quality repair:
-- - leave primary/retry thinking budgets unchanged;
-- - give focused reinspections enough response headroom;
-- - pin the versioned prompt/router/coverage/assurance bundle.

update private.analysis_v4_configs
set prompt_version = 'v4-vision-core-v3',
    prompt_sha256 = '51e6a260154249305e565e77cd49d4cb98b1af1f4ef8d79da0dd281a346a5f60',
    router_version = 'claim-routing-v2',
    coverage_version = 'critical-coverage-v3',
    assurance_version = 'assurance-topic-v2',
    config = jsonb_set(
      jsonb_set(
        coalesce(config, '{}'::jsonb) || jsonb_build_object(
          'prompt_version', 'v4-vision-core-v3',
          'prompt_sha256', '51e6a260154249305e565e77cd49d4cb98b1af1f4ef8d79da0dd281a346a5f60',
          'prompt_bundle_sha256', '51e6a260154249305e565e77cd49d4cb98b1af1f4ef8d79da0dd281a346a5f60',
          'router_version', 'claim-routing-v2',
          'coverage_version', 'critical-coverage-v3',
          'assurance_version', 'assurance-topic-v2',
          'control_catalog_version', 'controls-v20',
          'targeted_prompt_compaction_version', 1,
          'primary_coverage_recovery_version', 2,
          'scoring_text_quality_patch_version', 1
        ),
        '{compute_profiles,premium,targeted_max_provider_output_tokens}',
        to_jsonb(4096),
        true
      ),
      '{compute_profiles,economy,targeted_max_provider_output_tokens}',
      to_jsonb(3072),
      true
    ),
    integrity_status = 'valid',
    updated_at = now()
where is_active and engine_version = 'vnext-v4';

do $$
declare
  v_route_definition text;
  v_begin_definition text;
begin
  if not exists (
    select 1
    from private.analysis_v4_configs
    where is_active
      and engine_version = 'vnext-v4'
      and prompt_version = 'v4-vision-core-v3'
      and router_version = 'claim-routing-v2'
      and coverage_version = 'critical-coverage-v3'
      and assurance_version = 'assurance-topic-v2'
      and config #>> '{compute_profiles,premium,targeted_max_provider_output_tokens}' = '4096'
      and config #>> '{compute_profiles,economy,targeted_max_provider_output_tokens}' = '3072'
  ) then
    raise exception 'active vnext-v4 quality config was not updated';
  end if;

  select pg_get_functiondef(
    'public.resolve_analysis_engine_route_v5(uuid,uuid,jsonb,jsonb)'::regprocedure
  ) into v_route_definition;
  if position('v4-vision-core-v2' in v_route_definition) = 0
    or position('claim-routing-v1' in v_route_definition) = 0 then
    raise exception 'route v5 version guard baseline mismatch';
  end if;
  execute replace(
    replace(v_route_definition, 'v4-vision-core-v2', 'v4-vision-core-v3'),
    'claim-routing-v1',
    'claim-routing-v2'
  );

  select pg_get_functiondef(
    'public.begin_analysis_engine_run_v4(uuid,uuid,bigint,integer,uuid,text)'::regprocedure
  ) into v_begin_definition;
  if position('v4-vision-core-v2' in v_begin_definition) = 0
    or position('claim-routing-v1' in v_begin_definition) = 0
    or position('controls-v19' in v_begin_definition) = 0 then
    raise exception 'begin v4 version baseline mismatch';
  end if;
  execute replace(
    replace(
      replace(v_begin_definition, 'v4-vision-core-v2', 'v4-vision-core-v3'),
      'claim-routing-v1',
      'claim-routing-v2'
    ),
    'controls-v19',
    'controls-v20'
  );
end;
$$;

update public.app_feature_flags
set value = jsonb_set(
  coalesce(value, '{}'::jsonb) || jsonb_build_object(
    'last_quality_patch', 'v4-quality-scoring-text-v3',
    'last_quality_patch_at', now()
  ),
  '{kill_switch}',
  'false'::jsonb,
  true
)
where key = 'analysis_engine_v4'
  and value->>'rollout_mode' = 'user_allowlist'
  and coalesce((value->>'general_release_approved')::boolean, false) = false;

select pg_notify('pgrst', 'reload schema');
