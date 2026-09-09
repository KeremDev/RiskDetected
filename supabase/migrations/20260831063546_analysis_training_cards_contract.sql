-- Canonical, auditable snapshot of the deterministic training recommendation
-- engine. Mobile clients may continue to derive the same cards for rendering;
-- this table is the cross-client/admin data contract.

create table if not exists private.analysis_training_cards (
  id uuid primary key,
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  catalog_code text not null,
  engine_version text not null,
  catalog_version text not null,
  recommendation_class text not null,
  applicability text not null,
  group_code text not null,
  title text not null,
  category_label text not null,
  audience_label text not null,
  recommendation_text text not null,
  duration_label text,
  duration_value text,
  duration_note text,
  trigger_codes jsonb not null default '[]'::jsonb,
  source_finding_ids jsonb not null default '[]'::jsonb,
  display_order integer not null default 0,
  generated_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint analysis_training_cards_analysis_catalog_key
    unique (analysis_id, catalog_code),
  constraint analysis_training_cards_catalog_code_check
    check (length(btrim(catalog_code)) between 1 and 160),
  constraint analysis_training_cards_versions_check
    check (
      length(btrim(engine_version)) between 1 and 160
      and length(btrim(catalog_version)) between 1 and 160
    ),
  constraint analysis_training_cards_title_check
    check (length(btrim(title)) between 1 and 500),
  constraint analysis_training_cards_text_check
    check (length(btrim(recommendation_text)) between 1 and 8000),
  constraint analysis_training_cards_trigger_codes_check
    check (jsonb_typeof(trigger_codes) = 'array'),
  constraint analysis_training_cards_source_ids_check
    check (jsonb_typeof(source_finding_ids) = 'array')
);

create index if not exists analysis_training_cards_analysis_order_idx
  on private.analysis_training_cards (analysis_id, display_order, catalog_code);

create index if not exists analysis_training_cards_user_updated_idx
  on private.analysis_training_cards (user_id, updated_at desc);

alter table private.analysis_training_cards enable row level security;

revoke all on table private.analysis_training_cards
  from public, anon, authenticated;

comment on table private.analysis_training_cards is
  'Canonical snapshots emitted by the deterministic training recommendation engine; not inferred from corrective or preventive measures.';

create or replace function public.result_hub_replace_training_cards_v1(
  p_user_id uuid,
  p_analysis_id uuid,
  p_engine_version text,
  p_catalog_version text,
  p_cards jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cards jsonb := coalesce(p_cards, '[]'::jsonb);
  v_count integer := 0;
begin
  if p_user_id is null or p_analysis_id is null then
    raise exception 'user_id and analysis_id are required'
      using errcode = '22023';
  end if;

  if jsonb_typeof(v_cards) <> 'array' then
    raise exception 'cards must be a JSON array'
      using errcode = '22023';
  end if;

  if jsonb_array_length(v_cards) > 100 then
    raise exception 'training card limit exceeded'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.analyses a
    where a.id = p_analysis_id
      and a.user_id = p_user_id
      and a.status = 'completed'
  ) then
    return jsonb_build_object(
      'ok', false,
      'state', 'completed_analysis_not_found',
      'analysis_id', p_analysis_id
    );
  end if;

  if nullif(btrim(coalesce(p_engine_version, '')), '') is null
    or nullif(btrim(coalesce(p_catalog_version, '')), '') is null then
    raise exception 'engine and catalog versions are required'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(v_cards) as c(
      id uuid,
      catalog_code text,
      recommendation_class text,
      applicability text,
      group_code text,
      title text,
      category_label text,
      audience_label text,
      recommendation_text text,
      duration_label text,
      duration_value text,
      duration_note text,
      trigger_codes jsonb,
      source_finding_ids jsonb,
      display_order integer
    )
    where c.id is null
      or nullif(btrim(coalesce(c.catalog_code, '')), '') is null
      or nullif(btrim(coalesce(c.recommendation_class, '')), '') is null
      or nullif(btrim(coalesce(c.applicability, '')), '') is null
      or nullif(btrim(coalesce(c.group_code, '')), '') is null
      or nullif(btrim(coalesce(c.title, '')), '') is null
      or nullif(btrim(coalesce(c.category_label, '')), '') is null
      or nullif(btrim(coalesce(c.audience_label, '')), '') is null
      or nullif(btrim(coalesce(c.recommendation_text, '')), '') is null
      or jsonb_typeof(coalesce(c.trigger_codes, '[]'::jsonb)) <> 'array'
      or jsonb_typeof(coalesce(c.source_finding_ids, '[]'::jsonb)) <> 'array'
  ) then
    raise exception 'invalid training card payload'
      using errcode = '22023';
  end if;

  insert into private.analysis_training_cards (
    id,
    analysis_id,
    user_id,
    catalog_code,
    engine_version,
    catalog_version,
    recommendation_class,
    applicability,
    group_code,
    title,
    category_label,
    audience_label,
    recommendation_text,
    duration_label,
    duration_value,
    duration_note,
    trigger_codes,
    source_finding_ids,
    display_order,
    generated_at,
    updated_at
  )
  select
    c.id,
    p_analysis_id,
    p_user_id,
    btrim(c.catalog_code),
    btrim(p_engine_version),
    btrim(p_catalog_version),
    btrim(c.recommendation_class),
    btrim(c.applicability),
    btrim(c.group_code),
    btrim(c.title),
    btrim(c.category_label),
    btrim(c.audience_label),
    btrim(c.recommendation_text),
    nullif(btrim(coalesce(c.duration_label, '')), ''),
    nullif(btrim(coalesce(c.duration_value, '')), ''),
    nullif(btrim(coalesce(c.duration_note, '')), ''),
    coalesce(c.trigger_codes, '[]'::jsonb),
    coalesce(c.source_finding_ids, '[]'::jsonb),
    coalesce(c.display_order, 0),
    now(),
    now()
  from jsonb_to_recordset(v_cards) as c(
    id uuid,
    catalog_code text,
    recommendation_class text,
    applicability text,
    group_code text,
    title text,
    category_label text,
    audience_label text,
    recommendation_text text,
    duration_label text,
    duration_value text,
    duration_note text,
    trigger_codes jsonb,
    source_finding_ids jsonb,
    display_order integer
  )
  on conflict (analysis_id, catalog_code) do update set
    id = excluded.id,
    user_id = excluded.user_id,
    engine_version = excluded.engine_version,
    catalog_version = excluded.catalog_version,
    recommendation_class = excluded.recommendation_class,
    applicability = excluded.applicability,
    group_code = excluded.group_code,
    title = excluded.title,
    category_label = excluded.category_label,
    audience_label = excluded.audience_label,
    recommendation_text = excluded.recommendation_text,
    duration_label = excluded.duration_label,
    duration_value = excluded.duration_value,
    duration_note = excluded.duration_note,
    trigger_codes = excluded.trigger_codes,
    source_finding_ids = excluded.source_finding_ids,
    display_order = excluded.display_order,
    updated_at = now();

  delete from private.analysis_training_cards existing
  where existing.analysis_id = p_analysis_id
    and not exists (
      select 1
      from jsonb_array_elements(v_cards) card
      where card->>'catalog_code' = existing.catalog_code
    );

  select count(*)::integer
  into v_count
  from private.analysis_training_cards c
  where c.analysis_id = p_analysis_id;

  return jsonb_build_object(
    'ok', true,
    'state', 'replaced',
    'analysis_id', p_analysis_id,
    'card_count', v_count,
    'engine_version', btrim(p_engine_version),
    'catalog_version', btrim(p_catalog_version)
  );
end;
$$;

revoke all on function public.result_hub_replace_training_cards_v1(
  uuid, uuid, text, text, jsonb
) from public, anon, authenticated;

grant execute on function public.result_hub_replace_training_cards_v1(
  uuid, uuid, text, text, jsonb
) to service_role;

comment on function public.result_hub_replace_training_cards_v1(
  uuid, uuid, text, text, jsonb
) is 'Atomically replaces one completed analysis training-card snapshot. Service role only.';

create or replace function public.admin_analysis_result_detail_v1(
  p_analysis_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_data_class text;
  v_effective_platform text;
  v_classification_source text;
  v_result jsonb;
begin
  if pg_catalog.to_regprocedure(
    'private.analysis_population_v1(uuid)'
  ) is not null then
    execute 'select data_class, effective_platform, classification_source '
      || 'from private.analysis_population_v1($1)'
      into v_data_class, v_effective_platform, v_classification_source
      using p_analysis_id;
  else
    select
      case
        when lower(coalesce(a.client_platform, '')) in ('ios', 'android')
          then 'production'
        else 'test'
      end,
      nullif(lower(coalesce(a.client_platform, '')), ''),
      case
        when lower(coalesce(a.client_platform, '')) in ('ios', 'android')
          then 'analysis.client_platform'
        else 'missing_platform'
      end
    into v_data_class, v_effective_platform, v_classification_source
    from public.analyses a
    where a.id = p_analysis_id;
  end if;

  with latest_run as (
    select r.id
    from private.analysis_engine_runs r
    where r.analysis_id = p_analysis_id
    order by r.started_at desc nulls last
    limit 1
  ),
  technical as (
    select coalesce(jsonb_agg(
      coalesce(i.canonical_payload, '{}'::jsonb)
      || jsonb_build_object(
        'id', i.id,
        'item_class', i.item_class,
        'title', i.title,
        'description', i.description,
        'recommended_action', coalesce(
          i.canonical_payload->>'recommended_action',
          i.control_text
        ),
        'recommended_measures', coalesce(
          i.canonical_payload->'recommended_measures',
          '[]'::jsonb
        ),
        'references_text', i.references_text,
        'needs_field_verification', i.needs_field_verification,
        'source_photo_indices', to_jsonb(i.source_photo_indices),
        'display_order', i.display_order,
        'feedback', '[]'::jsonb
      )
      order by i.display_order nulls last, i.created_at
    ), '[]'::jsonb) as value
    from private.analysis_items_v4 i
    where i.engine_run_id = (select id from latest_run)
      and i.item_class in ('positive_control', 'not_assessable')
  ),
  training as (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'id', c.id,
        'item_class', 'training_card',
        'catalog_code', c.catalog_code,
        'engine_version', c.engine_version,
        'catalog_version', c.catalog_version,
        'recommendation_class', c.recommendation_class,
        'applicability', c.applicability,
        'group_code', c.group_code,
        'title', c.title,
        'description', c.recommendation_text,
        'category', c.category_label,
        'category_label', c.category_label,
        'audience_label', c.audience_label,
        'duration_label', c.duration_label,
        'duration_value', c.duration_value,
        'duration_note', c.duration_note,
        'trigger_codes', c.trigger_codes,
        'source_finding_ids', c.source_finding_ids,
        'recommended_action', null,
        'recommended_measures', '[]'::jsonb,
        'references_text', null,
        'needs_field_verification', false,
        'source_photo_indices', '[]'::jsonb,
        'display_order', c.display_order,
        'generated_at', c.generated_at,
        'updated_at', c.updated_at,
        'feedback', '[]'::jsonb
      )
      order by c.display_order, c.catalog_code
    ), '[]'::jsonb) as value
    from private.analysis_training_cards c
    where c.analysis_id = p_analysis_id
  ),
  notebook as (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'id', n.id,
        'item_class', 'notebook_entry',
        'title', coalesce(nullif(n.grouping_key, ''), 'Onaylı defter kaydı'),
        'description', coalesce(
          n.finding_text_override,
          n.finding_text_generated
        ),
        'recommended_action', coalesce(
          n.recommendation_text_override,
          n.recommendation_text_generated
        ),
        'recommended_measures', '[]'::jsonb,
        'references_text', coalesce(
          n.reference_text_override,
          n.reference_text_generated
        ),
        'needs_field_verification', false,
        'source_finding_ids', to_jsonb(n.source_finding_ids),
        'display_order', n.display_order,
        'language', n.language,
        'projection_version', n.projection_version,
        'feedback', '[]'::jsonb
      )
      order by n.display_order nulls last, n.created_at
    ), '[]'::jsonb) as value
    from private.analysis_notebook_entries n
    where n.analysis_id = p_analysis_id
      and not n.is_suppressed
      and not n.is_projection_obsolete
  )
  select case
    when not exists (
      select 1
      from public.analyses a
      where a.id = p_analysis_id
    ) then jsonb_build_object(
      'status', 'not_found',
      'analysisId', p_analysis_id
    )
    else jsonb_build_object(
      'status', 'ok',
      'analysisId', p_analysis_id,
      'dataClass', v_data_class,
      'effectivePlatform', v_effective_platform,
      'classificationSource', v_classification_source,
      'technicalBackground', (select value from technical),
      'trainingRecommendations', (select value from training),
      'approvedNotebook', (select value from notebook)
    )
  end
  into v_result;

  return v_result;
end;
$$;

revoke all on function public.admin_analysis_result_detail_v1(uuid)
  from public, anon, authenticated;

grant execute on function public.admin_analysis_result_detail_v1(uuid)
  to service_role;

comment on function public.admin_analysis_result_detail_v1(uuid) is
  'Returns canonical private result projections, including persisted training recommendations, to the service-role admin API.';
