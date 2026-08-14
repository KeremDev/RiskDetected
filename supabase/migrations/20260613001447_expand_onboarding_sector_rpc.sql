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
  v_allowed_sectors text[] := array[
    'construction', 'manufacturing', 'energy', 'mining', 'office', 'other',
    'logistics_warehouse', 'chemical_laboratory', 'healthcare', 'food_production',
    'agriculture_livestock', 'retail', 'municipal_field_services', 'education', 'hospitality'
  ]::text[];
begin
  if v_user_id is null then raise exception 'auth_required' using errcode = '28000'; end if;
  v_hazard_classes := coalesce((select array_agg(distinct h order by h) from unnest(coalesce(p_hazard_classes, '{}'::text[])) as hazard(h) where h is not null and btrim(h) <> ''), '{}'::text[]);
  v_sectors := coalesce((select array_agg(distinct s order by s) from unnest(coalesce(p_sectors, '{}'::text[])) as sector(s) where s is not null and btrim(s) <> ''), '{}'::text[]);
  if p_onboarding_version is distinct from 'v2' then raise exception 'invalid_onboarding_version' using errcode = '22023'; end if;
  if p_certificate_class is not null and p_certificate_class not in ('A', 'B', 'C', 'doctor', 'otherHealth') then raise exception 'invalid_certificate_class' using errcode = '22023'; end if;
  if not (v_hazard_classes <@ array['critical', 'high', 'low']::text[]) or cardinality(v_hazard_classes) > 3 then raise exception 'invalid_hazard_classes' using errcode = '22023'; end if;
  if not (v_sectors <@ v_allowed_sectors) or cardinality(v_sectors) > 15 then raise exception 'invalid_sectors' using errcode = '22023'; end if;
  if p_audit_frequency is not null and p_audit_frequency not in ('1', '2-5', '6-15', '15+') then raise exception 'invalid_audit_frequency' using errcode = '22023'; end if;
  if p_selected_plan is not null and p_selected_plan not in ('yearly', 'monthly') then raise exception 'invalid_selected_plan' using errcode = '22023'; end if;
  if jsonb_typeof(v_raw_answers) is distinct from 'object' then raise exception 'invalid_raw_answers' using errcode = '22023'; end if;
  insert into public.user_onboarding_answers (user_id, onboarding_version, certificate_class, hazard_classes, sectors, audit_frequency, selected_plan, raw_answers, completed_at)
  values (v_user_id, 'v2', p_certificate_class, v_hazard_classes, v_sectors, p_audit_frequency, p_selected_plan, v_raw_answers, now())
  on conflict (user_id) do update set onboarding_version = excluded.onboarding_version, certificate_class = coalesce(excluded.certificate_class, user_onboarding_answers.certificate_class), hazard_classes = case when cardinality(excluded.hazard_classes) > 0 then excluded.hazard_classes else user_onboarding_answers.hazard_classes end, sectors = case when cardinality(excluded.sectors) > 0 then excluded.sectors else user_onboarding_answers.sectors end, audit_frequency = coalesce(excluded.audit_frequency, user_onboarding_answers.audit_frequency), selected_plan = coalesce(excluded.selected_plan, user_onboarding_answers.selected_plan), raw_answers = coalesce(user_onboarding_answers.raw_answers, '{}'::jsonb) || excluded.raw_answers, completed_at = now()
  returning * into v_row;
  return v_row;
end;
$$;
select pg_notify('pgrst', 'reload schema');;
