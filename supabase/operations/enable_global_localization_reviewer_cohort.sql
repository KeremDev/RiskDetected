\set ON_ERROR_STOP on

\if :{?reviewer_email}
\else
  \echo 'reviewer_email psql variable is required'
  \quit 2
\endif

begin;

select set_config(
  'riskdetected.reviewer_email',
  :'reviewer_email',
  true
);

do $$
declare
  v_flag_count integer;
  v_non_off_count integer;
  v_hash_count integer;
  v_build_count integer;
  v_reviewer_count integer;
begin
  select
    count(*)::integer,
    count(*) filter (
      where value->>'rollout_mode' is distinct from 'off'
    )::integer,
    coalesce(sum(jsonb_array_length(
      coalesce(value->'enabled_user_hashes', '[]'::jsonb)
    )), 0)::integer,
    coalesce(sum(jsonb_array_length(
      coalesce(value->'enabled_ios_builds', '[]'::jsonb)
    )), 0)::integer
  into
    v_flag_count,
    v_non_off_count,
    v_hash_count,
    v_build_count
  from public.app_feature_flags
  where key = any (array[
    'localization_v2',
    'english_product_enabled',
    'global_localization_wave1',
    'safety_profile_en_intl_enabled',
    'safety_profile_en_gb_enabled',
    'safety_profile_en_us_enabled',
    'safety_profile_en_au_enabled',
    'safety_profile_en_ca_enabled',
    'localization_queue_payload_v1',
    'ai_language_guard_enabled',
    'ai_country_term_guard_enabled',
    'english_report_enabled',
    'english_notifications_enabled'
  ]::text[]);

  select count(*)::integer
  into v_reviewer_count
  from auth.users
  where lower(email) = lower(
    current_setting('riskdetected.reviewer_email', true)
  );

  if v_flag_count <> 13
     or v_non_off_count <> 0
     or v_hash_count <> 0
     or v_build_count <> 0
     or v_reviewer_count <> 1
  then
    raise exception
      'reviewer_cohort_preflight_failed flags=% non_off=% hashes=% builds=% reviewers=%',
      v_flag_count,
      v_non_off_count,
      v_hash_count,
      v_build_count,
      v_reviewer_count;
  end if;
end
$$;

with reviewer as (
  select substring(
    encode(extensions.digest(id::text, 'sha256'), 'hex')
    from 1 for 12
  ) as user_hash
  from auth.users
  where lower(email) = lower(
    current_setting('riskdetected.reviewer_email', true)
  )
),
updated as (
  update public.app_feature_flags f
  set value = jsonb_set(
    jsonb_set(
      f.value,
      '{rollout_mode}',
      to_jsonb('allowlist'::text),
      true
    ),
    '{enabled_user_hashes}',
    jsonb_build_array(reviewer.user_hash),
    true
  )
  from reviewer
  where f.key = any (array[
    'localization_v2',
    'english_product_enabled',
    'global_localization_wave1',
    'safety_profile_en_intl_enabled',
    'safety_profile_en_gb_enabled',
    'safety_profile_en_us_enabled',
    'safety_profile_en_au_enabled',
    'safety_profile_en_ca_enabled',
    'localization_queue_payload_v1',
    'ai_language_guard_enabled',
    'ai_country_term_guard_enabled',
    'english_report_enabled',
    'english_notifications_enabled'
  ]::text[])
  returning f.key, f.value
)
select
  count(*)::integer as updated_count,
  count(*) filter (
    where value->>'rollout_mode' = 'allowlist'
  )::integer as allowlist_count,
  coalesce(sum(jsonb_array_length(
    coalesce(value->'enabled_user_hashes', '[]'::jsonb)
  )), 0)::integer as hash_entry_count
from updated;

commit;

