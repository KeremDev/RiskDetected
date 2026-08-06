-- Covers E8 (20260806224500_android_client_platform_columns.sql): additive columns exist,
-- accept ios/android/null, reject anything else.

begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select extensions.plan(6);

select has_column('public', 'analyses', 'client_platform', 'analyses.client_platform exists');
select has_column('public', 'ai_usage_logs', 'client_platform', 'ai_usage_logs.client_platform exists');

insert into auth.users (id, email, aud, role, created_at, updated_at)
values (
  '00000000-0000-4000-8000-000000000901'::uuid,
  'client-platform-test@example.invalid',
  'authenticated', 'authenticated', now(), now()
);

select lives_ok(
  $$
    insert into public.analyses (id, user_id, status, kind, client_platform)
    values (
      '00000000-0000-4000-8000-000000000902'::uuid,
      '00000000-0000-4000-8000-000000000901'::uuid,
      'pending', 'photo',
      'android'
    )
  $$,
  'analyses row with client_platform=android is insertable'
);

select lives_ok(
  $$
    insert into public.analyses (id, user_id, status, kind, client_platform)
    values (
      '00000000-0000-4000-8000-000000000903'::uuid,
      '00000000-0000-4000-8000-000000000901'::uuid,
      'pending', 'photo',
      null
    )
  $$,
  'analyses row with client_platform=null is insertable (predates-this-column case)'
);

select throws_ok(
  $$
    insert into public.analyses (id, user_id, status, kind, client_platform)
    values (
      '00000000-0000-4000-8000-000000000904'::uuid,
      '00000000-0000-4000-8000-000000000901'::uuid,
      'pending', 'photo',
      'web'
    )
  $$,
  '23514', null,
  'an unknown client_platform value is rejected'
);

select throws_ok(
  $$
    insert into public.ai_usage_logs (analysis_id, user_id, model, client_platform)
    values (
      '00000000-0000-4000-8000-000000000902'::uuid,
      '00000000-0000-4000-8000-000000000901'::uuid,
      'test-model',
      'web'
    )
  $$,
  '23514', null,
  'ai_usage_logs.client_platform rejects the same unknown value'
);

select * from finish();
rollback;
