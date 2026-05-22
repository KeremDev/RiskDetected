/**
 * process-analysis-jobs — drains durable analysis_jobs queue.
 *
 * Trusted backend only. Reads one queued analysis job, invokes analyze in
 * service-role worker mode, then deletes the queue message on terminal success.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const QUEUE_NAME = "analysis_jobs";
const MAX_READ_COUNT = 3;

type QueueMessage = {
  msg_id: number | string;
  read_ct: number;
  message: Record<string, unknown>;
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function safeText(value: unknown, maxLength = 220): string {
  return String(value)
    .replace(/Bearer\s+[^\s]+/gi, "Bearer [redacted]")
    .slice(0, maxLength);
}

serve(async (req) => {
  if (req.method !== "POST") {
    return json(405, { error: "Method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json(500, { error: "Supabase service credentials missing" });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const workerSecret = Deno.env.get("PROCESS_ANALYSIS_JOBS_SECRET");
  const secretHeader = req.headers.get("x-analysis-worker-secret") ?? "";
  const authorizedBySecret = Boolean(workerSecret) && secretHeader === workerSecret;
  if (authHeader !== `Bearer ${serviceRoleKey}` && !authorizedBySecret) {
    return json(401, { error: "Unauthorized" });
  }

  let requestedLimit = 1;
  try {
    const body = await req.json();
    requestedLimit = Math.max(1, Math.min(3, Number(body?.limit ?? 1)));
  } catch {
    requestedLimit = 1;
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: messages, error: readError } = await supabase
    .rpc("read_analysis_job_messages", {
      p_limit: requestedLimit,
      p_visibility_timeout: 600,
    });

  if (readError) {
    return json(500, { error: "Queue read failed", detail: readError.message });
  }

  const queueMessages = (Array.isArray(messages) ? messages : []) as QueueMessage[];
  if (queueMessages.length === 0) {
    return json(200, { status: "empty", processed: 0 });
  }

  let processed = 0;
  let failed = 0;
  let retainedForRetry = 0;

  for (const message of queueMessages) {
    const job = message.message ?? {};
    const analysisID = typeof job.analysis_id === "string"
      ? job.analysis_id
      : null;
    const userID = typeof job.user_id === "string" ? job.user_id : null;

    try {
      const response = await fetch(`${supabaseUrl}/functions/v1/analyze`, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${serviceRoleKey}`,
          "Content-Type": "application/json",
          "x-request-id": String(job.request_id ?? crypto.randomUUID()),
          "x-support-id": String(job.support_id ?? ""),
        },
        body: JSON.stringify({ ...job, __worker: true }),
      });
      const responseText = await response.text();

      if (!response.ok) {
        throw new Error(`${response.status}:${safeText(responseText)}`);
      }

      const { error: deleteError } = await supabase
        .rpc("delete_analysis_job_message", {
          p_msg_id: message.msg_id,
        });
      if (deleteError) {
        throw new Error(`delete_failed:${deleteError.message}`);
      }
      processed += 1;
    } catch (error) {
      failed += 1;
      const errorText = safeText(error);
      if (analysisID && userID) {
        await supabase
          .from("analyses")
          .update({
            last_worker_error: errorText,
            worker_attempt_count: message.read_ct,
          })
          .eq("id", analysisID)
          .eq("user_id", userID);
      }

      if (message.read_ct >= MAX_READ_COUNT) {
        if (analysisID && userID) {
          await supabase
            .from("analyses")
            .update({
              status: "failed",
              status_message:
                "Analiz arka planda tamamlanamadı. Lütfen tekrar dene.",
              last_worker_error: errorText,
            })
            .eq("id", analysisID)
            .eq("user_id", userID);
        }
        await supabase
          .rpc("delete_analysis_job_message", {
            p_msg_id: message.msg_id,
          });
      } else {
        retainedForRetry += 1;
      }
    }
  }

  return json(200, {
    status: "drained",
    processed,
    failed,
    retained_for_retry: retainedForRetry,
  });
});
