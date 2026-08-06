# `client_capabilities` contract (F5)

**Status:** frozen 2026-08-07, mirrors the live iOS contract exactly.

## Why this exists

`analyze/index.ts`'s `parseClientReleaseContext` reads `client_capabilities` off every request
body — a client that omits a key is treated as `false` for that capability (fail-closed), not
"same as some other client". A multi-photo request without
`client_capabilities.multi_photo_coverage_v2=true` silently falls back to the legacy
`hazards[]` flow — no error, just quietly worse output. Android must send the same keys iOS
does, correctly, from day one of calling `analyze`.

## Source of truth

iOS: `App/Services/AnalysisService.swift`, `AppClientMetadata` enum (also used identically by
`generate-excel-report` and `register-report` calls, not just `analyze`).

## Contract

Every call to `analyze` / `generate-excel-report` / `register-report`, both platforms, sends:

```json
{
  "client_app_build": "<iOS CFBundleVersion | Android versionCode, as a string>",
  "client_platform": "ios" | "android",
  "client_capabilities": {
    "multi_photo_analysis": true,
    "multi_photo_coverage_v2": true,
    "editable_findings": true,
    "report_snapshot_v2": true,
    "global_localization_wave1": false
  }
}
```

`api_contract_version` is sent as an integer alongside these (currently `2` on iOS) — not part
of `client_capabilities` itself, but always present on the same request.

### Per-key notes

- `multi_photo_analysis`, `multi_photo_coverage_v2`, `editable_findings`,
  `report_snapshot_v2`: always `true` on iOS today (the capability has fully shipped) —
  Android should send `true` for these once the corresponding client-side feature actually
  exists; sending `true` before the feature is built just means the backend *would* route to
  the new-format flow with nothing on the client ready to render it. Sequence capability
  flags with the feature they gate, not ahead of it.
- `global_localization_wave1`: on iOS this is conditional
  (`RDGlobalLocalizationBuildGate.isCompiledIn` — a compile-time gate, not a runtime flag).
  Android has no equivalent build-gate infrastructure yet; `core:common`'s `RdClientMetadata`
  hardcodes this `false` until Android's localization pipeline exists (master §23.1) — do not
  flip it to `true` without also building the gate iOS has, or Android risks requesting
  localization-wave1 behavior the client can't actually render correctly.

## Test fixture requirement (Faz 5 acceptance, per plan Bölüm D.2 rule 4)

A Deno fixture proving `client_platform: "android"` + this exact capability shape resolves
through `analyze`'s multi-photo release gate the same way an equivalent iOS request does (both
respecting the *_ios_builds vs *_android_version_codes allowlists per F3) must exist before
Android's analysis submit ships. Not written yet.
