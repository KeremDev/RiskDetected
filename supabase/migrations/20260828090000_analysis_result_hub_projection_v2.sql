-- approved-notebook-projection-v2
--
-- The v1 RPC returned only the final routed item. The candidate's stable asset
-- reference and evidence region live in analysis_claim_candidates, so the
-- projector could not apply its documented asset + mechanism + region grouping
-- rule to real v4 data. This additive RPC revision exposes only the bounded
-- metadata needed by the service-role result endpoint. Private tables remain
-- unavailable to mobile clients.

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
    'asset_ref', c.normalized_payload->>'asset_ref',
    'candidate_key', c.candidate_key,
    'evidence_region', c.evidence_region,
    'verified_references', coalesce(refs.reference_texts, '[]'::jsonb)
  ) order by i.display_order), '[]'::jsonb)
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
    and i.public_finding_id is not null;
$$;

revoke all on function public.result_hub_v4_metadata(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.result_hub_v4_metadata(uuid, uuid)
  to service_role;

do $$
begin
  if has_function_privilege(
    'authenticated',
    'public.result_hub_v4_metadata(uuid,uuid)',
    'execute'
  ) then
    raise exception 'result_hub_v4_metadata_exposed_to_authenticated';
  end if;
  if not has_function_privilege(
    'service_role',
    'public.result_hub_v4_metadata(uuid,uuid)',
    'execute'
  ) then
    raise exception 'result_hub_v4_metadata_missing_service_role_grant';
  end if;
end $$;
