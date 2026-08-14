/**
 * send-report-ready-notification — authenticated wrapper for report_ready push.
 *
 * The mobile app can call this after a client-rendered PDF report is archived.
 * Ownership is verified against public.reports before the privileged push sender
 * is invoked with the service-role key.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type RequestBody = {
  report_id?: string;
  request_id?: string;
  support_id?: string;
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function isUUID(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

function safeTrace(value: unknown, fallback: string): string {
  if (typeof value !== "string") return fallback;
  const clean = value.trim().replace(/[^A-Za-z0-9._:-]/g, "").slice(0, 80);
  return clean.length > 0 ? clean : fallback;
}

function safeLogText(value: unknown, maxLength = 180): string {
  return String(value)
    .replace(/Bearer\s+[^\s]+/gi, "Bearer [redacted]")
    .slice(0, maxLength);
}

serve(async (req) => {
  if (req.method !== "POST") {
    return json(405, { error: "method_not_allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json(500, { error: "not_configured" });
  }

  const fallbackRequestID = crypto.randomUUID();
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json(401, { error: "auth_required" });
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const requestID = safeTrace(body.request_id, fallbackRequestID);
  const supportID = safeTrace(
    body.support_id,
    `RD-${crypto.randomUUID().slice(0, 8).toUpperCase()}`,
  );
  if (!isUUID(body.report_id)) {
    return json(400, {
      error: "invalid_report_id",
      request_id: requestID,
      support_id: supportID,
    });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const token = authHeader.replace("Bearer ", "");
  const { data: { user }, error: authError } = await supabase.auth.getUser(
    token,
  );
  if (authError || !user) {
    return json(401, {
      error: "auth_invalid",
      request_id: requestID,
      support_id: supportID,
    });
  }

  const { data: report, error: reportError } = await supabase
    .from("reports")
    .select("id,user_id,analysis_id,format,kind,report_ready_push_sent_at")
    .eq("id", body.report_id)
    .eq("user_id", user.id)
    .maybeSingle();

  if (reportError || !report) {
    return json(404, {
      error: "report_not_found",
      request_id: requestID,
      support_id: supportID,
    });
  }

  if (report.report_ready_push_sent_at) {
    return json(200, {
      ok: true,
      status: "already_sent",
      report_id: report.id,
      request_id: requestID,
      support_id: supportID,
    });
  }

  const response = await fetch(
    `${supabaseUrl}/functions/v1/send-push-notification`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${serviceRoleKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        user_id: user.id,
        kind: "report_ready",
        event_key: "report_ready",
        data: {
          report_id: report.id,
          analysis_id: report.analysis_id,
          destination: "reports",
          format: report.format,
          kind: report.kind,
          request_id: requestID,
          support_id: supportID,
        },
      }),
    },
  );

  const responseText = await response.text();
  if (!response.ok) {
    console.warn(
      "Report ready push failed",
      JSON.stringify({
        request_id: requestID,
        support_id: supportID,
        report_id: report.id,
        status: response.status,
        body: safeLogText(responseText),
      }),
    );
    return json(200, {
      ok: false,
      status: "push_failed",
      report_id: report.id,
      request_id: requestID,
      support_id: supportID,
    });
  }
  let pushResult: { status?: string; reason?: string } = {};
  try {
    pushResult = responseText ? JSON.parse(responseText) : {};
  } catch {
    pushResult = {};
  }
  if (pushResult.status !== "sent") {
    return json(200, {
      ok: false,
      status: pushResult.status === "skipped" ? "push_skipped" : "push_failed",
      reason: pushResult.reason ?? "push_not_sent",
      report_id: report.id,
      request_id: requestID,
      support_id: supportID,
    });
  }

  await supabase
    .from("reports")
    .update({ report_ready_push_sent_at: new Date().toISOString() })
    .eq("id", report.id)
    .eq("user_id", user.id)
    .is("report_ready_push_sent_at", null);

  return json(200, {
    ok: true,
    status: "sent",
    report_id: report.id,
    request_id: requestID,
    support_id: supportID,
  });
});
