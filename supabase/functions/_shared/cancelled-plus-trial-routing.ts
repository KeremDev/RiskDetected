import {
  isApproximatelySevenDayTrial,
  PLUS_YEARLY_PRODUCT_ID,
} from "./trial-reminder.ts";

export const CANCELLED_PLUS_TRIAL_ROUTING_FLAG_KEY =
  "cancelled_plus_trial_free_routing";
export const CANCELLED_PLUS_TRIAL_ROUTE = "cancelled_plus_trial_free";
export const TRIAL_PERIOD_END_TOLERANCE_MS = 5 * 60 * 1000;

const ACTIVE_SUBSCRIPTION_STATUSES = new Set([
  "active",
  "trialing",
  "grace_period",
]);

export type CancelledPlusTrialRoutingMode = "off" | "allowlist" | "on";

export type CancelledPlusTrialRoutingFlag = {
  mode: CancelledPlusTrialRoutingMode;
  userHashes: string[];
};

export type CancelledPlusTrialSubscription = {
  tier?: string | null;
  status?: string | null;
  product_id?: string | null;
  current_period_ends_at?: string | null;
  trial_started_at?: string | null;
  trial_ends_at?: string | null;
  trial_product_id?: string | null;
  will_renew?: boolean | null;
};

export type CancelledPlusTrialRoutingReason =
  | "enabled"
  | "flag_off"
  | "not_allowlisted"
  | "missing_subscription"
  | "not_plus"
  | "inactive_subscription"
  | "not_plus_yearly_product"
  | "not_cancelled"
  | "invalid_trial_dates"
  | "not_seven_day_trial"
  | "trial_not_started"
  | "trial_expired"
  | "subscription_period_expired"
  | "period_end_mismatch";

export type CancelledPlusTrialRoutingDecision = {
  eligible: boolean;
  enabled: boolean;
  mode: CancelledPlusTrialRoutingMode;
  reason: CancelledPlusTrialRoutingReason;
};

function recordValue(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function normalizeUserHashes(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return [
    ...new Set(
      value
        .map((item) => String(item ?? "").trim().toLowerCase())
        .filter((item) => /^[0-9a-f]{12}$/.test(item)),
    ),
  ];
}

export function normalizeCancelledPlusTrialRoutingFlag(
  value: unknown,
): CancelledPlusTrialRoutingFlag {
  const record = recordValue(value);
  const rawMode = typeof record.mode === "string"
    ? record.mode.trim().toLowerCase()
    : "off";
  const mode: CancelledPlusTrialRoutingMode = rawMode === "on" ||
      rawMode === "allowlist"
    ? rawMode
    : "off";

  return {
    mode,
    userHashes: normalizeUserHashes(record.user_hashes),
  };
}

function parsedTimestamp(value: string | null | undefined): number | null {
  if (!value) return null;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

export function cancelledPlusTrialEligibilityReason(
  subscription: CancelledPlusTrialSubscription | null,
  now = new Date(),
): CancelledPlusTrialRoutingReason {
  if (!subscription) return "missing_subscription";
  if (subscription.tier !== "plus") return "not_plus";
  if (!ACTIVE_SUBSCRIPTION_STATUSES.has(String(subscription.status ?? ""))) {
    return "inactive_subscription";
  }
  if (
    subscription.product_id !== PLUS_YEARLY_PRODUCT_ID ||
    subscription.trial_product_id !== PLUS_YEARLY_PRODUCT_ID
  ) {
    return "not_plus_yearly_product";
  }
  if (subscription.will_renew !== false) return "not_cancelled";

  const trialStartedAt = parsedTimestamp(subscription.trial_started_at);
  const trialEndsAt = parsedTimestamp(subscription.trial_ends_at);
  const currentPeriodEndsAt = parsedTimestamp(
    subscription.current_period_ends_at,
  );
  if (
    trialStartedAt == null || trialEndsAt == null ||
    currentPeriodEndsAt == null
  ) {
    return "invalid_trial_dates";
  }
  if (
    !isApproximatelySevenDayTrial(
      subscription.trial_started_at,
      subscription.trial_ends_at,
    )
  ) {
    return "not_seven_day_trial";
  }

  const nowMs = now.getTime();
  if (!Number.isFinite(nowMs)) return "invalid_trial_dates";
  if (nowMs < trialStartedAt) return "trial_not_started";
  if (nowMs >= trialEndsAt) return "trial_expired";
  if (nowMs >= currentPeriodEndsAt) return "subscription_period_expired";
  if (
    Math.abs(trialEndsAt - currentPeriodEndsAt) >
      TRIAL_PERIOD_END_TOLERANCE_MS
  ) {
    return "period_end_mismatch";
  }
  return "enabled";
}

export function cancelledPlusTrialRoutingDecision(params: {
  subscription: CancelledPlusTrialSubscription | null;
  flag: CancelledPlusTrialRoutingFlag;
  userHash: string;
  now?: Date;
}): CancelledPlusTrialRoutingDecision {
  const eligibilityReason = cancelledPlusTrialEligibilityReason(
    params.subscription,
    params.now,
  );
  if (eligibilityReason !== "enabled") {
    return {
      eligible: false,
      enabled: false,
      mode: params.flag.mode,
      reason: eligibilityReason,
    };
  }
  if (params.flag.mode === "off") {
    return {
      eligible: true,
      enabled: false,
      mode: params.flag.mode,
      reason: "flag_off",
    };
  }
  if (
    params.flag.mode === "allowlist" &&
    !params.flag.userHashes.includes(params.userHash.toLowerCase())
  ) {
    return {
      eligible: true,
      enabled: false,
      mode: params.flag.mode,
      reason: "not_allowlisted",
    };
  }
  return {
    eligible: true,
    enabled: true,
    mode: params.flag.mode,
    reason: "enabled",
  };
}
