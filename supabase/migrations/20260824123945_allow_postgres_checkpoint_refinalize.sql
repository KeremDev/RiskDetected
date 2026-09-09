-- Keep completed analyses terminal for application roles. A postgres-only,
-- exact-analysis GUC permits controlled checkpoint re-finalization during
-- production recovery without disabling the guard trigger globally.
create or replace function private.tg_protect_completed_analysis_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_checkpoint_refinalize_id text := current_setting(
    'app.analysis_checkpoint_refinalize_id',
    true
  );
begin
  if old.status::text = 'completed'
    and new.status::text <> 'completed'
    and not (
      session_user = 'postgres'
      and v_checkpoint_refinalize_id = old.id::text
    )
  then
    raise exception using
      errcode = '23514',
      message = 'completed_analysis_status_is_terminal';
  end if;
  return new;
end;
$$;
