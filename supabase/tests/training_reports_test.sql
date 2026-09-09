begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(9);

insert into auth.users (id, email, aud, role, created_at, updated_at)
select ('00000000-0000-4000-8000-00000000191' || n)::uuid,
  'training-report-' || n || '@example.invalid', 'authenticated', 'authenticated', now(), now()
from generate_series(1, 3) n;
insert into public.user_subscriptions(user_id, tier, status, current_period_ends_at)
values
  ('00000000-0000-4000-8000-000000001912', 'plus', 'active', now() + interval '1 month'),
  ('00000000-0000-4000-8000-000000001913', 'pro', 'active', now() + interval '1 month')
on conflict (user_id) do update set tier = excluded.tier, status = excluded.status, current_period_ends_at = excluded.current_period_ends_at;

select extensions.is(
  (public.check_report_quota_eligibility_v2(('00000000-0000-4000-8000-00000000191' || n)::uuid, 'standard', format, 'training_recommendations')->>'allowed')::boolean,
  n > 1, 'training report access for tier ' || n || ' / ' || format
) from generate_series(1, 3) n cross join (values ('pdf'), ('xlsx')) f(format);

select extensions.matches(public.next_report_document_no_v2('00000000-0000-4000-8000-000000001912', 'training_recommendations'), '^RD-EO-', 'training reports have their own document series');
select extensions.ok(not has_function_privilege('authenticated', 'public.check_report_quota_eligibility_v2(uuid,text,text,text)', 'execute'), 'quota remains service-only');
select extensions.ok(not has_function_privilege('anon', 'public.next_report_document_no_v2(uuid,text)', 'execute'), 'document numbering remains service-only');
select * from extensions.finish();
rollback;
