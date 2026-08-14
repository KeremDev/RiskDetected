-- Durable idempotency for Supabase Auth Send Email Hook -> Resend delivery.
--
-- The database stores only hashes of the signed webhook ID/body. A short
-- processing lease prevents concurrent delivery; Resend receives a stable
-- Idempotency-Key so an ambiguous provider response can be retried safely.

create table if not exists private.auth_email_delivery_attempts (
  webhook_id_sha256 text not null,
  delivery_index smallint not null,
  request_body_sha256 text not null,
  state text not null,
  lease_token uuid,
  lease_expires_at timestamptz,
  provider_message_id text,
  attempt_count integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  sent_at timestamptz,
  primary key (webhook_id_sha256, delivery_index),
  constraint auth_email_delivery_webhook_hash_check
    check (webhook_id_sha256 ~ '^[0-9a-f]{64}$'),
  constraint auth_email_delivery_body_hash_check
    check (request_body_sha256 ~ '^[0-9a-f]{64}$'),
  constraint auth_email_delivery_index_check
    check (delivery_index between 0 and 1),
  constraint auth_email_delivery_state_check
    check (state in ('processing', 'retryable', 'sent')),
  constraint auth_email_delivery_attempt_count_check
    check (attempt_count between 1 and 1000)
);

alter table private.auth_email_delivery_attempts enable row level security;
revoke all on private.auth_email_delivery_attempts
  from public, anon, authenticated;
grant select, insert, update, delete
  on private.auth_email_delivery_attempts
  to service_role;

create index if not exists auth_email_delivery_attempts_cleanup_idx
  on private.auth_email_delivery_attempts (updated_at)
  where state = 'sent';

create or replace function public.claim_auth_email_delivery_v1(
  p_webhook_id_sha256 text,
  p_delivery_index integer,
  p_request_body_sha256 text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row private.auth_email_delivery_attempts%rowtype;
  v_token uuid := gen_random_uuid();
begin
  if coalesce(p_webhook_id_sha256, '') !~ '^[0-9a-f]{64}$'
     or coalesce(p_request_body_sha256, '') !~ '^[0-9a-f]{64}$'
     or p_delivery_index is null
     or p_delivery_index not between 0 and 1 then
    raise exception using
      errcode = '22023',
      message = 'AUTH_EMAIL_IDEMPOTENCY_INPUT_INVALID';
  end if;

  insert into private.auth_email_delivery_attempts (
    webhook_id_sha256,
    delivery_index,
    request_body_sha256,
    state,
    lease_token,
    lease_expires_at
  )
  values (
    p_webhook_id_sha256,
    p_delivery_index,
    p_request_body_sha256,
    'processing',
    v_token,
    now() + interval '5 minutes'
  )
  on conflict (webhook_id_sha256, delivery_index) do nothing
  returning *
  into v_row;

  if found then
    return jsonb_build_object(
      'status', 'claimed',
      'claimed', true,
      'lease_token', v_row.lease_token,
      'attempt_count', v_row.attempt_count
    );
  end if;

  select attempt.*
  into v_row
  from private.auth_email_delivery_attempts attempt
  where attempt.webhook_id_sha256 = p_webhook_id_sha256
    and attempt.delivery_index = p_delivery_index
  for update;

  if v_row.request_body_sha256 is distinct from p_request_body_sha256 then
    raise exception using
      errcode = '22023',
      message = 'AUTH_EMAIL_WEBHOOK_BODY_MISMATCH';
  end if;
  if v_row.state = 'sent' then
    return jsonb_build_object(
      'status', 'sent',
      'claimed', false,
      'attempt_count', v_row.attempt_count
    );
  end if;
  if v_row.state = 'processing'
     and v_row.lease_expires_at > now() then
    return jsonb_build_object(
      'status', 'processing',
      'claimed', false,
      'attempt_count', v_row.attempt_count
    );
  end if;

  update private.auth_email_delivery_attempts
  set
    state = 'processing',
    lease_token = v_token,
    lease_expires_at = now() + interval '5 minutes',
    attempt_count = attempt_count + 1,
    updated_at = now()
  where webhook_id_sha256 = p_webhook_id_sha256
    and delivery_index = p_delivery_index
  returning *
  into v_row;

  return jsonb_build_object(
    'status', 'claimed',
    'claimed', true,
    'lease_token', v_row.lease_token,
    'attempt_count', v_row.attempt_count
  );
end
$function$;

create or replace function public.complete_auth_email_delivery_v1(
  p_webhook_id_sha256 text,
  p_delivery_index integer,
  p_request_body_sha256 text,
  p_lease_token uuid,
  p_provider_message_id text
)
returns boolean
language sql
security definer
set search_path = ''
as $function$
  with completed as (
    update private.auth_email_delivery_attempts
    set
      state = 'sent',
      provider_message_id = left(nullif(btrim(p_provider_message_id), ''), 160),
      lease_token = null,
      lease_expires_at = null,
      sent_at = now(),
      updated_at = now()
    where webhook_id_sha256 = p_webhook_id_sha256
      and delivery_index = p_delivery_index
      and request_body_sha256 = p_request_body_sha256
      and state = 'processing'
      and lease_token = p_lease_token
    returning 1
  )
  select exists(select 1 from completed);
$function$;

create or replace function public.release_auth_email_delivery_v1(
  p_webhook_id_sha256 text,
  p_delivery_index integer,
  p_request_body_sha256 text,
  p_lease_token uuid
)
returns boolean
language sql
security definer
set search_path = ''
as $function$
  with released as (
    update private.auth_email_delivery_attempts
    set
      state = 'retryable',
      lease_token = null,
      lease_expires_at = null,
      updated_at = now()
    where webhook_id_sha256 = p_webhook_id_sha256
      and delivery_index = p_delivery_index
      and request_body_sha256 = p_request_body_sha256
      and state = 'processing'
      and lease_token = p_lease_token
    returning 1
  )
  select exists(select 1 from released);
$function$;

revoke all on function public.claim_auth_email_delivery_v1(
  text, integer, text
) from public, anon, authenticated;
revoke all on function public.complete_auth_email_delivery_v1(
  text, integer, text, uuid, text
) from public, anon, authenticated;
revoke all on function public.release_auth_email_delivery_v1(
  text, integer, text, uuid
) from public, anon, authenticated;

grant execute on function public.claim_auth_email_delivery_v1(
  text, integer, text
) to service_role;
grant execute on function public.complete_auth_email_delivery_v1(
  text, integer, text, uuid, text
) to service_role;
grant execute on function public.release_auth_email_delivery_v1(
  text, integer, text, uuid
) to service_role;

select pg_notify('pgrst', 'reload schema');
