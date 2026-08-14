/**
 * Operations Center API for notification rules, templates and campaigns.
 *
 * verify_jwt=true. The function additionally resolves the user from the bearer
 * token, checks admin status/scopes in DB RPCs, and never returns service keys.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function allowedBrowserOrigin(req: Request): string | null {
  const origin = req.headers.get("Origin");
  if (!origin) return null;
  const allowed = (Deno.env.get("OPERATIONS_CENTER_ALLOWED_ORIGINS") ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  return allowed.includes(origin) ? origin : null;
}

function responseHeaders(req: Request): HeadersInit {
  const origin = allowedBrowserOrigin(req);
  return {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
    "Vary": "Origin",
    ...(origin
      ? {
        "Access-Control-Allow-Origin": origin,
        "Access-Control-Allow-Headers": "authorization, content-type",
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      }
      : {}),
  };
}

function json(
  req: Request,
  status: number,
  body: Record<string, unknown>,
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: responseHeaders(req),
  });
}

function bearerToken(req: Request): string | null {
  const authorization = req.headers.get("Authorization") ?? "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  return match?.[1]?.trim() || null;
}

function safeErrorCode(value: unknown): string {
  const raw = typeof value === "object" && value !== null && "code" in value
    ? String((value as { code?: unknown }).code ?? "unknown")
    : "unknown";
  return raw.replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 80) || "unknown";
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    if (req.headers.has("Origin") && !allowedBrowserOrigin(req)) {
      return json(req, 403, { error: "Origin not allowed" });
    }
    return new Response(null, { status: 204, headers: responseHeaders(req) });
  }
  if (!["GET", "POST"].includes(req.method)) {
    return json(req, 405, { error: "Method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const token = bearerToken(req);
  if (!supabaseUrl || !serviceRoleKey) {
    return json(req, 500, { error: "Operations API is not configured" });
  }
  if (!token) return json(req, 401, { error: "Unauthorized" });

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await supabase.auth.getUser(
    token,
  );
  if (userError || !userData.user?.id) {
    return json(req, 401, { error: "Unauthorized" });
  }
  const actorUserID = userData.user.id;

  if (req.method === "GET") {
    const { data, error } = await supabase.rpc(
      "admin_notification_snapshot_v1",
      { p_actor_user_id: actorUserID },
    );
    if (error) {
      const forbidden = error.code === "42501";
      return json(req, forbidden ? 403 : 500, {
        error: forbidden ? "Forbidden" : "snapshot_failed",
        code: safeErrorCode(error),
      });
    }
    return json(req, 200, { ok: true, snapshot: data });
  }

  const body = await req.json().catch(() => null) as
    | Record<
      string,
      unknown
    >
    | null;
  if (!body) return json(req, 400, { error: "Invalid JSON body" });

  if (body.operation === "preview") {
    const { data, error } = await supabase.rpc(
      "admin_notification_preview_v1",
      {
        p_actor_user_id: actorUserID,
        p_rule_id: typeof body.rule_id === "string" ? body.rule_id : null,
        p_campaign_id: typeof body.campaign_id === "string"
          ? body.campaign_id
          : null,
        p_now: new Date().toISOString(),
      },
    );
    if (error) {
      const forbidden = error.code === "42501";
      return json(req, forbidden ? 403 : 400, {
        error: forbidden ? "Forbidden" : "preview_failed",
        code: safeErrorCode(error),
      });
    }
    return json(req, 200, { ok: true, preview: data });
  }

  if (body.operation !== "mutate" || typeof body.action !== "string") {
    return json(req, 400, { error: "Unsupported operation" });
  }
  const payload = typeof body.payload === "object" && body.payload !== null &&
      !Array.isArray(body.payload)
    ? body.payload
    : {};
  const { data, error } = await supabase.rpc(
    "admin_notification_mutation_v1",
    {
      p_actor_user_id: actorUserID,
      p_action: body.action,
      p_payload: payload,
    },
  );
  if (error) {
    const forbidden = error.code === "42501";
    return json(req, forbidden ? 403 : 400, {
      error: forbidden ? "Forbidden" : "mutation_failed",
      code: safeErrorCode(error),
    });
  }

  return json(req, 200, { ok: true, result: data });
});
