/**
 * firebase-phone-bridge
 *
 * Phone authentication is paused for the MVP. This disabled endpoint is kept
 * only so accidental calls fail explicitly instead of exposing the previous
 * reusable credential bridge.
 *
 * Before re-enabling phone auth, replace this with a short-lived exchange flow
 * that does not return reusable Supabase email/password credentials to clients.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

serve((_req) =>
  json(410, {
    error: "firebase_phone_bridge_disabled",
    message:
      "Phone authentication is paused. Re-enable only after replacing the reusable credential bridge with a short-lived exchange flow.",
  })
);
