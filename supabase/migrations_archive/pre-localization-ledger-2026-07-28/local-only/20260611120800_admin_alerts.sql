-- V3: Admin alert rules and events

create table if not exists public.admin_alert_rules (
  id uuid primary key default gen_random_uuid(),
  rule_key text not null unique,
  name text not null,
  description text not null default '',
  metric_key text not null,
  operator text not null,
  threshold numeric not null,
  severity text not null default 'warning',
  is_enabled boolean not null default true,
  cooldown_minutes integer not null default 60,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint admin_alert_rules_operator_check
    check (operator in ('gt', 'gte', 'lt', 'lte', 'eq')),
  constraint admin_alert_rules_severity_check
    check (severity in ('critical', 'warning', 'info')),
  constraint admin_alert_rules_cooldown_check
    check (cooldown_minutes between 5 and 1440)
);

create table if not exists public.admin_alert_events (
  id uuid primary key default gen_random_uuid(),
  rule_id uuid not null references public.admin_alert_rules(id) on delete cascade,
  rule_key text not null,
  severity text not null,
  title text not null,
  message text not null,
  metric_key text not null,
  metric_value numeric not null,
  threshold numeric not null,
  status text not null default 'open',
  fingerprint text not null,
  acknowledged_at timestamptz,
  acknowledged_by uuid references auth.users(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint admin_alert_events_status_check
    check (status in ('open', 'acknowledged', 'resolved')),
  constraint admin_alert_events_severity_check
    check (severity in ('critical', 'warning', 'info'))
);

create index if not exists admin_alert_events_status_created_idx
  on public.admin_alert_events(status, created_at desc);

create index if not exists admin_alert_events_rule_status_idx
  on public.admin_alert_events(rule_id, status, created_at desc);

create unique index if not exists admin_alert_events_fingerprint_open_idx
  on public.admin_alert_events(fingerprint)
  where status = 'open';

alter table public.admin_alert_rules enable row level security;
alter table public.admin_alert_events enable row level security;

revoke all on table public.admin_alert_rules from anon;
revoke all on table public.admin_alert_rules from authenticated;
revoke all on table public.admin_alert_events from anon;
revoke all on table public.admin_alert_events from authenticated;

grant select, insert, update, delete on table public.admin_alert_rules to service_role;
grant select, insert, update, delete on table public.admin_alert_events to service_role;

insert into public.admin_alert_rules (
  rule_key, name, description, metric_key, operator, threshold, severity, cooldown_minutes
)
values
  (
    'stale_queue',
    'Bayat analiz kuyruğu',
    '15 dakikadan uzun süredir queued durumunda analiz var',
    'stale_queue',
    'gte',
    1,
    'critical',
    30
  ),
  (
    'queue_backlog',
    'Yüksek kuyruk backlog',
    'Bekleyen veya çalışan analiz sayısı eşiği aştı',
    'queue_backlog',
    'gte',
    10,
    'warning',
    60
  ),
  (
    'failed_analyses_7d',
    'Başarısız analiz artışı',
    'Son 7 günde başarısız analiz sayısı yükseldi',
    'failed_analyses_7d',
    'gte',
    5,
    'warning',
    120
  ),
  (
    'ai_errors_7d',
    'AI hata oranı',
    'Son 7 günde AI çağrı hataları eşiği aştı',
    'ai_errors_7d',
    'gte',
    20,
    'warning',
    120
  ),
  (
    'subscription_inconsistency',
    'Abonelik tutarsızlığı',
    'Profil planı ile RevenueCat aboneliği uyuşmuyor',
    'subscription_inconsistencies',
    'gte',
    1,
    'critical',
    180
  ),
  (
    'data_quality_high',
    'Yüksek öncelikli veri sorunu',
    'Veri kalitesi monitöründe yüksek öncelikli kayıt var',
    'data_quality_high',
    'gte',
    1,
    'critical',
    180
  ),
  (
    'pending_deletions',
    'Silme talebi birikimi',
    'Bekleyen hesap silme talebi sayısı arttı',
    'pending_deletions',
    'gte',
    5,
    'warning',
    240
  ),
  (
    'health_score_low',
    'Düşük operasyon skoru',
    'Operasyon sağlık skoru kritik seviyenin altına düştü',
    'health_score',
    'lte',
    70,
    'warning',
    120
  )
on conflict (rule_key) do nothing;
