/**
 * process-analysis-jobs — drains durable analysis_jobs queue.
 *
 * Trusted backend only. Reads one queued analysis job, invokes analyze in
 * service-role worker mode, then deletes the queue message on terminal success.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  classifyDispatchObservation,
  DispatchObservation,
  forceCoverageQualityFallback,
  reconcileQueueAfterDispatch,
} from "./dispatch-policy.ts";

const QUEUE_NAME = "analysis_jobs";
const MAX_READ_COUNT = 3;
const ANALYZE_WORKER_TIMEOUT_MS = 135_000;
const ANALYSIS_JOB_VISIBILITY_TIMEOUT_SECONDS = 180;
const ANALYSIS_JOB_LEASE_SECONDS = 300;

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

function isPipelineV2Message(job: Record<string, unknown>): boolean {
  return Number(job.pipeline_version) === 2 &&
    Number.isInteger(Number(job.__job_generation)) &&
    Number(job.__job_generation) > 0;
}

function claimGuardVersion(job: Record<string, unknown>): number {
  return Number(job.claim_guard_version) === 2 ? 2 : 1;
}

async function deferAnalysisJobMessage(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  msgID: QueueMessage["msg_id"],
  seconds: number,
) {
  const { error } = await supabase.rpc("defer_analysis_job_message_v2", {
    p_msg_id: msgID,
    p_visibility_timeout: Math.max(1, Math.min(900, Math.ceil(seconds))),
  });
  if (error) throw new Error(`defer_failed:${error.message}`);
}

async function recordV2WorkerFailure(params: {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  userID: string;
  analysisID: string;
  msgID: QueueMessage["msg_id"];
  generation: number;
  claimToken: string;
  errorText: string;
  errorCode: string;
  terminal: boolean;
}): Promise<Record<string, unknown> | null> {
  const { data, error } = await params.supabase.rpc(
    "record_analysis_job_failure_v2",
    {
      p_user_id: params.userID,
      p_analysis_id: params.analysisID,
      p_msg_id: params.msgID,
      p_generation: params.generation,
      p_claim_token: params.claimToken,
      p_error: params.errorText,
      p_failure_code: params.errorCode,
      p_status_message: "Analiz arka planda tamamlanamadı. Lütfen tekrar dene.",
      p_terminal: params.terminal,
      p_raw_ai_response: null,
    },
  );
  if (error) {
    console.error(
      "V2 worker failure persistence failed",
      JSON.stringify({
        analysis_id: params.analysisID,
        error: safeText(error.message),
      }),
    );
    return null;
  }
  return data && typeof data === "object"
    ? data as Record<string, unknown>
    : null;
}

async function recordV2JobEvent(params: {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  userID: string;
  analysisID: string;
  msgID: QueueMessage["msg_id"];
  generation: number;
  workerAttempt: number;
  jobMode: "analysis" | "repair";
  eventType: string;
  httpStatus?: number | null;
  responseCode?: string | null;
  claimAction?: string | null;
  errorText?: string | null;
}): Promise<void> {
  try {
    const { error } = await params.supabase.rpc(
      "record_analysis_job_event_v2",
      {
        p_user_id: params.userID,
        p_analysis_id: params.analysisID,
        p_msg_id: params.msgID,
        p_generation: params.generation,
        p_worker_attempt: Math.max(1, Math.round(params.workerAttempt)),
        p_job_mode: params.jobMode,
        p_event_type: params.eventType,
        p_http_status: params.httpStatus ?? null,
        p_response_code: params.responseCode ?? null,
        p_claim_action: params.claimAction ?? null,
        p_safe_error_text: params.errorText
          ? safeText(params.errorText, 500)
          : null,
      },
    );
    if (error) {
      console.warn(
        "Analysis job event write skipped",
        JSON.stringify({
          analysis_id: params.analysisID,
          event_type: params.eventType,
          error: safeText(error.message),
        }),
      );
    }
  } catch (error) {
    console.warn(
      "Analysis job event write failed",
      JSON.stringify({
        analysis_id: params.analysisID,
        event_type: params.eventType,
        error: safeText(error),
      }),
    );
  }
}

async function reconcileGuardedV2Dispatch(params: {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  userID: string;
  analysisID: string;
  msgID: QueueMessage["msg_id"];
  generation: number;
  claimToken: string;
  workerAttempt: number;
  jobMode: "analysis" | "repair";
  observation: DispatchObservation;
  httpStatus: number | null;
  responseCode: string | null;
  errorText: string | null;
}): Promise<"deleted" | "kept"> {
  const eventType = params.observation === "success_response"
    ? "dispatch_success_response"
    : params.observation === "application_error"
    ? "dispatch_application_error"
    : "dispatch_ambiguous_transport";
  await recordV2JobEvent({
    ...params,
    eventType,
    claimAction: "reconcile",
  });

  const { data: validation, error: validationError } = await params.supabase
    .rpc("validate_analysis_job_claim_v2", {
      p_user_id: params.userID,
      p_analysis_id: params.analysisID,
      p_msg_id: params.msgID,
      p_generation: params.generation,
      p_claim_token: params.claimToken,
    });
  const claimState = validationError
    ? null
    : String(validation?.state ?? "unknown");
  const decision = reconcileQueueAfterDispatch({
    claimGuardVersion: 2,
    claimState,
    validationFailed: Boolean(validationError),
  });

  if (decision.action === "delete") {
    if (claimState === "superseded") {
      await recordV2JobEvent({
        ...params,
        eventType: "repair_superseded",
        claimAction: "delete",
      });
    }
    if (
      claimState === "completed" &&
      params.observation === "ambiguous_transport"
    ) {
      await recordV2JobEvent({
        ...params,
        eventType: "message_deleted_after_response_loss",
        claimAction: "delete",
      });
    }
    await deleteAnalysisJobMessage(params.supabase, params.msgID);
    return "deleted";
  }

  await recordV2JobEvent({
    ...params,
    eventType: "claim_kept",
    responseCode: params.responseCode ?? claimState,
    claimAction: decision.reason,
    errorText: validationError
      ? `claim_validation_failed:${safeText(validationError.message)}`
      : params.errorText,
  });
  return "kept";
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
    const isPipelineV2 = isPipelineV2Message(job);
    const guardVersion = isPipelineV2 ? claimGuardVersion(job) : 1;
    const isGuardedV2 = isPipelineV2 && guardVersion === 2;
    const generation = isPipelineV2 ? Number(job.__job_generation) : null;
    let claimToken: string | null = null;
    let workerAttempt = message.read_ct;
    let responseStatus: number | null = null;
    let responseCode: string | null = null;
    let responseBodyParsed = false;
    let guardedDispatchReconciled = false;

    try {
      if (isPipelineV2) {
        if (!analysisID || !userID || generation === null) {
          await deleteAnalysisJobMessage(params.supabase, message.msg_id);
          failed += 1;
          continue;
        }
        const { data: claim, error: claimError } = await params.supabase.rpc(
          "claim_analysis_job_v2",
          {
            p_user_id: userID,
            p_analysis_id: analysisID,
            p_msg_id: message.msg_id,
            p_generation: generation,
            p_job_mode: isRepairJob ? "repair" : "analysis",
            p_lease_seconds: ANALYSIS_JOB_LEASE_SECONDS,
            p_max_attempts: MAX_READ_COUNT,
          },
        );
        if (claimError) {
          throw new Error(`claim_failed:${claimError.message}`);
        }
        const claimState = String(claim?.state ?? "unknown");
        if (
          ["completed", "failed", "superseded", "max_attempts"].includes(
            claimState,
          )
        ) {
          if (isGuardedV2 && claimState === "max_attempts") {
            await recordV2JobEvent({
              supabase: params.supabase,
              userID,
              analysisID,
              msgID: message.msg_id,
              generation,
              workerAttempt: Number(claim?.worker_attempt ?? MAX_READ_COUNT),
              jobMode: isRepairJob ? "repair" : "analysis",
              eventType: "max_attempts",
              claimAction: "delete",
            });
          }
          await deleteAnalysisJobMessage(params.supabase, message.msg_id);
          processed += 1;
          continue;
        }
        if (claimState === "busy") {
          await deferAnalysisJobMessage(
            params.supabase,
            message.msg_id,
            Number(claim?.retry_after_seconds ?? 30),
          );
          retainedForRetry += 1;
          continue;
        }
        if (claim?.ok !== true || typeof claim?.claim_token !== "string") {
          throw new Error(`claim_rejected:${claimState}`);
        }
        claimToken = claim.claim_token;
        workerAttempt = Number(claim.worker_attempt ?? 1);
        if (isGuardedV2) {
          await recordV2JobEvent({
            supabase: params.supabase,
            userID,
            analysisID,
            msgID: message.msg_id,
            generation,
            workerAttempt,
            jobMode: isRepairJob ? "repair" : "analysis",
            eventType: "claim_acquired",
            responseCode: String(claim?.claim_reason ?? "unknown"),
            claimAction: "dispatch",
          });
          if (claim?.claim_reason === "lease_expired") {
            await recordV2JobEvent({
              supabase: params.supabase,
              userID,
              analysisID,
              msgID: message.msg_id,
              generation,
              workerAttempt,
              jobMode: isRepairJob ? "repair" : "analysis",
              eventType: "lease_expired_retry",
              responseCode: "lease_expired",
              claimAction: "dispatch",
            });
          }
        }
      }

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
          body: JSON.stringify({
            ...job,
            __worker: true,
            ...(isPipelineV2
              ? {
                pipeline_version: 2,
                __queue_msg_id: Number(message.msg_id),
                __job_generation: generation,
                __worker_claim_token: claimToken,
                __worker_attempt: workerAttempt,
              }
              : {}),
            ...(forceCoverageQualityFallback({
                repairKind: job.repair_kind,
                workerAttempt,
              })
              ? {
                coverage_repair_fallback_only: true,
                coverage_repair_fallback_reason:
                  "coverage_quality_single_attempt_guard",
              }
              : {}),
          }),
        },
        ANALYZE_WORKER_TIMEOUT_MS,
      );
      responseStatus = response.status;
      const responseText = await response.text();
      try {
        const responseBody = responseText ? JSON.parse(responseText) : null;
        responseBodyParsed = responseBody !== null &&
          typeof responseBody === "object";
        responseCode = typeof responseBody?.code === "string"
          ? responseBody.code
          : null;
      } catch {
        responseBodyParsed = false;
        responseCode = null;
      }

      if (
        isGuardedV2 && analysisID && userID && generation !== null &&
        claimToken
      ) {
        const observation = classifyDispatchObservation({
          transportError: false,
          httpStatus: responseStatus,
          responseBodyParsed,
        });
        const reconciliation = await reconcileGuardedV2Dispatch({
          supabase: params.supabase,
          userID,
          analysisID,
          msgID: message.msg_id,
          generation,
          claimToken,
          workerAttempt,
          jobMode: isRepairJob ? "repair" : "analysis",
          observation,
          httpStatus: responseStatus,
          responseCode,
          errorText: response.ok ? null : safeText(responseText, 500),
        });
        guardedDispatchReconciled = true;
        if (reconciliation === "deleted") {
          processed += 1;
        } else {
          if (observation !== "success_response") failed += 1;
          retainedForRetry += 1;
        }
        continue;
      }

      if (!response.ok) {
        throw new Error(`${response.status}:${safeText(responseText)}`);
      }

      await deleteAnalysisJobMessage(params.supabase, message.msg_id);
      processed += 1;
    } catch (error) {
      let errorText = safeText(error);

      if (
        isGuardedV2 && !guardedDispatchReconciled && analysisID && userID &&
        generation !== null && claimToken
      ) {
        try {
          const reconciliation = await reconcileGuardedV2Dispatch({
            supabase: params.supabase,
            userID,
            analysisID,
            msgID: message.msg_id,
            generation,
            claimToken,
            workerAttempt,
            jobMode: isRepairJob ? "repair" : "analysis",
            observation: "ambiguous_transport",
            httpStatus: responseStatus,
            responseCode,
            errorText,
          });
          if (reconciliation === "deleted") {
            processed += 1;
          } else {
            failed += 1;
            retainedForRetry += 1;
          }
        } catch (reconciliationError) {
          console.error(
            "Guarded V2 dispatch reconciliation failed; message retained",
            JSON.stringify({
              analysis_id: analysisID,
              error: safeText(reconciliationError),
            }),
          );
          failed += 1;
          retainedForRetry += 1;
        }
        continue;
      }

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

      if (
        isPipelineV2 &&
        (!analysisID || !userID || generation === null || !claimToken)
      ) {
        failed += 1;
        retainedForRetry += 1;
        continue;
      }

      if (
        isPipelineV2 && analysisID && userID && generation !== null &&
        claimToken
      ) {
        if (
          workerAttempt >= MAX_READ_COUNT && isRepairJob &&
          responseCode !== "lost_claim" && responseCode !== "superseded"
        ) {
          try {
            const fallbackResponse = await fetchWithTimeout(
              `${params.supabaseUrl}/functions/v1/analyze`,
              {
                method: "POST",
                headers: {
                  "Authorization": `Bearer ${params.serviceRoleKey}`,
                  "Content-Type": "application/json",
                  "x-request-id": String(
                    job.request_id ?? crypto.randomUUID(),
                  ),
                  "x-support-id": String(job.support_id ?? ""),
                },
                body: JSON.stringify({
                  ...job,
                  __worker: true,
                  pipeline_version: 2,
                  __queue_msg_id: Number(message.msg_id),
                  __job_generation: generation,
                  __worker_claim_token: claimToken,
                  __worker_attempt: workerAttempt,
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

        const deterministicFailure = responseStatus !== null &&
          responseStatus >= 400 && responseStatus < 500 &&
          ![408, 409, 425, 429].includes(responseStatus);
        const terminal = workerAttempt >= MAX_READ_COUNT ||
          deterministicFailure;
        const failureResult = await recordV2WorkerFailure({
          supabase: params.supabase,
          userID,
          analysisID,
          msgID: message.msg_id,
          generation,
          claimToken,
          errorText,
          errorCode: responseCode ??
            (responseStatus
              ? `analyze_http_${responseStatus}`
              : "worker_transport_error"),
          terminal,
        });

        if (terminal && failureResult?.ok === true) {
          await deleteAnalysisJobMessage(params.supabase, message.msg_id);
        } else if (responseCode === "superseded") {
          await deleteAnalysisJobMessage(params.supabase, message.msg_id);
        } else {
          retainedForRetry += 1;
        }
        failed += 1;
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
