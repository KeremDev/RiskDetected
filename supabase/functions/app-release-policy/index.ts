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

type IOSReleasePolicy = {
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

const DEFAULT_POLICY: IOSReleasePolicy = {
  minimum_supported_build: 62,
  latest_build: 71,
  hard_update_enabled: false,
  soft_update_enabled: false,
  app_store_url:
    "https://apps.apple.com/tr/app/riskdetected-i-sg-risk-analizi/id6769498181",
  message_tr: "Yeni sürüm mevcut. Devam etmek için uygulamayı güncelleyin.",
  message_en: "A new version is available. Please update the app to continue.",
  policy_version: "fallback",
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

function sanitizePolicy(raw: unknown): IOSReleasePolicy {
  const value = raw && typeof raw === "object"
    ? raw as Record<string, unknown>
    : {};

  const minimum = positiveInt(
    value.minimum_supported_build,
    DEFAULT_POLICY.minimum_supported_build,
  );
  const latest = positiveInt(value.latest_build, DEFAULT_POLICY.latest_build);

  return {
    minimum_supported_build: Math.min(minimum, 999_999),
    latest_build: Math.max(Math.min(latest, 999_999), minimum),
    hard_update_enabled: bool(
      value.hard_update_enabled,
      DEFAULT_POLICY.hard_update_enabled,
    ),
    soft_update_enabled: bool(
      value.soft_update_enabled,
      DEFAULT_POLICY.soft_update_enabled,
    ),
    app_store_url: cleanURL(
      value.app_store_url,
      DEFAULT_POLICY.app_store_url,
    ),
    message_tr: text(value.message_tr, DEFAULT_POLICY.message_tr, 220),
    message_en: text(value.message_en, DEFAULT_POLICY.message_en, 220),
    policy_version: text(value.policy_version, "v1", 80),
  };
}

function decisionFor(policy: IOSReleasePolicy, build: number | null) {
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

async function readPolicy(): Promise<IOSReleasePolicy> {
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceRoleKey) return DEFAULT_POLICY;

  const supabase = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await supabase
    .from("app_feature_flags")
    .select("value")
    .eq("key", "ios_release_policy")
    .maybeSingle();

  if (error || !data?.value) return DEFAULT_POLICY;
  return sanitizePolicy(data.value);
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
  const policy = await readPolicy();

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
