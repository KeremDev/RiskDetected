-- F4 (review doc, blocker/mimari): record_notification_delivery_attempt_v1's parameter
-- `p_apns_id` is APNs-specific by name. Rather than repurpose it for FCM message IDs (which
-- would blur its meaning for every existing iOS row/query), this adds a provider-agnostic v2
-- and turns v1 into a thin delegating wrapper — v1's external signature/behavior is byte-for-
-- byte identical to before, so every existing iOS call site (and every existing row) is
-- completely unaffected.

alter table private.notification_delivery_attempts
  add column if not exists provider text not null default 'apns'
    check (provider in ('apns', 'fcm'));

alter table private.notification_delivery_attempts
  add column if not exists provider_message_id text;

comment on column private.notification_delivery_attempts.provider is
  'Push transport for this attempt. Default apns preserves every existing row''s meaning unchanged.';
comment on column private.notification_delivery_attempts.apns_id is
  'APNs-specific message id. Only ever set when provider = apns — kept as-is (not renamed) so every existing query against this column keeps working. FCM attempts use provider_message_id instead.';
comment on column private.notification_delivery_attempts.provider_message_id is
  'FCM (or any future non-APNs provider) message id. NULL for apns rows — those keep using apns_id.';

create or replace function public.record_notification_delivery_attempt_v2(
  p_notification_event_id uuid,
  p_job_id uuid,
  p_push_device_token_id uuid,
  p_environment text,
  p_attempt_number integer,
  p_outcome text,
  p_provider text default 'apns',
  p_http_status integer default null,
  p_provider_message_id text default null,
  p_reason text default null,
  p_duration_ms integer default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id bigint;
  v_message_id text := nullif(left(btrim(coalesce(p_provider_message_id, '')), 200), '');
begin
  if p_provider not in ('apns', 'fcm') then
    raise exception 'record_notification_delivery_attempt_v2: unknown provider %', p_provider;
  end if;

  insert into private.notification_delivery_attempts (
    notification_event_id,
    job_id,
    push_device_token_id,
    environment,
    attempt_number,
    outcome,
    http_status,
    provider,
    apns_id,
    provider_message_id,
    reason,
    duration_ms
  )
  values (
    p_notification_event_id,
    p_job_id,
    p_push_device_token_id,
    p_environment,
    p_attempt_number,
    p_outcome,
    p_http_status,
    p_provider,
    case when p_provider = 'apns' then v_message_id else null end,
    case when p_provider = 'fcm' then v_message_id else null end,
    nullif(left(btrim(coalesce(p_reason, '')), 500), ''),
    p_duration_ms
  )
  on conflict (
    notification_event_id,
    push_device_token_id,
    attempt_number
  ) do update set
    outcome = excluded.outcome,
    http_status = excluded.http_status,
    provider = excluded.provider,
    apns_id = excluded.apns_id,
    provider_message_id = excluded.provider_message_id,
    reason = excluded.reason,
    duration_ms = excluded.duration_ms
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.record_notification_delivery_attempt_v2(
  uuid, uuid, uuid, text, integer, text, text, integer, text, text, integer
) from public, anon, authenticated;
grant execute on function public.record_notification_delivery_attempt_v2(
  uuid, uuid, uuid, text, integer, text, text, integer, text, text, integer
) to service_role;

-- v1 becomes a thin delegate — identical external signature, identical resulting row shape
-- for every apns call (provider defaults to 'apns', p_apns_id maps straight to
-- p_provider_message_id which v2 writes back into the same apns_id column as before).
create or replace function public.record_notification_delivery_attempt_v1(
  p_notification_event_id uuid,
  p_job_id uuid,
  p_push_device_token_id uuid,
  p_environment text,
  p_attempt_number integer,
  p_outcome text,
  p_http_status integer default null,
  p_apns_id text default null,
  p_reason text default null,
  p_duration_ms integer default null
)
returns bigint
language sql
security definer
set search_path = ''
as $$
  select public.record_notification_delivery_attempt_v2(
    p_notification_event_id,
    p_job_id,
    p_push_device_token_id,
    p_environment,
    p_attempt_number,
    p_outcome,
    'apns',
    p_http_status,
    p_apns_id,
    p_reason,
    p_duration_ms
  );
$$;

revoke all on function public.record_notification_delivery_attempt_v1(
  uuid, uuid, uuid, text, integer, text, integer, text, text, integer
) from public, anon, authenticated;
grant execute on function public.record_notification_delivery_attempt_v1(
  uuid, uuid, uuid, text, integer, text, integer, text, text, integer
) to service_role;
