create index if not exists analysis_job_events_user_created_idx
  on private.analysis_job_events (user_id, created_at desc);

drop policy if exists "Deny anonymous job event access"
  on private.analysis_job_events;
create policy "Deny anonymous job event access"
  on private.analysis_job_events
  for all
  to anon
  using (false)
  with check (false);

drop policy if exists "Deny authenticated job event access"
  on private.analysis_job_events;
create policy "Deny authenticated job event access"
  on private.analysis_job_events
  for all
  to authenticated
  using (false)
  with check (false);

revoke all on table private.analysis_job_events
  from public, anon, authenticated;
