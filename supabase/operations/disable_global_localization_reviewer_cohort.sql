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
  v_reviewer_count integer;
begin
  select count(*)::integer
  into v_reviewer_count
  from auth.users
  where lower(email) = lower(
    current_setting('riskdetected.reviewer_email', true)
  );

  if v_reviewer_count <> 1 then
    raise exception
      'reviewer_cohort_rollback_preflight_failed reviewers=%',
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
cleaned as (
  select
    f.key,
    coalesce(
      (
        select jsonb_agg(item)
        from jsonb_array_elements_text(
          coalesce(f.value->'enabled_user_hashes', '[]'::jsonb)
        ) item
        where item <> reviewer.user_hash
      ),
      '[]'::jsonb
    ) as remaining_hashes
  from public.app_feature_flags f
  cross join reviewer
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
),
updated as (
  update public.app_feature_flags f
  set value = jsonb_set(
    jsonb_set(
      f.value,
      '{enabled_user_hashes}',
      cleaned.remaining_hashes,
      true
    ),
    '{rollout_mode}',
    to_jsonb(
      case
        when jsonb_array_length(cleaned.remaining_hashes) = 0 then 'off'
        else 'allowlist'
      end
    ),
    true
  )
  from cleaned
  where f.key = cleaned.key
  returning f.key, f.value
)
select
  count(*)::integer as updated_count,
  count(*) filter (
    where value->>'rollout_mode' = 'off'
  )::integer as off_count,
  coalesce(sum(jsonb_array_length(
    coalesce(value->'enabled_user_hashes', '[]'::jsonb)
  )), 0)::integer as remaining_hash_entry_count
from updated;

commit;

