/**
 * retention-cleanup — RiskDetected scheduled retention worker
 *
 * Intended use:
 * - Run daily from Supabase Cron or manually by an operator.
 * - Requires a privileged Authorization bearer token. In production, call with
 *   the service-role key from a secured server/cron context, never from the app.
 *
 * Policy:
 * - Free analysis photos expire after 30 days.
 * - Pro analysis photos expire after 365 days.
 * - Raw AI responses expire after 30 days.
 * - PDF reports stay until the user deletes them.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type ExpiredPhoto = {
  id: string;
  storage_path: string;
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method !== "POST") {
    return json(405, { error: "Method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !serviceRoleKey) {
    return json(500, { error: "Retention cleanup is not configured" });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const expectedHeader = `Bearer ${serviceRoleKey}`;
  const cleanupSecret = Deno.env.get("RETENTION_CLEANUP_SECRET");
  const providedSecret = req.headers.get("x-retention-cleanup-secret");

  if (authHeader !== expectedHeader && (!cleanupSecret || providedSecret !== cleanupSecret)) {
    return json(401, { error: "Unauthorized" });
  }

  let batchSize = 500;
  try {
    const body = await req.json().catch(() => ({}));
    if (typeof body.batch_size === "number" && Number.isFinite(body.batch_size)) {
      batchSize = Math.max(1, Math.min(1000, Math.floor(body.batch_size)));
    }
  } catch {
    // Keep default batch size.
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const now = new Date().toISOString();

  const { data: rawRows, error: rawSelectError } = await supabase
    .from("analyses")
    .select("id")
    .not("raw_ai_response", "is", null)
    .lte("raw_ai_response_expires_at", now)
    .order("raw_ai_response_expires_at", { ascending: true })
    .limit(batchSize);

  if (rawSelectError) {
    return json(500, { error: "Failed to select expired raw AI responses", details: rawSelectError.message });
  }

  const rawIds = (rawRows ?? []).map((row) => row.id as string);
  let expiredRawAI = 0;

  if (rawIds.length > 0) {
    const { error: rawUpdateError } = await supabase
      .from("analyses")
      .update({ raw_ai_response: null, updated_at: now })
      .in("id", rawIds);

    if (rawUpdateError) {
      return json(500, { error: "Failed to clear expired raw AI responses", details: rawUpdateError.message });
    }

    expiredRawAI = rawIds.length;
  }

  const { data: expiredPhotos, error: photoSelectError } = await supabase
    .from("photos")
    .select("id, storage_path")
    .lte("retention_expires_at", now)
    .order("retention_expires_at", { ascending: true })
    .limit(batchSize);

  if (photoSelectError) {
    return json(500, { error: "Failed to select expired photos", details: photoSelectError.message });
  }

  const photos = (expiredPhotos ?? []) as ExpiredPhoto[];
  const photoIds = photos.map((photo) => photo.id);
  const storagePaths = photos.map((photo) => photo.storage_path).filter(Boolean);

  let removedStorageObjects = 0;
  let removedPhotoRows = 0;

  if (storagePaths.length > 0) {
    const { data: removed, error: storageRemoveError } = await supabase.storage
      .from("photos")
      .remove(storagePaths);

    if (storageRemoveError) {
      return json(500, { error: "Failed to remove expired photo objects", details: storageRemoveError.message });
    }

    removedStorageObjects = removed?.length ?? storagePaths.length;
  }

  if (photoIds.length > 0) {
    await supabase
      .from("findings")
      .update({ photo_id: null })
      .in("photo_id", photoIds);

    const { error: photoDeleteError } = await supabase
      .from("photos")
      .delete()
      .in("id", photoIds);

    if (photoDeleteError) {
      return json(500, { error: "Failed to delete expired photo rows", details: photoDeleteError.message });
    }

    removedPhotoRows = photoIds.length;
  }

  return json(200, {
    ok: true,
    expired_raw_ai: expiredRawAI,
    expired_photo_rows: removedPhotoRows,
    expired_storage_objects: removedStorageObjects,
  });
});
