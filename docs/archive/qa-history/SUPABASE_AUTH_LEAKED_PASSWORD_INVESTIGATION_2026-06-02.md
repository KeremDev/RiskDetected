# Supabase Auth Leaked-Password Investigation - 2026-06-02

Scope: App Review preflight gate for Supabase `auth_leaked_password_protection`.

Do not store Supabase access tokens, database passwords, API keys, or user identifiers in this file.

## Current Finding

- Status: `ACCEPTED_RISK` / `PASS`
- Timestamp: 2026-06-02 11:30 +03
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

This restore did not enable leaked-password protection. At 2026-06-02 11:30 +03, the release decision was updated to accept this known risk for the current submission path. The advisor may still report `auth_leaked_password_protection: 1`, but this item is no longer treated as an App Review blocker.

## Accepted-Risk Record

Decision:

- Do not enable leaked-password protection before this submission.
- Record the warning as accepted known risk for App Review preflight.
- Keep leaked-password protection as recommended post-release hardening if plan support and release timing allow it later.

Mitigation context:

- Release app auth surface uses Email OTP, Apple, and Google.
- Password demo sign-in is `#if DEBUG` only.
- No Supabase Auth config, DB schema, or migration change is required for this closure.

Post-release recommendation:

- If the Supabase plan supports it, enable Authentication -> Settings -> Password Security -> Prevent use of leaked passwords in the Dashboard and re-run advisors.

## Sources

- Supabase Password Security docs: `https://supabase.com/docs/guides/auth/password-security`
- Supabase Management API docs: `https://supabase.com/docs/reference/api/getting-started`
