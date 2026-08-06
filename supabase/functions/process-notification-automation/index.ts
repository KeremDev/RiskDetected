/**
 * process-notification-automation
 *
 * Cron-only job producer/consumer for engagement and manual app reminders.
 * It is deliberately independent from the analysis PGMQ worker.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  ambiguousNestedTransportDecision,
  type JobCompletionDecision,
  notificationJobCompletionDecision,
  type PushResultLike,
} from "./job-result-policy.ts";

type SupabaseAdminClient = ReturnType<typeof createClient<any>>;

type ClaimedJob = {
  job_id: string;
  claim_token: string;
  user_id: string;
  rule_id: string | null;
  rule_version_id: string | null;
  campaign_id: string | null;
  template_id: string | null;
  kind: string;
  title: string;
  body: string;
  destination: string;
  payload_data: Record<string, unknown>;
  dedupe_key: string;
  attempt_count: number;
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function clampLimit(value: unknown): number {
  const parsed = typeof value === "number"
    ? value
    : typeof value === "string"
    ? Number(value)
    : NaN;
  if (!Number.isFinite(parsed)) return 100;
  return Math.max(1, Math.min(Math.floor(parsed), 200));
}

function safeErrorText(value: unknown, maxLength = 300): string {
  return String(value)
    .replace(/Bearer\s+[^\s]+/gi, "Bearer [redacted]")
    .replace(/[A-Fa-f0-9]{64,}/g, "[hex]")
    .slice(0, maxLength);
}

async function completeJob(params: {
  supabase: SupabaseAdminClient;
  job: ClaimedJob;
  decision: JobCompletionDecision;
}) {
  const { data, error } = await params.supabase.rpc(
    "complete_notification_job_v1",
    {
      p_job_id: params.job.job_id,
      p_claim_token: params.job.claim_token,
      p_result: params.decision.result,
      p_notification_event_id: params.decision.eventID,
      p_retryable: params.decision.retryable,
      p_error_code: params.decision.errorCode,
      p_error_text: null,
      p_now: new Date().toISOString(),
    },
  );
  if (error) throw new Error(`job_complete_failed:${error.code}`);
  return data;
}

async function processJob(params: {
  supabase: SupabaseAdminClient;
  supabaseUrl: string;
  serviceRoleKey: string;
  job: ClaimedJob;
}) {
  const now = new Date().toISOString();
  const { data: validation, error: validationError } = await params.supabase
    .rpc(
      "validate_notification_job_v1",
      {
        p_job_id: params.job.job_id,
        p_claim_token: params.job.claim_token,
        p_now: now,
      },
    );
  if (validationError) {
    return { outcome: "claim_preserved", error: validationError.code };
  }
  if (validation?.allowed !== true) {
    if (validation?.reason === "already_delivered_current_job") {
      return { outcome: "sent", reconciled: true };
    }
    if (validation?.deferred === true) {
      return {
        outcome: "deferred",
        reason: validation?.reason ?? "send_deferred",
      };
    }
    return {
      outcome: "skipped",
      reason: validation?.reason ?? "send_revalidation_failed",
    };
  }

  let decision: JobCompletionDecision;
  try {
    const response = await fetch(
      `${params.supabaseUrl}/functions/v1/send-push-notification`,
      {
        method: "POST",
        signal: AbortSignal.timeout(120_000),
        headers: {
          "Authorization": `Bearer ${params.serviceRoleKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          user_id: params.job.user_id,
          kind: params.job.kind,
          data: {
            ...params.job.payload_data,
            destination: params.job.destination,
          },
          source: params.job.campaign_id ? "manual" : "automation",
          job_id: params.job.job_id,
          campaign_id: params.job.campaign_id,
          template_id: params.job.template_id,
          dedupe_key: `notification-job:${params.job.job_id}`,
        }),
      },
    );
    const payload = await response.json().catch(() => ({})) as PushResultLike;
    decision = notificationJobCompletionDecision(response.ok, payload);
  } catch {
    decision = ambiguousNestedTransportDecision();
  }

  await completeJob({
    supabase: params.supabase,
    job: params.job,
    decision,
  });
  return { outcome: decision.result, retryable: decision.retryable };
}

serve(async (req) => {
  if (req.method !== "POST") {
    return json(405, { error: "Method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const expectedSecret = Deno.env.get("NOTIFICATION_AUTOMATION_SECRET");
  if (!supabaseUrl || !serviceRoleKey || !expectedSecret) {
    return json(500, { error: "Notification automation is not configured" });
  }
  if (
    req.headers.get("x-notification-automation-secret") !== expectedSecret
  ) {
    return json(401, { error: "Unauthorized" });
  }

  const requestBody = await req.json().catch(() => ({})) as Record<
    string,
    unknown
  >;
  const limit = clampLimit(requestBody.limit);
  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const now = new Date().toISOString();

  const { data: enqueueSummary, error: enqueueError } = await supabase.rpc(
    "enqueue_notification_jobs_v1",
    { p_now: now, p_limit: limit * 5 },
  );
  if (enqueueError) {
    return json(500, {
      error: "notification_job_enqueue_failed",
      detail: safeErrorText(enqueueError.code),
    });
  }

  const { data: jobs, error: claimError } = await supabase.rpc(
    "claim_notification_jobs_v1",
    { p_now: now, p_limit: limit, p_lease_seconds: 300 },
  );
  if (claimError) {
    return json(500, {
      error: "notification_job_claim_failed",
      detail: safeErrorText(claimError.code),
      enqueue: enqueueSummary,
    });
  }

  const summary = {
    claimed: (jobs ?? []).length,
    sent: 0,
    skipped: 0,
    failed: 0,
    ambiguous: 0,
    deferred: 0,
    retry_released: 0,
    claim_preserved: 0,
  };

  for (const job of (jobs ?? []) as ClaimedJob[]) {
    try {
      const result = await processJob({
        supabase,
        supabaseUrl,
        serviceRoleKey,
        job,
      });
      if (result.outcome === "sent") summary.sent += 1;
      else if (result.outcome === "skipped") summary.skipped += 1;
      else if (result.outcome === "ambiguous") summary.ambiguous += 1;
      else if (result.outcome === "deferred") summary.deferred += 1;
      else if (result.outcome === "claim_preserved") {
        summary.claim_preserved += 1;
      } else if (result.retryable) summary.retry_released += 1;
      else summary.failed += 1;
    } catch (error) {
      summary.claim_preserved += 1;
      console.warn(
        "Notification automation job preserved",
        JSON.stringify({
          job_id: job.job_id,
          error: safeErrorText(error),
        }),
      );
    }
  }

  return json(200, {
    ok: true,
    enqueue: enqueueSummary,
    ...summary,
  });
});
