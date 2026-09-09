-- Three-section analysis result hub. The feature is expand-only and owner-
-- allowlisted; the v3/v4 analysis engines remain unchanged.

alter table public.reports
  add column if not exists content_scope text not null default 'legacy_combined',
  add column if not exists projection_version text,
  add column if not exists selected_item_keys text[] not null default '{}',
  add column if not exists content_snapshot_json jsonb,
  add column if not exists entitlement_tier_snapshot text,
  add column if not exists selection_count integer not null default 0,
  add column if not exists export_intent_id uuid;

alter table public.reports
  drop constraint if exists reports_content_scope_check;
alter table public.reports
  add constraint reports_content_scope_check check (
    content_scope in (
      'legacy_combined', 'risk_analysis', 'expert_recommendations',
      'approved_notebook'
    )
  );
alter table public.reports
  drop constraint if exists reports_selection_count_check;
alter table public.reports
  add constraint reports_selection_count_check check (selection_count >= 0);
alter table public.reports
  drop constraint if exists reports_content_snapshot_object_check;
alter table public.reports
  add constraint reports_content_snapshot_object_check check (
    content_snapshot_json is null or jsonb_typeof(content_snapshot_json) = 'object'
  );

create index if not exists reports_user_scope_created_idx
  on public.reports (user_id, content_scope, created_at desc);
create unique index if not exists reports_export_intent_unique_idx
  on public.reports (export_intent_id) where export_intent_id is not null;

create table private.analysis_result_hub_allowlist (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  enabled boolean not null default false,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into private.analysis_result_hub_allowlist (user_id, enabled, note)
select user_id, true, 'Copied from routing-first v4 owner pilot'
from private.analysis_v4_allowlist
where enabled
on conflict (user_id) do update
set enabled = excluded.enabled,
    note = excluded.note,
    updated_at = now();

create table private.analysis_notebook_entries (
  id uuid primary key,
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  language text not null check (language in ('tr', 'en')),
  projection_version text not null,
  template_version text not null,
  grouping_key text not null,
  source_finding_ids uuid[] not null default '{}',
  source_hash text not null check (source_hash ~ '^[a-f0-9]{64}$'),
  finding_text_generated text not null,
  recommendation_text_generated text not null,
  reference_text_generated text,
  finding_text_override text,
  recommendation_text_override text,
  reference_text_override text,
  display_order integer not null check (display_order >= 0),
  is_suppressed boolean not null default false,
  is_projection_obsolete boolean not null default false,
  is_stale boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (analysis_id, language, projection_version, grouping_key)
);

create index analysis_notebook_entries_user_analysis_idx
  on private.analysis_notebook_entries (user_id, analysis_id, language, display_order)
  where not is_projection_obsolete;

create table private.analysis_notebook_entry_revisions (
  id bigint generated always as identity primary key,
  entry_id uuid not null references private.analysis_notebook_entries(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  revision integer not null check (revision > 0),
  action text not null check (action in ('edit', 'suppress', 'restore', 'reset')),
  previous_snapshot jsonb not null default '{}'::jsonb,
  current_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (entry_id, revision)
);

create table private.analysis_item_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  target_kind text not null check (target_kind in ('finding', 'notebook_entry')),
  target_key text not null,
  public_finding_id uuid references public.findings(id) on delete set null,
  notebook_entry_id uuid references private.analysis_notebook_entries(id) on delete set null,
  section text not null check (section in (
    'risk_analysis', 'expert_recommendations', 'approved_notebook'
  )),
  item_class text,
  rating smallint not null check (rating in (-1, 1)),
  reason_code text,
  note text,
  content_snapshot jsonb not null default '{}'::jsonb,
  context_snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, analysis_id, target_kind, target_key),
  check (
    (target_kind = 'finding' and public_finding_id is not null)
    or (target_kind = 'notebook_entry' and notebook_entry_id is not null)
  )
);

create index analysis_item_feedback_admin_idx
  on private.analysis_item_feedback (rating, section, updated_at desc);

create table private.analysis_result_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  analysis_id uuid references public.analyses(id) on delete cascade,
  client_event_id uuid not null,
  funnel_session_id uuid,
  event_name text not null check (event_name in (
    'result_screen_viewed', 'result_section_selected',
    'locked_teaser_impression', 'locked_teaser_cta_tapped',
    'result_item_detail_opened', 'result_feedback_set',
    'result_feedback_cleared', 'report_selection_changed',
    'report_create_started', 'report_create_completed',
    'report_create_failed', 'paywall_viewed', 'checkout_started',
    'purchase_completed'
  )),
  section text check (section is null or section in (
    'risk_analysis', 'expert_recommendations', 'approved_notebook'
  )),
  target_kind text,
  target_key text,
  plan_snapshot text not null default 'free',
  client_platform text,
  client_app_version text,
  client_app_build text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (user_id, client_event_id)
);

create index analysis_result_events_funnel_idx
  on private.analysis_result_events (funnel_session_id, created_at)
  where funnel_session_id is not null;
create index analysis_result_events_admin_idx
  on private.analysis_result_events (event_name, section, created_at desc);

create table private.report_export_intents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  analysis_id uuid not null references public.analyses(id) on delete cascade,
  content_scope text not null check (content_scope in (
    'risk_analysis', 'expert_recommendations', 'approved_notebook'
  )),
  format text not null check (format in ('pdf', 'xlsx')),
  selected_item_keys text[] not null,
  content_snapshot jsonb not null check (jsonb_typeof(content_snapshot) = 'object'),
  source_edit_version integer not null default 0,
  projection_version text,
  tier_snapshot text not null check (tier_snapshot in ('free', 'plus', 'pro')),
  request_id text,
  status text not null default 'created'
    check (status in ('created', 'uploaded', 'consumed', 'expired')),
  expires_at timestamptz not null default (now() + interval '30 minutes'),
  created_at timestamptz not null default now(),
  consumed_at timestamptz,
  check (cardinality(selected_item_keys) > 0)
);

create index report_export_intents_lookup_idx
  on private.report_export_intents (user_id, analysis_id, status, created_at desc);
create unique index report_export_intents_request_unique_idx
  on private.report_export_intents (user_id, request_id)
  where request_id is not null;

do $$
declare v_table text;
begin
  foreach v_table in array array[
    'analysis_result_hub_allowlist', 'analysis_notebook_entries',
    'analysis_notebook_entry_revisions', 'analysis_item_feedback',
    'analysis_result_events', 'report_export_intents'
  ] loop
    execute format('alter table private.%I enable row level security', v_table);
    execute format(
      'revoke all on table private.%I from public, anon, authenticated',
      v_table
    );
    execute format(
      'grant select, insert, update, delete on table private.%I to service_role',
      v_table
    );
  end loop;
end $$;

grant usage, select on sequence private.analysis_notebook_entry_revisions_id_seq
  to service_role;
grant usage, select on sequence private.analysis_result_events_id_seq
  to service_role;

create or replace function private.result_hub_has_paid_access(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.user_plan_tier(p_user_id), 'free') in ('plus', 'pro');
$$;
revoke all on function private.result_hub_has_paid_access(uuid)
  from public, anon;
grant execute on function private.result_hub_has_paid_access(uuid)
  to authenticated, service_role;

create or replace function public.result_hub_allowlist_decision(p_user_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1
    from private.analysis_result_hub_allowlist a
    where a.user_id = p_user_id and a.enabled
  );
$$;
revoke all on function public.result_hub_allowlist_decision(uuid)
  from public, anon, authenticated;
grant execute on function public.result_hub_allowlist_decision(uuid)
  to service_role;

drop policy if exists findings_select_own on public.findings;
create policy findings_select_own
  on public.findings for select
  to authenticated
  using (
    (select auth.uid()) = user_id
    and (
      is_scored
      or (select private.result_hub_has_paid_access((select auth.uid())))
    )
  );

create or replace function public.result_hub_v4_metadata(
  p_user_id uuid,
  p_analysis_id uuid
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'public_finding_id', i.public_finding_id,
    'criticality', i.criticality,
    'canonical_payload', i.canonical_payload,
    'internal_priority', i.internal_priority,
    'verified_references', coalesce(refs.reference_texts, '[]'::jsonb)
  ) order by i.display_order), '[]'::jsonb)
  from private.analysis_items_v4 i
  left join lateral (
    select jsonb_agg(l.reference_text order by l.standard_id)
      filter (where nullif(btrim(l.reference_text), '') is not null) as reference_texts
    from private.analysis_item_standard_links l
    join private.standards_registry s on s.id = l.standard_id
    where l.item_id = i.id
      and s.status = 'active'
      and s.source_rights <> 'unverified'
  ) refs on true
  where i.user_id = p_user_id
    and i.analysis_id = p_analysis_id
    and i.public_finding_id is not null;
$$;
revoke all on function public.result_hub_v4_metadata(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.result_hub_v4_metadata(uuid, uuid)
  to service_role;

create or replace function public.result_hub_upsert_notebook_entries(
  p_user_id uuid,
  p_analysis_id uuid,
  p_language text,
  p_projection_version text,
  p_template_version text,
  p_entries jsonb
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_entry jsonb;
  v_ids uuid[] := '{}';
begin
  if p_language not in ('tr', 'en')
    or jsonb_typeof(coalesce(p_entries, '[]'::jsonb)) <> 'array' then
    raise exception 'invalid_notebook_projection' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.analyses a
    where a.id = p_analysis_id and a.user_id = p_user_id and a.status = 'completed'
  ) then
    raise exception 'analysis_not_found' using errcode = 'P0002';
  end if;

  for v_entry in select value from jsonb_array_elements(p_entries) loop
    v_ids := array_append(v_ids, (v_entry->>'id')::uuid);
    insert into private.analysis_notebook_entries (
      id, analysis_id, user_id, language, projection_version,
      template_version, grouping_key, source_finding_ids, source_hash,
      finding_text_generated, recommendation_text_generated,
      reference_text_generated, display_order, is_projection_obsolete
    ) values (
      (v_entry->>'id')::uuid,
      p_analysis_id,
      p_user_id,
      p_language,
      p_projection_version,
      p_template_version,
      left(v_entry->>'grouping_key', 500),
      array(select jsonb_array_elements_text(v_entry->'source_finding_ids'))::uuid[],
      v_entry->>'source_hash',
      left(v_entry->>'finding_text', 4000),
      left(v_entry->>'recommendation_text', 6000),
      nullif(left(coalesce(v_entry->>'reference_text', ''), 4000), ''),
      greatest(0, coalesce((v_entry->>'display_order')::integer, 0)),
      false
    )
    on conflict (id) do update
    set template_version = excluded.template_version,
        grouping_key = excluded.grouping_key,
        source_finding_ids = excluded.source_finding_ids,
        finding_text_generated = excluded.finding_text_generated,
        recommendation_text_generated = excluded.recommendation_text_generated,
        reference_text_generated = excluded.reference_text_generated,
        display_order = excluded.display_order,
        is_projection_obsolete = false,
        is_stale = case
          when private.analysis_notebook_entries.source_hash <> excluded.source_hash
            and (
              private.analysis_notebook_entries.finding_text_override is not null
              or private.analysis_notebook_entries.recommendation_text_override is not null
              or private.analysis_notebook_entries.reference_text_override is not null
            ) then true
          else false
        end,
        source_hash = excluded.source_hash,
        updated_at = now();
  end loop;

  update private.analysis_notebook_entries e
  set is_projection_obsolete = true,
      is_stale = (
        e.finding_text_override is not null
        or e.recommendation_text_override is not null
        or e.reference_text_override is not null
      ),
      updated_at = now()
  where e.user_id = p_user_id
    and e.analysis_id = p_analysis_id
    and e.language = p_language
    and e.projection_version = p_projection_version
    and not (e.id = any(v_ids));

  return public.result_hub_list_notebook_entries(
    p_user_id, p_analysis_id, p_language
  );
end;
$$;

create or replace function public.result_hub_list_notebook_entries(
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
    'id', e.id,
    'analysis_id', e.analysis_id,
    'language', e.language,
    'projection_version', e.projection_version,
    'template_version', e.template_version,
    'grouping_key', e.grouping_key,
    'source_finding_ids', e.source_finding_ids,
    'source_hash', e.source_hash,
    'finding_text', coalesce(e.finding_text_override, e.finding_text_generated),
    'recommendation_text', coalesce(e.recommendation_text_override, e.recommendation_text_generated),
    'reference_text', coalesce(e.reference_text_override, e.reference_text_generated),
    'is_user_edited', (
      e.finding_text_override is not null
      or e.recommendation_text_override is not null
      or e.reference_text_override is not null
    ),
    'is_suppressed', e.is_suppressed,
    'is_stale', e.is_stale,
    'display_order', e.display_order,
    'updated_at', e.updated_at
  ) order by e.display_order, e.id), '[]'::jsonb)
  from private.analysis_notebook_entries e
  where e.user_id = p_user_id
    and e.analysis_id = p_analysis_id
    and e.language = p_language
    and not e.is_projection_obsolete;
$$;

create or replace function public.result_hub_mutate_notebook_entry(
  p_user_id uuid,
  p_analysis_id uuid,
  p_entry_id uuid,
  p_action text,
  p_finding_text text default null,
  p_recommendation_text text default null,
  p_reference_text text default null
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_entry private.analysis_notebook_entries%rowtype;
  v_revision integer;
  v_previous jsonb;
begin
  select * into v_entry
  from private.analysis_notebook_entries e
  where e.id = p_entry_id
    and e.user_id = p_user_id
    and e.analysis_id = p_analysis_id
    and not e.is_projection_obsolete
  for update;
  if not found then
    raise exception 'notebook_entry_not_found' using errcode = 'P0002';
  end if;
  if p_action not in ('edit', 'suppress', 'restore', 'reset') then
    raise exception 'invalid_notebook_action' using errcode = '22023';
  end if;

  v_previous := to_jsonb(v_entry);
  select coalesce(max(r.revision), 0) + 1 into v_revision
  from private.analysis_notebook_entry_revisions r
  where r.entry_id = p_entry_id;

  if p_action = 'edit' then
    if nullif(btrim(coalesce(p_finding_text, '')), '') is null
      or nullif(btrim(coalesce(p_recommendation_text, '')), '') is null then
      raise exception 'notebook_text_required' using errcode = '22023';
    end if;
    update private.analysis_notebook_entries
    set finding_text_override = left(btrim(p_finding_text), 4000),
        recommendation_text_override = left(btrim(p_recommendation_text), 6000),
        reference_text_override = nullif(left(btrim(coalesce(p_reference_text, '')), 4000), ''),
        is_stale = false,
        updated_at = now()
    where id = p_entry_id;
  elsif p_action = 'suppress' then
    update private.analysis_notebook_entries
    set is_suppressed = true, updated_at = now() where id = p_entry_id;
  elsif p_action = 'restore' then
    update private.analysis_notebook_entries
    set is_suppressed = false, updated_at = now() where id = p_entry_id;
  else
    update private.analysis_notebook_entries
    set finding_text_override = null,
        recommendation_text_override = null,
        reference_text_override = null,
        is_stale = false,
        updated_at = now()
    where id = p_entry_id;
  end if;

  insert into private.analysis_notebook_entry_revisions (
    entry_id, user_id, analysis_id, revision, action,
    previous_snapshot, current_snapshot
  )
  select id, user_id, analysis_id, v_revision, p_action,
    v_previous, to_jsonb(e)
  from private.analysis_notebook_entries e where e.id = p_entry_id;

  return public.result_hub_list_notebook_entries(
    p_user_id, p_analysis_id, v_entry.language
  );
end;
$$;

create or replace function public.result_hub_upsert_feedback(
  p_user_id uuid,
  p_analysis_id uuid,
  p_target_kind text,
  p_target_key text,
  p_public_finding_id uuid,
  p_notebook_entry_id uuid,
  p_section text,
  p_item_class text,
  p_rating integer,
  p_reason_code text,
  p_note text,
  p_content_snapshot jsonb,
  p_context_snapshot jsonb
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare v_row private.analysis_item_feedback%rowtype;
begin
  if p_rating = 0 then
    delete from private.analysis_item_feedback f
    where f.user_id = p_user_id
      and f.analysis_id = p_analysis_id
      and f.target_kind = p_target_kind
      and f.target_key = p_target_key;
    return jsonb_build_object('reaction', 'none');
  end if;
  if p_rating not in (-1, 1) then
    raise exception 'invalid_feedback_rating' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.analyses a
    where a.id = p_analysis_id and a.user_id = p_user_id
  ) then
    raise exception 'analysis_not_found' using errcode = 'P0002';
  end if;

  insert into private.analysis_item_feedback (
    user_id, analysis_id, target_kind, target_key, public_finding_id,
    notebook_entry_id, section, item_class, rating, reason_code, note,
    content_snapshot, context_snapshot
  ) values (
    p_user_id, p_analysis_id, p_target_kind, left(p_target_key, 200),
    p_public_finding_id, p_notebook_entry_id, p_section,
    left(coalesce(p_item_class, ''), 80), p_rating,
    nullif(left(btrim(coalesce(p_reason_code, '')), 80), ''),
    nullif(left(btrim(coalesce(p_note, '')), 1000), ''),
    coalesce(p_content_snapshot, '{}'::jsonb),
    coalesce(p_context_snapshot, '{}'::jsonb)
  )
  on conflict (user_id, analysis_id, target_kind, target_key) do update
  set rating = excluded.rating,
      reason_code = excluded.reason_code,
      note = excluded.note,
      content_snapshot = excluded.content_snapshot,
      context_snapshot = excluded.context_snapshot,
      public_finding_id = excluded.public_finding_id,
      notebook_entry_id = excluded.notebook_entry_id,
      item_class = excluded.item_class,
      section = excluded.section,
      updated_at = now()
  returning * into v_row;
  return jsonb_build_object(
    'reaction', case when v_row.rating = 1 then 'like' else 'dislike' end,
    'reason_code', v_row.reason_code,
    'updated_at', v_row.updated_at
  );
end;
$$;

create or replace function public.result_hub_feedback_for_analysis(
  p_user_id uuid,
  p_analysis_id uuid
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'target_kind', f.target_kind,
    'target_key', f.target_key,
    'reaction', case when f.rating = 1 then 'like' else 'dislike' end,
    'reason_code', f.reason_code
  )), '[]'::jsonb)
  from private.analysis_item_feedback f
  where f.user_id = p_user_id and f.analysis_id = p_analysis_id;
$$;

create or replace function public.result_hub_insert_event(
  p_user_id uuid,
  p_analysis_id uuid,
  p_client_event_id uuid,
  p_funnel_session_id uuid,
  p_event_name text,
  p_section text,
  p_target_kind text,
  p_target_key text,
  p_plan_snapshot text,
  p_client_platform text,
  p_client_app_version text,
  p_client_app_build text,
  p_metadata jsonb
)
returns boolean
language plpgsql
set search_path = ''
as $$
begin
  insert into private.analysis_result_events (
    user_id, analysis_id, client_event_id, funnel_session_id, event_name,
    section, target_kind, target_key, plan_snapshot, client_platform,
    client_app_version, client_app_build, metadata
  ) values (
    p_user_id, p_analysis_id, p_client_event_id, p_funnel_session_id,
    p_event_name, p_section, nullif(left(coalesce(p_target_kind, ''), 80), ''),
    nullif(left(coalesce(p_target_key, ''), 200), ''),
    coalesce(nullif(p_plan_snapshot, ''), 'free'),
    nullif(left(coalesce(p_client_platform, ''), 40), ''),
    nullif(left(coalesce(p_client_app_version, ''), 40), ''),
    nullif(left(coalesce(p_client_app_build, ''), 40), ''),
    coalesce(p_metadata, '{}'::jsonb)
  ) on conflict (user_id, client_event_id) do nothing;
  return found;
end;
$$;

create or replace function public.result_hub_create_report_intent(
  p_user_id uuid,
  p_analysis_id uuid,
  p_content_scope text,
  p_format text,
  p_selected_item_keys text[],
  p_content_snapshot jsonb,
  p_source_edit_version integer,
  p_projection_version text,
  p_tier_snapshot text,
  p_request_id text
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare v_row private.report_export_intents%rowtype;
begin
  if nullif(btrim(coalesce(p_request_id, '')), '') is not null then
    select * into v_row
    from private.report_export_intents i
    where i.user_id = p_user_id
      and i.request_id = left(btrim(p_request_id), 100);

    if found then
      if v_row.analysis_id <> p_analysis_id
        or v_row.content_scope <> p_content_scope
        or v_row.format <> p_format
        or v_row.selected_item_keys <> p_selected_item_keys then
        raise exception 'report_intent_idempotency_conflict' using errcode = '23505';
      end if;
      return jsonb_build_object(
        'id', v_row.id,
        'analysis_id', v_row.analysis_id,
        'content_scope', v_row.content_scope,
        'format', v_row.format,
        'selected_item_keys', v_row.selected_item_keys,
        'content_snapshot', v_row.content_snapshot,
        'source_edit_version', v_row.source_edit_version,
        'projection_version', v_row.projection_version,
        'tier_snapshot', v_row.tier_snapshot,
        'expires_at', v_row.expires_at
      );
    end if;
  end if;

  insert into private.report_export_intents (
    user_id, analysis_id, content_scope, format, selected_item_keys,
    content_snapshot, source_edit_version, projection_version,
    tier_snapshot, request_id
  ) values (
    p_user_id, p_analysis_id, p_content_scope, p_format,
    p_selected_item_keys, p_content_snapshot,
    greatest(coalesce(p_source_edit_version, 0), 0),
    p_projection_version, p_tier_snapshot,
    nullif(left(coalesce(p_request_id, ''), 100), '')
  ) returning * into v_row;
  return jsonb_build_object(
    'id', v_row.id,
    'analysis_id', v_row.analysis_id,
    'content_scope', v_row.content_scope,
    'format', v_row.format,
    'selected_item_keys', v_row.selected_item_keys,
    'content_snapshot', v_row.content_snapshot,
    'source_edit_version', v_row.source_edit_version,
    'projection_version', v_row.projection_version,
    'tier_snapshot', v_row.tier_snapshot,
    'expires_at', v_row.expires_at
  );
end;
$$;

create or replace function public.result_hub_get_report_intent(
  p_user_id uuid,
  p_intent_id uuid
)
returns jsonb
language sql
set search_path = ''
as $$
  select to_jsonb(i)
  from private.report_export_intents i
  where i.id = p_intent_id
    and i.user_id = p_user_id
    and i.status in ('created', 'uploaded')
    and i.expires_at > now();
$$;

create or replace function public.result_hub_consume_report_intent(
  p_user_id uuid,
  p_intent_id uuid,
  p_status text default 'consumed'
)
returns boolean
language plpgsql
set search_path = ''
as $$
begin
  if p_status not in ('uploaded', 'consumed') then
    raise exception 'invalid_report_intent_status' using errcode = '22023';
  end if;
  update private.report_export_intents i
  set status = p_status,
      consumed_at = case when p_status = 'consumed' then now() else consumed_at end
  where i.id = p_intent_id
    and i.user_id = p_user_id
    and i.status in ('created', 'uploaded')
    and i.expires_at > now();
  return found;
end;
$$;

create or replace function public.check_report_quota_eligibility_v2(
  p_user_id uuid,
  p_kind text,
  p_format text,
  p_content_scope text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tier text;
begin
  if p_content_scope not in (
    'legacy_combined', 'risk_analysis', 'expert_recommendations',
    'approved_notebook'
  ) then
    raise exception 'invalid_report_content_scope' using errcode = '22023';
  end if;

  v_tier := coalesce(private.user_plan_tier(p_user_id), 'free');
  if v_tier = 'free'
    and p_content_scope in ('expert_recommendations', 'approved_notebook') then
    return jsonb_build_object(
      'allowed', false,
      'error_code', 'premium_required',
      'limit', 0,
      'used', 0,
      'period', 'subscription'
    );
  end if;

  return public.check_report_quota_eligibility(
    p_user_id,
    case when p_content_scope = 'risk_analysis' then 'riskAnalysis' else p_kind end,
    case when p_content_scope = 'risk_analysis' then 'pdf' else p_format end
  );
end;
$$;
revoke all on function public.check_report_quota_eligibility_v2(uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.check_report_quota_eligibility_v2(uuid, text, text, text)
  to service_role;

create table public.report_scope_year_counters (
  scope_prefix text not null check (scope_prefix in ('RA', 'UG', 'OD')),
  year integer not null,
  last_no integer not null default 0,
  primary key (scope_prefix, year)
);
alter table public.report_scope_year_counters enable row level security;
revoke all on table public.report_scope_year_counters
  from public, anon, authenticated;
grant select, insert, update on table public.report_scope_year_counters
  to service_role;

insert into public.report_scope_year_counters(scope_prefix, year, last_no)
select parsed.scope_prefix, parsed.year, max(parsed.no)::integer
from (
  select
    split_part(document_no, '-', 2) as scope_prefix,
    split_part(document_no, '-', 3)::integer as year,
    split_part(document_no, '-', 4)::integer as no
  from public.reports
  where document_no ~ '^RD-(RA|UG|OD)-[0-9]{4}-[0-9]+$'
) parsed
where parsed.scope_prefix is not null
group by parsed.scope_prefix, parsed.year
on conflict (scope_prefix, year) do update
set last_no = greatest(public.report_scope_year_counters.last_no, excluded.last_no);

create or replace function public.next_report_document_no_v2(
  p_user_id uuid,
  p_content_scope text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_year integer := extract(year from now())::integer;
  v_no integer;
  v_prefix text;
begin
  if not exists (select 1 from public.profiles p where p.id = p_user_id) then
    raise exception 'user_not_found' using errcode = 'P0002';
  end if;
  v_prefix := case p_content_scope
    when 'risk_analysis' then 'RA'
    when 'expert_recommendations' then 'UG'
    when 'approved_notebook' then 'OD'
    else null
  end;
  if v_prefix is null then
    raise exception 'invalid_report_content_scope' using errcode = '22023';
  end if;

  insert into public.report_scope_year_counters(scope_prefix, year, last_no)
  values (v_prefix, v_year, 1)
  on conflict (scope_prefix, year) do update
    set last_no = public.report_scope_year_counters.last_no + 1
  returning last_no into v_no;

  return 'RD-' || v_prefix || '-' || v_year::text || '-' || lpad(v_no::text, 4, '0');
end;
$$;
revoke all on function public.next_report_document_no_v2(uuid, text)
  from public, anon, authenticated;
grant execute on function public.next_report_document_no_v2(uuid, text)
  to service_role;

create or replace function private.pp_process_report_created()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_mdp integer := 60;
  v_uncapped_mdp integer := 60;
  v_is_risk_report boolean := false;
  v_workflow_existing_mdp integer := 0;
  v_inserted boolean;
  v_week_start date;
  v_week_reports integer;
  v_month_findings integer;
  v_best record;
  v_competency text;
begin
  v_is_risk_report := new.content_scope = 'risk_analysis'
    or (
      new.content_scope = 'legacy_combined'
      and (
        coalesce(new.kind, '') in ('riskAnalysis', 'risk_analysis')
        or coalesce(new.format, '') = 'xlsx'
      )
    );
  if v_is_risk_report then
    v_uncapped_mdp := v_uncapped_mdp + 90;
  end if;

  v_mdp := v_uncapped_mdp;

  if new.analysis_id is not null then
    select coalesce(sum(mdp_delta), 0)::int
      into v_workflow_existing_mdp
    from public.professional_progress_events
    where user_id = new.user_id
      and analysis_id = new.analysis_id
      and event_type in ('analysis_completed', 'first_competency_used', 'report_created');

    v_mdp := least(v_uncapped_mdp, greatest(400 - coalesce(v_workflow_existing_mdp, 0), 0));
  end if;

  v_inserted := private.pp_record_event(
    new.user_id,
    'report_created:' || new.id::text,
    'report_created',
    v_mdp,
    new.analysis_id,
    new.id,
    null,
    jsonb_build_object(
      'format', new.format,
      'kind', new.kind,
      'risk_report', v_is_risk_report,
      'uncapped_mdp', v_uncapped_mdp,
      'workflow_cap_mdp', 400,
      'workflow_existing_mdp', v_workflow_existing_mdp,
      'economy_version', 'result_hub_v1_2026_08_26'
    ),
    new.created_at
  );
  if not v_inserted then
    return new;
  end if;

  update public.professional_progress_profiles
  set total_reports = total_reports + 1,
      updated_at = now()
  where user_id = new.user_id;

  for v_competency in
    select distinct competency_key
    from public.professional_progress_finding_classifications
    where user_id = new.user_id
      and analysis_id = new.analysis_id
      and competency_key <> 'unclassified'
  loop
    update public.professional_progress_competency_stats
    set report_count = report_count + 1,
        updated_at = now()
    where user_id = new.user_id
      and competency_key = v_competency;
  end loop;

  v_week_start := (date_trunc('week', new.created_at at time zone 'Europe/Istanbul'))::date;
  perform private.pp_record_event(
    new.user_id,
    'weekly_bonus:' || v_week_start::text,
    'weekly_report_bonus',
    25,
    null,
    new.id,
    null,
    jsonb_build_object(
      'week_start', v_week_start,
      'economy_version', 'result_hub_v1_2026_08_26'
    ),
    new.created_at
  );

  select count(*)
    into v_week_reports
  from public.reports r
  where r.user_id = new.user_id
    and (r.created_at at time zone 'Europe/Istanbul')::date >= v_week_start
    and (r.created_at at time zone 'Europe/Istanbul')::date < v_week_start + 7;

  select coalesce(sum(finding_count), 0)
    into v_month_findings
  from public.professional_progress_competency_stats
  where user_id = new.user_id;

  select c.competency_key, c.risk_level, count(*)::int as count
    into v_best
  from public.professional_progress_finding_classifications c
  where c.user_id = new.user_id
    and c.analysis_id = new.analysis_id
    and c.competency_key <> 'unclassified'
  group by c.competency_key, c.risk_level
  order by private.pp_risk_rank(c.risk_level) desc, count(*) desc
  limit 1;

  if v_best.competency_key is not null then
    perform private.pp_insert_message(
      new.user_id,
      'instant',
      'Rapor arşivlendi',
      case
        when v_best.risk_level in ('critical', 'high') then
          'Bu raporda ' || private.pp_competency_label(v_best.competency_key) || ' alanında yüksek/kritik riskleri görünür kıldın.'
        else
          'Bu hafta ' || coalesce(v_week_reports, 1)::text || '. raporun. İstikrarlı ilerliyorsun.'
      end,
      new.analysis_id,
      new.id,
      v_best.competency_key,
      v_best.risk_level,
      jsonb_build_object('week_reports', v_week_reports, 'total_documented_risks', v_month_findings)
    );
  else
    perform private.pp_insert_message(
      new.user_id,
      'instant',
      'Rapor arşivlendi',
      'Bu hafta ' || coalesce(v_week_reports, 1)::text || '. raporun. İstikrarlı ilerliyorsun.',
      new.analysis_id,
      new.id,
      null,
      null,
      jsonb_build_object('week_reports', v_week_reports, 'total_documented_risks', v_month_findings)
    );
  end if;

  perform private.pp_refresh_active_days(new.user_id);
  perform private.pp_refresh_weekly_summary(new.user_id, new.created_at);
  perform private.pp_unlock_badges_for_user(new.user_id);

  return new;
exception when others then
  raise warning 'professional_progress report processing failed for report %: %', new.id, sqlerrm;
  return new;
end;
$$;
revoke all on function private.pp_process_report_created() from public, anon, authenticated;


create or replace function public.admin_analysis_feedback_v1(
  p_days integer default 30,
  p_limit integer default 100,
  p_offset integer default 0,
  p_section text default null,
  p_rating integer default null
)
returns table (
  id uuid,
  user_id uuid,
  analysis_id uuid,
  section text,
  target_kind text,
  target_key text,
  rating smallint,
  reason_code text,
  note text,
  content_snapshot jsonb,
  context_snapshot jsonb,
  updated_at timestamptz
)
language sql
stable
set search_path = ''
as $$
  select f.id, f.user_id, f.analysis_id, f.section, f.target_kind,
    f.target_key, f.rating, f.reason_code, f.note,
    f.content_snapshot, f.context_snapshot, f.updated_at
  from private.analysis_item_feedback f
  where f.updated_at >= now() - make_interval(days => greatest(1, least(p_days, 3650)))
    and (p_section is null or f.section = p_section)
    and (p_rating is null or f.rating = p_rating)
  order by f.updated_at desc
  limit greatest(1, least(p_limit, 500))
  offset greatest(0, p_offset);
$$;

create or replace function public.admin_analysis_result_funnel_v1(
  p_days integer default 30
)
returns table (
  event_name text,
  section text,
  plan_snapshot text,
  event_count bigint,
  unique_users bigint,
  unique_sessions bigint
)
language sql
stable
set search_path = ''
as $$
  select e.event_name, e.section, e.plan_snapshot,
    count(*) as event_count,
    count(distinct e.user_id) as unique_users,
    count(distinct e.funnel_session_id) as unique_sessions
  from private.analysis_result_events e
  where e.created_at >= now() - make_interval(days => greatest(1, least(p_days, 3650)))
  group by e.event_name, e.section, e.plan_snapshot
  order by e.event_name, e.section, e.plan_snapshot;
$$;

do $$
declare v_signature text;
begin
  foreach v_signature in array array[
    'public.result_hub_upsert_notebook_entries(uuid,uuid,text,text,text,jsonb)',
    'public.result_hub_list_notebook_entries(uuid,uuid,text)',
    'public.result_hub_mutate_notebook_entry(uuid,uuid,uuid,text,text,text,text)',
    'public.result_hub_upsert_feedback(uuid,uuid,text,text,uuid,uuid,text,text,integer,text,text,jsonb,jsonb)',
    'public.result_hub_feedback_for_analysis(uuid,uuid)',
    'public.result_hub_insert_event(uuid,uuid,uuid,uuid,text,text,text,text,text,text,text,text,jsonb)',
    'public.result_hub_create_report_intent(uuid,uuid,text,text,text[],jsonb,integer,text,text,text)',
    'public.result_hub_get_report_intent(uuid,uuid)',
    'public.result_hub_consume_report_intent(uuid,uuid,text)',
    'public.check_report_quota_eligibility_v2(uuid,text,text,text)',
    'public.next_report_document_no_v2(uuid,text)',
    'public.admin_analysis_feedback_v1(integer,integer,integer,text,integer)',
    'public.admin_analysis_result_funnel_v1(integer)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', v_signature);
    execute format('grant execute on function %s to service_role', v_signature);
  end loop;
end $$;

insert into public.app_feature_flags (key, value)
values (
  'analysis_result_hub_v1',
  jsonb_build_object(
    'kill_switch', false,
    'rollout_mode', 'user_allowlist',
    'required_capability', 'analysis_result_hub_v1',
    'contract_version', 'analysis-result-sections-v1',
    'secure_premium_projection', true,
    'approved_notebook_projector', true,
    'selective_reports', true,
    'feedback', true,
    'funnel_analytics', true
  )
)
on conflict (key) do update
set value = excluded.value,
    updated_at = now();

comment on table private.analysis_notebook_entries is
  'Deterministic, editable Approved Notebook / Safety Log projections. No provider calls.';
comment on table private.analysis_item_feedback is
  'User-facing like/dislike state; separate from v4 human evaluation labels.';
comment on table private.analysis_result_events is
  'Idempotent result-screen and paywall-funnel event ledger.';
comment on table private.report_export_intents is
  'Authoritative selected-item snapshot shared by PDF and XLSX generation.';
