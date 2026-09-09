create or replace function private.normalize_localized_onboarding_answers()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if lower(nullif(btrim(new.raw_answers->>'app_language'), '')) = 'en' then
    new.certificate_class := null;
    new.hazard_classes := '{}'::text[];
    new.raw_answers := coalesce(new.raw_answers, '{}'::jsonb) || jsonb_build_object(
      'certificate_class', null,
      'hazard_classes', '[]'::jsonb
    );
  end if;

  return new;
end;
$$;

revoke all on function private.normalize_localized_onboarding_answers() from public, anon, authenticated;

drop trigger if exists normalize_localized_onboarding_answers
  on public.user_onboarding_answers;

create trigger normalize_localized_onboarding_answers
before insert or update on public.user_onboarding_answers
for each row execute function private.normalize_localized_onboarding_answers();

-- Repair any historic English row whose scalar fields were already cleaned but
-- whose raw JSON still retained Turkish-only terminology from an older session.
update public.user_onboarding_answers as answers
set
  certificate_class = null,
  hazard_classes = '{}'::text[],
  raw_answers = coalesce(answers.raw_answers, '{}'::jsonb) || jsonb_build_object(
    'certificate_class', null,
    'hazard_classes', '[]'::jsonb
  )
from public.profiles as profile
where profile.id = answers.user_id
  and lower(
    coalesce(
      nullif(btrim(answers.raw_answers->>'app_language'), ''),
      nullif(btrim(profile.app_language), ''),
      ''
    )
  ) = 'en'
  and (
    answers.certificate_class is not null
    or cardinality(answers.hazard_classes) > 0
    or coalesce(answers.raw_answers->>'certificate_class', '') <> ''
    or jsonb_array_length(
      case
        when jsonb_typeof(answers.raw_answers->'hazard_classes') = 'array'
          then answers.raw_answers->'hazard_classes'
        else '[]'::jsonb
      end
    ) > 0
  );

select pg_notify('pgrst', 'reload schema');
