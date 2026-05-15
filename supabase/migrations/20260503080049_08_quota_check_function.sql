
-- Free tier kullanıcı için günlük kota kontrolü ve azaltma
create or replace function public.check_and_consume_quota(p_user_id uuid)
returns table(allowed boolean, remaining int, tier subscription_tier)
language plpgsql security definer set search_path = public as $$
declare
  v_tier subscription_tier;
  v_used int;
  v_reset date;
  v_limit int := 5;          -- Free tier günlük limit
begin
  select tier, daily_quota_used, daily_quota_reset_at
    into v_tier, v_used, v_reset
  from public.profiles
  where id = p_user_id
  for update;

  if not found then
    return query select false, 0, 'free'::subscription_tier;
    return;
  end if;

  -- Pro: sınırsız
  if v_tier = 'pro' then
    return query select true, 9999, v_tier;
    return;
  end if;

  -- Gün değiştiyse sıfırla
  if v_reset < current_date then
    update public.profiles
       set daily_quota_used = 0,
           daily_quota_reset_at = current_date
     where id = p_user_id;
    v_used := 0;
  end if;

  if v_used >= v_limit then
    return query select false, 0, v_tier;
    return;
  end if;

  update public.profiles
     set daily_quota_used = daily_quota_used + 1
   where id = p_user_id;

  return query select true, (v_limit - v_used - 1), v_tier;
end $$;

revoke all on function public.check_and_consume_quota(uuid) from public, anon;
grant execute on function public.check_and_consume_quota(uuid) to authenticated, service_role;
;
