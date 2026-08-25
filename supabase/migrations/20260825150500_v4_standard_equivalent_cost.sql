-- Fill the Standard-equivalent comparison from physical provider attempts
-- before the completed-run trace trigger snapshots authoritative totals.
create or replace function private.set_v4_standard_equivalent_cost()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.engine_version='vnext-v4' and new.status='completed' then
    select coalesce(sum(standard_equivalent_cost_usd),0)
    into new.total_standard_equivalent_cost_usd
    from private.analysis_provider_attempts
    where engine_run_id=new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists analysis_engine_runs_v4_standard_cost
  on private.analysis_engine_runs;
create trigger analysis_engine_runs_v4_standard_cost
before insert or update of status
on private.analysis_engine_runs
for each row execute function private.set_v4_standard_equivalent_cost();

revoke all on function private.set_v4_standard_equivalent_cost()
  from public,anon,authenticated;
