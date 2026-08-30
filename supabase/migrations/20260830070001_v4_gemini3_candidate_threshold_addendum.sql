-- A candidate threshold for the Gemini 3 family. 2.5 keeps its own, untouched.
--
-- gemini-3.7-flash returned zero candidates on the crane workshop, and unlike
-- gemini-3.5-flash-lite it was not blind. Its coverage note explains itself:
--
--   "Kenar kısımlarda depolanan malzemeler bulunmakla birlikte ana yürüme yolu
--    üzerinde kritik takılma/çarpma engeli bulunmamaktadır."
--
-- It saw the clutter, judged it not critical, and filtered before emitting.
-- flash-lite had said the opposite thing -- "Zemin düzenli ve boştur" -- which
-- was simply false. One is a perception failure, the other a threshold, and
-- only the second is ours to fix.
--
-- It is ours because the architecture already assigns that decision elsewhere:
-- the model reports what is physically visible, the router decides class,
-- severity, and whether an item scores at all. gemini-2.5-flash happens to
-- report first and judge later, which is why it finds this clutter in four runs
-- out of four. The Gemini 3 models apply their own actionability bar first. The
-- addendum takes that decision back.
--
-- It does not lower the evidence bar, and says so in its own last section. The
-- failure in the other direction is the fabricated hook latch that cost three
-- router versions, and an addendum that read as "claim more" would buy findings
-- back at exactly that price. What it forbids is a specific move: writing
-- "present, but not critical" and emitting nothing. The first half of that
-- sentence is a candidate.
--
-- Versioned and hashed separately from the base bundle, so V4_PROMPT_VERSION
-- stays v4-vision-core-v10 at SHA 823b6ad1... and the five measured 2.5 runs
-- remain comparable. Selection is by model family in the provider, applied to
-- every call -- primary, coverage repair, targeted, verification -- because a
-- threshold that held for one pass and not the next would produce candidates
-- the second look then dropped.
--
-- One confound stays on the record rather than being argued away: the Gemini 3
-- path differs from 2.5 in four ways at once -- model, thinking parameter,
-- absent temperature, per-part ultra_high -- so "2.5 finds more" is a property
-- of that whole set, not of the model alone. Within the Gemini 3 family the
-- comparison is clean.
do $$
declare
  v_base constant text :=
    '823b6ad1fa8a5cebecc18182c55fa2d9f68809e9e73b6832d07a6cc3a0e9fd1e';
  v_addendum constant text :=
    '59ab8abb632063c1e890a7b4cea251da4c208f7e61ee24805208b08f74bceb69';
  v_rows int;
begin
  update private.analysis_v4_configs
  set config = config || jsonb_build_object(
        'gemini3_prompt_version', 'v4-gemini3-threshold-v1',
        'gemini3_prompt_addendum_sha256', v_addendum
      ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'no active v4 config to annotate';
  end if;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and integrity_status = 'valid'
    and router_version = 'claim-routing-v30'
    -- Unmoved, and the whole point: 2.5 receives the same bytes it was
    -- measured on.
    and prompt_version = 'v4-vision-core-v10'
    and prompt_sha256 = v_base
    and config->>'prompt_bundle_sha256' = v_base
    and config->>'gemini3_prompt_version' = 'v4-gemini3-threshold-v1'
    and config->>'gemini3_prompt_addendum_sha256' = v_addendum
    and config->>'primary_model' = 'gemini-3.7-flash';
  if not found then
    raise exception 'gemini3 addendum did not land cleanly';
  end if;

  perform 1 from private.analysis_v4_configs
  where config->>'checkpoint_label' = 'known_good_checkpoint_2026_08_26'
    and is_active = false and integrity_status = 'retired';
  if not found then
    raise exception 'the 2026-08-26 restore point is missing or was activated';
  end if;
end $$;
