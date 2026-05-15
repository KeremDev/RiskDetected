
-- search_path'i tüm fonksiyonlara sabitle
alter function public.tg_set_updated_at() set search_path = public;
alter function public.tg_recalc_finding_count() set search_path = public;
alter function public.next_document_no(uuid) set search_path = public;

-- next_document_no: sadece service_role çağırabilsin (Edge Function üzerinden)
revoke all on function public.next_document_no(uuid) from public, anon, authenticated;
grant execute on function public.next_document_no(uuid) to service_role;

-- tg_create_profile_for_new_user: trigger için. RPC'den erişimi kaldır.
revoke all on function public.tg_create_profile_for_new_user() from public, anon, authenticated;

-- check_and_consume_quota: yalnızca service_role (Edge Function)
revoke all on function public.check_and_consume_quota(uuid) from public, anon, authenticated;
grant execute on function public.check_and_consume_quota(uuid) to service_role;
;
