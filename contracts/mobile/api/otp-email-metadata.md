# Email OTP metadata contract (F6)

**Status:** frozen 2026-08-06, first real content in `contracts/` per Bölüm D.1/D.2 of the
Android plan — written before the Android implementation, not after.

## Why this exists

`auth-send-email-hook` picks the OTP email template (TR/EN) from this metadata. If it's
missing, the hook falls back to legacy Turkish (kept for pre-build-77 iOS compatibility).
Android must send it too, or an English-language user gets a Turkish OTP email — bad UX,
worse in a Play review.

## Source of truth

iOS: `App/Services/AuthService.swift` (`sendEmailOTP`), values from
`App/Services/RDLocalization.swift` (`RDLanguage`) and
`App/Generated/SafetyProfiles.generated.swift` (`RDContentLocale`).

## Contract

Every `auth.signInWithOtp` / `auth.signInWith(OTP)` call, both platforms, must pass this
`data` object:

```json
{
  "app_language": "tr" | "en",
  "content_locale": "tr-TR" | "en-001"
}
```

- `app_language`: the device's resolved app language (`tr` or `en` only — no other values
  are meaningful to the email hook).
- `content_locale`: derived from `app_language`, not independently chosen —
  `app_language == "en"` → `"en-001"`, otherwise → `"tr-TR"`. (`RDContentLocale` has more
  cases — `en-GB`/`en-US`/`en-AU`/`en-CA` — used elsewhere for safety-profile jurisdiction,
  but the OTP email hook only ever receives the two values above; do not send the others here.)

## Test fixture requirement (Faz 3 acceptance)

Per plan Bölüm D.2 rule 4: a Deno fixture test proving an Android-shaped OTP request with
`app_language: "en"` resolves to the English email template must exist before this ships,
mirroring whatever fixture already covers the iOS case (see `auth-send-email-hook` test
suite). Not written yet — this doc exists first, on purpose.
