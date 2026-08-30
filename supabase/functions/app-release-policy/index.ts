/**
 * app-release-policy — public, sanitized mobile release policy endpoint.
 *
 * This function lets approved builds fetch force/soft update decisions without
 * exposing app_feature_flags or service-role credentials to the mobile client.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { userFacingCopy } from "../_shared/user-facing-copy.ts";
import { readAndroidRuntimeGates } from "../_shared/android-runtime-gates.ts";

type ReleasePolicyBody = {
  client_platform?: unknown;
  client_app_version?: unknown;
  client_app_build?: unknown;
  api_contract_version?: unknown;
  app_language?: unknown;
  android_legal_context?: unknown;
};

// F9 (Android review, 2026-08-06): renamed from IOSReleasePolicy — the shape itself was
// always platform-agnostic, only the naming and single-flag-key lookup were iOS-only.
type ReleasePolicy = {
  minimum_supported_build: number;
  latest_build: number;
  hard_update_enabled: boolean;
  soft_update_enabled: boolean;
  app_store_url: string;
  message_tr: string;
  message_en: string;
  policy_version: string;
};

type AndroidLegalDocument = {
  kind: "terms" | "privacy" | "kvkk" | "consent";
  version: string;
  checksum: string;
  change_type:
    | "info"
    | "material_terms"
    | "material_privacy"
    | "explicit_consent";
};

type AndroidLegalPolicy = {
  schema_version: number;
  enabled: boolean;
  document_set_id: string;
  manifest_checksum: string;
  policy_version: string;
  message_tr: string;
  message_en: string;
  documents: AndroidLegalDocument[];
};

type AndroidLegalContext = {
  document_set_id: string;
  manifest_checksum: string;
  accepted_policy_version: string;
};

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const DEFAULT_IOS_POLICY: ReleasePolicy = {
  // minimum_supported_build and hard_update_enabled stay put even though the
  // live flag is now 88/true: this fallback fires when Supabase is
  // unreachable, and a hardcoded hard-block that can't be dialled back
  // without a new App Store release would turn any outage into an app-wide
  // lockout. Only latest_build (an informational nudge, gated by
  // soft_update_enabled staying false here) tracks the real release.
  minimum_supported_build: 62,
  latest_build: 88,
  hard_update_enabled: false,
  soft_update_enabled: false,
  app_store_url:
    "https://apps.apple.com/tr/app/riskdetected-i-sg-risk-analizi/id6769498181",
  message_tr: "Yeni sürüm mevcut. Devam etmek için uygulamayı güncelleyin.",
  message_en: "A new version is available. Please update the app to continue.",
  policy_version: "fallback",
};

// F9: Android has no shipped build yet — this fallback can never signal an update is needed
// (both *_update_enabled stay false) no matter what a caller sends, matching the DB row
// android_release_policy inserted alongside the android_*_enabled kill switches.
const DEFAULT_ANDROID_POLICY: ReleasePolicy = {
  minimum_supported_build: 1,
  latest_build: 1,
  hard_update_enabled: false,
  soft_update_enabled: false,
  app_store_url: "",
  message_tr: "Yeni sürüm mevcut. Devam etmek için uygulamayı güncelleyin.",
  message_en: "A new version is available. Please update the app to continue.",
  policy_version: "pending-play-listing",
};

// F9: an unrecognized platform gets a policy that can never force/soft-update it — the safe
// direction for a client we don't recognize is "don't pressure it to update", not "apply iOS's
// build numbers to it" (which is what this endpoint silently did before this fix).
const DEFAULT_UNKNOWN_PLATFORM_POLICY: ReleasePolicy = {
  minimum_supported_build: 1,
  latest_build: 999_999,
  hard_update_enabled: false,
  soft_update_enabled: false,
  app_store_url: "",
  message_tr: "",
  message_en: "",
  policy_version: "unrecognized-platform",
};

// Legal policy is Android-only and closed by default. Keeping the complete, current document
// identity in the fallback makes the response deterministic for tests while `enabled: false`
// guarantees that an absent/malformed flag can never block a user.
const DEFAULT_ANDROID_LEGAL_POLICY: AndroidLegalPolicy = {
  schema_version: 1,
  enabled: false,
  document_set_id: "tr-android-v1",
  manifest_checksum:
    "aaa169338de3d9425e76cc4d8b9e98047847934c39cf646cb4f87f708c63cfec",
  policy_version: "android-legal-2026-08-09",
  message_tr: userFacingCopy("legalDocumentsUpdated", "tr"),
  message_en: userFacingCopy("legalDocumentsUpdated", "en"),
  documents: [
    {
      kind: "terms",
      version: "terms-android-2026-08-09",
      checksum:
        "aebbb01c27012192ddf36669b73036889fe8d1f4266a08326aa96e248829e749",
      change_type: "info",
    },
    {
      kind: "privacy",
      version: "privacy-android-2026-08-09",
      checksum:
        "ac811bcf95946e4251ebdbf3d2bd71622e94e3753fc0ca68b1fbaeccb9817672",
      change_type: "info",
    },
    {
      kind: "kvkk",
      version: "kvkk-android-2026-08-09",
      checksum:
        "7cf16880546a414df03202ea1fd09ff0d7aafa48c9f1adb89f62d897741bb297",
      change_type: "info",
    },
    {
      kind: "consent",
      version: "consent-android-2026-08-09",
      checksum:
        "53b380da568e67d6d7406f2a8bad0787b45ddcd2fdf0485f1aaec8f3e517a5c2",
      change_type: "info",
    },
  ],
};

const DEFAULT_ANDROID_LEGAL_POLICY_EN: AndroidLegalPolicy = {
  schema_version: 1,
  enabled: false,
  document_set_id: "en-global-v1",
  manifest_checksum:
    "6b30e321170934890adbbbd747be09fb1f3c8959026cf8bb856d086901d8d704",
  policy_version: "android-legal-en-2026-07-31.1",
  message_tr: userFacingCopy("legalDocumentsUpdated", "tr"),
  message_en: userFacingCopy("legalDocumentsUpdated", "en"),
  documents: [
    {
      kind: "terms",
      version: "terms-en-2026-07-31.1",
      checksum:
        "49a9b3f164b9dc8048453be930509aa334a854834c2abfa0cd8b11fd67ef6efa",
      change_type: "material_terms",
    },
    {
      kind: "privacy",
      version: "privacy-en-2026-07-31.1",
      checksum:
        "ef3d7e01b2b3c09603ff79c7f14bac631493feece7c1a0d6b0bd9a5f0e76ece4",
      change_type: "material_privacy",
    },
    {
      kind: "consent",
      version: "ai-data-en-2026-07-31.1",
      checksum:
        "a8c9873f57228a36a4ede597e33648ff9251f9c814f1d1afc3e912c82ae08e1b",
      change_type: "explicit_consent",
    },
  ],
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function text(value: unknown, fallback = "", maxLength = 240): string {
  if (typeof value !== "string") return fallback;
  return value.trim().slice(0, maxLength);
}

function positiveInt(value: unknown, fallback: number): number {
  const parsed = Math.round(Number(value));
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function bool(value: unknown, fallback: boolean): boolean {
  return typeof value === "boolean" ? value : fallback;
}

function sha256(value: unknown, fallback: string): string {
  const candidate = text(value, "", 64).toLowerCase();
  return /^[0-9a-f]{64}$/.test(candidate) ? candidate : fallback;
}

function cleanURL(value: unknown, fallback: string): string {
  const candidate = text(value, fallback, 500);
  try {
    const url = new URL(candidate);
    return url.protocol === "https:" ? url.toString() : fallback;
  } catch {
    return fallback;
  }
}

function parseBuild(value: unknown): number | null {
  const parsed = Math.round(Number(text(value, "", 40)));
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function sanitizePolicy(raw: unknown, fallback: ReleasePolicy): ReleasePolicy {
  const value = raw && typeof raw === "object"
    ? raw as Record<string, unknown>
    : {};

  const minimum = positiveInt(
    value.minimum_supported_build,
    fallback.minimum_supported_build,
  );
  const latest = positiveInt(value.latest_build, fallback.latest_build);

  return {
    minimum_supported_build: Math.min(minimum, 999_999),
    latest_build: Math.max(Math.min(latest, 999_999), minimum),
    hard_update_enabled: bool(
      value.hard_update_enabled,
      fallback.hard_update_enabled,
    ),
    soft_update_enabled: bool(
      value.soft_update_enabled,
      fallback.soft_update_enabled,
    ),
    app_store_url: cleanURL(
      value.app_store_url,
      fallback.app_store_url,
    ),
    message_tr: text(value.message_tr, fallback.message_tr, 220),
    message_en: text(value.message_en, fallback.message_en, 220),
    policy_version: text(value.policy_version, fallback.policy_version, 80),
  };
}

function sanitizeAndroidLegalPolicy(
  raw: unknown,
  fallbackPolicy: AndroidLegalPolicy,
): AndroidLegalPolicy {
  const value = raw && typeof raw === "object"
    ? raw as Record<string, unknown>
    : {};
  const rawDocuments = Array.isArray(value.documents) ? value.documents : [];
  const fallbackByKind = new Map(
    fallbackPolicy.documents.map((
      document,
    ) => [document.kind, document]),
  );
  const allowedKinds = new Set(["terms", "privacy", "kvkk", "consent"]);
  const allowedChangeTypes = new Set([
    "info",
    "material_terms",
    "material_privacy",
    "explicit_consent",
  ]);
  const documents = rawDocuments.slice(0, 4).flatMap((rawDocument) => {
    if (!rawDocument || typeof rawDocument !== "object") return [];
    const document = rawDocument as Record<string, unknown>;
    const kind = text(document.kind, "", 20);
    if (!allowedKinds.has(kind)) return [];
    const fallback = fallbackByKind.get(kind as AndroidLegalDocument["kind"]);
    if (!fallback) return [];
    const changeType = text(document.change_type, fallback.change_type, 30);
    return [{
      kind: kind as AndroidLegalDocument["kind"],
      version: text(document.version, fallback.version, 100),
      checksum: sha256(document.checksum, fallback.checksum),
      change_type: (allowedChangeTypes.has(changeType)
        ? changeType
        : fallback.change_type) as AndroidLegalDocument["change_type"],
    }];
  });

  return {
    schema_version: positiveInt(value.schema_version, 1),
    enabled: bool(value.enabled, false),
    document_set_id: text(
      value.document_set_id,
      fallbackPolicy.document_set_id,
      80,
    ),
    manifest_checksum: sha256(
      value.manifest_checksum,
      fallbackPolicy.manifest_checksum,
    ),
    policy_version: text(
      value.policy_version,
      fallbackPolicy.policy_version,
      100,
    ),
    message_tr: text(
      value.message_tr,
      fallbackPolicy.message_tr,
      240,
    ),
    message_en: text(
      value.message_en,
      fallbackPolicy.message_en,
      240,
    ),
    documents: documents.length === fallbackPolicy.documents.length
      ? documents
      : fallbackPolicy.documents,
  };
}

function parseAndroidLegalContext(raw: unknown): AndroidLegalContext {
  const value = raw && typeof raw === "object"
    ? raw as Record<string, unknown>
    : {};
  return {
    document_set_id: text(value.document_set_id, "", 80),
    manifest_checksum: sha256(value.manifest_checksum, ""),
    accepted_policy_version: text(value.accepted_policy_version, "", 100),
  };
}

function androidLegalDecision(
  policy: AndroidLegalPolicy,
  context: AndroidLegalContext,
) {
  if (!policy.enabled) {
    return { ...policy, required: false, action: "none", reason: "disabled" };
  }
  const hasCurrentDocuments =
    context.document_set_id === policy.document_set_id &&
    context.manifest_checksum === policy.manifest_checksum;
  if (!hasCurrentDocuments) {
    return {
      ...policy,
      required: true,
      action: "update_app",
      reason: "legal_documents_outdated",
    };
  }
  const requiresAcknowledgement =
    context.accepted_policy_version !== policy.policy_version &&
    policy.documents.some((document) => document.change_type !== "info");
  return {
    ...policy,
    required: requiresAcknowledgement,
    action: requiresAcknowledgement ? "accept" : "none",
    reason: requiresAcknowledgement ? "acknowledgement_required" : "current",
  };
}

function decisionFor(policy: ReleasePolicy, build: number | null) {
  const hardUpdateRequired = build != null &&
    policy.hard_update_enabled &&
    build < policy.minimum_supported_build;
  const softUpdateAvailable = !hardUpdateRequired &&
    build != null &&
    policy.soft_update_enabled &&
    build < policy.latest_build;

  return {
    hard_update_required: hardUpdateRequired,
    soft_update_available: softUpdateAvailable,
    reason: hardUpdateRequired
      ? "minimum_build"
      : softUpdateAvailable
      ? "latest_build"
      : "current",
  };
}

// F9: platform picks both the app_feature_flags row AND the closed-by-default fallback.
// "unknown"/anything else never reads ios_release_policy — that was the actual bug: this
// endpoint used to serve iOS build numbers to any caller regardless of what platform it
// claimed, silently. Now an unrecognized platform gets a policy that never pressures it.
function policyKeyAndFallback(
  platform: string,
): { key: string; fallback: ReleasePolicy } {
  if (platform === "ios") {
    return { key: "ios_release_policy", fallback: DEFAULT_IOS_POLICY };
  }
  if (platform === "android") {
    return { key: "android_release_policy", fallback: DEFAULT_ANDROID_POLICY };
  }
  return { key: "", fallback: DEFAULT_UNKNOWN_PLATFORM_POLICY };
}

// deno-lint-ignore no-explicit-any
function serviceClient(): any | null {
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceRoleKey) return null;
  return createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

async function readPolicy(
  platform: string,
  supabase: any | null,
): Promise<ReleasePolicy> {
  const { key, fallback } = policyKeyAndFallback(platform);
  if (!key) return fallback;
  if (!supabase) return fallback;
  const { data, error } = await supabase
    .from("app_feature_flags")
    .select("value")
    .eq("key", key)
    .maybeSingle();

  if (error || !data?.value) return fallback;
  return sanitizePolicy(data.value, fallback);
}

async function readAndroidLegalPolicy(
  platform: string,
  appLanguage: string,
  supabase: any | null,
): Promise<AndroidLegalPolicy | null> {
  if (platform !== "android") return null;
  const isEnglish = appLanguage === "en";
  const fallback = isEnglish
    ? DEFAULT_ANDROID_LEGAL_POLICY_EN
    : DEFAULT_ANDROID_LEGAL_POLICY;
  if (!supabase) return fallback;
  const { data, error } = await supabase
    .from("app_feature_flags")
    .select("value")
    .eq("key", isEnglish ? "android_legal_policy_en" : "android_legal_policy")
    .maybeSingle();
  if (error || !data?.value) return fallback;
  return sanitizeAndroidLegalPolicy(data.value, fallback);
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST" && req.method !== "GET") {
    return json(405, { error: "method_not_allowed" });
  }

  let body: ReleasePolicyBody = {};
  if (req.method === "POST") {
    body = await req.json().catch(() => ({})) as ReleasePolicyBody;
  } else {
    const url = new URL(req.url);
    body = {
      client_platform: url.searchParams.get("client_platform"),
      client_app_version: url.searchParams.get("client_app_version"),
      client_app_build: url.searchParams.get("client_app_build"),
      api_contract_version: url.searchParams.get("api_contract_version"),
      app_language: url.searchParams.get("app_language"),
      android_legal_context: null,
    };
  }

  const platform = text(body.client_platform, "unknown", 40).toLowerCase();
  const appLanguage = text(body.app_language, "tr", 8).toLowerCase() === "en"
    ? "en"
    : "tr";
  const build = parseBuild(body.client_app_build);
  const supabase = serviceClient();
  const [policy, androidRuntimeGates, androidLegalPolicy] = await Promise.all([
    readPolicy(platform, supabase),
    readAndroidRuntimeGates(supabase, platform, build),
    readAndroidLegalPolicy(platform, appLanguage, supabase),
  ]);

  return json(200, {
    ok: true,
    client_platform: platform,
    client_app_version: text(body.client_app_version, "unknown", 80),
    client_app_build: text(body.client_app_build, "unknown", 40),
    api_contract_version: positiveInt(body.api_contract_version, 1),
    policy,
    decision: decisionFor(policy, build),
    ...(androidRuntimeGates
      ? { android_runtime_gates: androidRuntimeGates }
      : {}),
    ...(androidLegalPolicy
      ? {
        android_legal_policy: androidLegalDecision(
          androidLegalPolicy,
          parseAndroidLegalContext(body.android_legal_context),
        ),
      }
      : {}),
  });
});
