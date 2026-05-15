# Supabase Migration History Repair - 2026-05-15

## Decision

Remote-only 3 May base migrations were not stale noise. They contain the first project schema:

- extensions/enums;
- profiles;
- analyses/photos;
- findings;
- reports/audit;
- RLS;
- storage buckets;
- quota function hardening.

Decision: keep those migrations, fetch them into the repository, and align the remote migration history with the local migration chain. Do not delete the base history from remote.

## Local Cleanup

- Fetched missing remote base migrations with `supabase migration fetch`.
- Removed duplicate short-version AI usage migration:
  - removed `20260504_ai_usage_logs.sql`;
  - kept remote-backed `20260504063219_ai_usage_logs.sql`.
- Renamed short-version reports migration to a valid timestamp:
  - old: `20260506_reports_storage.sql`;
  - new: `20260506193000_reports_storage.sql`.

## Remote Repair

Marked already-applied local migrations as applied in remote history:

```bash
supabase migration repair \
  20260506192136 \
  20260507221522 \
  20260508021838 \
  20260508022421 \
  20260508185954 \
  20260508192153 \
  20260509001429 \
  20260509230500 \
  20260510002500 \
  20260510004500 \
  20260510180047 \
  20260515183236 \
  --status applied --yes
```

Replaced malformed short version:

```bash
supabase migration repair 20260506 --status reverted --yes
supabase migration repair 20260506193000 --status applied --yes
```

## Remote Schema Checks

Confirmed on linked Supabase project:

- `public.consents` exists.
- `public.account_deletion_requests` exists.
- `public.push_device_tokens` exists.
- `public.notification_preferences` exists.
- `public.notification_events` exists.
- `public.reports.format` exists.
- `public.reports.request_id` exists.
- `public.ai_usage_logs.api_key_alias` exists.
- `public.profiles.company_logo_url` exists.
- `private.cleanup_expired_retention(integer)` exists.
- `reports` bucket allows XLSX MIME type.
- `riskdetected-retention-cleanup-daily` cron job exists.
- `pg_cron`, `pg_net` and `supabase_vault` extensions exist.

## Final Verification

`supabase migration list` is clean: every local migration version now has a matching remote version.

No schema-changing SQL was executed during repair; only Supabase migration history rows were updated.
