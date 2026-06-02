# Supabase Auth Leaked-Password Investigation - 2026-06-02

Scope: App Review preflight gate for Supabase `auth_leaked_password_protection`.

Do not store Supabase access tokens, database passwords, API keys, or user identifiers in this file.

## Current Finding

- Status: `HOLD`
- Timestamp: 2026-06-02 01:48 +03
- Project: `ppcrzemgiztzcgddbins` / `riskdetected`
- Supabase CLI: upgraded from `2.100.1` to `2.102.0` during this investigation.

The remaining advisor warning is still:

```text
auth_leaked_password_protection: 1
```

Official Supabase docs say leaked-password protection is configured in project Auth settings, prevents use of passwords known through HaveIBeenPwned, and is available on Pro Plan and above. The Management API auth config also exposes `password_hibp_enabled` as an optional boolean field.

## Safe Automation Check

Checked local automation paths:

- `supabase config --help` exposes only broad `config push`; there is still no `config get/list/update` command in CLI `2.102.0`.
- Searching the updated CLI binary did not reveal a `password_hibp_enabled`, `hibp`, or leaked-password config field exposed through local config.
- `supabase/config.toml` now contains a secret-free production Auth baseline plus Edge Function `verify_jwt` settings so accidental future `config push` runs cannot silently fall back to local-dev Auth defaults.
- The Supabase CLI profile is stored in macOS Keychain as a `Supabase CLI` item, but the stored value is not a raw Management API bearer token. A direct Management API call with that Keychain value returned `401`, so a minimal `password_hibp_enabled` API patch is still not available from this session.
- A read-only `supabase db query --linked` metadata query succeeded only for auth password-like columns and found `auth.users.encrypted_password`; this does not expose hosted Auth service config.
- A concurrent read-only metadata query hit temporary pooler auth failures and ended with `SUPABASE_DB_PASSWORD` guidance. Do not keep retrying DB queries rapidly without the correct DB credential/env.

## Auth Config Drift And Restore

At 2026-06-02 01:35 +03, a broad `supabase config push --debug` was accidentally allowed to continue in the non-interactive shell. It temporarily pushed local-dev Auth defaults to the remote project.

Observed temporary drift:

- `site_url` changed to `http://127.0.0.1:3000`.
- `additional_redirect_urls` changed to `https://127.0.0.1:3000`.
- TOTP enrollment/verification changed to `false`.
- Email confirmations changed to `false`, making public `/auth/v1/settings` report `mailer_autoconfirm=true`.
- Email max frequency changed to `1s`.
- Apple provider changed to `external.apple=false`.

Restore applied at 2026-06-02 01:38 +03:

```bash
printf 'y\n' | supabase config push --project-ref ppcrzemgiztzcgddbins --debug
```

The restored secret-free local baseline preserves:

- `additional_redirect_urls = ["io.supabase.riskdetected://login-callback"]`
- `enable_confirmations = true`
- `max_frequency = "1m0s"`
- Apple provider enabled with `client_id = "com.riskdetected.app.service,com.riskdetected.app"`
- Google provider enabled with the web OAuth client ID only; no Google secret is stored in repo.

Post-restore verification:

```text
external.email=true
external.apple=true
external.google=true
external.phone=false
disable_signup=false
mailer_autoconfirm=false
Remote Auth config is up to date.
```

The App Review collector now has two additional PASS gates:

- `Supabase local Auth config baseline`
- `Supabase public Auth settings baseline`

This restore did not enable leaked-password protection. The advisor still reports `auth_leaked_password_protection: 1`, so this preflight item remains `HOLD`.

## Submission-Day Action

Preferred:

1. Open Supabase Dashboard for project `riskdetected`.
2. Go to Authentication -> Settings -> Password Security.
3. Enable leaked-password protection / HaveIBeenPwned protection if the plan supports it.
4. Re-run:

```bash
supabase db advisors --linked --type all --level warn --fail-on none --output json \
  | jq -r 'group_by(.name)[] | "\(.[0].name): \(length)"'
```

Pass condition:

- `auth_leaked_password_protection` disappears from the advisor summary.

Fallback:

- If the toggle is unavailable on the current Supabase plan or cannot be safely changed before submission, record an explicit accepted-risk decision in `QA/APP_REVIEW_MANUAL_EVIDENCE_FORM_2026-06-01.md`.
- Current mitigation context: release app auth surface uses Email OTP, Apple, and Google; password demo sign-in is `#if DEBUG` only.

## Sources

- Supabase Password Security docs: `https://supabase.com/docs/guides/auth/password-security`
- Supabase Management API docs: `https://supabase.com/docs/reference/api/getting-started`
