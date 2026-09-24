# Account Deletion Completion QA

Date: 2026-05-16

## Implemented

- Added `account-deletion-complete` Supabase Edge Function.
- Added migration `20260516152207_account_deletion_completion.sql`.
- The iOS app still only records a user-facing deletion request.
- Completion is privileged and requires either:
  - `Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>`, or
  - `x-account-deletion-secret: <ACCOUNT_DELETION_ADMIN_SECRET>`.

## Completion Flow

1. Operator/backend calls the Edge Function with `request_id` or `user_id`.
2. Function locks the request as `processing`.
3. Function records target user id/email/hash for audit continuity.
4. Function removes Storage objects under the user's prefix from:
   - `photos`
   - `reports`
   - `logos`
5. Function deletes the Supabase Auth user with admin privileges.
6. Database cascades remove profile, analyses, findings, reports, subscriptions and related user rows.
7. Request row is preserved as `completed` because its Auth FK now uses `on delete set null`.

## Deployment

```bash
supabase functions deploy account-deletion-complete --use-api --no-verify-jwt
```

Set the optional admin secret if the function will be called without the service-role bearer:

```bash
supabase secrets set ACCOUNT_DELETION_ADMIN_SECRET='<strong-random-secret>'
```

## Manual Operator Calls

Dry run:

```bash
curl -X POST \
  'https://ppcrzemgiztzcgddbins.supabase.co/functions/v1/account-deletion-complete' \
  -H 'Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{"request_id":"<account_deletion_request_id>","dry_run":true,"processed_by":"operator"}'
```

Execute:

```bash
curl -X POST \
  'https://ppcrzemgiztzcgddbins.supabase.co/functions/v1/account-deletion-complete' \
  -H 'Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>' \
  -H 'Content-Type: application/json' \
  -d '{"request_id":"<account_deletion_request_id>","processed_by":"operator"}'
```

## Verification

- `deno check supabase/functions/account-deletion-complete/index.ts` passed.
- `supabase db push --linked --yes` applied `20260516152207_account_deletion_completion.sql` to project `ppcrzemgiztzcgddbins`.
- `supabase functions deploy account-deletion-complete --use-api --no-verify-jwt` deployed the function.
- `supabase functions list --project-ref ppcrzemgiztzcgddbins` shows `account-deletion-complete` as `ACTIVE`.
- Remote schema query confirmed the new completion columns on `public.account_deletion_requests`.
- Unauthenticated function call returns `401 unauthorized`.
- Local migration list could not run because local Supabase Postgres was not started on `127.0.0.1:54322`.
- Remote `db lint` still reports pre-existing issues in `private.cleanup_expired_retention` and `public.check_and_consume_quota`; these were already present and are outside this deletion-completion change.

## Production Spot-Check

Before App Store release, create a disposable TestFlight account, request deletion from Profile > Verilerim, run the function once with `dry_run: true`, then execute it. Confirm:

- Auth user no longer exists.
- `profiles`, `analyses`, `photos`, `findings`, `reports`, `user_subscriptions`, `usage_events` user rows are gone.
- Storage prefixes are empty in `photos`, `reports`, `logos`.
- `account_deletion_requests.status = completed`.
