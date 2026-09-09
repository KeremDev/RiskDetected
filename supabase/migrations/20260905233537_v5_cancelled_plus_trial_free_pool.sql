-- Applied as 20260905233537; preserve PLUS entitlement and quotas.
-- The enqueue service attests a still-active, cancelled seven-day PLUS trial.
-- Old snapshots remain immutable; deploy the compatible engine before enabling.
do $migration$
declare
  definition text;
  anchor text := '    v_compute := jsonb_build_object(';
begin
  definition := pg_get_functiondef(
    'public.resolve_analysis_engine_route_v5(uuid,uuid,jsonb,jsonb)'::regprocedure
  );
  if position(anchor in definition) = 0
    or position('v5_free_repeat_enabled' in definition) = 0
    or position('v5_cancelled_plus_trial_free_enabled' in definition) > 0 then
    raise exception 'Cancelled PLUS trial V5 route baseline mismatch';
  end if;
  definition := replace(definition, anchor, $patch$
    if v_plan = 'plus' and v_route_name = 'cancelled_plus_trial_free'
      and p_compute_routing->>'cancelled_plus_trial_free_candidate' = 'true'
      and p_compute_routing->>'cancelled_plus_trial_free_enabled' = 'true'
      and v_config.config->>'engine_mode' = 'free'
      and v_config.config->>'v5_cancelled_plus_trial_free_enabled' = 'true'
    then
      v_pool := 'free_standard'; v_tier := 'standard';
    end if;
    v_compute := jsonb_build_object($patch$);
  definition := replace(definition,
    '''product_plan'', v_plan,',
    '''product_plan'', v_plan,
      ''cancelled_plus_trial_free_candidate'', coalesce(p_compute_routing->''cancelled_plus_trial_free_candidate'', ''false''::jsonb),
      ''cancelled_plus_trial_free_enabled'', coalesce(p_compute_routing->''cancelled_plus_trial_free_enabled'', ''false''::jsonb),');
  execute definition;
end;
$migration$;

update private.analysis_v4_configs
set config = jsonb_build_object('v5_cancelled_plus_trial_free_enabled', false)
  || coalesce(config, '{}'::jsonb), updated_at = now()
where is_active and engine_version = 'vnext-v4';
