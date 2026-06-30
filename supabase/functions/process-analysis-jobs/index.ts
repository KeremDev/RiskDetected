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
const ANALYZE_WORKER_TIMEOUT_MS = 135_000;
const ANALYSIS_JOB_VISIBILITY_TIMEOUT_SECONDS = 180;

type QueueMessage = {
  msg_id: number | string;
  read_ct: number;
  message: Record<string, unknown>;
};

type DrainResult = {
  processed: number;
  failed: number;
  retainedForRetry: number;
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

async function fetchWithTimeout(
  url: string,
  init: RequestInit,
  timeoutMs: number,
): Promise<Response> {
  const controller = new AbortController();
  const timeoutID = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new Error(`analyze_fetch_timeout:${timeoutMs}`);
    }
    throw error;
  } finally {
    clearTimeout(timeoutID);
  }
}

async function deleteAnalysisJobMessage(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  msgID: QueueMessage["msg_id"],
) {
  const { error: deleteError } = await supabase
    .rpc("delete_analysis_job_message", {
      p_msg_id: msgID,
    });
  if (deleteError) {
    throw new Error(`delete_failed:${deleteError.message}`);
  }
}

async function deleteMessageIfAnalysisTerminal(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  msgID: QueueMessage["msg_id"],
  analysisID: string,
  userID: string,
): Promise<boolean> {
  const { data, error } = await supabase
    .from("analyses")
    .select("status")
    .eq("id", analysisID)
    .eq("user_id", userID)
    .maybeSingle();

  if (error) {
    console.error(
      "Analysis terminal status lookup failed",
      JSON.stringify({ analysis_id: analysisID, error: safeText(error) }),
    );
    return false;
  }

  if (data?.status !== "completed" && data?.status !== "failed") {
    return false;
  }

  await deleteAnalysisJobMessage(supabase, msgID);
  return true;
}

async function drainQueueMessages(params: {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  supabaseUrl: string;
  serviceRoleKey: string;
  queueMessages: QueueMessage[];
}): Promise<DrainResult> {
  let processed = 0;
  let failed = 0;
  let retainedForRetry = 0;

  for (const message of params.queueMessages) {
    const job = message.message ?? {};
    const analysisID = typeof job.analysis_id === "string"
      ? job.analysis_id
      : null;
    const userID = typeof job.user_id === "string" ? job.user_id : null;
    const isRepairJob = job.job_mode === "repair";

    try {
      const response = await fetchWithTimeout(
        `${params.supabaseUrl}/functions/v1/analyze`,
        {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${params.serviceRoleKey}`,
            "Content-Type": "application/json",
            "x-request-id": String(job.request_id ?? crypto.randomUUID()),
            "x-support-id": String(job.support_id ?? ""),
          },
          body: JSON.stringify({ ...job, __worker: true }),
        },
        ANALYZE_WORKER_TIMEOUT_MS,
      );
      const responseText = await response.text();

      if (!response.ok) {
        throw new Error(`${response.status}:${safeText(responseText)}`);
      }

      await deleteAnalysisJobMessage(params.supabase, message.msg_id);
      processed += 1;
    } catch (error) {
      let errorText = safeText(error);

      if (
        analysisID && userID &&
        await deleteMessageIfAnalysisTerminal(
          params.supabase,
          message.msg_id,
          analysisID,
          userID,
        )
      ) {
        processed += 1;
        continue;
      }

      if (message.read_ct >= MAX_READ_COUNT && isRepairJob) {
        try {
          const fallbackResponse = await fetchWithTimeout(
            `${params.supabaseUrl}/functions/v1/analyze`,
            {
              method: "POST",
              headers: {
                "Authorization": `Bearer ${params.serviceRoleKey}`,
                "Content-Type": "application/json",
                "x-request-id": String(job.request_id ?? crypto.randomUUID()),
                "x-support-id": String(job.support_id ?? ""),
              },
              body: JSON.stringify({
                ...job,
                __worker: true,
                coverage_repair_fallback_only: true,
                coverage_repair_fallback_reason: errorText,
              }),
            },
            ANALYZE_WORKER_TIMEOUT_MS,
          );
          const fallbackText = await fallbackResponse.text();
          if (!fallbackResponse.ok) {
            throw new Error(
              `repair_fallback_failed:${fallbackResponse.status}:${
                safeText(fallbackText)
              }`,
            );
          }
          await deleteAnalysisJobMessage(params.supabase, message.msg_id);
          processed += 1;
          continue;
        } catch (fallbackError) {
          errorText = safeText(fallbackError);
        }
      }

      failed += 1;
      if (analysisID && userID) {
        await params.supabase
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
          await params.supabase
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
        await deleteAnalysisJobMessage(params.supabase, message.msg_id);
      } else {
        retainedForRetry += 1;
      }
    }
  }

  return { processed, failed, retainedForRetry };
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
  const authorizedBySecret = Boolean(workerSecret) &&
    secretHeader === workerSecret;
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
      p_visibility_timeout: ANALYSIS_JOB_VISIBILITY_TIMEOUT_SECONDS,
    });

  if (readError) {
    return json(500, { error: "Queue read failed", detail: readError.message });
  }

  const queueMessages =
    (Array.isArray(messages) ? messages : []) as QueueMessage[];
  if (queueMessages.length === 0) {
    return json(200, { status: "empty", processed: 0 });
  }

  const drain = drainQueueMessages({
    supabase,
    supabaseUrl,
    serviceRoleKey,
    queueMessages,
  });

  const edgeRuntime = (globalThis as unknown as {
    EdgeRuntime?: { waitUntil?: (promise: Promise<unknown>) => void };
  }).EdgeRuntime;

  if (edgeRuntime?.waitUntil) {
    edgeRuntime.waitUntil(
      drain.catch((error) => {
        console.error("Queue drain failed", safeText(error));
      }),
    );
    return json(202, {
      status: "accepted",
      accepted: queueMessages.length,
      visibility_timeout_seconds: ANALYSIS_JOB_VISIBILITY_TIMEOUT_SECONDS,
    });
  }

  const { processed, failed, retainedForRetry } = await drain;

  return json(200, {
    status: "drained",
    processed,
    failed,
    retained_for_retry: retainedForRetry,
  });
});
