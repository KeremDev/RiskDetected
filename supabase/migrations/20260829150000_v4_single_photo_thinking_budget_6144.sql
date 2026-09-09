-- Single-photo thinking budget 3072 -> 6144 (premium profile only).
--
-- Gemini 2.5 Flash takes a numeric thinking budget, not an effort level; the
-- ceiling is 24 576. Every v4 run has been spending 3068-3071 of its 3072, i.e.
-- hitting the cap on every call, on both the primary pass and the single-photo
-- verification pass. We have been running at 12.5% of the ceiling and truncating
-- deliberation every time.
--
-- The failure this is aimed at looks like haste rather than blindness: five
-- consecutive runs of one process-tank photograph each claimed a different
-- guardrail defect -- toeboard, top rail, mid rail, mid rail, then an unnamed
-- gap -- on a frame where every platform carries all three members. The model
-- sees the rail and does not finish counting it.
--
-- Cost: thinking bills at the output rate, and the verification pass means the
-- budget is paid twice. ~$0.042 -> ~$0.057 per single-photo analysis, against
-- the configured average_cost_limit_usd of 0.10.
--
-- Single photo only. Multi-photo stays at 3072: there the budget is paid once
-- per photo and doubling it scales with the photo count.
--
-- Derived budgets are clamped to the primary in compute-profile.ts, so the
-- technical retry (1536) and targeted (768) are unchanged by this.
do $$
declare
  v_before integer;
  v_after integer;
begin
  select (config->'compute_profiles'->'premium'->>'single_photo_gemini_thinking_budget')::int
    into v_before
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4' and is_active = true;

  if v_before is distinct from 3072 then
    raise exception 'unexpected single-photo thinking budget before bump: %', v_before;
  end if;

  update private.analysis_v4_configs
  set config = jsonb_set(
        config,
        '{compute_profiles,premium,single_photo_gemini_thinking_budget}',
        to_jsonb(6144)
      ) || jsonb_build_object('single_photo_thinking_budget_version', 2),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  select (config->'compute_profiles'->'premium'->>'single_photo_gemini_thinking_budget')::int
    into v_after
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4' and is_active = true;

  if v_after is distinct from 6144 then
    raise exception 'single-photo thinking budget did not land: %', v_after;
  end if;

  -- Multi-photo must not move with it.
  perform 1 from private.analysis_v4_configs
  where engine_version = 'vnext-v4' and is_active = true
    and (config->'compute_profiles'->'premium'->>'multi_photo_gemini_thinking_budget')::int = 3072;
  if not found then
    raise exception 'multi-photo thinking budget changed unexpectedly';
  end if;

  perform 1 from private.analysis_v4_configs
  where config->>'checkpoint_label' = 'known_good_checkpoint_2026_08_26'
    and is_active = false and integrity_status = 'retired';
  if not found then
    raise exception 'the 2026-08-26 restore point is missing or was activated';
  end if;
end $$;
