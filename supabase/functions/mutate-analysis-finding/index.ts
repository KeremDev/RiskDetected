/**
 * mutate-analysis-finding — authenticated edits/deletes for AI findings.
 *
 * The mobile app never receives direct write grants on public.findings. This
 * endpoint verifies ownership, writes an audit event, updates/deletes the row,
 * recalculates analysis aggregates, and returns the refreshed analysis bundle.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type MutationAction = "update" | "delete";

type MeasurePatch = {
  kind?: unknown;
  title?: unknown;
  text?: unknown;
};

type FindingPatch = {
  title?: unknown;
  category?: unknown;
  description?: unknown;
  recommended_action?: unknown;
  recommended_measures?: unknown;
  references_text?: unknown;
  root_cause_text?: unknown;
  fk_probability?: unknown;
  fk_frequency?: unknown;
  fk_severity?: unknown;
  m5_probability?: unknown;
  m5_severity?: unknown;
  source_photo_indices?: unknown;
};

type Body = {
  analysis_id?: unknown;
  finding_id?: unknown;
  action?: unknown;
  patch?: FindingPatch;
  expected_finding_version?: unknown;
  client_app_version?: unknown;
  client_app_build?: unknown;
  client_platform?: unknown;
  api_contract_version?: unknown;
  client_capabilities?: unknown;
  request_id?: unknown;
  support_id?: unknown;
};

type FindingRow = Record<string, unknown> & {
  id: string;
  analysis_id: string;
  user_id: string;
  title: string;
  finding_version?: number | null;
};

const FK_PROBABILITY_VALUES = [0.2, 0.5, 1, 3, 6, 10];
const FK_FREQUENCY_VALUES = [0.5, 1, 2, 3, 6, 10];
const FK_SEVERITY_VALUES = [1, 3, 7, 15, 40, 100];

type ReleaseRolloutMode = "off" | "build_allowlist" | "min_build" | "all";

type ClientReleaseContext = {
  platform: string;
  appBuild: string | null;
  appBuildNumber: number | null;
  apiContractVersion: number;
  capabilities: Record<string, boolean>;
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function safeTrace(value: unknown, fallback: string): string {
  if (typeof value !== "string") return fallback;
  const clean = value.trim().replace(/[^A-Za-z0-9._:-]/g, "").slice(0, 80);
  return clean.length > 0 ? clean : fallback;
}

function isUUID(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

function text(value: unknown, maxLength: number): string | undefined {
  if (value === undefined) return undefined;
  const clean = String(value ?? "").trim().slice(0, maxLength);
  return clean;
}

function requiredText(
  value: unknown,
  field: string,
  maxLength: number,
): string {
  const clean = text(value, maxLength) ?? "";
  if (!clean) throw new Error(`validation:${field}`);
  return clean;
}

function bool(value: unknown, fallback: boolean): boolean {
  return typeof value === "boolean" ? value : fallback;
}

function positiveInt(value: unknown, fallback: number): number {
  const parsed = Math.round(Number(value));
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function optionalPositiveInt(value: unknown): number | null {
  const parsed = Math.round(Number(value));
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function stringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => String(item ?? "").trim())
    .filter((item) => item.length > 0);
}

function rolloutMode(value: unknown): ReleaseRolloutMode {
  const mode = String(value ?? "off").trim().toLowerCase();
  if (
    mode === "off" || mode === "build_allowlist" || mode === "min_build" ||
    mode === "all"
  ) {
    return mode;
  }
  return "off";
}

function clientReleaseContext(body: Body): ClientReleaseContext {
  const appBuild = typeof body.client_app_build === "string"
    ? body.client_app_build.trim()
    : null;
  const capabilities = body.client_capabilities &&
      typeof body.client_capabilities === "object"
    ? Object.fromEntries(
      Object.entries(body.client_capabilities as Record<string, unknown>)
        .map(([key, value]) => [key, value === true]),
    )
    : {};
  return {
    platform: typeof body.client_platform === "string"
      ? body.client_platform.trim().toLowerCase()
      : "unknown",
    appBuild,
    appBuildNumber: appBuild ? optionalPositiveInt(appBuild) : null,
    apiContractVersion: positiveInt(body.api_contract_version, 1),
    capabilities,
  };
}

function editableReleaseGateOpen(
  value: Record<string, unknown>,
  client: ClientReleaseContext,
): boolean {
  if (bool(value.kill_switch, false)) return false;
  if (client.platform !== "ios") return false;
  if (client.apiContractVersion < 2) return false;
  if (!client.appBuild) return false;
  if (client.capabilities.editable_findings !== true) return false;

  const mode = rolloutMode(value.rollout_mode);
  if (mode === "all") return true;
  if (mode === "build_allowlist") {
    const allowed = stringArray(value.enabled_ios_builds);
    if (allowed.includes(client.appBuild)) return true;
    return client.appBuildNumber != null &&
      allowed
        .map((build) => optionalPositiveInt(build))
        .some((build) => build === client.appBuildNumber);
  }
  if (mode === "min_build") {
    const minimum = optionalPositiveInt(value.min_ios_build);
    return client.appBuildNumber != null && minimum != null &&
      client.appBuildNumber >= minimum;
  }
  return false;
}

function optionalNumberFromSet(
  value: unknown,
  allowed: number[],
  field: string,
): number | undefined {
  if (value === undefined) return undefined;
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || !allowed.includes(numeric)) {
    throw new Error(`validation:${field}`);
  }
  return numeric;
}

function optionalIntRange(
  value: unknown,
  min: number,
  max: number,
  field: string,
): number | undefined {
  if (value === undefined) return undefined;
  const numeric = Math.round(Number(value));
  if (!Number.isFinite(numeric) || numeric < min || numeric > max) {
    throw new Error(`validation:${field}`);
  }
  return numeric;
}

function fkBand(score: number): "low" | "medium" | "high" | "critical" {
  if (score <= 70) return "low";
  if (score <= 200) return "medium";
  if (score <= 400) return "high";
  return "critical";
}

function m5Band(score: number): "low" | "medium" | "high" | "critical" {
  if (score <= 4) return "low";
  if (score <= 9) return "medium";
  if (score <= 19) return "high";
  return "critical";
}

function withDerivedRiskSnapshot(
  before: FindingRow,
  update: Record<string, unknown>,
): FindingRow {
  const snapshot = { ...before, ...update } as FindingRow;
  const fkP = Number(snapshot.fk_probability);
  const fkF = Number(snapshot.fk_frequency);
  const fkS = Number(snapshot.fk_severity);
  const m5P = Number(snapshot.m5_probability);
  const m5S = Number(snapshot.m5_severity);
  if (Number.isFinite(fkP) && Number.isFinite(fkF) && Number.isFinite(fkS)) {
    const score = fkP * fkF * fkS;
    snapshot.fk_score = score;
    snapshot.fk_band = fkBand(score);
  }
  if (Number.isFinite(m5P) && Number.isFinite(m5S)) {
    const score = m5P * m5S;
    snapshot.m5_score = score;
    snapshot.m5_band = m5Band(score);
  }
  return snapshot;
}

function normalizeMeasures(value: unknown):
  | Array<{
    kind: string;
    title: string;
    text: string;
  }>
  | undefined {
  if (value === undefined) return undefined;
  if (!Array.isArray(value)) throw new Error("validation:recommended_measures");
  const measures = value
    .slice(0, 8)
    .map((item: MeasurePatch) => {
      const kind =
        String(item?.kind ?? "corrective").toLowerCase() === "preventive"
          ? "preventive"
          : "corrective";
      const title = text(item?.title, 80) ||
        (kind === "preventive" ? "Önleyici Kontrol" : "Düzeltici Önlem");
      const body = text(item?.text, 900) ?? "";
      return body ? { kind, title, text: body } : null;
    })
    .filter((item): item is { kind: string; title: string; text: string } =>
      item !== null
    );

  if (measures.length === 0) {
    throw new Error("validation:recommended_measures");
  }
  return measures;
}

function normalizeSourcePhotoIndices(
  value: unknown,
  photoCount: number,
): number[] | undefined {
  if (value === undefined) return undefined;
  if (!Array.isArray(value)) throw new Error("validation:source_photo_indices");
  const indices = [
    ...new Set(
      value.map((item) => Math.round(Number(item))).filter((item) =>
        Number.isFinite(item)
      ),
    ),
  ].sort((a, b) => a - b);
  if (indices.some((item) => item < 1 || item > Math.max(photoCount, 1))) {
    throw new Error("validation:source_photo_indices");
  }
  return indices;
}

function changedFields(
  before: FindingRow,
  update: Record<string, unknown>,
): string[] {
  return Object.keys(update).filter((key) =>
    JSON.stringify(before[key] ?? null) !== JSON.stringify(update[key] ?? null)
  );
}

function publicBundleSelects() {
  return {
    analysis:
      "id,user_id,company_id,title,kind,canvas,status,status_message,ai_summary,total_score_fk,total_score_m5,highest_band_fk,highest_band_m5,finding_count,created_at,analysis_sector,analysis_sector_source,analysis_sector_prompt_version,input_payload_version,photo_count,max_photos_allowed_at_creation,max_findings_per_photo,max_findings_total,generated_findings_count,visible_findings_count,hidden_or_rejected_findings_count,has_user_edits,user_edit_count,analysis_edit_version,plan_at_creation,capability_snapshot,rollout_snapshot",
    findings:
      "id,analysis_id,ordinal,title,category,description,recommended_action,recommended_measures,references_text,root_cause_text,confidence,needs_field_verification,fk_probability,fk_frequency,fk_severity,fk_score,fk_band,m5_probability,m5_severity,m5_score,m5_band,origin,source_photo_indices,source_photo_observations,ai_confidence,last_user_edit_at,last_user_edit_by,user_edit_count,finding_version,display_group,display_order",
    photos:
      "analysis_id,storage_path,width,height,mime_type,sequence_index,client_photo_id,is_primary,thumbnail_storage_path,annotation_storage_path,user_caption,ai_scene_summary",
    photoSummaries:
      "analysis_id,photo_sequence_index,scene_summary,candidate_findings_count,generated_findings_count,highest_risk_level,ai_confidence,coverage_status,coverage_gap_reason,target_findings_min,target_findings_max",
  };
}

async function editableFindingsEnabled(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  client: ClientReleaseContext,
): Promise<boolean> {
  const { data, error } = await supabase
    .from("app_feature_flags")
    .select("value")
    .eq("key", "multi_photo_analysis")
    .maybeSingle();
  if (error) return false;
  const value = data?.value as Record<string, unknown> | undefined;
  if (!value || !editableReleaseGateOpen(value, client)) return false;
  const features = value.features && typeof value.features === "object"
    ? value.features as Record<string, unknown>
    : {};
  return bool(
    features.editable_findings,
    bool(value.enable_editable_findings, false),
  );
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

  let body: Body;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const requestID = safeTrace(body.request_id, crypto.randomUUID());
  const supportID = safeTrace(
    body.support_id,
    `RD-${crypto.randomUUID().slice(0, 8).toUpperCase()}`,
  );
  const clientRelease = clientReleaseContext(body);

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader) {
    return json(401, {
      error: "auth_required",
      request_id: requestID,
      support_id: supportID,
    });
  }

  if (!isUUID(body.analysis_id) || !isUUID(body.finding_id)) {
    return json(400, {
      error: "invalid_identifier",
      message: "Analiz veya bulgu doğrulanamadı.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  const action = body.action === "delete"
    ? "delete"
    : body.action === "update"
    ? "update"
    : null;
  if (!action) {
    return json(400, {
      error: "invalid_action",
      message: "Geçersiz bulgu işlemi.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const token = authHeader.replace(/^Bearer\s+/i, "");
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

  if (!(await editableFindingsEnabled(supabase, clientRelease))) {
    return json(423, {
      error: "editable_findings_disabled",
      message: "Bulgu düzenleme geçici olarak kapalı.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  const analysisID = body.analysis_id;
  const findingID = body.finding_id;
  const selects = publicBundleSelects();

  const { data: analysis, error: analysisError } = await supabase
    .from("analyses")
    .select(
      "id,user_id,status,analysis_edit_version,user_edit_count,photo_count",
    )
    .eq("id", analysisID)
    .eq("user_id", user.id)
    .maybeSingle();
  if (analysisError || !analysis) {
    return json(404, {
      error: "analysis_not_found",
      message: "Analiz bulunamadı.",
      request_id: requestID,
      support_id: supportID,
    });
  }
  if (analysis.status !== "completed") {
    return json(409, {
      error: "analysis_not_completed",
      message: "Bulgu düzenlemek için analiz tamamlanmış olmalı.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  const { data: finding, error: findingError } = await supabase
    .from("findings")
    .select("*")
    .eq("id", findingID)
    .eq("analysis_id", analysisID)
    .eq("user_id", user.id)
    .maybeSingle();
  if (findingError || !finding) {
    return json(404, {
      error: "finding_not_found",
      message: "Bulgu bulunamadı.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  const before = finding as FindingRow;
  const beforeVersion = Number(before.finding_version ?? 1);
  if (
    body.expected_finding_version !== undefined &&
    Number(body.expected_finding_version) !== beforeVersion
  ) {
    return json(409, {
      error: "finding_version_conflict",
      message:
        "Bu bulgu başka bir işlemle güncellenmiş. Lütfen sayfayı yenileyip tekrar dene.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  try {
    if (action === "delete") {
      const { error: eventError } = await supabase
        .from("finding_edit_events")
        .insert({
          analysis_id: analysisID,
          finding_id: findingID,
          actor_user_id: user.id,
          event_type: "hard_delete",
          before_snapshot: before,
          after_snapshot: null,
          changed_fields: ["__deleted__"],
          finding_version_before: beforeVersion,
          finding_version_after: null,
          client_app_version: text(body.client_app_version, 80) ?? null,
          request_id: requestID,
          support_id: supportID,
        });
      if (eventError) throw new Error(`audit:${eventError.message}`);

      const { error: deleteError } = await supabase
        .from("findings")
        .delete()
        .eq("id", findingID)
        .eq("analysis_id", analysisID)
        .eq("user_id", user.id);
      if (deleteError) throw new Error(`delete:${deleteError.message}`);
    } else {
      const patch = body.patch ?? {};
      const update: Record<string, unknown> = {};

      if (patch.title !== undefined) {
        update.title = requiredText(patch.title, "title", 180);
      }
      if (patch.category !== undefined) {
        update.category = text(patch.category, 160) ?? "";
      }
      if (patch.description !== undefined) {
        update.description = requiredText(
          patch.description,
          "description",
          2000,
        );
      }
      if (patch.references_text !== undefined) {
        update.references_text = text(patch.references_text, 1600) ?? "";
      }
      if (patch.root_cause_text !== undefined) {
        update.root_cause_text = text(patch.root_cause_text, 1200) ?? "";
      }

      const measures = normalizeMeasures(patch.recommended_measures);
      if (measures) {
        update.recommended_measures = measures;
        update.recommended_action = measures[0]?.text ?? "";
      } else if (patch.recommended_action !== undefined) {
        update.recommended_action = requiredText(
          patch.recommended_action,
          "recommended_action",
          1200,
        );
      }

      const photoIndices = normalizeSourcePhotoIndices(
        patch.source_photo_indices,
        Number(analysis.photo_count ?? 0),
      );
      if (photoIndices) update.source_photo_indices = photoIndices;

      const fkP = optionalNumberFromSet(
        patch.fk_probability,
        FK_PROBABILITY_VALUES,
        "fk_probability",
      );
      const fkF = optionalNumberFromSet(
        patch.fk_frequency,
        FK_FREQUENCY_VALUES,
        "fk_frequency",
      );
      const fkS = optionalNumberFromSet(
        patch.fk_severity,
        FK_SEVERITY_VALUES,
        "fk_severity",
      );
      const resolvedFkP = fkP ?? Number(before.fk_probability);
      const resolvedFkF = fkF ?? Number(before.fk_frequency);
      const resolvedFkS = fkS ?? Number(before.fk_severity);
      if (fkP !== undefined) update.fk_probability = fkP;
      if (fkF !== undefined) update.fk_frequency = fkF;
      if (fkS !== undefined) update.fk_severity = fkS;
      if (fkP !== undefined || fkF !== undefined || fkS !== undefined) {
        const fkScore = resolvedFkP * resolvedFkF * resolvedFkS;
        update.fk_band = fkBand(fkScore);
      }

      const m5P = optionalIntRange(
        patch.m5_probability,
        1,
        5,
        "m5_probability",
      );
      const m5S = optionalIntRange(patch.m5_severity, 1, 5, "m5_severity");
      const resolvedM5P = m5P ?? Number(before.m5_probability);
      const resolvedM5S = m5S ?? Number(before.m5_severity);
      if (m5P !== undefined) update.m5_probability = m5P;
      if (m5S !== undefined) update.m5_severity = m5S;
      if (m5P !== undefined || m5S !== undefined) {
        const m5Score = resolvedM5P * resolvedM5S;
        update.m5_band = m5Band(m5Score);
      }

      if (Object.keys(update).length === 0) {
        return json(400, {
          error: "empty_patch",
          message: "Kaydedilecek değişiklik bulunamadı.",
          request_id: requestID,
          support_id: supportID,
        });
      }

      update.last_user_edit_at = new Date().toISOString();
      update.last_user_edit_by = user.id;
      update.user_edit_count = Number(before.user_edit_count ?? 0) + 1;
      update.finding_version = beforeVersion + 1;

      const fields = changedFields(before, update);
      const afterSnapshot = withDerivedRiskSnapshot(before, update);

      const { error: eventError } = await supabase
        .from("finding_edit_events")
        .insert({
          analysis_id: analysisID,
          finding_id: findingID,
          actor_user_id: user.id,
          event_type: "update",
          before_snapshot: before,
          after_snapshot: afterSnapshot,
          changed_fields: fields,
          finding_version_before: beforeVersion,
          finding_version_after: beforeVersion + 1,
          client_app_version: text(body.client_app_version, 80) ?? null,
          request_id: requestID,
          support_id: supportID,
        });
      if (eventError) throw new Error(`audit:${eventError.message}`);

      const { error: updateError } = await supabase
        .from("findings")
        .update(update)
        .eq("id", findingID)
        .eq("analysis_id", analysisID)
        .eq("user_id", user.id);
      if (updateError) throw new Error(`update:${updateError.message}`);
    }

    const { error: analysisUpdateError } = await supabase
      .from("analyses")
      .update({
        has_user_edits: true,
        user_edit_count:
          Number((analysis as Record<string, unknown>).user_edit_count ?? 0) +
          1,
        analysis_edit_version: Number(
          (analysis as Record<string, unknown>).analysis_edit_version ?? 0,
        ) + 1,
        updated_at: new Date().toISOString(),
      })
      .eq("id", analysisID)
      .eq("user_id", user.id);
    if (analysisUpdateError) {
      throw new Error(`analysis_update:${analysisUpdateError.message}`);
    }

    const { error: rollupError } = await supabase.rpc(
      "recalc_analysis_rollup",
      { p_analysis_id: analysisID },
    );
    if (rollupError) throw new Error(`rollup:${rollupError.message}`);

    const { data: refreshedAnalysis, error: refreshedAnalysisError } =
      await supabase
        .from("analyses")
        .select(selects.analysis)
        .eq("id", analysisID)
        .eq("user_id", user.id)
        .single();
    const { data: refreshedFindings, error: refreshedFindingsError } =
      await supabase
        .from("findings")
        .select(selects.findings)
        .eq("analysis_id", analysisID)
        .eq("user_id", user.id)
        .order("ordinal", { ascending: true });
    const { data: refreshedPhotos, error: refreshedPhotosError } =
      await supabase
        .from("photos")
        .select(selects.photos)
        .eq("analysis_id", analysisID)
        .eq("user_id", user.id)
        .order("sequence_index", { ascending: true, nullsFirst: false })
        .order("storage_path", { ascending: true });
    const {
      data: refreshedPhotoSummaries,
      error: refreshedPhotoSummariesError,
    } = await supabase
      .from("analysis_photo_summaries")
      .select(selects.photoSummaries)
      .eq("analysis_id", analysisID)
      .order("photo_sequence_index", { ascending: true });

    if (
      refreshedAnalysisError || refreshedFindingsError ||
      refreshedPhotosError ||
      refreshedPhotoSummariesError
    ) {
      throw new Error("refresh_failed");
    }

    return json(200, {
      ok: true,
      action,
      bundle: {
        analysis: refreshedAnalysis,
        findings: refreshedFindings ?? [],
        photos: refreshedPhotos ?? [],
        photoSummaries: refreshedPhotoSummaries ?? [],
      },
      request_id: requestID,
      support_id: supportID,
    });
  } catch (error) {
    const message = String(error);
    if (message.startsWith("validation:")) {
      return json(400, {
        error: "validation_failed",
        field: message.replace("validation:", ""),
        message: "Bulgu alanları doğrulanamadı.",
        request_id: requestID,
        support_id: supportID,
      });
    }
    console.error(
      "Finding mutation failed",
      JSON.stringify({
        request_id: requestID,
        support_id: supportID,
        analysis_id: analysisID,
        finding_id: findingID,
        error: message.slice(0, 300),
      }),
    );
    return json(500, {
      error: "finding_mutation_failed",
      message: "Bulgu güncellenemedi. Lütfen tekrar dene.",
      request_id: requestID,
      support_id: supportID,
    });
  }
});
