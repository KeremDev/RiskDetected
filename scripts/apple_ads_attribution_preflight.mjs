#!/usr/bin/env node

import { existsSync, readFileSync } from "node:fs";
import path from "node:path";

const ROOT = process.cwd();

const checks = [];

function read(relativePath) {
  const absolutePath = path.join(ROOT, relativePath);
  if (!existsSync(absolutePath)) return null;
  return readFileSync(absolutePath, "utf8");
}

function add(status, name, detail, evidence = "") {
  checks.push({ status, name, detail, evidence });
}

function requireFile(relativePath) {
  const contents = read(relativePath);
  if (contents === null) {
    add("FAIL", `${relativePath} exists`, "file is missing");
    return null;
  }
  add("PASS", `${relativePath} exists`, "ok");
  return contents;
}

function includesAll(contents, patterns) {
  return patterns.filter((pattern) => !contents.includes(pattern));
}

function checkSourceDoesNotUseTrackingFrameworks() {
  const files = [
    "App/AppState.swift",
    "App/RiskDetectedApp.swift",
    "App/Services/SubscriptionManager.swift",
    "Config/RiskDetectedInfo.plist",
    "RiskDetected.xcodeproj/project.pbxproj",
  ];
  const forbidden = [
    "import AppTrackingTransparency",
    "ATTrackingManager",
    "ASIdentifierManager",
    "advertisingIdentifier",
    "AdSupport.framework",
    "NSUserTrackingUsageDescription",
  ];

  const hits = [];
  for (const file of files) {
    const contents = read(file);
    if (contents === null) continue;
    for (const pattern of forbidden) {
      if (contents.includes(pattern)) hits.push(`${file}: ${pattern}`);
    }
  }

  add(
    hits.length === 0 ? "PASS" : "FAIL",
    "No ATT/IDFA/AdSupport source usage",
    hits.length === 0
      ? "Standard Apple Ads AdServices path is still no-ATT/no-IDFA."
      : hits.join("; "),
  );
}

function checkRevenueCatAdServices() {
  const file = "App/Services/SubscriptionManager.swift";
  const contents = requireFile(file);
  if (!contents) return;

  const missing = includesAll(contents, [
    "Purchases.shared.attribution.enableAdServicesAttributionTokenCollection()",
    "enableAppleAdsAttributionCollection()",
    "Purchases.configure(withAPIKey: RDConfig.Subscription.revenueCatAPIKey",
    "Purchases.shared.logIn(appUserID)",
  ]);

  add(
    missing.length === 0 ? "PASS" : "FAIL",
    "RevenueCat AdServices token collection",
    missing.length === 0
      ? "Token collection is enabled after configure and re-triggered after RevenueCat logIn."
      : `missing markers: ${missing.join(", ")}`,
  );
}

function checkLegacyIAdNotUsed() {
  const files = [
    "App/Services/SubscriptionManager.swift",
    "App/AppState.swift",
    "RiskDetected.xcodeproj/project.pbxproj",
  ];
  const forbidden = ["import iAd", "ADClient", "requestAttributionDetails"];
  const hits = [];

  for (const file of files) {
    const contents = read(file);
    if (contents === null) continue;
    for (const pattern of forbidden) {
      if (contents.includes(pattern)) hits.push(`${file}: ${pattern}`);
    }
  }

  add(
    hits.length === 0 ? "PASS" : "FAIL",
    "Legacy iAd attribution not used",
    hits.length === 0 ? "No legacy iAd attribution API markers found." : hits.join("; "),
  );
}

function checkPrivacyManifest() {
  const file = "App/PrivacyInfo.xcprivacy";
  const contents = requireFile(file);
  if (!contents) return;

  const hasNoTrackingFlag = contents.includes("<key>NSPrivacyTracking</key>") &&
    contents.includes("<false/>");
  add(
    hasNoTrackingFlag ? "PASS" : "FAIL",
    "Privacy manifest tracking flag",
    hasNoTrackingFlag ? "NSPrivacyTracking is false." : "Expected NSPrivacyTracking=false.",
  );
}

function checkSupabaseEventJoinSurface() {
  const subscriptionMigration = requireFile("supabase/migrations/20260513101505_free_plus_pro_subscription_system.sql");
  const paywallMigration = requireFile("supabase/migrations/20260522085000_add_paywall_events.sql");
  const onboardingMigration = requireFile("supabase/migrations/20260520083317_add_onboarding_answers.sql");
  const webhook = requireFile("supabase/functions/revenuecat-webhook/index.ts");
  const paywallService = requireFile("App/Services/PaywallEventService.swift");
  if (!subscriptionMigration || !paywallMigration || !onboardingMigration || !webhook || !paywallService) return;

  const missingSchemaMarkers = [
    ...includesAll(subscriptionMigration, [
      "create table if not exists public.user_subscriptions",
      "revenuecat_app_user_id text",
      "create table if not exists public.subscription_events",
      "event_id text primary key",
      "app_user_id text",
      "raw_event jsonb not null",
      "processed_at timestamptz",
    ]),
    ...includesAll(paywallMigration, [
      "create table if not exists public.paywall_events",
      "user_id uuid not null references auth.users(id)",
      "funnel_session_id uuid not null",
      "event_name text not null",
    ]),
    ...includesAll(onboardingMigration, [
      "create table if not exists public.user_onboarding_answers",
      "user_id uuid primary key references auth.users(id)",
      "upsert_onboarding_v2_answers",
    ]),
  ];

  add(
    missingSchemaMarkers.length === 0 ? "PASS" : "FAIL",
    "Supabase attribution join surface",
    missingSchemaMarkers.length === 0
      ? "paywall_events, subscription_events, user_subscriptions, and onboarding answers can join by user_id/app_user_id."
      : `missing markers: ${missingSchemaMarkers.join(", ")}`,
  );

  const missingWebhookMarkers = includesAll(webhook, [
    ".select(\"event_id,processed_at\")",
    "duplicate: true",
    "app_user_id: appUserID",
    "raw_event: event",
    "event_id: eventID",
    "processed_at: new Date().toISOString()",
  ]);

  add(
    missingWebhookMarkers.length === 0 ? "PASS" : "FAIL",
    "RevenueCat webhook idempotency and raw event capture",
    missingWebhookMarkers.length === 0
      ? "Webhook stores app_user_id/raw_event and treats processed event_id as duplicate."
      : `missing markers: ${missingWebhookMarkers.join(", ")}`,
  );

  const missingPaywallMarkers = includesAll(paywallService, [
    "case purchaseStarted = \"purchase_started\"",
    "case purchaseSucceeded = \"purchase_succeeded\"",
    "case purchaseFailed = \"purchase_failed\"",
    "funnelSessionID",
    "selectedPackageID",
  ]);

  add(
    missingPaywallMarkers.length === 0 ? "PASS" : "FAIL",
    "Paywall funnel event markers",
    missingPaywallMarkers.length === 0
      ? "Paywall funnel tracks purchase start/success/failure with funnel session context."
      : `missing markers: ${missingPaywallMarkers.join(", ")}`,
  );
}

function checkP1NotAccidentallyEnabled() {
  const files = [
    "App/Services/SubscriptionManager.swift",
    "App/AppState.swift",
    "App/Services/SupabaseService.swift",
    "supabase/config.toml",
  ];
  const p1Markers = [
    "AAAttribution.attributionToken()",
    "apple-ads-attribution-token",
    "api-adservices.apple.com/api/v1",
  ];
  const hits = [];

  for (const file of files) {
    const contents = read(file);
    if (contents === null) continue;
    for (const marker of p1Markers) {
      if (contents.includes(marker)) hits.push(`${file}: ${marker}`);
    }
  }

  add(
    hits.length === 0 ? "PASS" : "FAIL",
    "P1 raw backend attribution remains deferred",
    hits.length === 0
      ? "No app-to-Supabase Apple attribution token resolver is active in this build."
      : hits.join("; "),
  );
}

function addManualGates() {
  add(
    "MANUAL",
    "RevenueCat dashboard integration",
    "Confirm Apple AdServices remains Active and Basic/Advanced both show Done before release.",
  );
  add(
    "MANUAL",
    "Live Apple Ads cohort validation",
    "After App Store release, run a small Apple Ads campaign and verify RevenueCat Charts segments before scaling spend.",
  );
}

function printReport() {
  console.log("# Apple Ads Attribution Preflight\n");
  for (const check of checks) {
    console.log(`- [${check.status}] ${check.name}: ${check.detail}`);
    if (check.evidence) console.log(`  ${check.evidence}`);
  }

  const failCount = checks.filter((check) => check.status === "FAIL").length;
  const manualCount = checks.filter((check) => check.status === "MANUAL").length;
  console.log(`\nSummary: ${checks.length - failCount - manualCount} pass, ${failCount} fail, ${manualCount} manual gate(s).`);
  if (failCount > 0) process.exitCode = 1;
}

checkRevenueCatAdServices();
checkLegacyIAdNotUsed();
checkSourceDoesNotUseTrackingFrameworks();
checkPrivacyManifest();
checkSupabaseEventJoinSurface();
checkP1NotAccidentallyEnabled();
addManualGates();
printReport();
