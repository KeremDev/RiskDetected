# RiskDetected - New Chat Handoff Context

Last updated: 2026-08-02, Europe/Istanbul  
Workspace: `/Users/keremkayalar/Documents/Kerem-APPler/RiskDetected`  
Branch observed: `codex/global-localization-wave1`  
Latest observed commit: `740d551 Enable notification shadow evaluation`

This document is the single-file handoff for continuing the RiskDetected Build 80 localization/App Review work in a new Codex chat.

Do not paste or expose private secrets. This file intentionally records secret locations and service names only, not values.

## Immediate status

RiskDetected `1.3.0 (80)` is prepared for App Store review.

- App Store app id: `6769498181`
- Bundle id: `com.riskdetected.app`
- Candidate version: `1.3.0`
- Candidate build: `80`
- App Store version id: `9a2f5061-8992-4957-a9e8-7b8a96747323`
- Build id: `71cc9591-32b9-4fee-b6c4-8c4d30713b23`
- Release type: `MANUAL`
- Last verified state before this handoff:
  - `node scripts/app_store_connect/verify.mjs` passed: 102/102 checks green.
  - `asc review status` showed `NOT_SUBMITTED`, `PREPARE_FOR_SUBMISSION`, `reviewDetail=configured`, `blockerCount=0`.
  - `asc validate subscriptions` showed 4 subscriptions, 0 errors, 0 blocking.
  - Build 80 is `VALID`.

Owner-only actions:

- The owner presses `Add for Review` in App Store Connect.
- Do not submit, release, or change production rollout flags unless the owner explicitly instructs it.
- After Apple approval, release is still manual. The app will not auto-release.

If continuing after the owner submitted, first verify current state:

```bash
asc review status --app 6769498181 --output markdown
node scripts/app_store_connect/verify.mjs
```

## Hard safety rules for live system

RiskDetected is a live production system.

- Do not impact live users.
- Do not activate global localization/runtime flags for production unless the owner explicitly says Apple approved and asks to activate.
- Do not change Turkish App Store metadata, Turkish screenshots, or Turkish subscription copy unless explicitly requested.
- Do not mutate App Store Connect, Supabase production flags, RevenueCat products, or live secrets during diagnostics.
- Prefer read-only checks first.
- Any final release operation is owner-authorized only.

Current intended release staging:

- Build 80 localization and multi-photo quality work is prepared.
- Live Build 77 remains protected from Build 80+ activation gates.
- Build 80+ keeps:
  - 12-layer multi-photo audit enabled.
  - Gemini thinking budget at `6144`.
  - English prompt quality rules aligned with Turkish analysis quality rules.
  - Physical hazards should not be incorrectly merged into one finding.
  - Coverage checks compare returned findings to actionable layers/photo coverage.

## Project overview

RiskDetected is an iOS workplace-safety risk analysis app.

Core product:

- Users upload or capture workplace/site photos.
- AI-assisted analysis produces safety findings.
- Findings are linked to source photos for verification.
- Risk is scored via Fine-Kinney or 5x5 matrix.
- Users can generate PDF and Excel reports.
- Plus/Pro subscriptions unlock higher limits and multi-photo workflows.
- App is advisory decision support only; it does not certify legal compliance and does not replace a qualified occupational safety professional.

Important product boundaries:

- AI findings can be incomplete or inaccurate.
- Non-Turkish safety profiles are terminology guidance only.
- Country terminology profiles do not claim legal/regulatory certification.
- China mainland is excluded for this AI-assisted release.

## Main technologies

iOS app:

- Swift / SwiftUI
- iOS deployment target: 16.0
- Xcode project: `RiskDetected.xcodeproj`
- Main app sources: `App/`
- Localization catalogs: `App/Localization/*.xcstrings`
- Generated safety profile Swift: `localization/generated/SafetyProfiles.generated.swift`
- Snapshot/UI tests: `RiskDetectedSnapshotTests/`, `RiskDetectedUITests/`

iOS packages:

- Supabase Swift: `https://github.com/supabase/supabase-swift.git`
- Google Sign-In: `https://github.com/google/GoogleSignIn-iOS.git`
- RevenueCat / RevenueCatUI: `https://github.com/RevenueCat/purchases-ios-spm.git`
- SnapshotPreviews: `https://github.com/getsentry/SnapshotPreviews.git`

Backend:

- Supabase project ref: `ppcrzemgiztzcgddbins`
- Supabase database, storage, auth, and Edge Functions.
- Edge Functions are under `supabase/functions/`.
- Shared backend modules are under `supabase/functions/_shared/`.
- Migrations are under `supabase/migrations/`.
- Tests include Deno static/unit tests and pgTAP SQL tests.

External services:

- App Store Connect via `asc` CLI.
- RevenueCat / StoreKit for IAP subscriptions and entitlements.
- Google Gemini / Google AI for primary AI analysis.
- Groq-compatible fallback path.
- Resend through Supabase Edge Functions for transactional/support email.
- APNs for push notifications.
- Applyra MCP for ASO keyword/ranking tracking.

## App Store localization scope

Build 80 Wave 1 locales:

- Protected Turkish locale: `tr`
- New/updated English store locales:
  - `en-US`
  - `en-GB`
  - `en-CA`
  - `en-AU`

English App Store work completed:

- English metadata configured.
- English legal/support URLs configured:
  - `https://riskdetected.com/en/privacy`
  - `https://riskdetected.com/en/terms`
  - `https://riskdetected.com/en/support`
- English screenshots uploaded and ASC read-after-write verified.
- Screenshots use light theme.
- Turkish screenshots and Turkish metadata were not mutated by automation.

Key evidence:

- `docs/localization/phase-8/BUILD80_FINAL_SUBMIT_READINESS_2026-08-02.md`
- `output/app-review-preflight/App_Review_Preflight_Evidence_2026-08-02-build80.md`
- `appstore/review/app-review-notes.md`
- `appstore/review/localization-evidence.md`
- `.asc/evidence/verify-1.3.0-result.json`
- `.asc/evidence/review-notes-build80-readback.json`
- `.asc/evidence/app-privacy-browser-readback-2026-08-02.json`
- `.asc/evidence/app-privacy-published-2026-08-02.png`

## Safety terminology / localization architecture

Safety profiles:

- Turkish current profile: `tr-tr-current-v1`
- English International: `en-intl-generic-v1`
- English US: `en-us-generic-v1`
- English UK: `en-gb-generic-v1`
- English Australia WHS: `en-au-generic-v1`
- English Canada OHS: `en-ca-generic-v1`

Source files:

- `localization/safety-profiles/*.yaml`
- `localization/safety-profiles/manifest.yaml`
- `localization/generated/safety-profiles.generated.ts`
- `localization/generated/SafetyProfiles.generated.swift`
- `supabase/functions/_shared/safety-profile-manifest.ts`
- `supabase/functions/_shared/localization-context-resolver.ts`
- `App/Views/Onboarding/V2/Screens/OBSafetyProfileSelectionView.swift`

Important behavior:

- English users explicitly select a safety terminology profile during onboarding.
- If a user bypasses onboarding, default profile should be International.
- Storefront, IP address, or device region must not infer safety jurisdiction.
- App language and output language are immutable analysis context once a request is created.

## AI analysis / Build 80 quality changes

Build 80 critical AI changes:

- Multi-photo 12-layer audit is enabled for Build 80+ and future builds.
- Multi-photo Gemini thinking budget is `6144` for Build 80+ and future builds.
- English prompt quality rules were aligned with Turkish quality rules.
- The prompt discourages merging distinct physical hazards into one finding.
- Coverage/quality logic compares returned findings to actionable layers/photo coverage.
- Static/fixture tests should be used before any final real analysis.

Real Build 80 evidence:

- Real physical-device analysis id: `0854fa06-4ea5-462d-82e8-ad1e67e8fc2b`
- Completed with:
  - 2 photos
  - 4 findings
  - app language `en`
  - output locale `en-001`
  - safety profile `en-intl-generic-v1`
  - client build `80`
  - language validation `passed`
  - Gemini provider HTTP 200, no fallback, no error

Relevant backend files:

- `supabase/functions/analyze/index.ts`
- `supabase/functions/analyze/inspection-layer-audit.ts`
- `supabase/functions/analyze/photo-coverage-contract.ts`
- `supabase/functions/analyze/multi_photo_quality_static_test.ts`
- `supabase/functions/_shared/ai-localization-prompt.ts`
- `supabase/functions/_shared/ai-localization-validation.ts`
- `supabase/functions/_shared/gemini-provider-client.ts`
- `supabase/functions/_shared/photo-source-indices.ts`
- `supabase/functions/_shared/finding-confidence.ts`

## Subscriptions and pricing

Subscription product ids:

- `riskdetected_plus_monthly`
- `riskdetected_plus_yearly`
- `riskdetected_pro_monthly`
- `riskdetected_pro_yearly`

RevenueCat offering id:

- `default`

Important pricing behavior:

- Prices are not hardcoded by app language.
- iOS price display uses RevenueCat/StoreKit localized price strings.
- Apple storefront / Apple ID country determines currency and price.
- TR region includes a fail-closed guard: if StoreKit returns USD for TR, the app should not show it as a valid Turkish price.

Verified storefront prices:

| Storefront | Plus Monthly | Plus Yearly | Pro Monthly | Pro Yearly |
| --- | ---: | ---: | ---: | ---: |
| Turkey | 249.99 TRY | 2499.99 TRY | 499.99 TRY | 4999.99 TRY |
| United States | 4.99 USD | 49.99 USD | 9.99 USD | 99.99 USD |
| United Kingdom | 4.99 GBP | 49.99 GBP | 9.99 GBP | 99.99 GBP |
| Canada | 6.99 CAD | 69.99 CAD | 12.99 CAD | 129.99 CAD |
| Australia | 7.99 AUD | 79.99 AUD | 14.99 AUD | 149.99 AUD |

Key code:

- `App/Services/SubscriptionManager.swift`
- `App/Views/Onboarding/V2/Screens/OBTimelinePaywallView.swift`
- `App/Views/Onboarding/V2/Screens/OBPaywallView.swift`
- `App/Views/Paywall/InAppPaywallView.swift`
- `supabase/functions/revenuecat-webhook/index.ts`
- `supabase/functions/sync-revenuecat-subscription/index.ts`

Latest validation:

```bash
asc validate subscriptions --app 6769498181 --output markdown
```

Expected current result:

- 4 subscriptions
- 0 errors
- 0 blocking
- 4 warnings only for optional subscription promotional images

## App Store Review notes / Turkish release notes

Current review notes file:

- `appstore/review/app-review-notes.md`

The owner requested manual insertion of Turkish `What's New` and a short review-note addendum.

Suggested Turkish `What's New`:

```text
• Uygulamaya tam İngilizce dil desteği eklendi.
• International, UK, US, AU ve CA iş güvenliği terminoloji profilleri eklendi.
• İngilizce analiz, bildirim, PDF ve Excel rapor akışları hazırlandı.
• Erişilebilirlik, performans ve güvenilirlik iyileştirmeleri yapıldı.

AI çıktıları karar destek amaçlıdır; yetkili iş güvenliği uzmanı değerlendirmesi veya hukuki incelemenin yerine geçmez.
```

Suggested App Review Notes addendum:

```text
Turkish localization note:
The Turkish App Store listing, screenshots and existing Turkish product positioning remain unchanged for this submission. The Turkish “What’s New” field has been filled only to describe the 1.3.0 update and to avoid an empty release-notes field. The main new functionality in this build is the English localization, English report workflows, and country-appropriate English safety terminology profiles.
```

## Applyra keyword tracking

Applyra app:

- Internal app id: `318921`
- Bundle: `com.riskdetected.app`
- Store: `ITUNES`

Latest Applyra action:

- Localization keyword source: `appstore/versions/1.3.0/*.json` -> `version_info.keywords`
- 51 locale keyword rows processed.
- 48 new tracking rows added.
- 3 TR keywords were already tracked: `osgb`, `is guvenligi`, `isg`
- Applyra keyword count increased from `25` to `73`.

Tracked locale/country groups added:

- TR / `tr-TR`
- US / `en-US`
- GB / `en-GB`
- CA / `en-CA`
- AU / `en-AU`

Use Applyra MCP, not shell, for future keyword tracking:

- `mcp__applyra.list_applications`
- `mcp__applyra.list_keywords`
- `mcp__applyra.track_keywords`
- `mcp__applyra.inspect_keyword`

## Security status

Security remediation doc:

- `docs/security/CODEX_SECURITY_REMEDIATION_2026-08-01.md`

Current security disposition:

- Codex Security open finding count: 0.
- Six source-scan findings were remediated or closed as already fixed.
- No user row, storage object, subscription, release, rollout flag, or Turkish App Store content was changed during security validation.
- Remaining Supabase advisor warnings are accepted/non-blocking for this App Review path:
  - leaked-password protection accepted/deferred
  - authenticated security-definer executable function warnings documented
  - multiple permissive policy warnings documented

Important warning:

- Supabase leaked-password protection is disabled/accepted as known risk for this release path.
- Do not enable it casually; it can change live signup/password behavior.

## Keychain and secret handling

Never print secret values.

Local keychain service names used by repo tooling:

- `riskdetected_supabase_access_token`
- `riskdetected_supabase_db_password`
- `riskdetected_revenuecat_rest_api_key`

Safe status check:

```bash
node scripts/rd_ops_env.mjs status
```

Expected result:

```text
PASS supabaseAccessToken (riskdetected_supabase_access_token)
PASS supabaseDBPassword (riskdetected_supabase_db_password)
PASS revenueCatRestAPIKey (riskdetected_revenuecat_rest_api_key)
```

Use repo wrapper for Supabase CLI operations that need credentials:

```bash
node scripts/rd_ops_env.mjs supabase <supabase args...>
```

Do not run commands that echo keychain values.

Remote Supabase secrets were checked by name/fingerprint only. Critical configured categories:

- Supabase runtime: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY`
- Gemini: free/paid key pool aliases including `GEMINI_API_KEY`, `GEMINI_API_KEY_PAID`, `GEMINI_API_KEY_SECONDARY`, preferred aliases
- Groq fallback: free/plus-pro key and model aliases
- Resend: `RESEND_API_KEY`, `RESEND_FROM_EMAIL`
- Auth email hook: `SEND_EMAIL_HOOK_SECRET`
- RevenueCat server side: `REVENUECAT_REST_API_KEY`, `REVENUECAT_WEBHOOK_AUTHORIZATION`
- APNs: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_BUNDLE_ID`, `APNS_ENV`
- Background jobs: `PROCESS_ANALYSIS_JOBS_SECRET`, `NOTIFICATION_AUTOMATION_SECRET`, `RETENTION_CLEANUP_SECRET`, `TRIAL_REMINDER_SECRET`
- Support: `SUPPORT_TO_EMAIL`

Observed caveats:

- `RESEND_REPLY_TO_EMAIL` is not configured remotely, but code falls back to `info@riskdetected.com`.
- `ACCOUNT_DELETION_ADMIN_SECRET` is not configured remotely; current in-app deletion path uses service-role authorization. The admin-secret header is an optional/manual fallback.
- Supabase CLI may warn `SUPABASE_AUTH_EXTERNAL_APPLE_SECRET` is unset in local config. This is not proof of a broken production Apple auth secret. Do not push local Auth config blindly.

Public/publishable app config present in Build 80:

- Supabase URL is configured.
- Supabase publishable key is configured.
- RevenueCat iOS SDK key is configured.
- Google Sign-In client/server IDs are configured.

Do not paste public keys into chats unless there is a concrete need; even publishable keys should be treated with hygiene.

## Supabase Edge Functions

Build 80 preflight expected 19 production Edge Functions active:

- `account-deletion-complete`
- `analyze`
- `app-release-policy`
- `auth-send-email-hook`
- `generate-excel-report`
- `manage-notification-automation`
- `mutate-analysis-finding`
- `process-analysis-jobs`
- `process-notification-automation`
- `register-report`
- `request-account-deletion`
- `retention-cleanup`
- `revenuecat-webhook`
- `send-push-notification`
- `send-report-ready-notification`
- `send-trial-reminder-notifications`
- `send-welcome-email`
- `support-contact`
- `sync-revenuecat-subscription`

Read-only check:

```bash
supabase functions list --project-ref ppcrzemgiztzcgddbins --output json
```

Prefer the keychain wrapper if credentials are needed:

```bash
node scripts/rd_ops_env.mjs supabase functions list --project-ref ppcrzemgiztzcgddbins --output json
```

## Current validation commands

Core App Store checks:

```bash
node scripts/app_store_connect/verify.mjs
asc review status --app 6769498181 --output markdown
asc validate --app 6769498181 --version-id 9a2f5061-8992-4957-a9e8-7b8a96747323 --platform IOS --output markdown
asc validate subscriptions --app 6769498181 --output markdown
```

Localization/release gates:

```bash
make localization-wave1-audit
make localization-phase6-test
make localization-test
make localization-phase5-release-gate
bash scripts/localization_release_build_gate.sh
```

Preflight collector:

```bash
node scripts/app_review_preflight_collect.mjs \
  --output output/app-review-preflight/App_Review_Preflight_Evidence_2026-08-02-build80.md \
  --ipa-app .asc/artifacts/RiskDetected-1.3.0-80-extracted/Payload/RiskDetected.app
```

Known latest gate results:

- `app_store_connect/verify`: 102/102 green.
- Preflight collector: 47 PASS, 2 WARN, 0 HOLD, 0 FAIL, 1 SKIP.
- `make localization-wave1-audit`: 37 requirements satisfied.
- `make localization-phase6-test`: Node 35/35, Deno 73/73, pgTAP 45/45.
- `make localization-test`: passed.
- `make localization-phase5-release-gate`: passed.

## Worktree condition

The worktree is intentionally large/dirty from the ongoing localization/security/App Store preparation wave.

Important:

- Do not assume uncommitted changes are yours.
- Do not reset, checkout, or delete broad paths.
- Use `git status --short` before changing files.
- Release staging guard previously reported no forbidden dirty files, but many files are modified/untracked.
- Staged files were 0 in the last preflight.

Observed branch:

- `codex/global-localization-wave1`

If asked to commit, first produce a curated staging plan. Do not blindly stage all files.

## Important source and evidence map

Project master/reference:

- `docs/RISKDETECTED_ACTIVE_SYSTEM_MASTER_REFERENCE_2026-07-28.md`
- `docs/RISKDETECTED_GLOBAL_LOCALIZATION_COUNTRY_SAFETY_INTEGRATION_EXECUTION_PLAN_2026-07-28.md`
- `docs/specs/RISKDETECTED_GLOBAL_LOCALIZATION_COUNTRY_SAFETY_CODEX_IMPLEMENTATION_PLAN_2026-07-28.md`

App Store / phase 8:

- `docs/localization/phase-8/BUILD80_FINAL_SUBMIT_READINESS_2026-08-02.md`
- `docs/localization/phase-8/WAVE1_COMPLETION_MATRIX_2026-08-02_BUILD80.json`
- `docs/localization/phase-8/PHYSICAL_BUILD_80_SMOKE_READINESS_2026-08-02.json`
- `output/app-review-preflight/App_Review_Preflight_Evidence_2026-08-02-build80.md`
- `appstore/plan.json`
- `appstore/app.json`
- `appstore/versions/1.3.0/*.json`
- `appstore/review/app-review-notes.md`
- `appstore/review/localization-evidence.md`
- `appstore/screenshots/final/`

Phase 5 external gates:

- `docs/localization/phase-5/EXTERNAL_RELEASE_GATES_2026-07-30.md`
- `docs/localization/phase-5/PHASE_5_EXTERNAL_GATE_EVIDENCE_2026-07-31.json`
- `docs/localization/phase-5/LEGAL_COUNSEL_APPROVAL_2026-07-31_V2.json`
- `docs/localization/phase-5/NOTIFICATION_COPY_APPROVAL_2026-07-31.json`
- `docs/localization/phase-5/AUTH_EMAIL_HOOK_PRODUCTION_VERIFICATION_2026-07-31.json`

Security:

- `docs/security/CODEX_SECURITY_REMEDIATION_2026-08-01.md`
- `docs/localization/phase-6/SECURITY_REMEDIATION_SUMMARY_2026-07-31.md`

Runtime/localization tests:

- `scripts/localization_phase5_tests.mjs`
- `scripts/localization_catalog_tests.mjs`
- `scripts/localization_profiles_tests.mjs`
- `scripts/verify_wave1_completion_matrix.mjs`
- `scripts/verify_phase5_external_gates.mjs`
- `scripts/app_review_preflight_collect.mjs`
- `scripts/app_store_connect/verify.mjs`

## User approvals and reviewer identity recorded during this wave

User/reviewer:

- Name: Kerem
- Qualification given by user: qualified to evaluate English workplace-safety text.

Approvals recorded:

- English language/safety/product review approved for checksum `3a68229b1860572ff70600287412d3dadf890597698acfc3edb23afc3edb23afc8b9c6932` context.
- Notification copy approved by Kerem.
- Legal sections approved by Kerem.
- Email-related operations approved.
- English screenshots approved; light theme required.
- Turkish screenshots and metadata must remain unchanged unless explicitly requested.

## Known non-blocking warnings

App Store / binary:

- RevenueCat attribution marker strings appear in binary scans.
- AdSupport is not imported.
- Privacy manifests report tracking=false.
- Interpretation: not an App Review blocker; no ATT prompt required unless attribution/tracking is actually enabled later.

ASC validation:

- Subscription promotional images missing: optional warning only.
- Manual release type: info only and intentionally desired.
- App Privacy API publish state may be unverified via public API; browser readback confirms published.

Supabase:

- Leaked password protection warning accepted/deferred.
- Some authenticated security-definer functions are documented as intentional client entry points with internal ownership checks.
- Some permissive policy/performance advisor warnings pre-exist and are not part of the localization blocker set.

## 1.3.0 App Review approval sonrası yapılacaklar

Bu bölüm sadece Apple, `1.3.0 (80)` sürümünü onayladıktan sonra uygulanır.

Onaydan sonra bile canlıya alma otomatik değildir. Bu sürüm App Store Connect tarafında `MANUAL` release olarak hazırlandı. Owner açıkça istemeden:

- production rollout flag açma,
- App Store release yapma,
- RevenueCat/Supabase canlı davranışını değiştirme.

### 0. Başlangıç durumu doğrulama

Önce App Store Connect durumunu read-only doğrula:

```bash
asc review status --app 6769498181 --output markdown
node scripts/app_store_connect/verify.mjs
```

Beklenen onay sonrası durum:

- Review/App Store state artık Apple onaylı bir state göstermeli.
- Version id hâlâ `9a2f5061-8992-4957-a9e8-7b8a96747323` olmalı.
- Build hâlâ `1.3.0 (80)` / `71cc9591-32b9-4fee-b6c4-8c4d30713b23` olmalı.
- Release type hâlâ `MANUAL` olmalı.
- Yeni blocker olmamalı.

Eğer build/version id değiştiyse, hiçbir işlem yapma; önce owner'a raporla.

### 1. Owner onayı al

Owner açıkça şu iki ayrı aksiyonu onaylamalı:

- Activating Build 80/global localization production flags.
- Releasing the manually held App Store version.

Bu iki aksiyon farklıdır. Flag aktivasyonu ve App Store release aynı anda yapılmak zorunda değildir.

### 2. Pre-release son gate çalıştır

Canlı flag veya release öncesi tekrar çalıştır:

```bash
node scripts/app_store_connect/verify.mjs
asc validate --app 6769498181 --version-id 9a2f5061-8992-4957-a9e8-7b8a96747323 --platform IOS --output markdown
asc validate subscriptions --app 6769498181 --output markdown
make localization-wave1-audit
make localization-phase6-test
make localization-test
make localization-phase5-release-gate
bash scripts/localization_release_build_gate.sh
```

Devam şartı:

- blocking/error yok,
- subscription error yok,
- localization-wave1 audit geçiyor,
- Phase 5/6 gate geçiyor.

### 3. Production flag aktivasyon planı

Flag aktivasyonu App Store release'ten ayrı ve kontrollü yapılmalı.

Amaç:

- Build 80+ cihazlarda global localization davranışını açmak.
- Eski canlı buildlerin davranışını bozmayacak build-scope guardları korumak.
- 12-layer multi-photo audit ve `6144` thinking budget kalıcı Build 80+ davranışı olarak sürmeli.

Aktivasyondan önce Supabase tarafında mevcut flag state'i read-only oku. Doğrudan SQL update yapmadan önce ilgili migration/runbook ve mevcut flag JSON'unu incele:

- `docs/localization/phase-5/GLOBAL_LOCALIZATION_BUILD_FLAG_RUNBOOK_2026-07-31.md`
- `supabase/migrations/20260801213000_allow_multi_photo_build_80.sql`
- `supabase/migrations/20260801214500_default_english_international_safety_profile.sql`
- `supabase/migrations/20260801220000_build80_multi_photo_layer_audit.sql`
- `scripts/localization_release_build_gate.sh`
- `scripts/verify_wave1_completion_matrix.mjs`

Read-only DB kontrol için keychain wrapper kullan:

```bash
node scripts/rd_ops_env.mjs status
node scripts/rd_ops_env.mjs supabase db query --linked -o json "select key, value, updated_at from public.app_feature_flags where key ilike '%localization%' or key ilike '%multi_photo%' or key ilike '%build80%' order by key"
```

Not:

- Yukarıdaki SQL sadece okuma içindir.
- Gerçek flag update yapılacaksa önce owner'a hangi key/value değişeceğini düz metin olarak göster.
- Flag update sonrası aynı query ile readback al.

### 4. App Store manual release

Sadece owner açıkça "release et" derse App Store release yapılır.

Release öncesi tekrar doğrula:

```bash
asc review status --app 6769498181 --output markdown
node scripts/app_store_connect/verify.mjs
```

Release komutu, ancak owner onayı sonrası:

```bash
asc versions release --version-id 9a2f5061-8992-4957-a9e8-7b8a96747323 --confirm
```

Release sonrası readback:

```bash
asc review status --app 6769498181 --output markdown
```

Eğer ASC komutu farklı release syntax isterse `asc versions release --help` ile doğrula; tahmin ederek komut çalıştırma.

### 5. Post-release smoke

Release veya flag aktivasyonu sonrası hızlı production smoke:

1. App Store Connect state readback.
2. Supabase Edge Functions active check:

   ```bash
   supabase functions list --project-ref ppcrzemgiztzcgddbins --output json
   ```

3. Public legal/support URL health:

   ```bash
   curl -L -I --max-time 15 https://riskdetected.com/en/privacy
   curl -L -I --max-time 15 https://riskdetected.com/en/terms
   curl -L -I --max-time 15 https://riskdetected.com/en/support
   ```

4. If a Build 80+ device is available:
   - English app language opens correctly.
   - Safety profile defaults to International if onboarding is bypassed.
   - Safety profile selector shows International, UK, US, AU WHS, CA OHS.
   - Paywall prices are StoreKit-localized; no hardcoded/fallback price is shown.
   - One English analysis can complete.
   - PDF/Excel export can open/generate.

Do not spend more Gemini/API money on broad retesting unless there is a concrete failure. One focused production check is enough after already completed Build 80 evidence.

### 6. Monitoring after release

First 24 hours after release:

- Watch App Store Connect status.
- Watch Supabase function logs for `analyze`, `generate-excel-report`, `send-welcome-email`, `auth-send-email-hook`, `revenuecat-webhook`, `sync-revenuecat-subscription`.
- Watch support/contact errors.
- Watch AI usage logs for:
  - provider errors,
  - language validation failures,
  - schema fallback,
  - unexpectedly low finding coverage,
  - non-English output for English requests.
- Watch RevenueCat/Supabase entitlement sync.

Suggested read-only metadata query examples:

```bash
node scripts/rd_ops_env.mjs supabase db query --linked -o json "select provider, http_status, error_code, output_language, output_locale, language_validation_status, client_build, count(*) from public.ai_usage_logs where created_at > now() - interval '24 hours' group by provider, http_status, error_code, output_language, output_locale, language_validation_status, client_build order by count(*) desc"
```

```bash
node scripts/rd_ops_env.mjs supabase db query --linked -o json "select status, app_language, output_language, output_locale, client_build, count(*) from public.analyses where created_at > now() - interval '24 hours' group by status, app_language, output_language, output_locale, client_build order by count(*) desc"
```

Do not query user content, prompts, raw photos, report bodies, or private PII unless the owner explicitly authorizes a scoped incident investigation.

### 7. Rollback / kill-switch posture

If production issues appear:

- Do not delete data.
- Do not roll back broad database migrations manually.
- Prefer build-scoped feature flags / kill switches first.
- Keep Build 80+ localization/multi-photo behavior scoped while preserving old live behavior.
- Record exact incident time, symptoms, affected build, and read-only evidence.

Escalate to owner before any destructive or broad production operation.

### 8. Completion record

After all approved post-review actions are complete, create a short evidence note under:

- `docs/localization/phase-8/`

Suggested filename:

- `BUILD80_POST_APPROVAL_RELEASE_EVIDENCE_YYYY-MM-DD.md`

Include:

- ASC approval state and release state.
- Whether production flags were activated.
- Exact flags changed and readback.
- Smoke checks run.
- Any known warnings.
- Confirmation that Turkish protected metadata/screenshots were not modified unless owner explicitly requested it.
