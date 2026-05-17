-- `reports_user_created` covers the same access path: user_id + created_at desc.
-- Keep the newer canonical index and remove the older duplicate to reduce write
-- amplification on report archive inserts/deletes.
drop index if exists public.reports_user_id_idx;
