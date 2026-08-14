-- Covers 20260807214500_android_legal_document_set.sql: profiles.client_platform exists,
-- rejects unknown values, and private.enforce_profile_localization_pair_v1 only produces
-- 'tr-android-v1' when client_platform='android' -- every other case (NULL, 'ios', English)
-- must keep producing exactly what it produced before this migration.

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select extensions.plan(10);

select has_column('public', 'profiles', 'client_platform', 'profiles.client_platform exists');

-- 20260801170000_client_field_authority_hardening.sql column-scoped authenticated's grants on
-- profiles; a new column is unwritable by the client until explicitly added there too. This
-- would otherwise fail silently at the RPC layer (permission denied) rather than at the CHECK/
-- trigger this migration is actually about -- worth a dedicated assertion, not just implied by
-- the UPDATE statements above succeeding as the table owner/service role.
select ok(
  has_column_privilege('authenticated', 'public.profiles', 'client_platform', 'update'),
  'authenticated can update the client-owned client_platform column'
);
select ok(
  has_column_privilege('authenticated', 'public.profiles', 'client_platform', 'insert'),
  'authenticated can insert the client-owned client_platform column'
);

insert into auth.users (id, email, aud, role, created_at, updated_at)
values
  ('00000000-0000-4000-8000-000000000911'::uuid, 'legal-set-android@example.invalid', 'authenticated', 'authenticated', now(), now()),
  ('00000000-0000-4000-8000-000000000912'::uuid, 'legal-set-null@example.invalid', 'authenticated', 'authenticated', now(), now()),
  ('00000000-0000-4000-8000-000000000913'::uuid, 'legal-set-ios@example.invalid', 'authenticated', 'authenticated', now(), now()),
  ('00000000-0000-4000-8000-000000000914'::uuid, 'legal-set-en-android@example.invalid', 'authenticated', 'authenticated', now(), now()),
  ('00000000-0000-4000-8000-000000000915'::uuid, 'legal-set-check-only@example.invalid', 'authenticated', 'authenticated', now(), now());

-- tg_create_profile_for_new_user already inserted a row per id above; drive the trigger under
-- test the same way the app actually does, via UPDATE of app_language (+ client_platform).

update public.profiles set app_language = 'tr', client_platform = 'android'
  where id = '00000000-0000-4000-8000-000000000911'::uuid;
select results_eq(
  $$ select legal_document_set from public.profiles where id = '00000000-0000-4000-8000-000000000911'::uuid $$,
  $$ values ('tr-android-v1'::text) $$,
  'app_language=tr + client_platform=android -> legal_document_set=tr-android-v1'
);

update public.profiles set app_language = 'tr', client_platform = null
  where id = '00000000-0000-4000-8000-000000000912'::uuid;
select results_eq(
  $$ select legal_document_set from public.profiles where id = '00000000-0000-4000-8000-000000000912'::uuid $$,
  $$ values ('tr-current'::text) $$,
  'app_language=tr + client_platform=null (predates-column/legacy) -> unchanged tr-current'
);

update public.profiles set app_language = 'tr', client_platform = 'ios'
  where id = '00000000-0000-4000-8000-000000000913'::uuid;
select results_eq(
  $$ select legal_document_set from public.profiles where id = '00000000-0000-4000-8000-000000000913'::uuid $$,
  $$ values ('tr-current'::text) $$,
  'app_language=tr + client_platform=ios (explicit iOS) -> unchanged tr-current'
);

-- English branch must stay platform-blind: DEC-10 only carved out a Turkish Android set, English
-- already has its own review-gated global set shared by both platforms.
update public.profiles
  set app_language = 'en', safety_profile_id = 'en-us-generic-v1', client_platform = 'android'
  where id = '00000000-0000-4000-8000-000000000914'::uuid;
select results_eq(
  $$ select legal_document_set from public.profiles where id = '00000000-0000-4000-8000-000000000914'::uuid $$,
  $$ values ('en-global-v1'::text) $$,
  'app_language=en + client_platform=android -> still en-global-v1, English branch is platform-blind'
);

select throws_ok(
  $$
    update public.profiles set client_platform = 'web'
    where id = '00000000-0000-4000-8000-000000000911'::uuid
  $$,
  '23514', null,
  'an unknown client_platform value is rejected'
);

-- id 915 never gets app_language set, so the trigger's if/elsif never match and
-- legal_document_set keeps exactly what this UPDATE assigns -- isolates the CHECK constraint
-- itself from the trigger's own assignment, unlike the earlier rows.
select lives_ok(
  $$
    update public.profiles set legal_document_set = 'tr-android-v1'
    where id = '00000000-0000-4000-8000-000000000915'::uuid
  $$,
  'tr-android-v1 is an accepted profiles.legal_document_set value (CHECK constraint widened)'
);

select throws_ok(
  $$
    update public.profiles set legal_document_set = 'android-made-up-set'
    where id = '00000000-0000-4000-8000-000000000915'::uuid
  $$,
  '23514', null,
  'an unrecognized legal_document_set value is still rejected'
);

select * from finish();
rollback;
