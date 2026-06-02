-- Wrap auth.uid() calls used by active RLS policies so Postgres can evaluate
-- them once per statement via initPlan instead of once per row.

alter policy "Users create own deletion requests"
  on public.account_deletion_requests
  with check ((select auth.uid()) = user_id);

alter policy "Users read own deletion requests"
  on public.account_deletion_requests
  using ((select auth.uid()) = user_id);

alter policy "Users read own logs"
  on public.ai_usage_logs
  using ((select auth.uid()) = user_id);

alter policy analyses_delete_own
  on public.analyses
  using ((select auth.uid()) = user_id);

alter policy analyses_insert_own
  on public.analyses
  with check ((select auth.uid()) = user_id and status = 'pending'::analysis_status);

alter policy analyses_select_own
  on public.analyses
  using ((select auth.uid()) = user_id);

alter policy analyses_update_own_editable_fields
  on public.analyses
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

alter policy audit_logs_select_own
  on public.audit_logs
  using ((select auth.uid()) = user_id);

alter policy companies_insert_paid_own
  on public.companies
  with check (
    (select auth.uid()) = user_id
    and (select coalesce(private.company_limit_for_user((select auth.uid())), 0)) > 0
  );

alter policy companies_select_own
  on public.companies
  using ((select auth.uid()) = user_id);

alter policy companies_update_paid_own
  on public.companies
  using (
    (select auth.uid()) = user_id
    and (select coalesce(private.company_limit_for_user((select auth.uid())), 0)) > 0
  )
  with check (
    (select auth.uid()) = user_id
    and (select coalesce(private.company_limit_for_user((select auth.uid())), 0)) > 0
  );

alter policy "Users insert own consents"
  on public.consents
  with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

alter policy "Users read own consents"
  on public.consents
  using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

alter policy findings_select_own
  on public.findings
  using ((select auth.uid()) = user_id);

alter policy "Users read own notification events"
  on public.notification_events
  using ((select auth.uid()) = user_id);

alter policy "Users insert own notification preferences"
  on public.notification_preferences
  with check ((select auth.uid()) = user_id);

alter policy "Users read own notification preferences"
  on public.notification_preferences
  using ((select auth.uid()) = user_id);

alter policy "Users update own notification preferences"
  on public.notification_preferences
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

alter policy photos_delete_own
  on public.photos
  using ((select auth.uid()) = user_id);

alter policy photos_insert_own
  on public.photos
  with check ((select auth.uid()) = user_id);

alter policy photos_select_own
  on public.photos
  using ((select auth.uid()) = user_id);

alter policy photos_update_own
  on public.photos
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

alter policy "Users insert own profile"
  on public.profiles
  with check ((select auth.uid()) = id);

alter policy "Users read own profile"
  on public.profiles
  using ((select auth.uid()) = id);

alter policy "Users update own profile"
  on public.profiles
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

alter policy profiles_select_own
  on public.profiles
  using ((select auth.uid()) = id);

alter policy profiles_update_own
  on public.profiles
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

alter policy "Users delete own push tokens"
  on public.push_device_tokens
  using ((select auth.uid()) = user_id);

alter policy "Users insert own push tokens"
  on public.push_device_tokens
  with check ((select auth.uid()) = user_id);

alter policy "Users read own push tokens"
  on public.push_device_tokens
  using ((select auth.uid()) = user_id);

alter policy "Users update own push tokens"
  on public.push_device_tokens
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

alter policy report_counters_select_own
  on public.report_counters
  using ((select auth.uid()) = user_id);

alter policy "Users delete own reports"
  on public.reports
  using ((select auth.uid()) = user_id);

alter policy "Users read own reports"
  on public.reports
  using ((select auth.uid()) = user_id);

alter policy "Users read own usage events"
  on public.usage_events
  using ((select auth.uid()) = user_id);

alter policy "Users delete own avatar files"
  on storage.objects
  using (
    bucket_id = 'avatars'
    and lower((storage.foldername(name))[1]) = (select auth.uid())::text
  );

alter policy "Users insert own avatar files"
  on storage.objects
  with check (
    bucket_id = 'avatars'
    and lower((storage.foldername(name))[1]) = (select auth.uid())::text
  );

alter policy "Users read own avatar files"
  on storage.objects
  using (
    bucket_id = 'avatars'
    and lower((storage.foldername(name))[1]) = (select auth.uid())::text
  );

alter policy "Users update own avatar files"
  on storage.objects
  using (
    bucket_id = 'avatars'
    and lower((storage.foldername(name))[1]) = (select auth.uid())::text
  )
  with check (
    bucket_id = 'avatars'
    and lower((storage.foldername(name))[1]) = (select auth.uid())::text
  );

alter policy "Users delete own logo files"
  on storage.objects
  using (
    bucket_id = 'logos'
    and auth.role() = 'authenticated'
    and lower((storage.foldername(name))[1]) = (select auth.uid())::text
  );

alter policy "Users insert own logo files"
  on storage.objects
  with check (
    bucket_id = 'logos'
    and auth.role() = 'authenticated'
    and lower((storage.foldername(name))[1]) = (select auth.uid())::text
  );

alter policy "Users read own logo files"
  on storage.objects
  using (
    bucket_id = 'logos'
    and auth.role() = 'authenticated'
    and lower((storage.foldername(name))[1]) = (select auth.uid())::text
  );

alter policy "Users update own logo files"
  on storage.objects
  using (
    bucket_id = 'logos'
    and auth.role() = 'authenticated'
    and lower((storage.foldername(name))[1]) = (select auth.uid())::text
  )
  with check (
    bucket_id = 'logos'
    and auth.role() = 'authenticated'
    and lower((storage.foldername(name))[1]) = (select auth.uid())::text
  );

alter policy "Users delete own report files"
  on storage.objects
  using (
    bucket_id = 'reports'
    and auth.role() = 'authenticated'
    and lower((storage.foldername(name))[1]) = (select auth.uid())::text
  );

alter policy "Users insert own report files"
  on storage.objects
  with check (
    bucket_id = 'reports'
    and auth.role() = 'authenticated'
    and lower((storage.foldername(name))[1]) = (select auth.uid())::text
  );

alter policy "Users read own report files"
  on storage.objects
  using (
    bucket_id = 'reports'
    and auth.role() = 'authenticated'
    and lower((storage.foldername(name))[1]) = (select auth.uid())::text
  );

alter policy "Users update own report files"
  on storage.objects
  using (
    bucket_id = 'reports'
    and auth.role() = 'authenticated'
    and lower((storage.foldername(name))[1]) = (select auth.uid())::text
  )
  with check (
    bucket_id = 'reports'
    and auth.role() = 'authenticated'
    and lower((storage.foldername(name))[1]) = (select auth.uid())::text
  );

alter policy logos_delete_own
  on storage.objects
  using (bucket_id = 'logos' and (storage.foldername(name))[1] = (select auth.uid())::text);

alter policy logos_insert_own
  on storage.objects
  with check (bucket_id = 'logos' and (storage.foldername(name))[1] = (select auth.uid())::text);

alter policy logos_select_own
  on storage.objects
  using (bucket_id = 'logos' and (storage.foldername(name))[1] = (select auth.uid())::text);

alter policy logos_update_own
  on storage.objects
  using (bucket_id = 'logos' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'logos' and (storage.foldername(name))[1] = (select auth.uid())::text);

alter policy photos_delete_own
  on storage.objects
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

alter policy photos_insert_own
  on storage.objects
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

alter policy photos_select_own
  on storage.objects
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

alter policy photos_update_own
  on storage.objects
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

alter policy reports_delete_own
  on storage.objects
  using (bucket_id = 'reports' and (storage.foldername(name))[1] = (select auth.uid())::text);

alter policy reports_insert_own
  on storage.objects
  with check (bucket_id = 'reports' and (storage.foldername(name))[1] = (select auth.uid())::text);

alter policy reports_select_own
  on storage.objects
  using (bucket_id = 'reports' and (storage.foldername(name))[1] = (select auth.uid())::text);
