-- Store the first device region observed after an authenticated profile is ready.
-- This is a device setting snapshot, not an App Store storefront attribution.

alter table public.profiles
  add column if not exists first_seen_device_region_code text,
  add column if not exists first_seen_device_region_at timestamptz;

alter table public.profiles
  drop constraint if exists profiles_first_seen_device_region_code_check;

alter table public.profiles
  add constraint profiles_first_seen_device_region_code_check
  check (
    first_seen_device_region_code is null
    or first_seen_device_region_code ~ '^[A-Z]{2}$'
  );

comment on column public.profiles.first_seen_device_region_code is
  'ISO 3166-1 alpha-2 region from the device locale when first observed; not an App Store storefront.';
comment on column public.profiles.first_seen_device_region_at is
  'Timestamp when first_seen_device_region_code was recorded.';

create or replace function public.record_first_seen_device_region_v1(
  p_region_code text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_region_code text := upper(btrim(p_region_code));
  v_recorded_region_code text;
begin
  if v_user_id is null then
    raise exception 'auth_required' using errcode = '28000';
  end if;

  if v_region_code is null or v_region_code !~ '^[A-Z]{2}$' then
    raise exception 'invalid_device_region_code' using errcode = '22023';
  end if;

  update public.profiles as profile
  set first_seen_device_region_code = v_region_code,
      first_seen_device_region_at = statement_timestamp()
  where profile.id = v_user_id
    and profile.first_seen_device_region_code is null
  returning profile.first_seen_device_region_code
  into v_recorded_region_code;

  if v_recorded_region_code is null then
    select profile.first_seen_device_region_code
    into v_recorded_region_code
    from public.profiles as profile
    where profile.id = v_user_id;
  end if;

  if v_recorded_region_code is null then
    raise exception 'profile_not_found' using errcode = 'P0002';
  end if;

  return v_recorded_region_code;
end;
$$;

revoke all on function public.record_first_seen_device_region_v1(text)
  from public, anon;
grant execute on function public.record_first_seen_device_region_v1(text)
  to authenticated;

revoke insert (
  first_seen_device_region_code,
  first_seen_device_region_at
) on table public.profiles from anon, authenticated;
revoke update (
  first_seen_device_region_code,
  first_seen_device_region_at
) on table public.profiles from anon, authenticated;
