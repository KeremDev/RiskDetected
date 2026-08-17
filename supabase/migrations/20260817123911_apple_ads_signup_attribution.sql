-- Server-side Apple Ads attribution for signup cohorts. This table is
-- intentionally isolated from auth, subscription, quota, analysis and report
-- execution paths: a RevenueCat outage must never affect the product.

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

create table if not exists public.user_ad_attribution (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null default 'ios',
  provider text,
  media_source text,
  campaign_name text,
  campaign_id text,
  ad_group_name text,
  ad_group_id text,
  keyword_name text,
  keyword_id text,
  ad_id text,
  org_id text,
  claim_type text,
  conversion_type text,
  country_or_region text,
  supply_placement text,
  sync_status text not null default 'pending',
  source text not null default 'revenuecat_customer_attributes_v2',
  source_updated_at timestamptz,
  first_fetched_at timestamptz,
  last_fetched_at timestamptz,
  attempt_count integer not null default 0,
  next_attempt_at timestamptz default now(),
  last_http_status integer,
  last_error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_ad_attribution_user_platform_key unique (user_id, platform),
  constraint user_ad_attribution_platform_check
    check (platform in ('ios', 'android')),
  constraint user_ad_attribution_provider_check
    check (provider is null or provider = 'apple_ads'),
  constraint user_ad_attribution_sync_status_check
    check (sync_status in ('pending', 'attributed', 'unavailable', 'not_found', 'error')),
  constraint user_ad_attribution_source_check
    check (source = 'revenuecat_customer_attributes_v2'),
  constraint user_ad_attribution_attempt_count_check
    check (attempt_count >= 0 and attempt_count <= 1000),
  constraint user_ad_attribution_http_status_check
    check (last_http_status is null or last_http_status between 100 and 599),
  constraint user_ad_attribution_fetch_order_check
    check (
      first_fetched_at is null
      or last_fetched_at is null
      or first_fetched_at <= last_fetched_at
    ),
  constraint user_ad_attribution_text_lengths_check
    check (
      length(coalesce(media_source, '')) <= 120
      and length(coalesce(campaign_name, '')) <= 256
      and length(coalesce(campaign_id, '')) <= 128
      and length(coalesce(ad_group_name, '')) <= 256
      and length(coalesce(ad_group_id, '')) <= 128
      and length(coalesce(keyword_name, '')) <= 256
      and length(coalesce(keyword_id, '')) <= 128
      and length(coalesce(ad_id, '')) <= 128
      and length(coalesce(org_id, '')) <= 128
      and length(coalesce(claim_type, '')) <= 80
      and length(coalesce(conversion_type, '')) <= 80
      and length(coalesce(country_or_region, '')) <= 32
      and length(coalesce(supply_placement, '')) <= 80
      and length(coalesce(last_error_code, '')) <= 120
    )
);

comment on table public.user_ad_attribution is
  'First-touch Apple Ads attribution resolved server-side from RevenueCat customer attributes.';
comment on column public.user_ad_attribution.user_id is
  'Supabase auth UUID, also used as the RevenueCat app user ID.';
comment on column public.user_ad_attribution.sync_status is
  'Unavailable means no attribution was supplied after the retry window; it does not mean organic.';
comment on column public.user_ad_attribution.source is
  'Fixed provenance marker; raw RevenueCat attributes and PII are never stored.';

create index if not exists user_ad_attribution_due_idx
  on public.user_ad_attribution (platform, sync_status, next_attempt_at)
  where sync_status in ('pending', 'not_found', 'error');

create index if not exists user_ad_attribution_campaign_idx
  on public.user_ad_attribution (platform, provider, campaign_id, ad_group_id, keyword_id);

drop trigger if exists user_ad_attribution_set_updated_at
  on public.user_ad_attribution;
create trigger user_ad_attribution_set_updated_at
before update on public.user_ad_attribution
for each row execute function public.tg_set_updated_at();

alter table public.user_ad_attribution enable row level security;

-- No client policy is created. The Edge Function and operation center use the
-- service role; mobile users cannot read or mutate attribution rows.
revoke all on table public.user_ad_attribution from public, anon, authenticated;
grant select, insert, update, delete on table public.user_ad_attribution to service_role;

do $$
declare
  has_project_url boolean;
  has_sync_secret boolean;
begin
  if exists (
    select 1 from cron.job
    where jobname = 'riskdetected-revenuecat-attribution-hourly'
  ) then
    perform cron.unschedule('riskdetected-revenuecat-attribution-hourly');
  end if;

  select exists (
    select 1 from vault.decrypted_secrets
    where name = 'project_url'
      and nullif(decrypted_secret, '') is not null
  ) into has_project_url;

  select exists (
    select 1 from vault.decrypted_secrets
    where name = 'attribution_sync_secret'
      and nullif(decrypted_secret, '') is not null
  ) into has_sync_secret;

  if has_project_url and has_sync_secret then
    perform cron.schedule(
      'riskdetected-revenuecat-attribution-hourly',
      '37 * * * *',
      $cron$
      select net.http_post(
        url := (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'project_url'
        ) || '/functions/v1/sync-revenuecat-attribution',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-attribution-sync-secret', (
            select decrypted_secret
            from vault.decrypted_secrets
            where name = 'attribution_sync_secret'
          )
        ),
        body := jsonb_build_object('source', 'pg_cron', 'limit', 25),
        timeout_milliseconds := 120000
      ) as request_id;
      $cron$
    );
  else
    raise notice 'RevenueCat attribution cron not scheduled: Vault secrets are missing';
  end if;
end
$$;

notify pgrst, 'reload schema';
