# AI Output Contract Remediation — 2026-08-21

## Scope

This release candidate addresses repeated user-facing
`OUTPUT_LANGUAGE_CONTRACT_FAILED` responses in Turkish and English-localized
analysis flows. The supported runtime matrix is `tr-TR`, `en-001`, `en-GB`,
`en-US`, `en-AU`, and `en-CA`.

## Production evidence

Three production failures were reconstructed. None was caused by Supabase Edge
runtime availability, quota exhaustion, image quality, or a provider outage.

- A valid `en-US` response was rejected by an English word-ratio heuristic.
- A valid Turkish limitation was rejected by a certainty-expression heuristic.
- In both repair-era cases, the second output was independently valid, but
  repair-integrity drift converted it into a terminal user error.

## Remediation

- Latin-script output is no longer classified with English, Turkish, or foreign
  word lists. Only a substantial incompatible writing-system leak remains a
  high-confidence language signal. Exact user-authored values are excluded.
- Missing preferred profile wording is no longer terminal. Cross-jurisdiction
  terminology, prohibited compliance claims, regulatory-reference policy,
  evidence-only assertions, and JSON structure remain enforced.
- Contract repair transforms the rejected JSON and receives no photo parts. It
  cannot re-run visual interpretation merely to repair prose.
- A repaired output that passes every semantic validator can complete when its
  only remaining problem is repair-integrity drift, provided photo topology is
  stable, findings were not added, and a non-empty result did not become empty.
- If repair transport or semantic validation still fails, a schema-valid first
  output is converted to a locale-reviewed zero-finding result. Rejected model
  prose and findings are removed, photo records are preserved, and analysis
  quota is not consumed.
- Repair transport, integrity drift, salvage, fallback strategy, and aggregate
  provider-request counts are recorded separately.
- The live localization canary uses the same JSON-only repair contract and does
  not resend image assets during repair.

## Remaining terminal boundary

A terminal contract error remains possible only when no schema-valid analysis
exists: both the first output and the single repair fail to produce the minimum
JSON structure required by the analysis pipeline. Semantic language, evidence,
certainty, terminology, and regulatory failures are non-terminal when the first
output is schema-valid.

## Verification

- Full Edge Function suite: 421 passed, 0 failed.
- Localization AI suite: 102 passed, 0 failed.
- Localization profile contract: 17 passed, 0 failed.
- Localization catalog gates: 25 passed, 0 failed.
- `deno check`, scoped `deno lint`, `deno fmt --check`, localization inventory,
  hard-coded copy guard, and `git diff --check` passed.
- The existing Phase 5 external `LEGAL-EN` live-publication gate remains
  blocked and is unrelated to this backend analysis change.

## Deployment impact

No database migration or mobile client build is required. Deploying the
`analyze` Edge Function is sufficient for the runtime change. This record does
not itself authorize or perform a production deployment.
