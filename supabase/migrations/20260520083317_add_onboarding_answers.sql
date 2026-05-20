create table if not exists public.user_onboarding_answers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  onboarding_version text not null default 'v2',
  certificate_class text,
  hazard_classes text[] not null default '{}'::text[],
  sectors text[] not null default '{}'::text[],
  audit_frequency text,
  selected_plan text,
  raw_answers jsonb not null default '{}'::jsonb,
  completed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_onboarding_answers_version_check
    check (onboarding_version in ('v2')),
  constraint user_onboarding_answers_certificate_check
    check (
      certificate_class is null
      or certificate_class in ('A', 'B', 'C', 'doctor', 'otherHealth')
    ),
  constraint user_onboarding_answers_hazards_check
    check (
      hazard_classes <@ array['critical', 'high', 'low']::text[]
      and cardinality(hazard_classes) <= 3
    ),
  constraint user_onboarding_answers_sectors_check
    check (
      sectors <@ array['construction', 'manufacturing', 'energy', 'mining', 'office', 'other']::text[]
      and cardinality(sectors) <= 2
    ),
  constraint user_onboarding_answers_frequency_check
    check (
      audit_frequency is null
      or audit_frequency in ('1', '2-5', '6-15', '15+')
    ),
  constraint user_onboarding_answers_plan_check
    check (
      selected_plan is null
      or selected_plan in ('yearly', 'monthly')
    ),
  constraint user_onboarding_answers_raw_object_check
    check (jsonb_typeof(raw_answers) = 'object')
);

alter table public.user_onboarding_answers enable row level security;

drop policy if exists user_onboarding_answers_select_own
  on public.user_onboarding_answers;
create policy user_onboarding_answers_select_own
  on public.user_onboarding_answers
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists user_onboarding_answers_insert_own
  on public.user_onboarding_answers;
create policy user_onboarding_answers_insert_own
  on public.user_onboarding_answers
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists user_onboarding_answers_update_own
  on public.user_onboarding_answers;
create policy user_onboarding_answers_update_own
  on public.user_onboarding_answers
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

revoke all on public.user_onboarding_answers from anon, public;
grant select, insert, update on public.user_onboarding_answers to authenticated;

drop trigger if exists user_onboarding_answers_set_updated_at
  on public.user_onboarding_answers;
create trigger user_onboarding_answers_set_updated_at
  before update on public.user_onboarding_answers
  for each row execute function public.tg_set_updated_at();

create or replace function public.upsert_onboarding_v2_answers(
  p_onboarding_version text default 'v2',
  p_certificate_class text default null,
  p_hazard_classes text[] default '{}'::text[],
  p_sectors text[] default '{}'::text[],
  p_audit_frequency text default null,
  p_selected_plan text default null,
  p_raw_answers jsonb default '{}'::jsonb
)
returns public.user_onboarding_answers
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_hazard_classes text[];
  v_sectors text[];
  v_raw_answers jsonb := coalesce(p_raw_answers, '{}'::jsonb);
  v_row public.user_onboarding_answers;
begin
  if v_user_id is null then
    raise exception 'auth_required'
      using errcode = '28000';
  end if;

  v_hazard_classes := coalesce(
    (
      select array_agg(distinct h order by h)
      from unnest(coalesce(p_hazard_classes, '{}'::text[])) as hazard(h)
      where h is not null and btrim(h) <> ''
    ),
    '{}'::text[]
  );

  v_sectors := coalesce(
    (
      select array_agg(distinct s order by s)
      from unnest(coalesce(p_sectors, '{}'::text[])) as sector(s)
      where s is not null and btrim(s) <> ''
    ),
    '{}'::text[]
  );

  if p_onboarding_version is distinct from 'v2' then
    raise exception 'invalid_onboarding_version'
      using errcode = '22023';
  end if;

  if p_certificate_class is not null
    and p_certificate_class not in ('A', 'B', 'C', 'doctor', 'otherHealth')
  then
    raise exception 'invalid_certificate_class'
      using errcode = '22023';
  end if;

  if not (v_hazard_classes <@ array['critical', 'high', 'low']::text[])
    or cardinality(v_hazard_classes) > 3
  then
    raise exception 'invalid_hazard_classes'
      using errcode = '22023';
  end if;

  if not (v_sectors <@ array['construction', 'manufacturing', 'energy', 'mining', 'office', 'other']::text[])
    or cardinality(v_sectors) > 2
  then
    raise exception 'invalid_sectors'
      using errcode = '22023';
  end if;

  if p_audit_frequency is not null
    and p_audit_frequency not in ('1', '2-5', '6-15', '15+')
  then
    raise exception 'invalid_audit_frequency'
      using errcode = '22023';
  end if;

  if p_selected_plan is not null
    and p_selected_plan not in ('yearly', 'monthly')
  then
    raise exception 'invalid_selected_plan'
      using errcode = '22023';
  end if;

  if jsonb_typeof(v_raw_answers) is distinct from 'object' then
    raise exception 'invalid_raw_answers'
      using errcode = '22023';
  end if;

  insert into public.user_onboarding_answers (
    user_id,
    onboarding_version,
    certificate_class,
    hazard_classes,
    sectors,
    audit_frequency,
    selected_plan,
    raw_answers,
    completed_at
  )
  values (
    v_user_id,
    'v2',
    p_certificate_class,
    v_hazard_classes,
    v_sectors,
    p_audit_frequency,
    p_selected_plan,
    v_raw_answers,
    now()
  )
  on conflict (user_id) do update
  set
    onboarding_version = excluded.onboarding_version,
    certificate_class = coalesce(excluded.certificate_class, user_onboarding_answers.certificate_class),
    hazard_classes = case
      when cardinality(excluded.hazard_classes) > 0 then excluded.hazard_classes
      else user_onboarding_answers.hazard_classes
    end,
    sectors = case
      when cardinality(excluded.sectors) > 0 then excluded.sectors
      else user_onboarding_answers.sectors
    end,
    audit_frequency = coalesce(excluded.audit_frequency, user_onboarding_answers.audit_frequency),
    selected_plan = coalesce(excluded.selected_plan, user_onboarding_answers.selected_plan),
    raw_answers = coalesce(user_onboarding_answers.raw_answers, '{}'::jsonb) || excluded.raw_answers,
    completed_at = now()
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.upsert_onboarding_v2_answers(
  text,
  text,
  text[],
  text[],
  text,
  text,
  jsonb
) from public, anon, authenticated;
grant execute on function public.upsert_onboarding_v2_answers(
  text,
  text,
  text[],
  text[],
  text,
  text,
  jsonb
) to authenticated;
