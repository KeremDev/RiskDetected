# Free API verification — 2026-09-06

## Subsequent authorized activation and hosted verification

After the initial checks below, the owner explicitly requested activation after
being informed of quota and provider data restrictions. Migration 20260905232257
was applied; worker v50 was deployed before analyze-v4 v96. Authentication
settings were preserved and the routing RPC remains service-role-only.
Only `v5_free_repeat_enabled` was enabled. Paid retry remains disabled.

`scripts/hosted_free_repeat_canary.mjs` created an isolated QA user and a labelled
prior-completed eligibility fixture, then uploaded a synthetic image and called
the normal analyze endpoint with build 88 / contract 3. The real hosted queue
completed analysis `9ab6a329-2dbd-4d30-863a-95df2f169b55`:

- Server-pinned route: free_legacy / free_standard / first_paid_ai_eligible=false.
- Actual provider telemetry: gemini-3.5-flash-lite, HTTP 200, 14,311 ms,
  attempt 1 persisted, cost_usd=0.
- One finding; one completed analysis_standard quota record; worker attempt 1;
  claim and lease released.
- First-Free, repeat-Free, PLUS and PRO database routing assertions passed in a
  rolled-back transaction. No extra inference was sent for those assertions.

QA user `034f0099-55b8-4efd-a5b6-758556ca060a`, labelled fixture and synthetic
analysis are retained for trace inspection. No customer records were used for
the canary. This is one additional hosted inference beyond the two initial API
tests below. Existing build allowlists and in-flight snapshots were preserved.
No commit or push was performed. Remaining hosted retry/fault-injection gaps
below still apply; the earlier statement that routing was not activated is
superseded by this section.

## Actual external checks

Authenticated Google AI Studio showed RiskDetected Gemini,
`gen-lang-client-0277913590`, as **Free tier** with Set up billing available.
The key copied from that project's key row matched the SHA-256 digest of the
production Supabase `GEMINI_API_KEY` secret. It did not match the paid or secondary
secret. Key values were kept in memory, not printed or committed; the clipboard
was cleared after testing.

| Check | Observed result |
| --- | --- |
| Model metadata using actual Free key | HTTP 200 for gemini-3.5-flash-lite |
| Synthetic text inference | HTTP 200; 1,915 ms; STOP; valid JSON |
| Synthetic image with application provider, V5 prompt/schema/parser | HTTP 200; 14,821 ms; STOP; 19 layers; one finding |
| AI Studio project usage | Two requests visible; no API errors displayed |
| Flash Lite quota displayed | 15 RPM; 250,000 TPM; 500 RPD, shared project limits |

The image was an artificial illustration of boxes and a cable crossing a marked
walkway, explicitly labelled synthetic. No customer photograph or personal data
was sent. Image inference reported 9,771 input tokens (including 2,160 image
tokens), 1,160 output tokens and 3,116 reasoning tokens. The application's
billing-aware estimator returned zero Free cost and USD 0.0136213 Standard
equivalent; this estimator is not an independent Google billing statement.

Manual canary: `scripts/free_api_release_canary.ts`. It requires explicit
`RD_ALLOW_SYNTHETIC_FREE_CANARY=1`, a valid key on the local clipboard and the
synthetic image at `/tmp/rd-free-synthetic-scene.png`. It writes no analysis or
quota records. The temporary image must be recreated if removed.

## Controlled tests, not real Google outages

35 tests passed, zero failed, across:

- `analyze-v4/v5-execution_test.ts`
- `analyze-v4/provider_billing_test.ts`
- `analyze-vnext/compute-profile_test.ts`
- `process-analysis-jobs/dispatch-policy_test.ts`

These cover trusted repeat-Free routing, first/old/untrusted snapshots retaining
paid routing, identical PLUS/PRO retry, simulated 503 and timeout, terminal Free
429 without paid fallback, checkpoint reuse, multi-photo partial failure,
redelivery limits, changed-request rejection and failed-attempt usage handling.
Network access was disabled for these tests. They are isolated tests, not proof
of hosted queue execution or actual provider timeout behavior.

## Initial pre-activation release gates (historical)

- Pending Free/retry migration, worker and engine have not been deployed in this
  verification. Production routing flags were not changed.
- Hosted queue/lease/retry/quota behavior still needs a synthetic end-to-end run
  after compatible staged deployment. Local tests do not replace that check.
- The real Google account was not deliberately exhausted to trigger 429, and
  Google 503/timeouts were not induced. No new paid inference was performed here.
- One synthetic image verifies integration, not real-world risk-analysis quality.
- Shared project quotas require capacity planning before broad rollout.
- Google unpaid-service terms prohibit submission of sensitive, confidential or
  personal information; API clients available in EEA, Switzerland or the UK
  require paid services. A successful API call does not establish eligibility
  for customer workplace data. Keep customer routing unchanged until resolved.

Primary references reviewed: [Google API terms](https://ai.google.dev/gemini-api/terms)
and [Flash Lite model documentation](https://ai.google.dev/gemini-api/docs/models/gemini-3.5-flash-lite).

No commit, push or production routing activation was performed in this check.
