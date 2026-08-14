import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  cancelledPlusTrialEligibilityReason,
  cancelledPlusTrialRoutingDecision,
  normalizeCancelledPlusTrialRoutingFlag,
} from "./cancelled-plus-trial-routing.ts";

const startedAt = new Date("2026-07-20T10:00:00.000Z");
const endsAt = new Date(startedAt.getTime() + 7 * 24 * 60 * 60 * 1000);
const userHash = "0123456789ab";

const cancelledTrial = {
  tier: "plus",
  status: "active",
  product_id: "riskdetected_plus_yearly",
  current_period_ends_at: endsAt.toISOString(),
  trial_started_at: startedAt.toISOString(),
  trial_ends_at: endsAt.toISOString(),
  trial_product_id: "riskdetected_plus_yearly",
  will_renew: false,
};

Deno.test("cancelled Plus yearly trial is eligible throughout the active window", () => {
  assertEquals(
    cancelledPlusTrialEligibilityReason(
      cancelledTrial,
      new Date(startedAt.getTime() + 10 * 60 * 1000),
    ),
    "enabled",
  );
  assertEquals(
    cancelledPlusTrialEligibilityReason(
      cancelledTrial,
      new Date(startedAt.getTime() + 2 * 24 * 60 * 60 * 1000),
    ),
    "enabled",
  );
  assertEquals(
    cancelledPlusTrialEligibilityReason(
      cancelledTrial,
      new Date(endsAt.getTime() - 1),
    ),
    "enabled",
  );
});

Deno.test("trial end boundary is exclusive", () => {
  assertEquals(
    cancelledPlusTrialEligibilityReason(cancelledTrial, endsAt),
    "trial_expired",
  );
  assertEquals(
    cancelledPlusTrialEligibilityReason(
      cancelledTrial,
      new Date(endsAt.getTime() + 1),
    ),
    "trial_expired",
  );
});

Deno.test("renewing, monthly, Pro and converted subscriptions stay ineligible", () => {
  assertEquals(
    cancelledPlusTrialEligibilityReason(
      { ...cancelledTrial, will_renew: true },
      startedAt,
    ),
    "not_cancelled",
  );
  assertEquals(
    cancelledPlusTrialEligibilityReason(
      {
        ...cancelledTrial,
        product_id: "riskdetected_plus_monthly",
      },
      startedAt,
    ),
    "not_plus_yearly_product",
  );
  assertEquals(
    cancelledPlusTrialEligibilityReason(
      {
        ...cancelledTrial,
        trial_product_id: "RISKDETECTED_PLUS_YEARLY",
      },
      startedAt,
    ),
    "not_plus_yearly_product",
  );
  assertEquals(
    cancelledPlusTrialEligibilityReason(
      { ...cancelledTrial, tier: "pro" },
      startedAt,
    ),
    "not_plus",
  );
  assertEquals(
    cancelledPlusTrialEligibilityReason(
      {
        ...cancelledTrial,
        current_period_ends_at: new Date(
          endsAt.getTime() + 365 * 24 * 60 * 60 * 1000,
        ).toISOString(),
      },
      new Date(startedAt.getTime() + 24 * 60 * 60 * 1000),
    ),
    "period_end_mismatch",
  );
});

Deno.test("missing or inconsistent trial metadata fails closed to paid", () => {
  assertEquals(
    cancelledPlusTrialEligibilityReason(
      { ...cancelledTrial, will_renew: null },
      startedAt,
    ),
    "not_cancelled",
  );
  assertEquals(
    cancelledPlusTrialEligibilityReason(
      { ...cancelledTrial, trial_started_at: null },
      startedAt,
    ),
    "invalid_trial_dates",
  );
  assertEquals(
    cancelledPlusTrialEligibilityReason(
      {
        ...cancelledTrial,
        trial_ends_at: new Date(
          startedAt.getTime() + 30 * 24 * 60 * 60 * 1000,
        ).toISOString(),
        current_period_ends_at: new Date(
          startedAt.getTime() + 30 * 24 * 60 * 60 * 1000,
        ).toISOString(),
      },
      startedAt,
    ),
    "not_seven_day_trial",
  );
});

Deno.test("verified Google Play yearly trial is eligible after cancellation", () => {
  assertEquals(
    cancelledPlusTrialEligibilityReason(
      {
        ...cancelledTrial,
        store: "PLAY_STORE",
        base_plan_id: "yearly",
        offer_id: "seven-day-trial",
        period_type: "TRIAL",
      },
      new Date(startedAt.getTime() + 60 * 60 * 1000),
    ),
    "enabled",
  );
});

Deno.test("Google Play routing requires verified base plan and trial period", () => {
  assertEquals(
    cancelledPlusTrialEligibilityReason(
      {
        ...cancelledTrial,
        store: "PLAY_STORE",
        base_plan_id: null,
        period_type: "TRIAL",
      },
      startedAt,
    ),
    "invalid_play_base_plan",
  );
  assertEquals(
    cancelledPlusTrialEligibilityReason(
      {
        ...cancelledTrial,
        store: "PLAY_STORE",
        base_plan_id: "yearly",
        period_type: "NORMAL",
      },
      startedAt,
    ),
    "not_trial_period",
  );
});

Deno.test("routing flag defaults off and validates anonymous hashes", () => {
  assertEquals(normalizeCancelledPlusTrialRoutingFlag(null), {
    mode: "off",
    userHashes: [],
  });
  assertEquals(
    normalizeCancelledPlusTrialRoutingFlag({
      mode: "allowlist",
      user_hashes: [userHash.toUpperCase(), "invalid", userHash],
    }),
    { mode: "allowlist", userHashes: [userHash] },
  );
});

Deno.test("off, allowlist and on modes gate an otherwise eligible trial", () => {
  const now = new Date(startedAt.getTime() + 60 * 60 * 1000);
  assertEquals(
    cancelledPlusTrialRoutingDecision({
      subscription: cancelledTrial,
      flag: { mode: "off", userHashes: [] },
      userHash,
      now,
    }),
    { eligible: true, enabled: false, mode: "off", reason: "flag_off" },
  );
  assertEquals(
    cancelledPlusTrialRoutingDecision({
      subscription: cancelledTrial,
      flag: { mode: "allowlist", userHashes: [] },
      userHash,
      now,
    }),
    {
      eligible: true,
      enabled: false,
      mode: "allowlist",
      reason: "not_allowlisted",
    },
  );
  assertEquals(
    cancelledPlusTrialRoutingDecision({
      subscription: cancelledTrial,
      flag: { mode: "allowlist", userHashes: [userHash] },
      userHash,
      now,
    }).enabled,
    true,
  );
  assertEquals(
    cancelledPlusTrialRoutingDecision({
      subscription: cancelledTrial,
      flag: { mode: "on", userHashes: [] },
      userHash,
      now,
    }).enabled,
    true,
  );
});
