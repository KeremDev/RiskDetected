import {
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  isAppleAdsAttribution,
  mergeFirstTouch,
  nextAttributionAttempt,
  parseRevenueCatAttributeItems,
  parseWebhookSubscriberAttributes,
} from "./revenuecat-attribution.ts";

Deno.test("v2 parser keeps only allowlisted Apple Ads attributes", () => {
  const parsed = parseRevenueCatAttributeItems([
    {
      name: "$mediaSource",
      value: "Apple Search Ads",
      updated_at: "2026-08-17T10:00:00Z",
    },
    {
      name: "$campaign",
      value: "TR - Safety",
      updated_at: "2026-08-17T10:00:01Z",
    },
    {
      name: "$adGroup",
      value: "Risk Analizi",
      updated_at: "2026-08-17T10:00:02Z",
    },
    {
      name: "$keyword",
      value: "risk analizi",
      updated_at: "2026-08-17T10:00:03Z",
    },
    { name: "$appleAdsCampaignId", value: "123" },
    { name: "$appleAdsAdGroupId", value: "456" },
    { name: "$appleAdsKeywordId", value: "789" },
    { name: "$email", value: "private@example.invalid" },
    { name: "$phoneNumber", value: "+905000000000" },
    { name: "$idfa", value: "secret-device-id" },
    { name: "$ip", value: "127.0.0.1" },
  ]);

  assertEquals(parsed.mediaSource, "Apple Search Ads");
  assertEquals(parsed.campaignName, "TR - Safety");
  assertEquals(parsed.adGroupName, "Risk Analizi");
  assertEquals(parsed.keywordName, "risk analizi");
  assertEquals(parsed.campaignId, "123");
  assertEquals(parsed.adGroupId, "456");
  assertEquals(parsed.keywordId, "789");
  assertEquals(parsed.sourceUpdatedAt, "2026-08-17T10:00:03.000Z");
  assertFalse("email" in parsed);
  assertFalse("phoneNumber" in parsed);
  assertFalse("idfa" in parsed);
  assertFalse("ip" in parsed);
});

Deno.test("parser supports current and production legacy country keys", () => {
  const current = parseRevenueCatAttributeItems([
    { name: "$countryOrRegion", value: "TUR" },
  ]);
  const legacy = parseRevenueCatAttributeItems([
    { name: "$appleAdsCountryOrRegion", value: "USA" },
  ]);
  assertEquals(current.countryOrRegion, "TUR");
  assertEquals(legacy.countryOrRegion, "USA");
});

Deno.test("webhook parser accepts stored production event shape and missing keyword", () => {
  const parsed = parseWebhookSubscriberAttributes({
    subscriber_attributes: {
      "$mediaSource": {
        value: "Apple Search Ads",
        updated_at_ms: 1_786_959_600_000,
      },
      "$campaign": { value: "Campaign A", updated_at_ms: 1_786_959_601_000 },
      "$adGroup": { value: "Group A" },
      "$email": { value: "ignored@example.invalid" },
    },
  });
  assertEquals(isAppleAdsAttribution(parsed), true);
  assertEquals(parsed.campaignName, "Campaign A");
  assertEquals(parsed.adGroupName, "Group A");
  assertEquals(parsed.keywordName, null);
});

Deno.test("non-Apple media source is never classified as Apple Ads", () => {
  const parsed = parseRevenueCatAttributeItems([
    { name: "$mediaSource", value: "Organic" },
    { name: "$campaign", value: "Do not classify" },
  ]);
  assertFalse(isAppleAdsAttribution(parsed));
});

Deno.test("first-touch merge enriches blanks without overwriting existing values", () => {
  const merged = mergeFirstTouch({
    mediaSource: "Apple Search Ads",
    campaignName: "First campaign",
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
  }, {
    mediaSource: "Apple Search Ads",
    campaignName: "Later campaign",
    campaignId: "123",
    adGroupName: "Resolved later",
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
  });
  assertEquals(merged.values.campaignName, "First campaign");
  assertEquals(merged.values.campaignId, "123");
  assertEquals(merged.values.adGroupName, "Resolved later");
  assertEquals(merged.conflict, true);
});

Deno.test("retry schedule terminates after the seven-day observation", () => {
  const now = new Date("2026-08-17T12:00:00Z");
  const retry = nextAttributionAttempt({
    signupCreatedAt: "2026-08-17T11:00:00Z",
    completedAttempts: 1,
    now,
  });
  assertEquals(retry.terminal, false);
  assertEquals(retry.nextAttemptAt, "2026-08-17T17:00:00.000Z");
  assertEquals(
    nextAttributionAttempt({
      signupCreatedAt: "2026-08-10T00:00:00Z",
      completedAttempts: 6,
      now,
    }),
    { terminal: true, nextAttemptAt: null },
  );
});
