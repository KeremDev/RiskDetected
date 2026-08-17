export const APPLE_ADS_MEDIA_SOURCE = "Apple Search Ads";

export type AttributionValues = {
  mediaSource: string | null;
  campaignName: string | null;
  campaignId: string | null;
  adGroupName: string | null;
  adGroupId: string | null;
  keywordName: string | null;
  keywordId: string | null;
  adId: string | null;
  orgId: string | null;
  claimType: string | null;
  conversionType: string | null;
  countryOrRegion: string | null;
  supplyPlacement: string | null;
  sourceUpdatedAt: string | null;
};

export type RevenueCatAttributeItem = {
  name?: unknown;
  key?: unknown;
  value?: unknown;
  updated_at?: unknown;
  updated_at_ms?: unknown;
};

const EMPTY_ATTRIBUTION: AttributionValues = {
  mediaSource: null,
  campaignName: null,
  campaignId: null,
  adGroupName: null,
  adGroupId: null,
  keywordName: null,
  keywordId: null,
  adId: null,
  orgId: null,
  claimType: null,
  conversionType: null,
  countryOrRegion: null,
  supplyPlacement: null,
  sourceUpdatedAt: null,
};

const KEY_TO_FIELD: Readonly<Record<string, keyof AttributionValues>> = {
  "$mediaSource": "mediaSource",
  "$campaign": "campaignName",
  "$appleAdsCampaignId": "campaignId",
  "$campaignId": "campaignId",
  "$adGroup": "adGroupName",
  "$appleAdsAdGroupId": "adGroupId",
  "$adGroupId": "adGroupId",
  "$keyword": "keywordName",
  "$appleAdsKeywordId": "keywordId",
  "$keywordId": "keywordId",
  "$appleAdsAdId": "adId",
  "$adId": "adId",
  "$appleAdsOrgId": "orgId",
  "$orgId": "orgId",
  "$claimType": "claimType",
  "$conversionType": "conversionType",
  "$countryOrRegion": "countryOrRegion",
  "$appleAdsCountryOrRegion": "countryOrRegion",
  "$supplyPlacement": "supplyPlacement",
};

function cleanText(value: unknown, maxLength = 256): string | null {
  if (typeof value !== "string") return null;
  const cleaned = value.trim();
  return cleaned ? cleaned.slice(0, maxLength) : null;
}

function timestampIso(value: unknown): string | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    const milliseconds = value > 10_000_000_000 ? value : value * 1000;
    const date = new Date(milliseconds);
    return Number.isNaN(date.getTime()) ? null : date.toISOString();
  }
  if (typeof value !== "string" || !value.trim()) return null;
  const numeric = Number(value);
  if (Number.isFinite(numeric)) return timestampIso(numeric);
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function newerTimestamp(left: string | null, right: string | null) {
  if (!left) return right;
  if (!right) return left;
  return Date.parse(right) > Date.parse(left) ? right : left;
}

function setAllowlistedValue(
  result: AttributionValues,
  key: string,
  value: unknown,
  updatedAt: unknown,
) {
  const field = KEY_TO_FIELD[key];
  if (!field || field === "sourceUpdatedAt") return;
  const maximum = field === "countryOrRegion"
    ? 32
    : ["claimType", "conversionType", "supplyPlacement"].includes(field)
    ? 80
    : field.endsWith("Id")
    ? 128
    : field === "mediaSource"
    ? 120
    : 256;
  const clean = cleanText(value, maximum);
  if (!clean || result[field]) return;
  result[field] = clean;
  result.sourceUpdatedAt = newerTimestamp(
    result.sourceUpdatedAt,
    timestampIso(updatedAt),
  );
}

/** Parse the RevenueCat API v2 customer-attribute collection. */
export function parseRevenueCatAttributeItems(
  items: RevenueCatAttributeItem[],
): AttributionValues {
  const result = { ...EMPTY_ATTRIBUTION };
  for (const item of items) {
    const key = cleanText(item.name ?? item.key, 128);
    if (!key) continue;
    setAllowlistedValue(
      result,
      key,
      item.value,
      item.updated_at ?? item.updated_at_ms,
    );
  }
  return result;
}

/** Parse subscriber_attributes embedded in a RevenueCat webhook event. */
export function parseWebhookSubscriberAttributes(
  rawEvent: unknown,
): AttributionValues {
  const root = asRecord(rawEvent);
  const event = asRecord(root?.event) ?? root;
  const attributes = asRecord(event?.subscriber_attributes);
  const result = { ...EMPTY_ATTRIBUTION };
  if (!attributes) return result;

  for (const [key, rawValue] of Object.entries(attributes)) {
    const attribute = asRecord(rawValue);
    setAllowlistedValue(
      result,
      key,
      attribute?.value ?? rawValue,
      attribute?.updated_at ?? attribute?.updated_at_ms,
    );
  }
  return result;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

export function isAppleAdsAttribution(values: AttributionValues): boolean {
  return values.mediaSource?.trim().toLocaleLowerCase("en-US") ===
    APPLE_ADS_MEDIA_SOURCE.toLocaleLowerCase("en-US");
}

export type StoredAttributionValues = Omit<
  AttributionValues,
  "sourceUpdatedAt"
>;

/**
 * First-touch merge: existing non-empty values are immutable, while a later
 * RevenueCat response may fill fields Apple had not resolved yet.
 */
export function mergeFirstTouch(
  existing: StoredAttributionValues,
  incoming: AttributionValues,
): { values: StoredAttributionValues; conflict: boolean } {
  let conflict = false;
  const values = { ...existing };
  for (
    const field of Object.keys(existing) as (keyof StoredAttributionValues)[]
  ) {
    const current = existing[field];
    const next = incoming[field];
    if (!current && next) values[field] = next;
    else if (current && next && current !== next) conflict = true;
  }
  return { values, conflict };
}

const RETRY_OFFSETS_HOURS = [1, 6, 24, 48, 72, 168] as const;

export function nextAttributionAttempt(params: {
  signupCreatedAt: string;
  completedAttempts: number;
  now?: Date;
}): { terminal: boolean; nextAttemptAt: string | null } {
  const now = params.now ?? new Date();
  const signup = new Date(params.signupCreatedAt);
  if (Number.isNaN(signup.getTime())) {
    return {
      terminal: params.completedAttempts >= RETRY_OFFSETS_HOURS.length,
      nextAttemptAt: params.completedAttempts >= RETRY_OFFSETS_HOURS.length
        ? null
        : new Date(now.getTime() + 60 * 60 * 1000).toISOString(),
    };
  }
  if (params.completedAttempts >= RETRY_OFFSETS_HOURS.length) {
    return { terminal: true, nextAttemptAt: null };
  }
  const target = new Date(
    signup.getTime() +
      RETRY_OFFSETS_HOURS[params.completedAttempts] * 60 * 60 * 1000,
  );
  const earliest = new Date(now.getTime() + 5 * 60 * 1000);
  return {
    terminal: false,
    nextAttemptAt: new Date(
      Math.max(target.getTime(), earliest.getTime()),
    ).toISOString(),
  };
}

export function emptyAttributionValues(): AttributionValues {
  return { ...EMPTY_ATTRIBUTION };
}
