-- One observation basis, fixed in code.
--
-- Every photograph in this product is taken by the specialist walking the site,
-- so the other three bases described a choice nobody needed to make. Offering
-- them only created a way to state something untrue by mistake, so the picker
-- is gone and the engine always writes under a site inspection.
--
-- Two consequences handled here:
--
--   Stored values are cleared. One analysis carried 'follow_up_check' from
--   testing, and leaving it while every paragraph reads "Saha incelemesinde"
--   would put a contradiction inside the record itself. The entries regenerate
--   under the fixed basis on the next load; their ids derive from the analysis
--   and the cluster, not the basis, so they update in place.
--
--   The setter is dropped. An RPC that can change what a legal record asserts,
--   with nothing calling it, is a loose end worth closing rather than leaving
--   for someone to find.
--
-- The column stays. A document review or a follow-up check is a real thing this
-- could serve later, and the slot costs nothing; null now means "the fixed
-- basis applied".
update public.analyses
set approved_book_observation_basis = null
where approved_book_observation_basis is not null;

drop function if exists public.result_hub_set_observation_basis(uuid, uuid, text);

comment on column public.analyses.approved_book_observation_basis is
  'Reserved. The approved-book engine currently writes every entry under a fixed site-inspection basis, so this stays null; it exists for the day a different basis becomes a real product case.';

do $$
declare
  v_remaining integer;
begin
  select count(*) into v_remaining from public.analyses
  where approved_book_observation_basis is not null;
  if v_remaining <> 0 then
    raise exception '% analyses still carry a stored observation basis', v_remaining;
  end if;

  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'result_hub_set_observation_basis'
  ) then
    raise exception 'the observation-basis setter is still installed';
  end if;
end $$;
