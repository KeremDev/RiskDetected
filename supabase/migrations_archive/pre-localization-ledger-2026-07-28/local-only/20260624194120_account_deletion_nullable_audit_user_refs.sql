-- Account deletion must preserve audit rows while allowing auth.users deletion.
-- User-owned data is removed through profile cascades; audit identity columns
-- that intentionally survive deletion must not block Supabase Auth removal.

alter table public.finding_edit_events
  alter column actor_user_id drop not null;

alter table public.finding_edit_events
  drop constraint if exists finding_edit_events_actor_user_id_fkey;

alter table public.finding_edit_events
  add constraint finding_edit_events_actor_user_id_fkey
  foreign key (actor_user_id) references auth.users(id) on delete set null;

alter table public.findings
  drop constraint if exists findings_last_user_edit_by_fkey;

alter table public.findings
  add constraint findings_last_user_edit_by_fkey
  foreign key (last_user_edit_by) references auth.users(id) on delete set null;

alter table public.findings
  drop constraint if exists findings_user_deleted_by_fkey;

alter table public.findings
  add constraint findings_user_deleted_by_fkey
  foreign key (user_deleted_by) references auth.users(id) on delete set null;

select pg_notify('pgrst', 'reload schema');
