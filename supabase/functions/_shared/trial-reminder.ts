export const PLUS_YEARLY_PRODUCT_ID = "riskdetected_plus_yearly";
export const TRIAL_LENGTH_DAYS = 7;
export const TRIAL_REMINDER_TARGET_DAY = 5;

export const TRIAL_REMINDER_KIND = "trial_reminder";
export const TRIAL_REMINDER_TITLE = "Detaylı Analiz 2 gün sonra kalıcı oluyor";
export const TRIAL_REMINDER_BODY =
  "Plus yıllık planınla detaylı tehlike analizleri ve paylaşılabilir raporların kesintisiz sürer. Vazgeçersen App Store > Abonelikler'den iptal edebilirsin.";

export const TRIAL_REMINDER_MIN_LEAD_MS = 24 * 60 * 60 * 1000;
export const TRIAL_REMINDER_MAX_LEAD_MS = 48 * 60 * 60 * 1000;
export const TRIAL_REMINDER_RETRY_AFTER_MS = 12 * 60 * 60 * 1000;

export type TrialReminderStatus =
  | "pending"
  | "sent"
  | "skipped"
  | "failed"
  | "inactive";

export type TrialMetadataPatch = {
  trial_started_at?: string | null;
  trial_ends_at?: string | null;
  trial_product_id?: string | null;
  will_renew?: boolean | null;
  trial_reminder_sent_at?: string | null;
  trial_reminder_last_attempt_at?: string | null;
  trial_reminder_status?: TrialReminderStatus | null;
  trial_reminder_notification_event_id?: string | null;
};

export type ExistingSubscriptionRow = {
  trial_started_at?: string | null;
  trial_ends_at?: string | null;
  trial_product_id?: string | null;
  will_renew?: boolean | null;
  trial_reminder_sent_at?: string | null;
  trial_reminder_last_attempt_at?: string | null;
  trial_reminder_status?: string | null;
  trial_reminder_notification_event_id?: string | null;
};

export type TrialReminderCandidate = {
  user_id?: string | null;
  tier?: string | null;
  status?: string | null;
  product_id?: string | null;
  trial_product_id?: string | null;
  trial_ends_at?: string | null;
  will_renew?: boolean | null;
  trial_reminder_sent_at?: string | null;
  trial_reminder_last_attempt_at?: string | null;
};

export type TrialReminderDecision = {
  due: boolean;
  reason:
    | "due"
    | "missing_user_id"
    | "not_plus"
    | "inactive_subscription"
    | "not_plus_yearly_trial"
    | "will_not_renew"
    | "already_sent"
    | "invalid_trial_end"
    | "too_late"
    | "too_early"
    | "retry_throttled";
};

const ACTIVE_SUBSCRIPTION_STATUSES = new Set([
  "active",
  "trialing",
  "grace_period",
]);

function stringValue(
  event: Record<string, unknown>,
  keys: string[],
): string | null {
  for (const key of keys) {
    const value = event[key];
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  return null;
}

export function isPlusYearlyProduct(productID: string | null | undefined) {
  return productID?.trim().toLowerCase() === PLUS_YEARLY_PRODUCT_ID;
}

export function revenueCatEventProductID(
  event: Record<string, unknown>,
): string | null {
  return stringValue(event, [
    "product_id",
    "product_identifier",
    "productIdentifier",
  ]);
}

export function revenueCatEventPeriodType(
  event: Record<string, unknown>,
): string | null {
  return stringValue(event, ["period_type", "periodType"])?.toUpperCase() ??
    null;
}

export function revenueCatTimestampToISO(value: unknown): string | null {
  const timestamp = typeof value === "number"
    ? value
    : typeof value === "string" && value.trim()
    ? Number(value)
    : NaN;
  if (!Number.isFinite(timestamp) || timestamp <= 0) return null;
  const date = new Date(timestamp);
  return Number.isFinite(date.getTime()) ? date.toISOString() : null;
}

function dateStringToISO(value: string | null | undefined): string | null {
  if (!value) return null;
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date.toISOString() : null;
}

export function isApproximatelySevenDayTrial(
  startedAt: string | null | undefined,
  endsAt: string | null | undefined,
): boolean {
  if (!startedAt || !endsAt) return false;
  const startedMs = Date.parse(startedAt);
  const endsMs = Date.parse(endsAt);
  if (!Number.isFinite(startedMs) || !Number.isFinite(endsMs)) return false;
  const durationDays = (endsMs - startedMs) / (24 * 60 * 60 * 1000);
  return durationDays >= TRIAL_LENGTH_DAYS - 1 &&
    durationDays <= TRIAL_LENGTH_DAYS + 1.5;
}

export function isPlusYearlyTrialPeriod(
  event: Record<string, unknown>,
  productID?: string | null,
): boolean {
  const resolvedProductID = revenueCatEventProductID(event) ?? productID ??
    null;
  if (!isPlusYearlyProduct(resolvedProductID)) return false;

  const periodType = revenueCatEventPeriodType(event);
  if (periodType === "TRIAL" || periodType === "INTRO") return true;
  if (event.is_trial_period === true) return true;

  const purchasedAt = revenueCatTimestampToISO(
    event.purchased_at_ms ?? event.purchase_at_ms ?? event.event_timestamp_ms,
  );
  const endsAt = revenueCatTimestampToISO(
    event.expiration_at_ms ?? event.expires_at_ms,
  );
  return isApproximatelySevenDayTrial(purchasedAt, endsAt);
}

export function resolveWillRenew(event: Record<string, unknown>): boolean {
  if (event.auto_renew_status === false) return false;
  if (event.auto_renew_status === true) return true;
  if (
    typeof event.unsubscribe_detected_at === "string" &&
    event.unsubscribe_detected_at.trim()
  ) {
    return false;
  }
  return true;
}

export type VerifiedRevenueCatSubscriptionTrialState = {
  productID?: string | null;
  periodType?: string | null;
  purchaseDate?: string | null;
  expiration?: string | null;
  renewalIntent?: boolean | null;
};

/**
 * RevenueCat's subscriber snapshot uses the presence of
 * `unsubscribe_detected_at` to expose current renewal intent. Keeping this
 * tri-state prevents an omitted field from being mistaken for an uncancel.
 */
export function revenueCatSubscriptionRenewalIntent(
  subscription: Record<string, unknown>,
): boolean | null {
  if (
    !Object.prototype.hasOwnProperty.call(
      subscription,
      "unsubscribe_detected_at",
    )
  ) {
    return null;
  }
  const value = subscription.unsubscribe_detected_at;
  if (value === null || value === "") return true;
  if (typeof value === "string" && value.trim()) return false;
  return null;
}

export function verifiedTrialMetadataPatch(
  state: VerifiedRevenueCatSubscriptionTrialState,
  existing: ExistingSubscriptionRow | null,
): TrialMetadataPatch | null {
  const periodType = state.periodType?.trim().toUpperCase() ?? null;
  const verifiedStartedAt = dateStringToISO(state.purchaseDate);
  const verifiedEndsAt = dateStringToISO(state.expiration);
  const verifiedSevenDayTrial = isApproximatelySevenDayTrial(
    verifiedStartedAt,
    verifiedEndsAt,
  );
  const currentTrial = isPlusYearlyProduct(state.productID) &&
    (periodType === "TRIAL" || periodType === "INTRO" ||
      verifiedSevenDayTrial);
  const historicalTrial = isPlusYearlyProduct(existing?.trial_product_id) &&
    isApproximatelySevenDayTrial(
      existing?.trial_started_at,
      existing?.trial_ends_at,
    );

  if (!currentTrial && !historicalTrial) return null;

  const patch: TrialMetadataPatch = {};
  if (currentTrial && verifiedSevenDayTrial) {
    patch.trial_product_id = PLUS_YEARLY_PRODUCT_ID;
    patch.trial_started_at = verifiedStartedAt;
    patch.trial_ends_at = verifiedEndsAt;
  }
  if (state.renewalIntent !== null && state.renewalIntent !== undefined) {
    patch.will_renew = state.renewalIntent;
  }
  return Object.keys(patch).length > 0 ? patch : null;
}

export function mergeTrialMetadataPatches(
  eventPatch: TrialMetadataPatch | null,
  verifiedPatch: TrialMetadataPatch | null,
): TrialMetadataPatch | null {
  if (!eventPatch && !verifiedPatch) return null;
  return {
    ...(eventPatch ?? {}),
    ...(verifiedPatch ?? {}),
  };
}

/** Transfer / deactivate: wipe subscription trial state entirely. */
export function clearTrialReminderMetadataPatch(): TrialMetadataPatch {
  return {
    trial_started_at: null,
    trial_ends_at: null,
    trial_product_id: null,
    will_renew: null,
    trial_reminder_sent_at: null,
    trial_reminder_last_attempt_at: null,
    trial_reminder_status: "inactive",
    trial_reminder_notification_event_id: null,
  };
}

function initialTrialPatch(
  event: Record<string, unknown>,
  verifiedExpiration?: string | null,
  verifiedPurchaseDate?: string | null,
): TrialMetadataPatch | null {
  const trialEndsAt = revenueCatTimestampToISO(
    event.expiration_at_ms ?? event.expires_at_ms,
  ) ?? dateStringToISO(verifiedExpiration);
  const trialStartedAt = revenueCatTimestampToISO(
    event.purchased_at_ms ?? event.purchase_at_ms ?? event.event_timestamp_ms,
  ) ?? dateStringToISO(verifiedPurchaseDate);

  if (!trialEndsAt || !trialStartedAt) return null;

  return {
    trial_product_id: PLUS_YEARLY_PRODUCT_ID,
    trial_started_at: trialStartedAt,
    trial_ends_at: trialEndsAt,
    will_renew: resolveWillRenew(event),
    trial_reminder_sent_at: null,
    trial_reminder_last_attempt_at: null,
    trial_reminder_status: null,
    trial_reminder_notification_event_id: null,
  };
}

export function buildTrialPatch(
  eventType: string,
  event: Record<string, unknown>,
  existing: ExistingSubscriptionRow | null,
  verifiedProductID?: string | null,
  verifiedExpiration?: string | null,
  verifiedPurchaseDate?: string | null,
): TrialMetadataPatch | null {
  const normalizedType = eventType.toUpperCase();
  const productID = revenueCatEventProductID(event) ?? verifiedProductID ??
    null;
  const isTrialConversion = event.is_trial_conversion === true;

  if (normalizedType === "CANCELLATION") {
    if (
      !isPlusYearlyProduct(productID) &&
      !isPlusYearlyProduct(existing?.trial_product_id)
    ) {
      return null;
    }
    return { will_renew: false };
  }

  if (normalizedType === "UNCANCELLATION") {
    if (
      !isPlusYearlyProduct(productID) &&
      !isPlusYearlyProduct(existing?.trial_product_id)
    ) {
      return null;
    }
    return { will_renew: true };
  }

  if (normalizedType === "RENEWAL") {
    if (
      !isPlusYearlyProduct(productID) &&
      !isPlusYearlyProduct(existing?.trial_product_id)
    ) {
      return null;
    }
    // Trial → paid: keep historical trial_* columns for admin reporting.
    return { will_renew: resolveWillRenew(event) };
  }

  if (normalizedType === "EXPIRATION") {
    if (!existing?.trial_started_at && !isPlusYearlyProduct(productID)) {
      return null;
    }
    return { trial_reminder_status: "inactive" };
  }

  if (normalizedType === "PRODUCT_CHANGE") {
    if (isPlusYearlyTrialPeriod(event, productID) && !isTrialConversion) {
      return initialTrialPatch(event, verifiedExpiration, verifiedPurchaseDate);
    }
    if (
      isPlusYearlyProduct(productID) ||
      isPlusYearlyProduct(existing?.trial_product_id)
    ) {
      return { will_renew: resolveWillRenew(event) };
    }
    return null;
  }

  if (!isPlusYearlyProduct(productID)) return null;

  if (
    normalizedType === "INITIAL_PURCHASE" &&
    isPlusYearlyTrialPeriod(event, productID) &&
    !isTrialConversion
  ) {
    return initialTrialPatch(event, verifiedExpiration, verifiedPurchaseDate);
  }

  return null;
}

export function trialMetadataPatchForRevenueCatEvent(
  eventType: string,
  event: Record<string, unknown>,
  verifiedProductID?: string | null,
  verifiedExpiration?: string | null,
  verifiedPurchaseDate?: string | null,
  existing?: ExistingSubscriptionRow | null,
): TrialMetadataPatch | null {
  return buildTrialPatch(
    eventType,
    event,
    existing ?? null,
    verifiedProductID,
    verifiedExpiration,
    verifiedPurchaseDate,
  );
}

export function trialReminderDecision(
  candidate: TrialReminderCandidate,
  now = new Date(),
  options: {
    minLeadMs?: number;
    maxLeadMs?: number;
    retryAfterMs?: number;
  } = {},
): TrialReminderDecision {
  const minLeadMs = options.minLeadMs ?? TRIAL_REMINDER_MIN_LEAD_MS;
  const maxLeadMs = options.maxLeadMs ?? TRIAL_REMINDER_MAX_LEAD_MS;
  const retryAfterMs = options.retryAfterMs ??
    TRIAL_REMINDER_RETRY_AFTER_MS;

  if (!candidate.user_id) return { due: false, reason: "missing_user_id" };
  if (candidate.tier !== "plus") return { due: false, reason: "not_plus" };
  if (!ACTIVE_SUBSCRIPTION_STATUSES.has(String(candidate.status ?? ""))) {
    return { due: false, reason: "inactive_subscription" };
  }
  if (
    !isPlusYearlyProduct(candidate.trial_product_id) &&
    !isPlusYearlyProduct(candidate.product_id)
  ) {
    return { due: false, reason: "not_plus_yearly_trial" };
  }
  if (candidate.will_renew === false) {
    return { due: false, reason: "will_not_renew" };
  }
  if (candidate.trial_reminder_sent_at) {
    return { due: false, reason: "already_sent" };
  }

  const trialEndsAt = Date.parse(candidate.trial_ends_at ?? "");
  if (!Number.isFinite(trialEndsAt)) {
    return { due: false, reason: "invalid_trial_end" };
  }

  const leadMs = trialEndsAt - now.getTime();
  if (leadMs <= minLeadMs) return { due: false, reason: "too_late" };
  if (leadMs > maxLeadMs) return { due: false, reason: "too_early" };

  if (candidate.trial_reminder_last_attempt_at) {
    const lastAttemptAt = Date.parse(candidate.trial_reminder_last_attempt_at);
    if (
      Number.isFinite(lastAttemptAt) &&
      now.getTime() - lastAttemptAt < retryAfterMs
    ) {
      return { due: false, reason: "retry_throttled" };
    }
  }

  return { due: true, reason: "due" };
}
