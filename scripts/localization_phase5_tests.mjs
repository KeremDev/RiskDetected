#!/usr/bin/env node

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const read = (path) => readFileSync(resolve(root, path), "utf8");
const sha256 = (data) => createHash("sha256").update(data).digest("hex");
let passed = 0;

const test = (name, body) => {
  body();
  passed += 1;
  console.log(`ok ${passed} - ${name}`);
};

const manifest = JSON.parse(read("App/LegalDocuments/en/manifest.json"));
const legalApproval = JSON.parse(
  read(
    "docs/localization/phase-5/LEGAL_COUNSEL_APPROVAL_2026-09-08_META.json",
  ),
);
const legalService = read("App/Services/LegalDocumentService.swift");
const rootView = read("App/RootView.swift");
const authService = read("App/Services/AuthService.swift");
const appState = read("App/AppState.swift");
const buildGate = read(
  "App/Localization/RDGlobalLocalizationBuildGate.swift",
);
const localizationService = read("App/Services/RDLocalization.swift");
const analysisService = read("App/Services/AnalysisService.swift");
const homeView = read("App/Views/Home/HomeView.swift");
const onboardingAnswersService = read(
  "App/Services/OnboardingAnswersService.swift",
);
const releaseBuildGate = read("scripts/localization_release_build_gate.sh");
const acceptanceService = read("App/Services/LegalAcceptanceService.swift");
const migration = read(
  "supabase/migrations/20260730213000_global_localization_delivery_wave1.sql",
);
const legalAcknowledgementBackfill = read(
  "supabase/migrations/20260802203947_backfill_legacy_turkish_legal_acknowledgements.sql",
);
const onboardingCatalog = JSON.parse(read("App/Localization/Onboarding.xcstrings"));
const subscriptionManager = read("App/Services/SubscriptionManager.swift");
const supportFunction = read("supabase/functions/support-contact/index.ts");
const authHook = read("supabase/functions/auth-send-email-hook/index.ts");
const pushFunction = read("supabase/functions/send-push-notification/index.ts");
const subscriptionDrafts = JSON.parse(
  read(
    "docs/localization/phase-5/ASC_SUBSCRIPTION_METADATA_DRAFTS_2026-07-30.json",
  ),
);
const offerSnapshot = JSON.parse(
  read(
    "docs/localization/phase-5/ASC_INTRODUCTORY_OFFER_READONLY_2026-07-30.json",
  ),
);

test("global localization is fail closed behind an approved build condition", () => {
  assert.ok(buildGate.includes("#if RD_GLOBAL_LOCALIZATION_WAVE1"));
  assert.ok(buildGate.includes("#if DEBUG"));
  assert.ok(
    buildGate.includes("RD_UI_TEST_GLOBAL_LOCALIZATION_ENABLED"),
  );
  assert.equal(buildGate.includes("UserDefaults"), false);
  assert.ok(
    localizationService.includes(
      "guard RDGlobalLocalizationBuildGate.isEnabled else",
    ),
  );
  assert.ok(
    analysisService.includes(
      '"global_localization_wave1":',
    ),
  );
  assert.ok(
    appState.includes(
      "guard RDGlobalLocalizationBuildGate.isEnabled else { return nil }",
    ),
  );
  assert.ok(
    homeView.includes(
      "if RDGlobalLocalizationBuildGate.isEnabled && localization == nil",
    ),
  );
  assert.ok(
    onboardingAnswersService.includes(
      "RDGlobalLocalizationBuildGate.isEnabled",
    ),
  );
  assert.ok(
    releaseBuildGate.includes(
      "verify_phase5_external_gates.mjs --mode=release --live",
    ),
  );
});

test("English legal review and production publication are approved", () => {
  assert.equal(manifest.document_set_id, "en-global-v1");
  assert.equal(manifest.locale, "en");
  assert.equal(manifest.release_status, "approved");
  assert.equal(manifest.counsel_review_status, "approved");
  assert.equal(manifest.reviewed_by, "Kerem");
  assert.equal(
    manifest.reviewer_qualification,
    "Hukuk belgelerini inceleme ve onaylama yetkinliğine sahip.",
  );
  assert.equal(manifest.reviewed_at, "2026-09-08T10:16:12Z");
  assert.equal(
    manifest.counsel_approval_record_path,
    "docs/localization/phase-5/LEGAL_COUNSEL_APPROVAL_2026-09-08_META.json",
  );
  assert.equal(
    manifest.counsel_approval_record_sha256,
    sha256(
      read(
        "docs/localization/phase-5/LEGAL_COUNSEL_APPROVAL_2026-09-08_META.json",
      ),
    ),
  );
  assert.equal(manifest.public_urls_verified_at, "2026-09-08T10:19:53Z");
  assert.deepEqual(manifest.public_urls, {
    terms:
      "https://riskdetected.com/legal-documents/en/Terms-of-Use.md",
    privacy:
      "https://riskdetected.com/legal-documents/en/Privacy-Policy.md",
    ai_data_processing_notice:
      "https://riskdetected.com/legal-documents/en/AI-and-Data-Processing-Notice.md",
  });
});

test("English legal approval and manifest cover every exact document hash", () => {
  assert.deepEqual(
    new Set(manifest.documents.map((document) => document.kind)),
    new Set(["terms", "privacy", "consent"]),
  );
  assert.equal(legalApproval.decision, "approved");
  assert.equal(legalApproval.reviewer_name, "Kerem");
  assert.equal(
    legalApproval.reviewed_preapproval_manifest_sha256,
    "008108dcb03fcc6db4955dbdc97c4e8f2091d78c8807832713de3ca9c051ad07",
  );
  for (const document of manifest.documents) {
    const data = read(`App/LegalDocuments/${document.path}`);
    assert.equal(sha256(data), document.hash);
    const approvedDocument = legalApproval.reviewed_documents.find(
      (candidate) => candidate.kind === document.kind,
    );
    assert.equal(approvedDocument.path, document.path);
    assert.equal(approvedDocument.sha256, document.hash);
  }
});

test("English legal approval requires counsel, verified URLs and hashes", () => {
  for (const marker of [
    'manifest.releaseStatus == "approved"',
    'manifest.counselReviewStatus == "approved"',
    "manifest.publicURLsVerifiedAt",
    'url.host?.lowercased() == "riskdetected.com"',
    "SHA256.hash(data: data)",
  ]) {
    assert.ok(legalService.includes(marker), marker);
  }
});

test("all sign-in entry points and purchase are legal-gated", () => {
  assert.equal(
    authService.match(/try RDLegalReleaseGate\.requireAuthAndPurchaseAccess\(\)/g)
      ?.length,
    6,
  );
  const purchase = appState.slice(
    appState.indexOf("func purchaseSubscription("),
    appState.indexOf("func restoreSubscriptions("),
  );
  assert.ok(purchase.includes("requireAuthAndPurchaseAccess"));
  const restore = appState.slice(
    appState.indexOf("func restoreSubscriptions("),
    appState.indexOf("func setDarkMode("),
  );
  assert.equal(restore.includes("requireAuthAndPurchaseAccess"), false);
});

test("legal acceptance persists set, locale and checksums", () => {
  for (const marker of [
    "legal_document_set",
    "legal_locale",
    "legal_set_manifest_checksum",
  ]) {
    assert.ok(acceptanceService.includes(marker), marker);
    assert.ok(migration.includes(marker), marker);
  }
  for (const marker of [
    "document_set_id",
    "document_locale",
    "document_checksum",
  ]) {
    assert.ok(legalService.includes(marker), marker);
    assert.ok(migration.includes(marker), marker);
  }
});

test("informational legal updates are shown once per exact document revision", () => {
  const pendingEvaluation = legalService.slice(
    legalService.indexOf("private func evaluatePendingUpdates"),
    legalService.indexOf("private func upsertAcknowledgements"),
  );
  assert.doesNotMatch(
    pendingEvaluation,
    /\.eq\("document_set_id"/u,
    "legacy Turkish acknowledgement rows must not be discarded by the query",
  );
  assert.doesNotMatch(
    pendingEvaluation,
    /\.eq\("document_locale"/u,
    "legacy Turkish acknowledgement rows must not be discarded by the query",
  );
  for (const marker of [
    "isLegacyTurkishRow",
    "recordPresented",
    "presentedInfoNoticeIDs",
    "localInfoSeenFingerprint",
    "normalizedChecksum",
    "document.checksum",
  ]) {
    assert.ok(legalService.includes(marker), marker);
  }
  assert.ok(rootView.includes(".task(id: notice.id)"));
  assert.ok(rootView.includes("legalDocuments.recordPresented"));
  assert.match(
    legalAcknowledgementBackfill,
    /document_set_id = 'tr-current'[\s\S]*document_locale = 'tr'/u,
  );
  assert.match(
    legalAcknowledgementBackfill,
    /document_set_id is null[\s\S]*document_locale is null/u,
  );
});

test("notification localization is exact-locale and fail closed", () => {
  for (const marker of [
    "notification_template_localizations",
    "NOTIFICATION_LOCALIZATION_SNAPSHOT_IMMUTABLE",
    "TEMPLATE_EXACT_LOCALE_MISSING",
    "notification_localization_failures",
  ]) {
    assert.ok(migration.includes(marker), marker);
  }
  for (const marker of [
    "reviewer_name",
    "reviewer_qualification",
    "reviewed_copy_sha256",
    "review_evidence_sha256",
    "5660f3a69595a0d8b80057fe2a5a0fb97c9393a003ff2bd72ad8208646955c87",
    "abfbf34bbfcd59e72ac06658ab84970d0429cc1d2020102d866ae48544921158",
  ]) {
    assert.ok(migration.includes(marker), marker);
  }
  assert.ok(
    migration.includes(
      "'İngilizce iş güvenliği metinlerini değerlendirme niteliğine sahip.'",
    ),
  );
  assert.ok(pushFunction.includes("event_key"));
  assert.ok(pushFunction.includes("localization_snapshot"));
});

test("email and support localization do not cross-language fallback", () => {
  assert.ok(authHook.includes("SEND_EMAIL_HOOK_SECRET"));
  assert.ok(authHook.includes("AUTH_EMAIL_EXACT_LOCALE_TEMPLATE_MISSING"));
  assert.equal(authHook.includes("console.log"), false);
  assert.ok(supportFunction.includes("preferred_response_language"));
  assert.ok(supportFunction.includes("user_message_language"));
  assert.ok(supportFunction.includes("acknowledgement"));
});

test("non-TR paywall removes the Turkish legislation benefit claim", () => {
  const key =
    "onboarding.obpaywall.view.mevzuat.referanslari.ile.927c6758";
  assert.equal(
    onboardingCatalog.strings[key].localizations.en.stringUnit.value,
    "Structured safety review",
  );
  assert.equal(
    onboardingCatalog.strings[key].localizations.tr.stringUnit.value,
    "Mevzuat referansları ile",
  );
});

test("StoreKit localized prices and four production product IDs are unchanged", () => {
  assert.ok(subscriptionManager.includes("package.localizedPriceString"));
  for (const productID of [
    "riskdetected_plus_monthly",
    "riskdetected_plus_yearly",
    "riskdetected_pro_monthly",
    "riskdetected_pro_yearly",
  ]) {
    assert.ok(subscriptionManager.includes(productID), productID);
  }
});

test("ASC subscription drafts cover four locales without mutating commerce", () => {
  const requiredLocales = new Set(["en-GB", "en-US", "en-AU", "en-CA"]);
  assert.equal(subscriptionDrafts.status, "draft_not_applied");
  assert.equal(subscriptionDrafts.mutation_performed, false);
  assert.deepEqual(
    new Set(
      subscriptionDrafts.subscription_group.localizations.map(
        (localization) => localization.locale,
      ),
    ),
    requiredLocales,
  );
  assert.equal(subscriptionDrafts.products.length, 4);
  for (const product of subscriptionDrafts.products) {
    assert.deepEqual(
      new Set(product.localizations.map((localization) => localization.locale)),
      requiredLocales,
    );
    for (const localization of product.localizations) {
      assert.ok(localization.name.length <= 30);
      assert.ok(localization.description.length <= 55);
      assert.doesNotMatch(
        localization.description,
        /legislat|regulat|compliance|6331|OSGB|mevzuat/iu,
      );
    }
  }
  assert.deepEqual(subscriptionDrafts.constraints, {
    product_ids_changed: false,
    prices_changed: false,
    limits_changed: false,
    offers_changed: false,
    legal_or_regulatory_compliance_claims_present: false,
  });
});

test("live ASC offer recheck preserves the isolated seven-day trial", () => {
  assert.equal(offerSnapshot.mutation_performed, false);
  const plusYearly = offerSnapshot.products.find(
    (product) => product.product_id === "riskdetected_plus_yearly",
  );
  assert.equal(plusYearly.introductory_offer_count, 175);
  assert.deepEqual(plusYearly.uniform_offer, {
    start_date: "2026-05-30",
    end_date: "2026-09-30",
    duration: "ONE_WEEK",
    offer_mode: "FREE_TRIAL",
    number_of_periods: 1,
  });
  assert.deepEqual(
    new Set(plusYearly.required_wave_1_territories_present),
    new Set(["AU", "CA", "GB", "US"]),
  );
  for (
    const product of offerSnapshot.products.filter(
      (entry) => entry.product_id !== "riskdetected_plus_yearly",
    )
  ) {
    assert.equal(product.introductory_offer_count, 0);
  }
});

console.log(`1..${passed}`);
