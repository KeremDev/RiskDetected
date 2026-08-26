-- claim-routing-v6.
--
-- Scored findings were shallower than the unscored items above them. Root cause
-- and measures were keyed by module across catalogs that covered six of the
-- nineteen modules, so on analysis d799ff50 five of eight findings -- a crane
-- hook with no latch, an excavator's articulated arm, an unguarded rotating
-- shaft, active excavation -- all published the same two sentences:
--   "Tehlike yoluna erişimi durdurun ve görünen fiziksel koşulu güvenli hale
--    getirin."
--   "Aynı koşulun tekrarını önleyecek sorumluluk, kontrol sıklığı ve fiziksel
--    koruma standardını belirleyin."
-- Meanwhile an assurance requirement carried five numbered field steps and a
-- standards list.
--
-- Module is also the wrong key for a root cause. Material falling out of an
-- excavator bucket was given the guardrail sentence "Görünen çalışma kenarında
-- toplu düşmeye karşı koruma sürekliliği sağlanmamıştır" because it shares a
-- module with edge protection. Root cause and measures now come from a playbook
-- keyed on mechanism, which is the causal axis the control text and the severity
-- cap already use; a module override remains only where its wording adds detail.
--
-- Two mechanism-resolution gaps from the same run:
--   * "nesne düşmesi ... aşağıdaki kişiye çarpma" through a missing toeboard
--     resolved to fall_from_height, because the falling-object test wanted the
--     literal words "cisim" or "düşen".
--   * High-pressure hydraulic lines arrive under the energy module and fell to
--     other_visible_physical, capping a fluid injection injury at severity 15.
--
-- Tuning only: the prompt bundle is untouched.
do $$
declare
  v_prompt text;
  v_sha text;
begin
  select prompt_version, prompt_sha256 into v_prompt, v_sha
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4' and is_active = true;

  update private.analysis_v4_configs
  set router_version = 'claim-routing-v6',
      config = config
        || jsonb_build_object(
             'router_version', 'claim-routing-v6',
             'mechanism_control_playbook_version', 1,
             'mechanism_root_cause_version', 1,
             'mechanism_control_mapping_version', 17,
             'root_cause_claim_policy_version', 7,
             'falling_object_object_noun_version', 1,
             'hydraulic_injection_mechanism_version', 1
           ),
      updated_at = now()
  where engine_version = 'vnext-v4' and is_active = true;

  perform 1
  from private.analysis_v4_configs
  where engine_version = 'vnext-v4'
    and is_active = true
    and router_version = 'claim-routing-v6'
    and prompt_version = v_prompt
    and prompt_sha256 = v_sha
    and integrity_status = 'valid';
  if not found then
    raise exception 'v4 router bump did not land cleanly (prompt or integrity moved)';
  end if;
end $$;
