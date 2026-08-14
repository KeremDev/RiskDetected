begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select extensions.plan(17);

select extensions.has_column(
  'public', 'account_deletion_requests', 'requested_via',
  'deletion audit records the requesting platform'
);
select extensions.has_column(
  'public', 'account_deletion_requests', 'completion_mode',
  'deletion request records immediate or queued completion'
);
select extensions.has_column(
  'public', 'account_deletion_requests', 'due_at',
  'queued request has an SLA timestamp'
);
select extensions.has_column(
  'public', 'account_deletion_requests', 'attempt_count',
  'queued request tracks bounded attempts'
);
select extensions.has_column(
  'public', 'account_deletion_requests', 'last_attempt_at',
  'queued request tracks the last attempt time'
);
select extensions.has_column(
  'public', 'account_deletion_requests', 'next_attempt_at',
  'queued request tracks retry backoff'
);
select extensions.has_column(
  'public', 'account_deletion_requests', 'last_error_code',
  'queued request stores a PII-free error code'
);

select extensions.col_not_null(
  'public', 'account_deletion_requests', 'requested_via',
  'requesting platform is required'
);
select extensions.col_not_null(
  'public', 'account_deletion_requests', 'completion_mode',
  'completion mode is required'
);
select extensions.col_not_null(
  'public', 'account_deletion_requests', 'due_at',
  'queue SLA timestamp is required'
);
select extensions.col_not_null(
  'public', 'account_deletion_requests', 'attempt_count',
  'attempt count is required'
);

select extensions.col_default_is(
  'public', 'account_deletion_requests', 'requested_via', 'legacy',
  'legacy callers remain backward compatible'
);
select extensions.col_default_is(
  'public', 'account_deletion_requests', 'completion_mode', 'immediate',
  'mobile behavior remains immediate by default'
);
select extensions.col_default_is(
  'public', 'account_deletion_requests', 'attempt_count', '0',
  'new requests start without failed attempts'
);

select extensions.ok(
  (select relrowsecurity from pg_class where oid = 'public.account_deletion_requests'::regclass),
  'account deletion request table keeps RLS enabled'
);
select extensions.ok(
  not has_table_privilege('anon', 'public.account_deletion_requests', 'SELECT')
  and not has_table_privilege('anon', 'public.account_deletion_requests', 'INSERT')
  and not has_table_privilege('anon', 'public.account_deletion_requests', 'UPDATE'),
  'anonymous clients have no deletion queue privileges'
);

select extensions.is(
  (
    select count(*)::bigint
    from cron.job
    where jobname = 'riskdetected-account-deletion-hourly'
  ),
  0::bigint,
  'hourly deletion worker remains unscheduled when local Vault secrets are absent'
);

select * from extensions.finish();
rollback;
