-- Keep the QA account on its existing Free entitlement while allowing it to
-- exercise the routing-first v4 engine and the new three-section result hub.
-- A fresh/local migration replay may not contain this production auth user;
-- in that case both inserts intentionally become no-ops.

insert into private.analysis_v4_allowlist (user_id, enabled, note)
select u.id, true, 'Free QA account for v4 analysis validation'
from auth.users u
join public.profiles p on p.id = u.id
where lower(trim(u.email)) = 'minecraft.ps2026@gmail.com'
on conflict (user_id) do update
set enabled = true,
    note = excluded.note,
    updated_at = now();

insert into private.analysis_result_hub_allowlist (user_id, enabled, note)
select u.id, true, 'Free QA account for result hub premium-lock validation'
from auth.users u
join public.profiles p on p.id = u.id
where lower(trim(u.email)) = 'minecraft.ps2026@gmail.com'
on conflict (user_id) do update
set enabled = true,
    note = excluded.note,
    updated_at = now();
