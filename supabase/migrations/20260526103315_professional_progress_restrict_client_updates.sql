-- Tighten client-side write surface for Professional Progress.
-- The original module migration revoked `public`, but Supabase projects may
-- have direct default privileges for `authenticated`. Revoke those explicitly
-- and grant only the intended read/seen_at surface.

revoke all on public.professional_progress_profiles from authenticated;
revoke all on public.professional_progress_events from authenticated;
revoke all on public.professional_progress_finding_classifications from authenticated;
revoke all on public.professional_progress_competency_stats from authenticated;
revoke all on public.professional_progress_badges from authenticated;
revoke all on public.professional_progress_messages from authenticated;
revoke all on public.professional_progress_weekly_summaries from authenticated;

grant select on public.professional_progress_profiles to authenticated;
grant select on public.professional_progress_events to authenticated;
grant select on public.professional_progress_finding_classifications to authenticated;
grant select on public.professional_progress_competency_stats to authenticated;
grant select on public.professional_progress_badges to authenticated;
grant update (seen_at) on public.professional_progress_badges to authenticated;
grant select on public.professional_progress_messages to authenticated;
grant update (seen_at) on public.professional_progress_messages to authenticated;
grant select on public.professional_progress_weekly_summaries to authenticated;

select pg_notify('pgrst', 'reload schema');
