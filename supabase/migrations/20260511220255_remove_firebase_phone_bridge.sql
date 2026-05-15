-- Remove the abandoned Firebase phone auth bridge.
-- Phone/Firebase login is no longer part of the MVP auth surface.

drop table if exists public.firebase_phone_auth_links;
select pg_notify('pgrst', 'reload schema');
