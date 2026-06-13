import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  clearTrialReminderMetadataPatch,
  PLUS_YEARLY_PRODUCT_ID,
  revenueCatTimestampToISO,
  trialMetadataPatchForRevenueCatEvent,
  trialReminderDecision,
} from "./trial-reminder.ts";

const now = new Date("2026-06-13T09:00:00.000Z");
const in47Hours = new Date(now.getTime() + 47 * 60 * 60 * 1000);
const in50Hours = new Date(now.getTime() + 50 * 60 * 60 * 1000);
const in23Hours = new Date(now.getTime() + 23 * 60 * 60 * 1000);

Deno.test("RevenueCat millisecond timestamps normalize to ISO", () => {
  assertEquals(
    revenueCatTimestampToISO(1_780_000_000_000),
    new Date(1_780_000_000_000).toISOString(),
  );
  assertEquals(revenueCatTimestampToISO(""), null);
});

Deno.test("Plus yearly trial INITIAL_PURCHASE creates trial reminder metadata", () => {
  const patch = trialMetadataPatchForRevenueCatEvent("INITIAL_PURCHASE", {
    product_id: PLUS_YEARLY_PRODUCT_ID,
    period_type: "TRIAL",
    purchased_at_ms: now.getTime(),
    expiration_at_ms: in47Hours.getTime(),
  });

  assertEquals(patch, {
    trial_started_at: now.toISOString(),
    trial_ends_at: in47Hours.toISOString(),
    trial_product_id: PLUS_YEARLY_PRODUCT_ID,
    will_renew: true,
    trial_reminder_sent_at: null,
    trial_reminder_last_attempt_at: null,
    trial_reminder_status: null,
    trial_reminder_notification_event_id: null,
  });
});

Deno.test("Non-trial purchases do not create trial reminder metadata", () => {
  assertEquals(
    trialMetadataPatchForRevenueCatEvent("INITIAL_PURCHASE", {
      product_id: PLUS_YEARLY_PRODUCT_ID,
      period_type: "NORMAL",
      expiration_at_ms: in47Hours.getTime(),
    }),
    null,
  );
});

Deno.test("Trial metadata can use verified subscriber expiration fallback", () => {
  const patch = trialMetadataPatchForRevenueCatEvent(
    "INITIAL_PURCHASE",
    {
      product_id: PLUS_YEARLY_PRODUCT_ID,
      period_type: "TRIAL",
    },
    PLUS_YEARLY_PRODUCT_ID,
    in47Hours.toISOString(),
    now.toISOString(),
  );

  assertEquals(patch?.trial_started_at, now.toISOString());
  assertEquals(patch?.trial_ends_at, in47Hours.toISOString());
  assertEquals(patch?.will_renew, true);
});

Deno.test("Cancellation and uncancellation toggle renewal intent", () => {
  assertEquals(
    trialMetadataPatchForRevenueCatEvent("CANCELLATION", {
      product_id: PLUS_YEARLY_PRODUCT_ID,
    }),
    { will_renew: false },
  );
  assertEquals(
    trialMetadataPatchForRevenueCatEvent("UNCANCELLATION", {
      product_id: PLUS_YEARLY_PRODUCT_ID,
    }),
    { will_renew: true },
  );
});

Deno.test("Renewal clears stale trial reminder metadata", () => {
  assertEquals(
    trialMetadataPatchForRevenueCatEvent("RENEWAL", {
      product_id: PLUS_YEARLY_PRODUCT_ID,
    }),
    clearTrialReminderMetadataPatch(),
  );
});

Deno.test("Trial reminder candidate is due only in the 24-48 hour window", () => {
  const baseCandidate = {
    user_id: "11111111-1111-4111-8111-111111111111",
    tier: "plus",
    status: "active",
    product_id: PLUS_YEARLY_PRODUCT_ID,
    trial_product_id: PLUS_YEARLY_PRODUCT_ID,
    will_renew: true,
    trial_reminder_sent_at: null,
    trial_reminder_last_attempt_at: null,
  };

  assertEquals(
    trialReminderDecision({
      ...baseCandidate,
      trial_ends_at: in47Hours.toISOString(),
    }, now),
    { due: true, reason: "due" },
  );
  assertEquals(
    trialReminderDecision({
      ...baseCandidate,
      trial_ends_at: in50Hours.toISOString(),
    }, now),
    { due: false, reason: "too_early" },
  );
  assertEquals(
    trialReminderDecision({
      ...baseCandidate,
      trial_ends_at: in23Hours.toISOString(),
    }, now),
    { due: false, reason: "too_late" },
  );
});

Deno.test("Trial reminder candidate excludes cancelled, sent and throttled rows", () => {
  const candidate = {
    user_id: "11111111-1111-4111-8111-111111111111",
    tier: "plus",
    status: "active",
    product_id: PLUS_YEARLY_PRODUCT_ID,
    trial_product_id: PLUS_YEARLY_PRODUCT_ID,
    trial_ends_at: in47Hours.toISOString(),
  };

  assertEquals(
    trialReminderDecision({ ...candidate, will_renew: false }, now),
    { due: false, reason: "will_not_renew" },
  );
  assertEquals(
    trialReminderDecision({
      ...candidate,
      will_renew: true,
      trial_reminder_sent_at: now.toISOString(),
    }, now),
    { due: false, reason: "already_sent" },
  );
  assertEquals(
    trialReminderDecision({
      ...candidate,
      will_renew: true,
      trial_reminder_last_attempt_at: new Date(
        now.getTime() - 30 * 60 * 1000,
      ).toISOString(),
    }, now),
    { due: false, reason: "retry_throttled" },
  );
});

Deno.test("Plus monthly and Pro products are excluded", () => {
  assertEquals(
    trialReminderDecision({
      user_id: "11111111-1111-4111-8111-111111111111",
      tier: "plus",
      status: "active",
      product_id: "riskdetected_plus_monthly",
      trial_product_id: "riskdetected_plus_monthly",
      trial_ends_at: in47Hours.toISOString(),
      will_renew: true,
    }, now),
    { due: false, reason: "not_plus_yearly_trial" },
  );
  assertEquals(
    trialReminderDecision({
      user_id: "11111111-1111-4111-8111-111111111111",
      tier: "pro",
      status: "active",
      product_id: "riskdetected_pro_yearly",
      trial_product_id: "riskdetected_pro_yearly",
      trial_ends_at: in47Hours.toISOString(),
      will_renew: true,
    }, now),
    { due: false, reason: "not_plus" },
  );
});
