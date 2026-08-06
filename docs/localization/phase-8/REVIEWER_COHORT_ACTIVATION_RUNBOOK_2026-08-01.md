# Reviewer-Only Localization Cohort Runbook

Status: prepared, not executed  
Production project: `ppcrzemgiztzcgddbins`  
Candidate: iOS 1.3.0 (78)  
Current live release: iOS 1.2.4 (77)

## Purpose

Give only the App Review demo account access to the Wave 1 localization
backend so Apple can execute the uploaded English review path. This is not the
public rollout and does not release the App Store version.

The operation requires explicit owner authorization. It must not run merely
because the App Store candidate is technically valid.

The canonical executor is
`scripts/reviewer_localization_cohort.mjs`. It reads the configured demo
account name directly from the candidate App Store review record without
requesting sensitive password output. The name exists only in process memory
and a mode-`0600` temporary SQL file that is deleted immediately after the
query. It is never printed or copied to evidence.

Activation is also sequence-locked: the executor refuses to mutate Supabase
until TestFlight stage 1 has canonical passing evidence and the rollout
manifest points to stage 2. It may be re-used after all nine stages pass to
retain reviewer-only App Review access. A command confirmation cannot bypass
this ordering gate.

## Isolation properties

- All 13 localization flags use `rollout_mode=allowlist`.
- Each flag contains one 12-character SHA-256-derived reviewer user hash.
- The reviewer email and user UUID are never written to the repository,
  evidence files, telemetry, or logs.
- Build 77 reports no localization capability and stays on the Turkish legacy
  path.
- No other user hash is added.
- No flag uses `rollout_mode=on`, `build_allowlist`, `min_build`, or a public
  percentage.
- No `enabled_ios_builds`, kill-switch, subscription, App Store review, or
  release value is changed.
- Public/post-approval rollout remains a separate owner-controlled operation.

## Exact flag set

1. `localization_v2`
2. `english_product_enabled`
3. `global_localization_wave1`
4. `safety_profile_en_intl_enabled`
5. `safety_profile_en_gb_enabled`
6. `safety_profile_en_us_enabled`
7. `safety_profile_en_au_enabled`
8. `safety_profile_en_ca_enabled`
9. `localization_queue_payload_v1`
10. `ai_language_guard_enabled`
11. `ai_country_term_guard_enabled`
12. `english_report_enabled`
13. `english_notifications_enabled`

## Preflight

The execution tool must first prove:

- 13/13 rows exist.
- 13/13 rollout modes are `off`.
- Total enabled reviewer hashes are zero.
- Total enabled iOS builds are zero.
- The demo account exists exactly once.
- `extensions.digest` is available.
- Build 78 is `VALID` and present in the internal TestFlight group.
- Build 77 is still the live App Store release.

Any mismatch aborts the operation without attempting to normalize unknown
state.

The canonical psql operations are:

- `supabase/operations/enable_global_localization_reviewer_cohort.sql`
- `supabase/operations/disable_global_localization_reviewer_cohort.sql`

Both require a runtime-only `reviewer_email` psql variable. They contain no
real reviewer address or hash.

Local operation verification on 2026-08-01:

- Synthetic reviewer fixture inserted into the local Supabase instance.
- Enable operation updated 13/13 flags to `allowlist`.
- Every flag contained exactly one reviewer hash.
- Enabled iOS build count remained zero.
- Rollback restored 13/13 flags to `off` and zero hashes.
- The synthetic reviewer fixture was deleted.
- Persistent local post-test state: 13/13 `off`, zero reviewer hashes.
- Secure executor and sequence-lock tests: 5/5 passed.
- Production read-only status: one matching auth account, 13/13 flags `off`,
  zero user-hash entries, zero build entries and zero active kill switches.
- Aggregate preflight:
  `docs/localization/phase-8/REVIEWER_COHORT_PREFLIGHT_2026-08-01.json`.
- Current activation status is `hold_prior_stage_incomplete`; the database is
  ready, but stage 1 must pass first.

Read-only status command:

```sh
node scripts/reviewer_localization_cohort.mjs status
```

After an explicit owner authorization, the guarded activation command is:

```sh
node scripts/reviewer_localization_cohort.mjs activate \
  --confirm=reviewer-only-allowlist
```

The exact rollback command is:

```sh
node scripts/reviewer_localization_cohort.mjs rollback \
  --confirm=rollback-reviewer-only-allowlist
```

The confirmation argument is a command safety guard. It does not replace the
required owner authorization in the active execution record.


## Activation transaction

`<REVIEWER_EMAIL>` is supplied only to the secure database execution call. It
must not be substituted into a committed file.

```sql
begin;

select set_config(
  'riskdetected.reviewer_email',
  '<REVIEWER_EMAIL>',
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
```

Expected result:

- `updated_count = 13`
- `allowlist_count = 13`
- `hash_entry_count = 13`

The result must not print the reviewer hash.

## Read-after-write verification

```sql
select
  count(*)::integer as flag_count,
  count(*) filter (
    where value->>'rollout_mode' = 'allowlist'
  )::integer as allowlist_count,
  count(*) filter (
    where jsonb_array_length(
      coalesce(value->'enabled_user_hashes', '[]'::jsonb)
    ) = 1
  )::integer as one_hash_count,
  coalesce(sum(jsonb_array_length(
    coalesce(value->'enabled_ios_builds', '[]'::jsonb)
  )), 0)::integer as enabled_build_count,
  count(*) filter (
    where coalesce((value->>'kill_switch')::boolean, false)
  )::integer as kill_switch_true_count
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
```

Expected:

- `flag_count = 13`
- `allowlist_count = 13`
- `one_hash_count = 13`
- `enabled_build_count = 0`
- `kill_switch_true_count = 0`

## Required reviewer smoke after activation

Using build 78 and the App Review demo account:

1. Launch with English selected in iOS Settings.
2. Select International and create one synthetic single-photo analysis.
3. Verify English result, Fine-Kinney/5×5 presentation, PDF and XLSX.
4. Repeat one bounded analysis for UK, US, AU and CA terminology profiles.
5. Confirm every non-TR result hides structured legislation.
6. Confirm restore purchases, English legal links and in-app account deletion.
7. Record only aggregate outcomes; do not store account credentials, photos,
   prompts, user UUID, reviewer email, or the reviewer hash.

This smoke is a minimum App Review access check. It does not replace the
nine-stage TestFlight rollout required by the execution plan.

## Rollback

Rollback removes only the same reviewer hash. If another authorized hash was
added later, it is preserved and the mode remains `allowlist`.

```sql
begin;

select set_config(
  'riskdetected.reviewer_email',
  '<REVIEWER_EMAIL>',
  true
);

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
    f.value,
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
)
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
where f.key = cleaned.key;

commit;
```

After rollback, run the production-isolation query again. If this reviewer was
the only cohort member, the expected state is 13/13 `off`, zero hashes and zero
enabled builds.
