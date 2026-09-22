-- Historical v4 analyses can outlive their private routing rows. The public
-- finding snapshot is the durable user-owned result, and it already contains
-- the bounded internal_priority.book_source metadata used by the deterministic
-- training recommendation projector. Serve that snapshot only when the
-- canonical private rows for the analysis are absent.

create or replace function public.result_hub_v4_metadata(
  p_user_id uuid,
  p_analysis_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with canonical as (
    select
      i.public_finding_id,
      i.criticality,
      i.canonical_payload,
      i.internal_priority,
      c.normalized_payload->>'asset_ref' as asset_ref,
      c.candidate_key,
      c.evidence_region,
      coalesce(refs.reference_texts, '[]'::jsonb) as verified_references,
      i.display_order
    from private.analysis_items_v4 i
    left join private.analysis_claim_candidates c
      on c.id = i.candidate_id
     and c.analysis_id = i.analysis_id
     and c.user_id = i.user_id
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
      and i.public_finding_id is not null
  ), historical as (
    select
      f.id as public_finding_id,
      coalesce(nullif(f.ai_original_snapshot->>'criticality', ''), 'ordinary') as criticality,
      coalesce(f.ai_original_snapshot, '{}'::jsonb) as canonical_payload,
      coalesce(f.ai_original_snapshot->'internal_priority', '{}'::jsonb) as internal_priority,
      coalesce(
        nullif(f.ai_original_snapshot#>>'{internal_priority,book_source,asset_ref}', ''),
        nullif(f.ai_original_snapshot->>'asset_ref', '')
      ) as asset_ref,
      coalesce(
        nullif(f.ai_original_snapshot->>'candidate_key', ''),
        f.id::text
      ) as candidate_key,
      f.ai_original_snapshot->'evidence_region' as evidence_region,
      case
        when nullif(btrim(f.references_text), '') is null then '[]'::jsonb
        else jsonb_build_array(f.references_text)
      end as verified_references,
      coalesce(f.display_order, f.ordinal) as display_order
    from public.findings f
    where f.user_id = p_user_id
      and f.analysis_id = p_analysis_id
      and coalesce(f.is_user_deleted, false) = false
      and f.report_visibility = 'visible'
      and not exists (select 1 from canonical)
  ), source as (
    select * from canonical
    union all
    select * from historical
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'public_finding_id', source.public_finding_id,
    'criticality', source.criticality,
    'canonical_payload', source.canonical_payload,
    'internal_priority', source.internal_priority,
    'asset_ref', source.asset_ref,
    'candidate_key', source.candidate_key,
    'evidence_region', source.evidence_region,
    'verified_references', source.verified_references
  ) order by source.display_order), '[]'::jsonb)
  from source;
$$;

revoke all on function public.result_hub_v4_metadata(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.result_hub_v4_metadata(uuid, uuid)
  to service_role;

comment on function public.result_hub_v4_metadata(uuid, uuid) is
  'Canonical v4 metadata with a public finding-snapshot fallback for historical analyses whose private routing rows have expired or were not migrated.';
