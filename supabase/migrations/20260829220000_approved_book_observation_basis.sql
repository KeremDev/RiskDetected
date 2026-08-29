-- Observation basis: how the specialist says they saw the site.
--
-- The approved-book engine may not write "saha incelemesinde gözlenmiştir"
-- about a photograph nobody took on site, and it cannot work out which case it
-- is by itself. So the basis is stored per analysis, set only by the specialist,
-- and null until they choose.
--
-- Null is a working state, not a missing value: with no basis the book
-- paragraph is not produced at all and the existing v2 notebook projection is
-- served unchanged. Choosing a basis IS the act that turns the deterministic
-- text on for that analysis, which keeps the switch in the open rather than
-- behind a flag nobody can see.
alter table public.analyses
  add column if not exists approved_book_observation_basis text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'analyses_approved_book_observation_basis_check'
  ) then
    alter table public.analyses
      add constraint analyses_approved_book_observation_basis_check
      check (
        approved_book_observation_basis is null
        or approved_book_observation_basis = any (array[
          'direct_site_observation',
          'employer_supplied_visual_record',
          'document_review',
          'follow_up_check'
        ])
      );
  end if;
end $$;

comment on column public.analyses.approved_book_observation_basis is
  'How the specialist states they observed the site, for the approved-book text. Never inferred: null means no book paragraph may claim an observation basis, and the v2 notebook projection is served instead.';

create or replace function public.result_hub_set_observation_basis(
  p_user_id uuid,
  p_analysis_id uuid,
  p_basis text
)
returns text
language plpgsql
set search_path = ''
as $$
declare
  v_basis text;
begin
  v_basis := nullif(btrim(coalesce(p_basis, '')), '');

  if v_basis is not null and v_basis not in (
    'direct_site_observation',
    'employer_supplied_visual_record',
    'document_review',
    'follow_up_check'
  ) then
    raise exception 'invalid_observation_basis' using errcode = '22023';
  end if;

  update public.analyses
  set approved_book_observation_basis = v_basis,
      updated_at = now()
  where id = p_analysis_id
    and user_id = p_user_id
    and status = 'completed';

  if not found then
    raise exception 'analysis_not_found' using errcode = 'P0002';
  end if;

  return v_basis;
end;
$$;

revoke all on function public.result_hub_set_observation_basis(uuid, uuid, text) from public;
grant execute on function public.result_hub_set_observation_basis(uuid, uuid, text) to service_role;
