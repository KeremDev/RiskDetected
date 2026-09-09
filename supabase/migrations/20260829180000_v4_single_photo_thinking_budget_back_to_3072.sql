-- Revert the single-photo thinking budget: 6144 -> 3072.
--
-- Two runs at 6144, measured against seven at 3072 on the same photograph:
--
--   thinking   5947 -> 8811   (+48%)
--   cost       $0.0394 -> $0.0472  (+20%, +$0.0078/analysis)
--   duration   64.8s -> 77.8s  (+20%, +13s the user waits)
--   visible output tokens  8979 -> 9190  (flat)
--
-- Cost and latency are certain. The quality gain is not: the budget change and
-- the v22/v23 routing gates shipped together, so nothing separates them, and
-- n=2. The one signal that is model-side rather than router-side is the model's
-- own positive controls -- at 6144 it wrote "tam bir korkuluk sistemi (üst
-- korkuluk, ara korkuluk ve etek tahtası) mevcuttur" for both platforms for the
-- first time in the series -- but the very next run at the same budget went back
-- to claiming a missing mid rail. One run out of two.
--
-- Meanwhile the false scored finding at 6144 (FK 270, "sıkışma noktaları
-- OLABİLECEK kısımlar") was stopped by a gate, not by the budget.
--
-- The premise behind the raise was also weaker than it looked. "The cap is hit
-- every call" was true for six of seven runs, but the cap was not the binding
-- constraint: at 6144 one primary pass stopped at 1989 tokens and another ran to
-- 6143. The model spends what it needs.
--
-- Testing this properly means freezing the routing gates and running a fixed
-- photo set three times per budget, counting false scored findings. Changing a
-- gate and a budget in the same round can never answer the question.
--
-- Routing gates stay: they carry recorded reason codes and demonstrable effect.
do $$
declare
  v_before integer;
  v_after integer;
begin
  select (config->'compute_profiles'->'premium'->>'single_photo_gemini_thinking_budget')::int
    into v_before
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4' and is_active = true;

  if v_before is distinct from 6144 then
    raise exception 'unexpected single-photo thinking budget before revert: %', v_before;
  end if;

  update private.analysis_v4_configs
  set config = jsonb_set(
        config,
        '{compute_profiles,premium,single_photo_gemini_thinking_budget}',
        to_jsonb(3072)
      ) || jsonb_build_object('single_photo_thinking_budget_version', 3),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  select (config->'compute_profiles'->'premium'->>'single_photo_gemini_thinking_budget')::int
    into v_after
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4' and is_active = true;

  if v_after is distinct from 3072 then
    raise exception 'single-photo thinking budget revert did not land: %', v_after;
  end if;

  perform 1 from private.analysis_v4_configs
  where engine_version = 'vnext-v4' and is_active = true
    and (config->'compute_profiles'->'premium'->>'multi_photo_gemini_thinking_budget')::int = 3072
    and router_version = 'claim-routing-v24'
    and prompt_version = 'v4-vision-core-v10'
    and integrity_status = 'valid';
  if not found then
    raise exception 'router/prompt/multi-photo state changed unexpectedly during revert';
  end if;

  perform 1 from private.analysis_v4_configs
  where config->>'checkpoint_label' = 'known_good_checkpoint_2026_08_26'
    and is_active = false and integrity_status = 'retired';
  if not found then
    raise exception 'the 2026-08-26 restore point is missing or was activated';
  end if;
end $$;
