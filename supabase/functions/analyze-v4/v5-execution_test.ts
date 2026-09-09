// deno-lint-ignore-file no-import-prefix -- Match the pinned Deno std used by the existing suite.
import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.208.0/testing/asserts.ts";
import { resolveVNextConfig } from "../analyze-vnext/compute-profile.ts";
import {
  cancelledPlusTrialRoutingDecision,
  type CancelledPlusTrialSubscription,
} from "../_shared/cancelled-plus-trial-routing.ts";
import { buildTrialPatch } from "../_shared/trial-reminder.ts";
import { type StructuredGeminiResponse, V4ProviderError } from "./provider.ts";
import {
  runV5PhotoAttempt,
  v5AttemptLimit,
  type V5Checkpoint,
  v5ProviderKey,
  V5RetryPending,
} from "./v5-execution.ts";

function snapshot(
  route = "free_legacy",
  plan = "free",
  first: boolean | undefined = false,
) {
  return {
    engine_config: {
      engine_mode: "free",
      v5_free_repeat_enabled: true,
      v5_same_model_retry_enabled: true,
      compute_profile_routing_enabled: true,
      paid_flex_enabled: true,
      primary_model: "gemini-3.5-flash-lite",
    },
    compute_routing: {
      source: "trusted_analyze_enqueue",
      snapshot_version: 1,
      ai_execution_route: route,
      product_plan: plan,
      first_paid_ai_eligible: first,
      provider_pool: "free_standard",
      compute_profile: route === "free_legacy" ? "economy" : "premium",
    },
  };
}

Deno.test("only attested repeat-Free V5 snapshots select Flash Lite free API", () => {
  const input = snapshot();
  const config = resolveVNextConfig(input, 1);
  assertEquals(config.providerPool, "free_standard");
  assertEquals(config.primaryModel, "gemini-3.5-flash-lite");
  assertEquals(config.requestedServiceTier, "standard");
  for (
    const bad of [
      snapshot("free_paid_trial", "free", true),
      snapshot("paid_plan", "plus"),
      snapshot("paid_plan", "pro"),
      snapshot("cancelled_plus_trial_free", "plus"),
      snapshot("free_legacy", "free", true),
      {
        ...input,
        compute_routing: {
          ...input.compute_routing,
          first_paid_ai_eligible: undefined,
        },
      },
      {
        ...input,
        compute_routing: { ...input.compute_routing, source: "client" },
      },
      {
        ...input,
        compute_routing: {
          ...input.compute_routing,
          provider_pool: "paid_flex",
        },
      },
      {
        ...input,
        engine_config: {
          ...input.engine_config,
          v5_free_repeat_enabled: false,
        },
      },
      {
        ...input,
        engine_config: { ...input.engine_config, engine_mode: "contract" },
      },
    ]
  ) {
    assertEquals(
      resolveVNextConfig(bad).providerPool === "free_standard",
      false,
    );
  }
});

Deno.test("legacy free secret aliases stay isolated from paid; no quota key rotation", () => {
  const keys: Record<string, string> = {
    GEMINI_API_KEY: "free",
    GEMINI_API_KEY_PAID: "paid",
    GEMINI_API_KEY_SECONDARY: "secondary",
  };
  assertEquals(v5ProviderKey("free_standard", (name) => keys[name]), "free");
  assertEquals(v5ProviderKey("paid_standard", (name) => keys[name]), "paid");
  delete keys.GEMINI_API_KEY;
  assertEquals(v5ProviderKey("free_standard", (name) => keys[name]), null);
});

function cancelledTrialSnapshot() {
  const input = snapshot("cancelled_plus_trial_free", "plus", true);
  return {
    engine_config: {
      ...input.engine_config,
      v5_cancelled_plus_trial_free_enabled: true,
      v5_free_repeat_enabled: false,
    },
    compute_routing: {
      ...input.compute_routing,
      compute_profile: "economy",
      cancelled_plus_trial_free_candidate: true,
      cancelled_plus_trial_free_enabled: true,
    },
  };
}

Deno.test("attested cancelled PLUS trial uses Free API even on its first analysis", () => {
  const input = cancelledTrialSnapshot();
  for (const count of [1, 2, 3]) {
    const config = resolveVNextConfig(input, count);
    assertEquals(config.providerPool, "free_standard");
    assertEquals(config.primaryModel, "gemini-3.5-flash-lite");
    assertEquals(config.requestedServiceTier, "standard");
    assertEquals(v5AttemptLimit(input, config), 1);
    assertEquals(input.compute_routing.product_plan, "plus");
  }
});

Deno.test("cancelled trial Free pool requires every server attestation and rollout gate", () => {
  const input = cancelledTrialSnapshot();
  for (
    const patch of [
      { source: "client" },
      { snapshot_version: 0 },
      { product_plan: "free" },
      { product_plan: "pro" },
      { ai_execution_route: "paid_plan" },
      { cancelled_plus_trial_free_candidate: false },
      { cancelled_plus_trial_free_candidate: undefined },
      { cancelled_plus_trial_free_enabled: false },
      { cancelled_plus_trial_free_enabled: "true" },
      { provider_pool: "paid_flex" },
    ]
  ) {
    const config = resolveVNextConfig({
      ...input,
      compute_routing: { ...input.compute_routing, ...patch },
    });
    assertEquals(config.providerPool === "free_standard", false);
  }
  for (const enabled of [false, undefined]) {
    const config = resolveVNextConfig({
      ...input,
      engine_config: {
        ...input.engine_config,
        v5_cancelled_plus_trial_free_enabled: enabled,
      },
    });
    assertEquals(config.providerPool === "free_standard", false);
  }
});

Deno.test("trial cancellation and uncancellation change routing without shortening PLUS access", () => {
  const start = "2026-09-06T00:00:00Z";
  const end = "2026-09-13T00:00:00Z";
  const original = {
    tier: "plus",
    status: "active",
    product_id: "riskdetected_plus_yearly",
    trial_product_id: "riskdetected_plus_yearly",
    store: "APP_STORE",
    trial_started_at: start,
    trial_ends_at: end,
    current_period_ends_at: end,
    will_renew: true,
  };
  const decide = (
    subscription: CancelledPlusTrialSubscription,
    now = new Date("2026-09-08T00:00:00Z"),
  ) =>
    cancelledPlusTrialRoutingDecision({
      subscription,
      now,
      userHash: "0123456789ab",
      flag: { mode: "on", userHashes: [] },
    });
  assertEquals(decide(original).enabled, false);
  const cancelled = {
    ...original,
    ...buildTrialPatch(
      "CANCELLATION",
      { product_id: original.product_id },
      original,
    ),
  };
  assertEquals(decide(cancelled).enabled, true);
  assertEquals(cancelled.tier, "plus");
  assertEquals(cancelled.current_period_ends_at, end);
  const restored = {
    ...cancelled,
    ...buildTrialPatch(
      "UNCANCELLATION",
      { product_id: original.product_id },
      cancelled,
    ),
  };
  assertEquals(decide(restored).enabled, false);
  assertEquals(restored.tier, "plus");
  assertEquals(decide(cancelled, new Date(end)).enabled, false);
});

Deno.test("only paid PLUS/PRO get one identical-model retry", () => {
  for (const plan of ["plus", "pro"]) {
    const input = snapshot("paid_plan", plan);
    assertEquals(v5AttemptLimit(input, resolveVNextConfig(input)), 2);
  }
  for (const input of [snapshot(), snapshot("free_paid_trial", "free", true)]) {
    assertEquals(v5AttemptLimit(input, resolveVNextConfig(input)), 1);
  }
});

function response(): StructuredGeminiResponse {
  return {
    text: JSON.stringify({
      scene_summary: "Empty test area.",
      layer_scan: [],
      findings: [],
      positive_controls: [],
    }),
    finishReason: "STOP",
    providerRequestID: "synthetic",
    durationMs: 15,
    httpStatus: 200,
    effectiveServiceTier: "standard",
    usage: {
      inputTokens: 10,
      outputTokens: 20,
      reasoningTokens: 30,
      cachedInputTokens: 0,
      costUSD: 0.001,
      standardEquivalentCostUSD: 0.001,
    },
  };
}

function harness(maxAttempts: 1 | 2 = 2) {
  let saved: V5Checkpoint | undefined;
  let time = 1_000;
  let calls = 0;
  const events: { state: string; number: number; kind: string }[] = [];
  const run = (call: () => Promise<StructuredGeminiResponse>) =>
    runV5PhotoAttempt({
      model: "gemini-3.5-flash-lite",
      identity: "same-prompt-image-settings",
      previous: saved,
      maxAttempts,
      maxOutputTokens: 32768,
      call: () => {
        calls++;
        return call();
      },
      checkpoint: (state) => {
        saved = structuredClone(state);
        return Promise.resolve();
      },
      recordAttempt: (event) => {
        events.push(event);
        return Promise.resolve();
      },
      now: () => time,
    });
  return {
    run,
    events,
    saved: () => saved,
    calls: () => calls,
    advance: () => {
      time += 61_000;
    },
  };
}

Deno.test("transient failure checkpoints, defers, retries once, and reuses completed result", async () => {
  const h = harness();
  await assertRejects(
    () =>
      h.run(() =>
        Promise.reject(
          new V4ProviderError("503", "provider_unavailable", 503, 110000, true),
        )
      ),
    V5RetryPending,
  );
  assertEquals(h.calls(), 1);
  // Queue redelivery before Retry-After must not call Google again.
  await assertRejects(
    () => h.run(() => Promise.resolve(response())),
    V5RetryPending,
  );
  assertEquals(h.calls(), 1);
  h.advance();
  const result = await h.run(() => Promise.resolve(response()));
  assertEquals(result.attemptCount, 2);
  assertEquals(h.calls(), 2);
  await h.run(() => Promise.reject(new Error("must not call completed photo")));
  assertEquals(h.calls(), 2);
  assertEquals(h.events.map((e) => [e.state, e.kind]), [
    ["received", "primary"],
    ["failed", "primary"],
    ["received", "technical_retry"],
    ["persisted", "technical_retry"],
  ]);
});

Deno.test("two failures exhaust paid retry without a third call", async () => {
  const h = harness();
  const fail = () =>
    Promise.reject(
      new V4ProviderError(
        "timeout",
        "provider_transport_error",
        null,
        110000,
        true,
      ),
    );
  await assertRejects(() => h.run(fail), V5RetryPending);
  h.advance();
  await assertRejects(() => h.run(fail), V4ProviderError);
  await assertRejects(() => h.run(fail), Error, "provider_transport_error");
  assertEquals(h.calls(), 2);
});

Deno.test("auth, safety and truncated output do not trigger identical retries", async () => {
  for (const code of ["provider_http_error", "provider_output_blocked"]) {
    const h = harness();
    await assertRejects(
      () =>
        h.run(() =>
          Promise.reject(new V4ProviderError(code, code, 403, 1, false))
        ),
      V4ProviderError,
    );
    assertEquals(h.saved()?.retryable, false);
  }
  const h = harness();
  await assertRejects(
    () =>
      h.run(() =>
        Promise.resolve({
          ...response(),
          text: "{",
          finishReason: "MAX_TOKENS",
        })
      ),
    V4ProviderError,
  );
  assertEquals(h.saved()?.retryable, false);
});

Deno.test("schema retry retains billed failed usage in final totals", async () => {
  const h = harness();
  await assertRejects(
    () => h.run(() => Promise.resolve({ ...response(), text: "{" })),
    V5RetryPending,
  );
  h.advance();
  const result = await h.run(() => Promise.resolve(response()));
  assertEquals(result.usage.inputTokens, 20);
  assertEquals(result.usage.costUSD, 0.002);
});

Deno.test("free repeat failure never silently retries on paid", async () => {
  const h = harness(1);
  await assertRejects(
    () =>
      h.run(() =>
        Promise.reject(
          new V4ProviderError("429", "provider_rate_limited", 429, 1, true),
        )
      ),
    V4ProviderError,
  );
  h.advance();
  await assertRejects(() => h.run(() => Promise.resolve(response())), Error);
  assertEquals(h.calls(), 1);
});

Deno.test("database telemetry failure does not become a provider retry", async () => {
  let calls = 0;
  await assertRejects(
    () =>
      runV5PhotoAttempt({
        model: "gemini-3.5-flash-lite",
        identity: "same",
        previous: undefined,
        maxAttempts: 2,
        maxOutputTokens: 32768,
        call: () => {
          calls++;
          return Promise.resolve(response());
        },
        checkpoint: () => Promise.resolve(),
        recordAttempt: (event) =>
          event.state === "persisted"
            ? Promise.reject(new Error("DB unavailable"))
            : Promise.resolve(),
      }),
    Error,
    "DB unavailable",
  );
  assertEquals(calls, 1);
});

Deno.test("multi-photo redelivery retries only the failed photo", async () => {
  const photos = [harness(), harness(), harness()];
  const first = await Promise.allSettled(
    photos.map((h, i) =>
      h.run(() =>
        i === 1
          ? Promise.reject(
            new V4ProviderError("503", "provider_unavailable", 503, 1, true),
          )
          : Promise.resolve(response())
      )
    ),
  );
  assertEquals(first.map((x) => x.status), [
    "fulfilled",
    "rejected",
    "fulfilled",
  ]);
  photos.forEach((h) => h.advance());
  await Promise.all(
    photos.map((h) => h.run(() => Promise.resolve(response()))),
  );
  assertEquals(photos.map((h) => h.calls()), [1, 2, 1]);
});

Deno.test("checkpoint rejects changed prompt/model/settings rather than spending again", async () => {
  const h = harness();
  await h.run(() => Promise.resolve(response()));
  let calls = 0;
  await assertRejects(
    () =>
      runV5PhotoAttempt({
        model: "gemini-3.5-flash-lite",
        identity: "changed-settings",
        previous: h.saved(),
        maxAttempts: 2,
        maxOutputTokens: 32768,
        call: () => {
          calls++;
          return Promise.resolve(response());
        },
        checkpoint: () => Promise.resolve(),
        recordAttempt: () => Promise.resolve(),
      }),
    Error,
    "v5_checkpoint_identity_mismatch",
  );
  assertEquals(calls, 0);
});
