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
};

type DeletionRequest = {
  id: string;
  status: string;
};

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
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

function cleanEmail(value: unknown, fallback: string | null): string | null {
  if (typeof value !== "string") return fallback;
  const clean = value.trim().toLowerCase().slice(0, 240);
  return clean.includes("@") ? clean : fallback;
}

function safeErrorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message.replace(/Bearer\s+[^\s]+/gi, "Bearer [redacted]")
      .slice(0, 240);
  }
  return String(error).replace(/Bearer\s+[^\s]+/gi, "Bearer [redacted]").slice(
    0,
    240,
  );
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
  },
): Promise<DeletionRequest> {
  const { data, error } = await supabase
    .from("account_deletion_requests")
    .insert({
      user_id: params.userID,
      email: params.email,
      requested_scope: "account_and_data",
      note:
        `User requested account and data deletion from iOS Profile > Verilerim. request_id=${params.requestID}`,
      target_user_id: params.userID,
      target_email: params.email,
    })
    .select("id,status")
    .single();

  if (error) {
    throw new Error(`request_create_failed:${error.message}`);
  }
  return data as DeletionRequest;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return json(405, { error: "method_not_allowed" });
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceRoleKey) {
    return json(500, {
      error: "not_configured",
      message: "Hesap silme servisi yapılandırılmamış.",
      support_id: newSupportID(),
    });
  }

  let body: RequestBody = {};
  try {
    body = await req.json();
  } catch {
    return json(400, {
      error: "invalid_json",
      message: "İstek verisi okunamadı.",
      support_id: newSupportID(),
    });
  }

  const requestID = cleanTrace(body.request_id, crypto.randomUUID());
  const supportID = cleanTrace(body.support_id, newSupportID());
  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) {
    return json(401, {
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
    return json(401, {
      error: "unauthorized",
      message: "Oturum doğrulanamadı.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  const email = cleanEmail(body.email, user.email ?? null);

  let deletionRequest: DeletionRequest;
  try {
    const openRequest = await findOpenRequest(supabase, user.id);
    deletionRequest = openRequest ?? (await createDeletionRequest(supabase, {
        userID: user.id,
        email,
        requestID,
      }));
  } catch (error) {
    return json(500, {
      error: "request_failed",
      message: "Hesap silme kaydı oluşturulamadı.",
      detail: safeErrorMessage(error),
      request_id: requestID,
      support_id: supportID,
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
    return json(202, {
      ok: true,
      completed: false,
      request_id: deletionRequest.id,
      support_id: String(workerBody.support_id ?? supportID),
      worker_status: workerResponse.status,
      worker_error: workerBody.error ?? "worker_failed",
      message:
        "Hesap silme isteğin alındı. Güvenli silme işlemi kuyruğa alındı; işlem tamamlanmazsa destek koduyla bize ulaş.",
    });
  }

  return json(200, {
    ok: true,
    completed: true,
    already_completed: workerBody.already_completed === true,
    auth_user_deleted: workerBody.auth_user_deleted === true ||
      workerBody.already_completed === true,
    request_id: deletionRequest.id,
    support_id: String(workerBody.support_id ?? supportID),
    message:
      "Hesabın ve verilerin silindi. Aktif App Store aboneliğin varsa Apple abonelik ayarlarından ayrıca yönetebilirsin.",
  });
});
