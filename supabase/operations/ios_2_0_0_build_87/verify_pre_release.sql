begin;
set local transaction read only;

select
  engine.value->>'rollout_mode' = 'build_allowlist' as engine_build_gate,
  engine.value->'enabled_ios_builds' ? '87' as engine_has_build_87,
  engine.value->>'general_release_approved' = 'true' as v4_release_approved,
  engine.value->>'kill_switch' = 'false' as engine_available,
  hub.value->>'rollout_mode' = 'build_allowlist' as hub_build_gate,
  hub.value->'enabled_ios_builds' ? '87' as hub_has_build_87,
  hub.value->>'kill_switch' = 'false' as hub_available,
  config.engine_version = 'vnext-v4' as engine_is_v4,
  config.client_api_contract >= 3 as api_contract_3,
  config.integrity_status = 'valid' and config.is_active as config_valid,
  policy.value->>'hard_update_enabled' = 'false' as hard_update_still_off
from public.app_feature_flags engine
join public.app_feature_flags hub on hub.key = 'analysis_result_hub_v1'
join public.app_feature_flags policy on policy.key = 'ios_release_policy'
cross join lateral (
  select *
  from private.analysis_v4_configs
  where is_active and integrity_status = 'valid'
  order by updated_at desc
  limit 1
) config
where engine.key = 'analysis_engine_v4';

rollback;
