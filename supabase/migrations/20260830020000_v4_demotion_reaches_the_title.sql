-- claim-routing-v30: a demoted item must stop asserting what it was demoted for.
--
-- Run d54b5165, third pass over the crane workshop. The resolution floor did
-- its job: both hook-latch candidates arrived at 0.03 by 0.05 and both were
-- demoted to field checks, and the item's description read honestly -- "mandal
-- net olarak görünmüyor". Its title, however, was still "Vinç kancasında
-- emniyet mandalı EKSİKLİĞİ".
--
-- The gate had changed the class and left the name alone. A reader scanning
-- titles sees a finding; the item underneath says go and look. The demotion has
-- to reach the title or it only half happened. Absence nouns in the title of a
-- verification request are now rewritten to "durumu" -- the thing to check
-- rather than the thing concluded. Scored findings keep their wording, under
-- test: a real absence should be named as one.
--
-- The same run also told a warehouse, about its pallet racking, to "verify the
-- continuity of the collective edge protection". Racking has no edge protection
-- whose continuity could be verified. v29 taught the control playbook to read
-- the asset the model named; the temporary-protection line for field checks was
-- a second, separate function that still keyed on module alone, where a rack
-- and a slab edge are indistinguishable. It now reads the asset too, and hooks
-- and racking each get the check that belongs to them.
do $$
declare
  v_sha constant text :=
    '823b6ad1fa8a5cebecc18182c55fa2d9f68809e9e73b6832d07a6cc3a0e9fd1e';
begin
  update private.analysis_v4_configs
  set router_version = 'claim-routing-v30',
      config = config || jsonb_build_object('router_version', 'claim-routing-v30'),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and prompt_version = 'v4-vision-core-v10'
    and prompt_sha256 = v_sha
    and config->>'prompt_bundle_sha256' = v_sha
    and router_version = 'claim-routing-v30'
    and integrity_status = 'valid'
    and (config->'compute_profiles'->'premium'->>'single_photo_gemini_thinking_budget')::int = 3072
    and (config->>'absence_resolution_floor')::numeric = 0.004
    and (config->>'positive_control_resolution_floor')::numeric = 0.004;
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
