-- claim-routing-v25: slipping off a ladder is a fall from height.
--
-- Analysis 3faeb7fb: a portable ladder leaning against an open mezzanine,
-- unsecured at the top and not extending past the landing. The model wrote the
-- event path as "merdivenden KAYMA/düşme yoluyla ciddi yaralanma".
--
-- The access_egress mechanism rule listed "kayma" among the same-level markers
-- alongside "takılma" and "aynı seviyede", and it was tested first. So the slip
-- word matched before the ladder rule could run: mechanism fall_same_level,
-- severity capped at 7, FK 126 where it should read 720, and the walkway root
-- cause -- "güvenli ve kesintisiz bir geçiş yolu korunacak biçimde
-- düzenlenmemiştir" -- attached to a ladder access defect.
--
-- Tripping stays a same-level word wherever it appears: a ladder lying across a
-- walkway is a trip hazard, and that case keeps its own test. Slipping does not,
-- when the path also names a ladder, platform, mezzanine or landing.
--
-- Prompt bundle untouched, single-photo thinking budget stays 3072; both asserted.
do $$
declare
  v_sha constant text :=
    '823b6ad1fa8a5cebecc18182c55fa2d9f68809e9e73b6832d07a6cc3a0e9fd1e';
begin
  update private.analysis_v4_configs
  set router_version = 'claim-routing-v25',
      config = config
        || jsonb_build_object(
             'router_version', 'claim-routing-v25',
             'ladder_access_mechanism_version', 2
           ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and prompt_version = 'v4-vision-core-v10'
    and prompt_sha256 = v_sha
    and config->>'prompt_bundle_sha256' = v_sha
    and router_version = 'claim-routing-v25'
    and integrity_status = 'valid'
    and (config->'compute_profiles'->'premium'->>'single_photo_gemini_thinking_budget')::int = 3072;
  if not found then
    raise exception 'v4 router bump did not land cleanly';
  end if;

  perform 1 from private.analysis_v4_configs
  where config->>'checkpoint_label' = 'known_good_checkpoint_2026_08_26'
    and is_active = false and integrity_status = 'retired';
  if not found then
    raise exception 'the 2026-08-26 restore point is missing or was activated';
  end if;
end $$;
