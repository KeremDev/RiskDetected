-- Canonical, notebook-only advisory prose contract. This table deliberately does not
-- replace public.findings.recommended_action: Risk Analizi and Uzman Görüşü
-- keep their operational wording while Onaylı Defter reads this sidecar.

create table private.analysis_notebook_advisories (
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  source_finding_id uuid not null references public.findings(id) on delete cascade,
  language text not null check (language in ('tr', 'en')),
  advisory_text text not null,
  source_hash text not null,
  generator_version text not null,
  generator_kind text not null check (generator_kind in ('model', 'fallback')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (source_finding_id, language),
  check (length(btrim(advisory_text)) between 20 and 1000),
  check (source_hash ~ '^[0-9a-f]{64}$'),
  check (length(btrim(generator_version)) between 1 and 120),
  check (
    language <> 'tr'
    or btrim(advisory_text) ~* '(önerilmektedir|tavsiye edilmektedir)\.$'
  )
);

create index analysis_notebook_advisories_analysis_idx
  on private.analysis_notebook_advisories (user_id, analysis_id, language);

alter table private.analysis_notebook_advisories enable row level security;
revoke all on table private.analysis_notebook_advisories
  from public, anon, authenticated;
grant select, insert, update, delete on table private.analysis_notebook_advisories
  to service_role;

create or replace function public.result_hub_list_notebook_advisories_v1(
  p_user_id uuid,
  p_analysis_id uuid,
  p_language text
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'source_finding_id', a.source_finding_id,
    'language', a.language,
    'advisory_text', a.advisory_text,
    'source_hash', a.source_hash,
    'generator_version', a.generator_version,
    'generator_kind', a.generator_kind,
    'updated_at', a.updated_at
  ) order by a.source_finding_id), '[]'::jsonb)
  from private.analysis_notebook_advisories a
  where a.user_id = p_user_id
    and a.analysis_id = p_analysis_id
    and a.language = p_language;
$$;

create or replace function public.result_hub_upsert_notebook_advisories_v1(
  p_user_id uuid,
  p_analysis_id uuid,
  p_language text,
  p_entries jsonb
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_entry jsonb;
  v_finding_id uuid;
  v_text text;
  v_source_hash text;
  v_generator_version text;
  v_generator_kind text;
begin
  if p_language not in ('tr', 'en')
    or jsonb_typeof(coalesce(p_entries, '[]'::jsonb)) <> 'array' then
    raise exception 'invalid_notebook_advisory_payload' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.analyses a
    where a.id = p_analysis_id
      and a.user_id = p_user_id
      and a.status = 'completed'
  ) then
    raise exception 'analysis_not_found' using errcode = 'P0002';
  end if;

  for v_entry in select value from jsonb_array_elements(p_entries) loop
    begin
      v_finding_id := (v_entry->>'source_finding_id')::uuid;
    exception when invalid_text_representation then
      raise exception 'invalid_notebook_advisory_finding' using errcode = '22023';
    end;
    v_text := btrim(coalesce(v_entry->>'advisory_text', ''));
    v_source_hash := lower(btrim(coalesce(v_entry->>'source_hash', '')));
    v_generator_version := btrim(coalesce(v_entry->>'generator_version', ''));
    v_generator_kind := btrim(coalesce(v_entry->>'generator_kind', ''));

    if not exists (
      select 1
      from public.findings f
      where f.id = v_finding_id
        and f.analysis_id = p_analysis_id
        and f.user_id = p_user_id
    ) then
      raise exception 'notebook_advisory_finding_not_found' using errcode = 'P0002';
    end if;
    if length(v_text) not between 20 and 1000
      or v_source_hash !~ '^[0-9a-f]{64}$'
      or length(v_generator_version) not between 1 and 120
      or v_generator_kind not in ('model', 'fallback')
      or (
        p_language = 'tr'
        and v_text !~* '(önerilmektedir|tavsiye edilmektedir)\.$'
      ) then
      raise exception 'invalid_notebook_advisory_entry' using errcode = '22023';
    end if;

    insert into private.analysis_notebook_advisories (
      analysis_id,
      user_id,
      source_finding_id,
      language,
      advisory_text,
      source_hash,
      generator_version,
      generator_kind
    ) values (
      p_analysis_id,
      p_user_id,
      v_finding_id,
      p_language,
      v_text,
      v_source_hash,
      v_generator_version,
      v_generator_kind
    )
    on conflict (source_finding_id, language) do update
    set analysis_id = excluded.analysis_id,
        user_id = excluded.user_id,
        advisory_text = excluded.advisory_text,
        source_hash = excluded.source_hash,
        generator_version = excluded.generator_version,
        generator_kind = excluded.generator_kind,
        updated_at = now()
    where private.analysis_notebook_advisories.analysis_id is distinct from excluded.analysis_id
       or private.analysis_notebook_advisories.user_id is distinct from excluded.user_id
       or private.analysis_notebook_advisories.advisory_text is distinct from excluded.advisory_text
       or private.analysis_notebook_advisories.source_hash is distinct from excluded.source_hash
       or private.analysis_notebook_advisories.generator_version is distinct from excluded.generator_version
       or private.analysis_notebook_advisories.generator_kind is distinct from excluded.generator_kind;
  end loop;

  return public.result_hub_list_notebook_advisories_v1(
    p_user_id,
    p_analysis_id,
    p_language
  );
end;
$$;

revoke all on function public.result_hub_list_notebook_advisories_v1(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.result_hub_list_notebook_advisories_v1(uuid, uuid, text)
  to service_role;

revoke all on function public.result_hub_upsert_notebook_advisories_v1(uuid, uuid, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.result_hub_upsert_notebook_advisories_v1(uuid, uuid, text, jsonb)
  to service_role;

comment on table private.analysis_notebook_advisories is
  'Canonical employer-facing advisory prose for Onaylı Defter only; Risk Analizi and Uzman Görüşü remain unchanged.';
