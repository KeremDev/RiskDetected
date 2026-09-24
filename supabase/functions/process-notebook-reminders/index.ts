import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";
import { deliverToAPNs } from "../send-push-notification/apns-delivery.ts";
import { userFacingCopy } from "../_shared/user-facing-copy.ts";

const base64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
const encode = (value: unknown) => base64url(new TextEncoder().encode(JSON.stringify(value)));
async function providerToken(): Promise<string> {
  const keyID = Deno.env.get("APNS_KEY_ID");
  const team = Deno.env.get("APNS_TEAM_ID");
  const pem = Deno.env.get("APNS_PRIVATE_KEY");
  if (!keyID || !team || !pem) throw new Error("PUSH_CONFIGURATION_UNAVAILABLE");
  const raw = pem.replaceAll("\\n", "\n").replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  const key = await crypto.subtle.importKey("pkcs8", Uint8Array.from(atob(raw), c => c.charCodeAt(0)),
    { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const data = `${encode({ alg: "ES256", kid: keyID })}.${encode({ iss: team, iat: Math.floor(Date.now() / 1000) })}`;
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(data));
  return `${data}.${base64url(new Uint8Array(signature))}`;
}

Deno.serve(async (request) => {
  const secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const workerSecret = Deno.env.get("ISG_WORKSPACE_JOBS_SECRET");
  const authorized = secret && request.headers.get("Authorization") === `Bearer ${secret}`;
  const scheduled = workerSecret && request.headers.get("x-isg-worker-secret") === workerSecret;
  if (!secret || (!authorized && !scheduled)) return new Response(null, { status: 401 });
  if (request.method !== "POST") return new Response(null, { status: 405 });
  const client = createClient(Deno.env.get("SUPABASE_URL")!, secret, { auth: { persistSession: false } });
  try {
    // Verify credentials before claiming: missing configuration cannot consume reminders.
    const token = await providerToken();
    const { data: jobs, error } = await client.rpc("isg_notebook_delivery_claim_v1", { p_limit: 5 });
    if (error) throw new Error("CLAIM_UNAVAILABLE");
    let sent = 0;
    for (const job of jobs ?? []) {
      const params = { p_id: job.id, p_claim: job.claim_token };
      const { data: device, error: snapshotError } = await client.rpc("isg_notebook_delivery_snapshot_v1", params);
      let state = "suppressed";
      if (!snapshotError && device) {
        const host = device.environment === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
        const result = await deliverToAPNs({ url: `https://${host}/3/device/${device.token}`,
          headers: { authorization: `bearer ${token}`, "apns-topic": device.application_id,
            "apns-push-type": "alert", "apns-priority": "10", "apns-collapse-id": job.id },
          payload: { aps: { alert: { title: userFacingCopy("notebookReminderTitle", device.language),
            body: userFacingCopy("notebookReminderBody", device.language) }, sound: "default" },
            kind: "personal_reminder", data: { destination: "notebook" } },
          maxAttempts: 3 });
        // Unknown transport outcome is never automatically retried: no duplicate pushes.
        state = result.final.outcome === "accepted" ? "sent" : result.final.httpStatus == null ? "ambiguous" : "failed";
        if (state === "sent") sent++;
      }
      const completed = await client.rpc("isg_notebook_delivery_complete_v1", { ...params, p_state: state });
      if (completed.error) throw new Error("COMPLETION_UNAVAILABLE");
    }
    return Response.json({ claimed: jobs?.length ?? 0, sent });
  } catch {
    // Never serialize tokens, note data, provider responses or credentials to logs.
    return Response.json({ error: "REMINDER_WORKER_UNAVAILABLE" }, { status: 503 });
  }
});
