/**
 * request-account-deletion — user-callable account deletion entrypoint.
 *
 * Verifies the caller's Supabase JWT, creates or reuses the user's deletion
 * request, then invokes the privileged completion worker with service-role
 * credentials. The mobile app calls this function; it never receives the
 * service-role key.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type SupabaseAdmin = ReturnType<typeof createClient<any, "public">>;

type RequestBody = {
  email?: unknown;
  request_id?: unknown;
  support_id?: unknown;
  client_platform?: unknown;
  completion_mode?: unknown;
};

type DeletionRequest = {
  id: string;
  status: string;
  completion_mode?: string;
  due_at?: string;
};

const BASE_CORS_HEADERS = {
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function allowedOrigins(): Set<string> {
  const configured = Deno.env.get("ACCOUNT_DELETION_ALLOWED_ORIGINS") ??
    "https://riskdetected.com";
  return new Set(
    configured.split(",").map((value) => value.trim()).filter(Boolean),
  );
}

function isAllowedBrowserOrigin(req: Request): boolean {
  const origin = req.headers.get("Origin");
  return !origin || allowedOrigins().has(origin);
}

function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin");
  return origin && allowedOrigins().has(origin)
    ? {
      ...BASE_CORS_HEADERS,
      "Access-Control-Allow-Origin": origin,
      "Vary": "Origin",
    }
    : { ...BASE_CORS_HEADERS };
}

function json(req: Request, status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json" },
  });
}

function newSupportID(): string {
  return `RD-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
}

function cleanTrace(value: unknown, fallback: string): string {
  if (typeof value !== "string") return fallback;
  const clean = value.trim().replace(/[^\p{L}\p{N}._:@-]/gu, "").slice(0, 80);
  return clean.length > 0 ? clean : fallback;
}

function isUUID(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function cleanEmail(value: unknown, fallback: string | null): string | null {
  if (typeof value !== "string") return fallback;
  const clean = value.trim().toLowerCase().slice(0, 240);
  return clean.includes("@") ? clean : fallback;
}

function enumValue<T extends string>(
  value: unknown,
  allowed: readonly T[],
  fallback: T,
): T | null {
  if (value === undefined || value === null || value === "") return fallback;
  return typeof value === "string" && allowed.includes(value as T)
    ? value as T
    : null;
}

async function sendRequestAcceptedEmail(
  email: string | null,
  supportID: string,
  estimatedCompletionAt: string,
): Promise<void> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  const from = Deno.env.get("RESEND_FROM_EMAIL") ??
    "RiskDetected <info@riskdetected.com>";
  if (!apiKey || !email) return;
  await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: [email],
      subject: "RiskDetected hesap silme talebin alındı",
      text:
        `Hesap ve veri silme talebin alındı. İşlem en geç 24 saat içinde tamamlanacaktır.\n\n` +
        `Destek kodu: ${supportID}\nTahmini son zaman: ${estimatedCompletionAt}\n\n` +
        "Aktif Google Play veya App Store aboneliğini mağaza abonelik ayarlarından ayrıca yönetmelisin.",
    }),
  }).catch(() => undefined);
}

function safeErrorCode(error: unknown): string {
  const raw = error instanceof Error ? error.message : String(error);
  const category = raw.split(":", 1)[0].toLowerCase();
  const sanitized = category.replace(/[^a-z0-9_]/g, "_").slice(0, 80);
  return sanitized || "request_failed";
}

async function findOpenRequest(
  supabase: SupabaseAdmin,
  userID: string,
): Promise<DeletionRequest | null> {
  const { data, error } = await supabase
    .from("account_deletion_requests")
    .select("id,status")
    .eq("target_user_id", userID)
    .in("status", ["pending", "processing"])
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle();

  if (error) {
    throw new Error(`request_lookup_failed:${error.message}`);
  }
  return data as DeletionRequest | null;
}

async function createDeletionRequest(
  supabase: SupabaseAdmin,
  params: {
    userID: string;
    email: string | null;
    requestID: string;
    clientPlatform: "ios" | "android" | "web";
    completionMode: "immediate" | "request_only";
    dueAt: string;
    targetUserHash: string;
  },
): Promise<DeletionRequest> {
  const { data, error } = await supabase
    .from("account_deletion_requests")
    .insert({
      user_id: params.userID,
      email: params.email,
      requested_scope: "account_and_data",
      note:
        `User requested account and data deletion. platform=${params.clientPlatform} request_id=${params.requestID}`,
      target_user_id: params.userID,
      target_email: params.email,
      target_user_hash: params.targetUserHash,
      requested_via: params.clientPlatform,
      completion_mode: params.completionMode,
      due_at: params.dueAt,
    })
    .select("id,status,completion_mode,due_at")
    .single();

  if (error) {
    throw new Error(`request_create_failed:${error.message}`);
  }
  return data as DeletionRequest;
}

async function alignOpenRequest(
  supabase: SupabaseAdmin,
  request: DeletionRequest,
  params: {
    userID: string;
    email: string | null;
    requestID: string;
    clientPlatform: "ios" | "android" | "web";
    completionMode: "immediate" | "request_only";
    dueAt: string;
    targetUserHash: string;
  },
): Promise<DeletionRequest> {
  const { data, error } = await supabase
    .from("account_deletion_requests")
    .update({
      email: params.email,
      target_user_id: params.userID,
      target_email: params.email,
      target_user_hash: params.targetUserHash,
      requested_via: params.clientPlatform,
      completion_mode: params.completionMode,
      due_at: params.dueAt,
      note:
        `User requested account and data deletion. platform=${params.clientPlatform} request_id=${params.requestID}`,
      next_attempt_at: null,
      updated_at: new Date().toISOString(),
    })
    .eq("id", request.id)
    .eq("status", request.status)
    .select("id,status,completion_mode,due_at")
    .maybeSingle();
  if (error) throw new Error(`request_align_failed:${error.message}`);
  return (data as DeletionRequest | null) ?? request;
}

serve(async (req) => {
  if (!isAllowedBrowserOrigin(req)) {
    return json(req, 403, { error: "origin_not_allowed" });
  }
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) });
  }

  if (req.method !== "POST") {
    return json(req, 405, { error: "method_not_allowed" });
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceRoleKey) {
    return json(req, 500, {
      error: "not_configured",
      message: "Hesap silme servisi yapılandırılmamış.",
      support_id: newSupportID(),
    });
  }

  let body: RequestBody = {};
  try {
    body = await req.json();
  } catch {
    return json(req, 400, {
      error: "invalid_json",
      message: "İstek verisi okunamadı.",
      support_id: newSupportID(),
    });
  }

  const requestID = cleanTrace(body.request_id, crypto.randomUUID());
  if (!isUUID(requestID)) {
    return json(req, 400, {
      error: "invalid_request_id",
      support_id: newSupportID(),
    });
  }
  const supportID = cleanTrace(body.support_id, newSupportID());
  const clientPlatform = enumValue(
    body.client_platform,
    ["ios", "android", "web"] as const,
    "ios",
  );
  const completionMode = enumValue(
    body.completion_mode,
    ["immediate", "request_only"] as const,
    "immediate",
  );
  if (
    !clientPlatform || !completionMode ||
    (clientPlatform !== "web" && completionMode === "request_only")
  ) {
    return json(req, 400, {
      error: "invalid_deletion_mode",
      request_id: requestID,
      support_id: supportID,
    });
  }
  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) {
    return json(req, 401, {
      error: "unauthorized",
      message: "Hesap silme için oturum gerekli.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  const supabase = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userResult, error: userError } = await supabase.auth.getUser(
    jwt,
  );
  const user = userResult?.user;
  if (userError || !user) {
    return json(req, 401, {
      error: "unauthorized",
      message: "Oturum doğrulanamadı.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  const email = cleanEmail(body.email, user.email ?? null);
  const dueAt = new Date(
    Date.now() + (completionMode === "request_only" ? 24 * 60 * 60 * 1000 : 0),
  ).toISOString();

  let deletionRequest: DeletionRequest;
  try {
    const requestParams = {
      userID: user.id,
      email,
      requestID,
      clientPlatform,
      completionMode,
      dueAt,
      targetUserHash: await sha256Hex(user.id),
    };
    const openRequest = await findOpenRequest(supabase, user.id);
    deletionRequest = openRequest
      ? await alignOpenRequest(supabase, openRequest, requestParams)
      : await createDeletionRequest(supabase, requestParams);
  } catch (error) {
    return json(req, 500, {
      error: "request_failed",
      message: "Hesap silme kaydı oluşturulamadı.",
      failure_code: safeErrorCode(error),
      request_id: requestID,
      support_id: supportID,
    });
  }

  if (completionMode === "request_only") {
    const estimatedCompletionAt = deletionRequest.due_at ?? dueAt;
    await sendRequestAcceptedEmail(email, supportID, estimatedCompletionAt);
    return json(req, 202, {
      ok: true,
      completed: false,
      status: "pending",
      request_id: deletionRequest.id,
      support_id: supportID,
      estimated_completion_at: estimatedCompletionAt,
      message:
        "Hesap ve veri silme talebin alındı. İşlem en geç 24 saat içinde tamamlanacaktır.",
    });
  }

  const workerResponse = await fetch(
    `${supabaseURL}/functions/v1/account-deletion-complete`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${serviceRoleKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        request_id: deletionRequest.id,
        processed_by: "edge:function:request-account-deletion",
      }),
    },
  );
  const workerBody = await workerResponse.json().catch(() => ({})) as Record<
    string,
    unknown
  >;

  if (!workerResponse.ok) {
    return json(req, 500, {
      ok: false,
      completed: false,
      request_id: deletionRequest.id,
      support_id: String(workerBody.support_id ?? supportID),
      worker_status: workerResponse.status,
      worker_error: workerBody.error ?? "worker_failed",
      message:
        "Hesap silme işlemi tamamlanamadı. Lütfen tekrar dene; sorun devam ederse destek koduyla bize ulaş.",
    });
  }

  const storeName = clientPlatform === "android" ? "Google Play" : "App Store";
  return json(req, 200, {
    ok: true,
    completed: true,
    already_completed: workerBody.already_completed === true,
    auth_user_deleted: workerBody.auth_user_deleted === true ||
      workerBody.already_completed === true,
    request_id: deletionRequest.id,
    support_id: String(workerBody.support_id ?? supportID),
    message:
      `Hesabın ve verilerin silindi. Aktif ${storeName} aboneliğin varsa mağaza abonelik ayarlarından ayrıca yönetebilirsin.`,
  });
});
