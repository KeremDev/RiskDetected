# App Review Submission Day Runbook - 2026-06-01

Scope: RiskDetected `1.0 (31)` App Review candidate.

Do not tap `Add for Review` until every item below is complete or explicitly accepted as a known risk.

Current hold: App Review contact fields are intentionally not filled yet. Keep this runbook as a final-day checklist until the release decision is made.

Use `QA/APP_REVIEW_MANUAL_EVIDENCE_FORM_2026-06-01.md` to record non-secret pass/fail evidence for manual gates. Do not write real mailbox passwords, private phone numbers, API keys, private keys, or sandbox Apple ID passwords in that file.

If continuing in another assistant/thread, start from `QA/APP_REVIEW_HANDOFF_FOR_CLAUDE_2026-06-01.md`.

## 1. Confirm Candidate Build

Expected:

- App: `6769498181`
- Version ID: `e97f1de1-7e8c-448b-a5b9-80869f0a8816`
- Version: `1.0`
- Build: `31`
- Build ID: `fca919e5-b12a-4129-8d82-cf46ce1736c8`
- Processing state: `VALID`

Verify:

```bash
asc builds info --app 6769498181 --build-number 31 --platform IOS --output json --pretty
asc review status --app 6769498181 --output markdown
```

Pass condition:

- Build `31` is `VALID`.
- `reviewState` is still `NOT_SUBMITTED` before the final manual submission step.

## 2. Fill App Review Information

In App Store Connect, open version `1.0` -> App Review Information.

Fill:

- Contact first name
- Contact last name
- Contact email
- Contact phone
- Demo account required: yes
- Demo user name: `riskdetected.appreview@fastmail.com`
- Demo password: `Email OTP login. See Notes for OTP mailbox access.`
- Notes: use `QA/App_Review_Webmail_OTP_Access_2026-06-01.md`

Important:

- Do not commit the real Fastmail mailbox password.
- Paste the real mailbox password only into App Store Connect Notes.
- Replace `<PASTE_ONLY_IN_APP_STORE_CONNECT_NOTES>` and `<PHYSICAL_DEVICE_DEMO_VIDEO_URL>` before submission.
- Keep all six new-submission review-note sections present: physical-device screen recording, app purpose, access instructions/test credentials, external services, regional differences, and regulated-industry documentation/not-applicable explanation.

Verify:

```bash
asc validate --app 6769498181 --version-id e97f1de1-7e8c-448b-a5b9-80869f0a8816 --platform IOS --output markdown
asc review status --app 6769498181 --output markdown
```

Pass condition:

- `review_details.missing_field` errors are gone.

## 3. Confirm App Privacy

Open:

- `https://appstoreconnect.apple.com/apps/6769498181/appPrivacy`

Confirm:

- App Privacy is completed and published.
- Nutrition labels match actual app behavior:
  - Account/auth identifiers.
  - User content/photos uploaded for analysis/reporting.
  - Diagnostics or support data if disclosed.
  - Purchases/subscriptions via Apple/RevenueCat.
  - No advertising tracking / no IDFA.
  - Google Sign-In data shown by bundled privacy manifests: name, email address, phone number, other data types, coarse location, user ID, device ID, and other usage data for app functionality/analytics.
  - RevenueCat data shown by bundled privacy manifests: purchase history for app functionality.

Verify:

```bash
asc validate --app 6769498181 --version-id e97f1de1-7e8c-448b-a5b9-80869f0a8816 --platform IOS --output markdown
```

Pass condition:

- Any App Privacy blocker in ASC UI is gone. The CLI may still report `privacy.publish_state.unverified` because public API visibility is limited; trust the ASC UI for this item.

## 4. Attach Subscriptions To Review

In App Store Connect version `1.0`, attach/submit all first-time subscriptions with the app version:

- `riskdetected_plus_monthly`
- `riskdetected_plus_yearly`
- `riskdetected_pro_monthly`
- `riskdetected_pro_yearly`

Verify:

```bash
asc validate subscriptions --app 6769498181 --output markdown
asc validate --app 6769498181 --version-id e97f1de1-7e8c-448b-a5b9-80869f0a8816 --platform IOS --output markdown
```

Pass condition:

- Subscription validation still has `0` errors.
- ASC UI shows all four subscriptions included with the app review submission.

## 5. Confirm Pricing And Storefront

In App Store Connect subscription pricing UI, confirm Turkey storefront prices:

- Plus monthly: `₺199,99`
- Plus yearly: `₺1.999,99`
- Pro monthly: `₺499,99`
- Pro yearly: `₺4.999,99`

CLI cross-check:

```bash
asc subscriptions pricing summary --app 6769498181 --territory Turkey --output markdown
```

Latest live CLI result, 2026-06-02 00:26 +03:

- Plus monthly: `199.99 TRY`
- Plus yearly: `1999.99 TRY`
- Pro monthly: `499.99 TRY`
- Pro yearly: `4999.99 TRY`

Then use a Turkey sandbox tester on a physical iPhone and confirm paywall display:

- Onboarding Plus monthly/yearly.
- In-app Plus monthly/yearly.
- In-app Pro monthly/yearly.
- No fallback price copy.
- No USD storefront price in the app.

Pass condition:

- Storefront and device paywall both show TL prices.

## 6. Decide China Mainland Availability

Current evidence:

```bash
asc pricing availability view --app 6769498181 --output json --pretty
asc pricing availability territory-availabilities --availability 6769498181 --paginate --output json --pretty
```

Latest live result, 2026-06-02 02:16 +03:

- `availableInNewTerritories=true`
- `CHN available=true`

Decision:

- Preferred first-release path: exclude China mainland in App Store Connect availability.
- Alternative: record a China-specific compliance decision before submission.

Context:

- App metadata and legal docs disclose AI-assisted analysis.
- Legal docs disclose Google Gemini / Google AI and Groq providers.
- China mainland availability can trigger additional AI/provider scrutiny.

Pass condition:

- `CHN available=false`, or `QA/APP_REVIEW_MANUAL_EVIDENCE_FORM_2026-06-01.md` records an explicit China-specific compliance decision.

## 7. Supabase Security Toggle

Open Supabase project `riskdetected`:

- Authentication -> Settings -> Password Security -> Prevent use of leaked passwords is accepted known risk for this submission path and optional post-release hardening.
- Investigation note: `QA/SUPABASE_AUTH_LEAKED_PASSWORD_INVESTIGATION_2026-06-02.md`

Action:

- Keep leaked-password protection recorded as accepted known risk for this submission; optionally enable it after release if plan support is available.
- Do not use `supabase config push` as a quick fix unless the full `supabase/config.toml` push scope has been reviewed; for this gate, dashboard enablement or a minimal Management API patch is safer.
- Do not retry `supabase db query --linked` loops rapidly if the pooler reports temporary auth failures; set the correct `SUPABASE_DB_PASSWORD` env first if DB-query evidence is needed.

Verify:

```bash
supabase db advisors --linked --type all --level warn --fail-on none --output json \
  | jq -r 'group_by(.name)[] | "\(.[0].name): \(length)"'
```

Pass condition:

- Accepted for this submission: `auth_leaked_password_protection` may remain while the accepted-risk decision is recorded.
- Acceptable known risk for submission only if the toggle is unavailable on the current Supabase plan and password login is still needed.

## 8. Physical-Device Smoke Test

Use TestFlight build `1.0 (31)` on a physical iPhone.

Current physical-device worksheet:

- `QA/APP_REVIEW_PHYSICAL_SMOKE_17PM_2026-06-01.md`

Confirmed target:

- `iPhone Kerem` / iPhone 17 Pro Max / iOS `26.5`
- `com.riskdetected.app` candidate `1.0 (31)`
- Screen viewer: `devices://device/open?id=F8EB649B-8963-59F6-90D0-CE4176B7D1DE`

Run:

- Email OTP login with `riskdetected.appreview@fastmail.com`.
- Apple login.
- Google login.
- Paywall product load.
- Sandbox purchase flow.
- Restore purchases.
- One Free analysis.
- One Plus/Pro entitlement sync.
- Account deletion request flow.

Pass condition:

- No blocker in login, paywall product loading, purchase/restore, analysis/report basics, or account deletion request path.
- `QA/APP_REVIEW_MANUAL_EVIDENCE_FORM_2026-06-01.md` has the physical-device smoke rows marked with non-secret evidence/notes.

## 9. Final Validation Before Tapping Add For Review

Run:

```bash
node scripts/app_review_preflight_collect.mjs --output QA/App_Review_Preflight_Evidence_2026-06-02.md
asc validate --app 6769498181 --version-id e97f1de1-7e8c-448b-a5b9-80869f0a8816 --platform IOS --output markdown
asc validate subscriptions --app 6769498181 --output markdown
asc review status --app 6769498181 --output markdown
```

Pass condition:

- No ASC blocking errors except known API-only App Privacy ambiguity that ASC UI proves complete.
- Evidence collector has no unreviewed `FAIL`; current known collector cleanup FAILs are old paywall legal-link marker expectations and old App Store screenshot path probing. Any remaining `HOLD`/`WARN`/accepted `FAIL` is resolved manually or explicitly accepted as known risk before submission.
- Manual evidence form completion `HOLD` is gone unless a remaining item is explicitly accepted as known risk.
- Review detail is configured.
- Build `1.0 (31)` remains attached.
- Subscriptions are ready and included with submission.

## 10. Release Staging

Before committing/tagging:

- Follow `QA/RELEASE_HYGIENE_2026-06-01.md`.
- Do not bulk-stage `output/`, `.DS_Store`, raw QA screenshots, local keys, or temporary exports.
- Keep marketing assets separate from runtime/backend release changes when possible.
- Run `node scripts/release_staging_guard.mjs` after staging and before commit/tag.
