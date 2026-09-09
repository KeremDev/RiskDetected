-- Applied as 20260905232257; opt-in V5 routing preserves existing snapshots.
-- Free API remains OFF until the actual legacy free project has passed model,
-- quota, billing and data/region eligibility preflight. No credential is stored
-- in a config snapshot. Deploy worker + analyze-v4 before enabling either flag.
do $migration$
declare
  definition text;
  anchor text := '    v_compute := jsonb_build_object(';
begin
  definition := pg_get_functiondef(
    'public.resolve_analysis_engine_route_v5(uuid,uuid,jsonb,jsonb)'::regprocedure
  );
  if position(anchor in definition) = 0 or
     position('''product_plan'', v_plan,' in definition) = 0 then
    raise exception 'V5 route baseline mismatch';
  end if;
  definition := replace(definition, anchor, $patch$
    if v_plan = 'free' and v_route_name = 'free_legacy'
      and p_compute_routing->>'first_paid_ai_eligible' = 'false'
      and v_config.config->>'engine_mode' = 'free'
      and v_config.config->>'v5_free_repeat_enabled' = 'true'
      and exists (
        select 1 from public.analyses prior
        where prior.user_id = p_user_id and prior.id <> p_analysis_id
          and prior.status::text = 'completed'
      )
    then
      v_pool := 'free_standard'; v_tier := 'standard';
    end if;
    v_compute := jsonb_build_object($patch$);
  definition := replace(definition,
    '''product_plan'', v_plan,',
    '''product_plan'', v_plan,
      ''first_paid_ai_eligible'', coalesce(p_compute_routing->''first_paid_ai_eligible'', ''true''::jsonb),');
  execute definition;

  definition := pg_get_functiondef(
    'public.record_analysis_provider_attempt_v5(uuid,uuid,uuid,uuid,text,integer,text,text,text,text,bigint,bigint,bigint,bigint,numeric,bigint,integer,text,text,text,text,text,numeric,text,text,text,integer)'::regprocedure
  );
  if position('(''paid_standard'',''paid_flex'')' in definition) = 0 then
    raise exception 'V5 telemetry baseline mismatch';
  end if;
  execute replace(definition, '(''paid_standard'',''paid_flex'')',
    '(''paid_standard'',''paid_flex'',''free_standard'')');
end;
$migration$;

update private.analysis_v4_configs
set config = jsonb_build_object(
  'v5_free_repeat_enabled', false,
  'v5_same_model_retry_enabled', false
) || coalesce(config, '{}'::jsonb), updated_at = now()
where is_active and engine_version = 'vnext-v4';
