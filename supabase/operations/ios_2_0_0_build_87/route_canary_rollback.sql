-- Transactional production canary. It leaves no user, analysis or route rows.
begin;

insert into auth.users (id, email, aud, role, created_at, updated_at)
values (
  '00000000-0000-4000-8000-000000008799',
  'release-87-route-canary@example.invalid',
  'authenticated',
  'authenticated',
  now(),
  now()
);

insert into public.analyses (
  id, user_id, kind, status, photo_count, plan_at_creation,
  client_platform, client_build
)
values
  ('00000000-0000-4000-8000-000000008791', '00000000-0000-4000-8000-000000008799', 'photo', 'pending', 1, 'free', 'ios', '87'),
  ('00000000-0000-4000-8000-000000008792', '00000000-0000-4000-8000-000000008799', 'photo', 'pending', 1, 'plus', 'ios', '87'),
  ('00000000-0000-4000-8000-000000008793', '00000000-0000-4000-8000-000000008799', 'photo', 'pending', 1, 'pro', 'ios', '87'),
  ('00000000-0000-4000-8000-000000008794', '00000000-0000-4000-8000-000000008799', 'photo', 'pending', 1, 'free', 'ios', '86'),
  ('00000000-0000-4000-8000-000000008795', '00000000-0000-4000-8000-000000008799', 'photo', 'pending', 1, 'free', 'android', '87');

do $canary$
declare
  v_compute constant jsonb :=
    '{"snapshot_version":1,"source":"trusted_analyze_enqueue","ai_execution_route":"paid_plan"}';
  v_ios87 constant jsonb :=
    '{"snapshot_version":1,"source":"trusted_analyze_enqueue","api_contract_version":3,"client_platform":"ios","client_app_build":"87","safety_claim_v4_scoreless":true}';
  v_ios86 constant jsonb :=
    '{"snapshot_version":1,"source":"trusted_analyze_enqueue","api_contract_version":3,"client_platform":"ios","client_app_build":"86","safety_claim_v4_scoreless":true}';
  v_android87 constant jsonb :=
    '{"snapshot_version":1,"source":"trusted_analyze_enqueue","api_contract_version":3,"client_platform":"android","client_app_build":"87","safety_claim_v4_scoreless":true}';
  v_variant text;
  v_analysis_id uuid;
begin
  foreach v_analysis_id in array array[
    '00000000-0000-4000-8000-000000008791'::uuid,
    '00000000-0000-4000-8000-000000008792'::uuid,
    '00000000-0000-4000-8000-000000008793'::uuid
  ] loop
    v_variant := public.resolve_analysis_engine_route_v5(
      '00000000-0000-4000-8000-000000008799',
      v_analysis_id,
      v_compute,
      v_ios87
    )->>'engine_variant';
    if v_variant <> 'vnext-v4' then
      raise exception 'build 87 route canary failed for %: %',
        v_analysis_id, v_variant;
    end if;
  end loop;

  if public.resolve_analysis_engine_route_v5(
    '00000000-0000-4000-8000-000000008799',
    '00000000-0000-4000-8000-000000008794',
    v_compute,
    v_ios86
  )->>'engine_variant' = 'vnext-v4' then
    raise exception 'build 86 unexpectedly entered V4';
  end if;

  if public.resolve_analysis_engine_route_v5(
    '00000000-0000-4000-8000-000000008799',
    '00000000-0000-4000-8000-000000008795',
    v_compute,
    v_android87
  )->>'engine_variant' = 'vnext-v4' then
    raise exception 'Android unexpectedly changed';
  end if;
end
$canary$;

select 'PASS: build87 Free/Plus/Pro=vnext-v4; iOS86/Android unchanged'
  as route_canary;

rollback;
