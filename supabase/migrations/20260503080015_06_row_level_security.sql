
-- Tüm public tablolarda RLS aç
alter table public.profiles      enable row level security;
alter table public.analyses      enable row level security;
alter table public.photos        enable row level security;
alter table public.findings      enable row level security;
alter table public.reports       enable row level security;
alter table public.report_counters enable row level security;
alter table public.audit_logs    enable row level security;

-- Profiles: kullanıcı sadece kendi profilini okur/günceller
create policy profiles_select_own on public.profiles
  for select to authenticated using (auth.uid() = id);

create policy profiles_update_own on public.profiles
  for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

-- INSERT yok — profile trigger ile oluşur

-- Analyses: kullanıcı sadece kendi analizlerini görür/yönetir
create policy analyses_select_own on public.analyses
  for select to authenticated using (auth.uid() = user_id);

create policy analyses_insert_own on public.analyses
  for insert to authenticated with check (auth.uid() = user_id);

create policy analyses_update_own on public.analyses
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy analyses_delete_own on public.analyses
  for delete to authenticated using (auth.uid() = user_id);

-- Photos: kullanıcı kendi fotoğraflarını yönetir
create policy photos_select_own on public.photos
  for select to authenticated using (auth.uid() = user_id);

create policy photos_insert_own on public.photos
  for insert to authenticated with check (auth.uid() = user_id);

create policy photos_update_own on public.photos
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy photos_delete_own on public.photos
  for delete to authenticated using (auth.uid() = user_id);

-- Findings: kullanıcı kendi bulgularını yönetir; AI tarafından eklenenler de aynı user_id'yle gelir
create policy findings_select_own on public.findings
  for select to authenticated using (auth.uid() = user_id);

create policy findings_insert_own on public.findings
  for insert to authenticated with check (auth.uid() = user_id);

create policy findings_update_own on public.findings
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy findings_delete_own on public.findings
  for delete to authenticated using (auth.uid() = user_id);

-- Reports: kullanıcı kendi raporlarını yönetir
create policy reports_select_own on public.reports
  for select to authenticated using (auth.uid() = user_id);

create policy reports_insert_own on public.reports
  for insert to authenticated with check (auth.uid() = user_id);

create policy reports_delete_own on public.reports
  for delete to authenticated using (auth.uid() = user_id);

-- Report counters: kullanıcı sadece kendi sayacını okur (manuel insert yok — function üretir)
create policy report_counters_select_own on public.report_counters
  for select to authenticated using (auth.uid() = user_id);

-- Audit logs: kullanıcı kendi loglarını okur (insert sadece function/trigger ile)
create policy audit_logs_select_own on public.audit_logs
  for select to authenticated using (auth.uid() = user_id);
;
