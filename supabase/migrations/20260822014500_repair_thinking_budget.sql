-- Gives the coverage-quality repair its own thinking budget.
--
-- The repair pass ran on a hard-coded 1024 while the analysis pass ran on
-- 6144. It is not a text touch-up: it re-reads the photo looking for hazards
-- the first pass missed. Across thirteen production repairs it added four
-- findings and rejected seventeen of its own candidates as duplicates, at
-- roughly twelve seconds and a full model call each.
--
-- 3072 sits between the old value and the analysis budget. It is a flag rather
-- than a constant so the next move can be measured and made without a deploy;
-- `repair_thinking_budget` is read through normalizeThinkingBudget, which
-- clamps to 0..8192 and falls back to 3072 on anything invalid.
--
-- This does not change how many photos the repair sees or what it is allowed
-- to attach a finding to. Those remain bounded by the first pass's layer audit.

do $repair_thinking_budget$
declare
  v_value jsonb;
begin
  select value into v_value
  from public.app_feature_flags
  where key = 'multi_photo_analysis'
  for update;

  if v_value is null then
    raise exception 'multi_photo_analysis flag is missing';
  end if;

  update public.app_feature_flags
  set value = v_value || jsonb_build_object('repair_thinking_budget', 3072),
      updated_at = now()
  where key = 'multi_photo_analysis';

  select value into v_value
  from public.app_feature_flags
  where key = 'multi_photo_analysis';

  if coalesce((v_value ->> 'repair_thinking_budget')::int, 0) <> 3072 then
    raise exception 'repair_thinking_budget did not apply';
  end if;
end;
$repair_thinking_budget$;
