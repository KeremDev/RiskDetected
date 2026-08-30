-- gemini-3.5-flash-lite: MEDIUM -> HIGH, one variable.
--
-- MEDIUM produced zero candidates on the crane workshop. Not zero scored
-- findings after the gates -- zero claims. The routing ledger is empty because
-- nothing arrived to route. Its own coverage notes read "Zemin ve geçiş yolları
-- açıktır", "Genel düzen ve temizlik tatmin edicidir", and the scene summary
-- called the floor "düzenli ve boş", over a floor carrying cardboard, pallets,
-- drums, a large coil and scattered equipment on both sides. gemini-2.5-flash
-- caught that clutter in four runs out of four and it was confirmed against the
-- photograph each time. It also returned two scene entities where 2.5 returned
-- eight.
--
-- So the model is not misreading the picture, it is barely looking at it. On
-- Gemini 3 the thinking level governs how much visual analysis happens as well
-- as how much reasoning, which is the part of the earlier recommendation that
-- did not carry over: on 2.5 the bottleneck was perception at fixed attention,
-- and MEDIUM was chosen on that evidence. A smaller model appears to spend the
-- level on looking.
--
-- HIGH is the last thing worth trying before the model is set aside. It stays a
-- single changed variable: same model, same per-part ultra_high, same prompt.
--
-- The other open question is measured now rather than argued. Google reports
-- prompt tokens by modality and the provider logs the image count, so the next
-- run says outright whether the per-part ultra_high applied -- 2240 tokens if
-- it did, 1120 if it was silently dropped. The totals could never separate
-- those, because changing model moves the text tokens at the same time.
do $$
declare
  v_rows int;
begin
  update private.analysis_v4_configs
  set config = jsonb_set(
        config,
        '{compute_profiles,premium,gemini_thinking_level}',
        '"HIGH"'::jsonb
      ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'no active v4 config to change';
  end if;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and integrity_status = 'valid'
    and router_version = 'claim-routing-v30'
    and config->>'primary_model' = 'gemini-3.5-flash-lite'
    and config->'compute_profiles'->'premium'->>'primary_model' = 'gemini-3.5-flash-lite'
    and config->'compute_profiles'->'premium'->>'gemini_thinking_level' = 'HIGH'
    -- Untouched, and still what a rollback to 2.5 would restore.
    and (config->'compute_profiles'->'premium'->>'single_photo_gemini_thinking_budget')::int = 3072
    and config->>'model_trial_previous_model' = 'gemini-2.5-flash';
  if not found then
    raise exception 'thinking level change did not land cleanly';
  end if;

  perform 1 from private.analysis_v4_configs
  where config->>'checkpoint_label' = 'known_good_checkpoint_2026_08_26'
    and is_active = false and integrity_status = 'retired';
  if not found then
    raise exception 'the 2026-08-26 restore point is missing or was activated';
  end if;
end $$;
