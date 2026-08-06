/**
 * app-release-policy — public, sanitized iOS release policy endpoint.
 *
 * This function lets approved builds fetch force/soft update decisions without
 * exposing app_feature_flags or service-role credentials to the mobile client.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type ReleasePolicyBody = {
  client_platform?: unknown;
  client_app_version?: unknown;
  client_app_build?: unknown;
  api_contract_version?: unknown;
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

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const DEFAULT_IOS_POLICY: ReleasePolicy = {
  minimum_supported_build: 62,
  latest_build: 76,
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

async function readPolicy(platform: string): Promise<ReleasePolicy> {
  const { key, fallback } = policyKeyAndFallback(platform);
  if (!key) return fallback;

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceRoleKey) return fallback;

  const supabase = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await supabase
    .from("app_feature_flags")
    .select("value")
    .eq("key", key)
    .maybeSingle();

  if (error || !data?.value) return fallback;
  return sanitizePolicy(data.value, fallback);
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
    };
  }

  const platform = text(body.client_platform, "unknown", 40).toLowerCase();
  const build = parseBuild(body.client_app_build);
  const policy = await readPolicy(platform);

  return json(200, {
    ok: true,
    client_platform: platform,
    client_app_version: text(body.client_app_version, "unknown", 80),
    client_app_build: text(body.client_app_build, "unknown", 40),
    api_contract_version: positiveInt(body.api_contract_version, 1),
    policy,
    decision: decisionFor(policy, build),
  });
});
