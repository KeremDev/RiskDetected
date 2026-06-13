/**
 * send-trial-reminder-notifications — sends Plus yearly trial reminders.
 *
 * Invoked by pg_cron through pg_net. JWT verification is disabled; callers must
 * provide x-trial-reminder-secret matching TRIAL_REMINDER_SECRET.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  PLUS_YEARLY_PRODUCT_ID,
  TRIAL_REMINDER_BODY,
  TRIAL_REMINDER_KIND,
  TRIAL_REMINDER_MAX_LEAD_MS,
  TRIAL_REMINDER_MIN_LEAD_MS,
  TRIAL_REMINDER_RETRY_AFTER_MS,
  TRIAL_REMINDER_TITLE,
  type TrialReminderCandidate,
  trialReminderDecision,
} from "../_shared/trial-reminder.ts";

type SupabaseAdminClient = ReturnType<typeof createClient<any>>;

type PushResult = {
  status?: string;
  event_id?: string | null;
  reason?: string;
  error?: string;
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function safeLogText(value: unknown, maxLength = 180): string {
  return String(value)
    .replace(/Bearer\s+[^\s]+/gi, "Bearer [redacted]")
    .slice(0, maxLength);
}

function clampLimit(value: unknown): number {
  const parsed = typeof value === "number"
    ? value
    : typeof value === "string"
    ? Number(value)
    : NaN;
  if (!Number.isFinite(parsed)) return 100;
  return Math.max(1, Math.min(Math.floor(parsed), 100));
}

async function loadCandidates(params: {
  supabase: SupabaseAdminClient;
  now: Date;
  limit: number;
}): Promise<TrialReminderCandidate[]> {
  const windowEnd = new Date(
    params.now.getTime() + TRIAL_REMINDER_MAX_LEAD_MS,
  ).toISOString();
  const windowStart = new Date(
    params.now.getTime() + TRIAL_REMINDER_MIN_LEAD_MS,
  ).toISOString();

  const { data, error } = await params.supabase
    .from("user_subscriptions")
    .select(
      "user_id,tier,status,product_id,trial_product_id,trial_ends_at,will_renew,trial_reminder_sent_at,trial_reminder_last_attempt_at",
    )
    .eq("tier", "plus")
    .in("status", ["active", "trialing", "grace_period"])
    .eq("trial_product_id", PLUS_YEARLY_PRODUCT_ID)
    .is("trial_reminder_sent_at", null)
    .gt("trial_ends_at", windowStart)
    .lte("trial_ends_at", windowEnd)
    .order("trial_ends_at", { ascending: true })
    .limit(params.limit * 2);

  if (error) throw new Error(`candidate_query_failed:${error.message}`);
  return (data ?? []) as TrialReminderCandidate[];
}

async function lockCandidate(params: {
  supabase: SupabaseAdminClient;
  userID: string;
  now: Date;
}): Promise<boolean> {
  const retryBefore = new Date(
    params.now.getTime() - TRIAL_REMINDER_RETRY_AFTER_MS,
  ).toISOString();

  const { data, error } = await params.supabase
    .from("user_subscriptions")
    .update({
      trial_reminder_last_attempt_at: params.now.toISOString(),
      trial_reminder_status: "pending",
    })
    .eq("user_id", params.userID)
    .eq("trial_product_id", PLUS_YEARLY_PRODUCT_ID)
    .eq("will_renew", true)
    .is("trial_reminder_sent_at", null)
    .or(
      `trial_reminder_last_attempt_at.is.null,trial_reminder_last_attempt_at.lt.${retryBefore}`,
    )
    .select("user_id")
    .maybeSingle();

  if (error) {
    throw new Error(`candidate_lock_failed:${safeLogText(error.message)}`);
  }
  return Boolean(data?.user_id);
}

async function sendPush(params: {
  supabaseUrl: string;
  serviceRoleKey: string;
  candidate: TrialReminderCandidate;
}): Promise<PushResult> {
  const response = await fetch(
    `${params.supabaseUrl}/functions/v1/send-push-notification`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${params.serviceRoleKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        user_id: params.candidate.user_id,
        kind: TRIAL_REMINDER_KIND,
        title: TRIAL_REMINDER_TITLE,
        body: TRIAL_REMINDER_BODY,
        data: {
          destination: "profile",
          event: TRIAL_REMINDER_KIND,
          product_id: PLUS_YEARLY_PRODUCT_ID,
          tier: "plus",
          trial_ends_at: params.candidate.trial_ends_at,
        },
      }),
    },
  );

  const payload = await response.json().catch(() => ({})) as PushResult;
  if (!response.ok) {
    return {
      status: "failed",
      error: payload.error ?? `push_http_${response.status}`,
      event_id: payload.event_id ?? null,
    };
  }
  return payload;
}

async function markResult(params: {
  supabase: SupabaseAdminClient;
  userID: string;
  now: Date;
  result: PushResult;
}) {
  const status = params.result.status === "sent"
    ? "sent"
    : params.result.status === "skipped"
    ? "skipped"
    : "failed";

  const { error } = await params.supabase
    .from("user_subscriptions")
    .update({
      trial_reminder_sent_at: status === "sent"
        ? params.now.toISOString()
        : null,
      trial_reminder_last_attempt_at: params.now.toISOString(),
      trial_reminder_status: status,
      trial_reminder_notification_event_id: params.result.event_id ?? null,
    })
    .eq("user_id", params.userID);
  if (error) {
    throw new Error(`trial_reminder_mark_failed:${safeLogText(error.message)}`);
  }
}

serve(async (req) => {
  if (req.method !== "POST") {
    return json(405, { error: "Method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const expectedSecret = Deno.env.get("TRIAL_REMINDER_SECRET");
  if (!supabaseUrl || !serviceRoleKey || !expectedSecret) {
    return json(500, { error: "Trial reminder function is not configured" });
  }

  if (req.headers.get("x-trial-reminder-secret") !== expectedSecret) {
    return json(401, { error: "Unauthorized" });
  }

  const body = await req.json().catch(() => ({}));
  const limit = clampLimit((body as Record<string, unknown>)?.limit);
  const now = new Date();
  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let candidates: TrialReminderCandidate[];
  try {
    candidates = await loadCandidates({ supabase, now, limit });
  } catch (error) {
    return json(500, {
      error: "trial_reminder_candidate_load_failed",
      detail: safeLogText(error instanceof Error ? error.message : error),
    });
  }

  const summary = {
    scanned: candidates.length,
    due: 0,
    sent: 0,
    skipped: 0,
    failed: 0,
    locked: 0,
    ignored: 0,
  };

  for (const candidate of candidates) {
    if (summary.due >= limit) break;
    const decision = trialReminderDecision(candidate, now);
    if (!decision.due || !candidate.user_id) {
      summary.ignored += 1;
      continue;
    }

    summary.due += 1;
    try {
      const locked = await lockCandidate({
        supabase,
        userID: candidate.user_id,
        now,
      });
      if (!locked) {
        summary.ignored += 1;
        continue;
      }
      summary.locked += 1;

      const result = await sendPush({
        supabaseUrl,
        serviceRoleKey,
        candidate,
      });
      await markResult({
        supabase,
        userID: candidate.user_id,
        now,
        result,
      });

      if (result.status === "sent") summary.sent += 1;
      else if (result.status === "skipped") summary.skipped += 1;
      else summary.failed += 1;
    } catch (error) {
      summary.failed += 1;
      await supabase
        .from("user_subscriptions")
        .update({
          trial_reminder_last_attempt_at: now.toISOString(),
          trial_reminder_status: "failed",
        })
        .eq("user_id", candidate.user_id);
      console.warn(
        "Trial reminder send failed",
        JSON.stringify({
          user_id: candidate.user_id,
          error: safeLogText(error instanceof Error ? error.message : error),
        }),
      );
    }
  }

  return json(200, { ok: true, ...summary });
});
