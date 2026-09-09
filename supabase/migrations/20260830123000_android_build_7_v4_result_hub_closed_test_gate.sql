-- RiskDetected Android 2.0.0 (versionCode 7) closed-test gate.
--
-- This admits only Android build 7 to the already-approved V4 engine and result-hub
-- contracts. It deliberately does not advance android_release_policy, minimum-version
-- enforcement, or any public-store rollout. iOS build allowlists are preserved verbatim.

-- Training is now a first-class result-hub section and can open the membership screen.
-- The original attribution constraint predated that section and would reject otherwise-valid
-- Android/iOS entry events.
alter table public.paywall_events
  drop constraint if exists paywall_events_result_section_check;

alter table public.paywall_events
  add constraint paywall_events_result_section_check
    check (
      result_section is null
      or result_section in (
        'risk_analysis',
        'expert_recommendations',
        'training_recommendations',
        'approved_notebook'
      )
    );

-- Training cards use stable catalog-derived string identifiers rather than finding/notebook
-- UUIDs. Extend the result feedback ledger so reactions for the fourth result section can be
-- persisted with the same note/reason contract as every other card.
alter table private.analysis_item_feedback
  drop constraint if exists analysis_item_feedback_target_kind_check,
  drop constraint if exists analysis_item_feedback_section_check,
  drop constraint if exists analysis_item_feedback_check;

alter table private.analysis_item_feedback
  add constraint analysis_item_feedback_target_kind_check
    check (target_kind in ('finding', 'notebook_entry', 'training_card')),
  add constraint analysis_item_feedback_section_check
    check (section in (
      'risk_analysis',
      'expert_recommendations',
      'training_recommendations',
      'approved_notebook'
    )),
  add constraint analysis_item_feedback_target_reference_check
    check (
      (target_kind = 'finding' and public_finding_id is not null and notebook_entry_id is null)
      or (
        target_kind = 'notebook_entry'
        and public_finding_id is null
        and notebook_entry_id is not null
      )
      or (
        target_kind = 'training_card'
        and public_finding_id is null
        and notebook_entry_id is null
      )
    );

do $preflight$
declare
  v_engine_flag jsonb;
  v_hub_flag jsonb;
begin
  select value into v_engine_flag
  from public.app_feature_flags
  where key = 'analysis_engine_v4';

  select value into v_hub_flag
  from public.app_feature_flags
  where key = 'analysis_result_hub_v1';

  if v_engine_flag is null
    or v_engine_flag->>'rollout_mode' <> 'build_allowlist'
    or not (coalesce(v_engine_flag->'enabled_ios_builds', '[]'::jsonb) ? '87')
    or not (coalesce(v_engine_flag->'enabled_ios_builds', '[]'::jsonb) ? '88')
    or coalesce(v_engine_flag->>'general_release_approved', 'false') <> 'true'
    or coalesce(v_engine_flag->>'kill_switch', 'true') <> 'false'
    or coalesce(v_engine_flag->>'required_api_contract', '') <> '3'
    or coalesce(v_engine_flag->>'required_capability', '') <> 'safety_claim_v4_scoreless'
  then
    raise exception 'Android build 7 V4 preflight state mismatch';
  end if;

  if v_hub_flag is null
    or v_hub_flag->>'rollout_mode' <> 'build_allowlist'
    or not (coalesce(v_hub_flag->'enabled_ios_builds', '[]'::jsonb) ? '87')
    or not (coalesce(v_hub_flag->'enabled_ios_builds', '[]'::jsonb) ? '88')
    or coalesce(v_hub_flag->>'kill_switch', 'true') <> 'false'
    or coalesce(v_hub_flag->>'required_capability', '') <> 'analysis_result_hub_v1'
  then
    raise exception 'Android build 7 result-hub preflight state mismatch';
  end if;
end;
$preflight$;

update public.app_feature_flags
set value = jsonb_set(
      value,
      '{enabled_android_builds}',
      (
        select jsonb_agg(distinct build order by build)
        from jsonb_array_elements_text(
          coalesce(value->'enabled_android_builds', '[]'::jsonb) || '["7"]'::jsonb
        ) as build
      ),
      true
    ),
    updated_at = now()
where key = 'analysis_engine_v4';

update public.app_feature_flags
set value = jsonb_set(
      value,
      '{enabled_android_builds}',
      (
        select jsonb_agg(distinct build order by build)
        from jsonb_array_elements_text(
          coalesce(value->'enabled_android_builds', '[]'::jsonb) || '["7"]'::jsonb
        ) as build
      ),
      true
    ),
    updated_at = now()
where key = 'analysis_result_hub_v1';

do $verification$
declare
  v_engine_flag jsonb;
  v_hub_flag jsonb;
  v_config private.analysis_v4_configs%rowtype;
begin
  select value into v_engine_flag
  from public.app_feature_flags
  where key = 'analysis_engine_v4';

  select value into v_hub_flag
  from public.app_feature_flags
  where key = 'analysis_result_hub_v1';

  select * into v_config
  from private.analysis_v4_configs
  where is_active and integrity_status = 'valid'
  order by updated_at desc
  limit 1;

  if not (coalesce(v_engine_flag->'enabled_android_builds', '[]'::jsonb) ? '7')
    or not (coalesce(v_engine_flag->'enabled_ios_builds', '[]'::jsonb) ? '87')
    or not (coalesce(v_engine_flag->'enabled_ios_builds', '[]'::jsonb) ? '88')
    or v_engine_flag->>'rollout_mode' <> 'build_allowlist'
    or coalesce(v_engine_flag->>'general_release_approved', 'false') <> 'true'
    or coalesce(v_engine_flag->>'kill_switch', 'true') <> 'false'
  then
    raise exception 'Android build 7 V4 gate verification failed';
  end if;

  if not (coalesce(v_hub_flag->'enabled_android_builds', '[]'::jsonb) ? '7')
    or not (coalesce(v_hub_flag->'enabled_ios_builds', '[]'::jsonb) ? '87')
    or not (coalesce(v_hub_flag->'enabled_ios_builds', '[]'::jsonb) ? '88')
    or v_hub_flag->>'rollout_mode' <> 'build_allowlist'
    or coalesce(v_hub_flag->>'kill_switch', 'true') <> 'false'
  then
    raise exception 'Android build 7 result-hub gate verification failed';
  end if;

  if not found
    or v_config.engine_version <> 'vnext-v4'
    or v_config.provider_contract_version <> 'visual-claim-candidate-v1'
    or v_config.domain_schema_version <> 'safety-claim-v4.0'
    or v_config.prompt_sha256 !~ '^[a-f0-9]{64}$'
  then
    raise exception 'Android build 7 active V4 configuration verification failed';
  end if;
end;
$verification$;
