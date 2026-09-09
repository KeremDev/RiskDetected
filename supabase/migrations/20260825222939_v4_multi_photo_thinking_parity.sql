-- Multi-photo runs were given less thinking than single-photo ones while doing
-- strictly more work. A 3-photo run consumed 6136 of its 6144 tokens - the cap
-- to the token - and the same starvation was measured on the v3 engine, where
-- one photo of three produced zero candidates after spending the whole budget
-- on its inventory.
--
-- Premium multi-photo now matches premium single-photo at 3072. Economy is
-- already at parity and is untouched. Prompt, router and schema are unchanged,
-- so no version moves and no deploy is required.

update private.analysis_v4_configs
set
  config = jsonb_set(
    config,
    '{compute_profiles,premium,multi_photo_gemini_thinking_budget}',
    '3072'::jsonb,
    true
  ) || jsonb_build_object('multi_photo_thinking_parity_version', 1),
  updated_at = now()
where engine_version = 'vnext-v4'
  and is_active = true;

do $$
declare
  v_config private.analysis_v4_configs%rowtype;
begin
  select * into v_config from private.analysis_v4_configs
  where engine_version = 'vnext-v4' and is_active = true;

  if not found
    or v_config.config #>> '{compute_profiles,premium,multi_photo_gemini_thinking_budget}' <> '3072'
    or v_config.config #>> '{compute_profiles,premium,single_photo_gemini_thinking_budget}' <> '3072'
    or v_config.prompt_version <> 'v4-vision-core-v4'
    or v_config.router_version <> 'claim-routing-v3'
    or v_config.integrity_status <> 'valid'
  then
    raise exception 'v4 multi-photo thinking parity verification failed';
  end if;
end;
$$;
