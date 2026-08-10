/**
 * process-account-deletion-queue — trusted hourly web deletion worker.
 *
 * It only selects authenticated web requests that opted into request_only.
 * Claiming and destructive work remain inside account-deletion-complete, which
 * provides the atomic status transition and idempotent retry contract.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type QueueBody = {
  limit?: unknown;
};

type QueueRequest = {
  id: string;
  attempt_count: number;
  due_at: string;
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function constantTimeEquals(left: string, right: string): boolean {
  const encoder = new TextEncoder();
  const leftBytes = encoder.encode(left);
  const rightBytes = encoder.encode(right);
  let mismatch = leftBytes.length ^ rightBytes.length;
  const maxLength = Math.max(leftBytes.length, rightBytes.length);
  for (let index = 0; index < maxLength; index += 1) {
    mismatch |= (leftBytes[index] ?? 0) ^ (rightBytes[index] ?? 0);
  }
  return mismatch === 0;
}

function safeLimit(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed)
    ? Math.max(1, Math.min(25, Math.trunc(parsed)))
    : 25;
}

function newSupportID(): string {
  return `RD-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
}

function safeAlarmToken(value: unknown, fallback: string): string {
  if (typeof value !== "string") return fallback;
  const clean = value.toLowerCase().replace(/[^a-z0-9_.-]/g, "_").slice(
    0,
    80,
  );
  return clean || fallback;
}

async function sendQueueFailureAlert(params: {
  supportID: string;
  failureCode: string;
  httpStatus: number;
}): Promise<void> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  const from = Deno.env.get("RESEND_FROM_EMAIL") ??
    "RiskDetected <info@riskdetected.com>";
  const to = Deno.env.get("ACCOUNT_DELETION_ALERT_EMAIL") ??
    "info@riskdetected.com";
  if (!apiKey || !to) return;
  await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: [to],
      subject: "RiskDetected hesap silme worker uyarısı",
      text: `PII içermeyen worker uyarısı\nDestek kodu: ${params.supportID}\n` +
        `Hata kodu: ${params.failureCode}\nHTTP: ${params.httpStatus}`,
    }),
  }).catch(() => undefined);
}

serve(async (req) => {
  if (req.method !== "POST") {
    return json(405, { error: "method_not_allowed" });
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const expectedSecret = Deno.env.get("ACCOUNT_DELETION_QUEUE_SECRET");
  const providedSecret = req.headers.get("x-account-deletion-queue-secret") ??
    "";

  if (!supabaseURL || !serviceRoleKey || !expectedSecret) {
    return json(500, { error: "not_configured" });
  }
  if (!constantTimeEquals(providedSecret, expectedSecret)) {
    return json(401, { error: "unauthorized" });
  }

  let body: QueueBody = {};
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const limit = safeLimit(body.limit);
  const now = new Date().toISOString();
  const supabase = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await supabase
    .from("account_deletion_requests")
    .select("id,attempt_count,due_at")
    .in("status", ["pending", "processing"])
    .eq("completion_mode", "request_only")
    .eq("requested_via", "web")
    .or(`next_attempt_at.is.null,next_attempt_at.lte.${now}`)
    .lt("attempt_count", 10)
    .order("created_at", { ascending: true })
    .limit(limit);

  if (error) {
    return json(500, { error: "queue_lookup_failed" });
  }

  let completed = 0;
  let failed = 0;
  let conflicts = 0;

  for (const item of (data ?? []) as QueueRequest[]) {
    try {
      const response = await fetch(
        `${supabaseURL}/functions/v1/account-deletion-complete`,
        {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${serviceRoleKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            request_id: item.id,
            processed_by: "edge:function:process-account-deletion-queue",
          }),
        },
      );

      const responseBody = await response.json().catch(() => ({})) as Record<
        string,
        unknown
      >;
      if (response.ok) {
        completed += 1;
      } else if (response.status === 409) {
        conflicts += 1;
      } else {
        failed += 1;
        await sendQueueFailureAlert({
          supportID: safeAlarmToken(responseBody.support_id, newSupportID()),
          failureCode: safeAlarmToken(
            responseBody.failure_code ?? responseBody.error,
            "worker_failed",
          ),
          httpStatus: response.status,
        });
      }
    } catch {
      failed += 1;
      await sendQueueFailureAlert({
        supportID: newSupportID(),
        failureCode: "worker_unreachable",
        httpStatus: 0,
      });
    }
  }

  return json(200, {
    ok: true,
    selected: data?.length ?? 0,
    completed,
    failed,
    conflicts,
  });
});
