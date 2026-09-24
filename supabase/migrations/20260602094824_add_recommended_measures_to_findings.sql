alter table public.findings
  add column if not exists recommended_measures jsonb not null default '[]'::jsonb;

alter table public.findings
  drop constraint if exists findings_recommended_measures_is_array;

alter table public.findings
  add constraint findings_recommended_measures_is_array
  check (jsonb_typeof(recommended_measures) = 'array');

update public.findings
set recommended_measures = jsonb_build_array(
  jsonb_build_object(
    'kind', 'corrective',
    'title', 'Düzeltici önlem',
    'text', recommended_action
  )
)
where recommended_measures = '[]'::jsonb
  and nullif(trim(coalesce(recommended_action, '')), '') is not null;
