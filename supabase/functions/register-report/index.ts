/**
 * register-report — validates and stores PDF report archive metadata.
 *
 * The mobile app uploads the PDF to the private reports bucket under the
 * user-owned path, then calls this JWT-protected function to create the
 * public.reports row with service-role authority.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { resolveReportLocalization } from "../_shared/report-localization.ts";
import { readAndroidRuntimeGates } from "../_shared/android-runtime-gates.ts";

const PDF_MIME = "application/pdf";
const MAX_PDF_BYTES = 20 * 1024 * 1024;

type RegisterReportBody = {
  analysis_id?: string;
  kind?: string;
  method?: string;
  title?: string;
  storage_path?: string;
  file_name?: string;
  mime_type?: string;
  file_size?: number;
  size_bytes?: number;
  page_count?: number;
  company_id?: string | null;
  findings_snapshot_json?: unknown;
  photos_snapshot_json?: unknown;
  analysis_edit_version?: number;
  generated_from_user_edited_findings?: boolean;
  source_photo_count?: number;
  visible_findings_count?: number;
  report_language?: "tr" | "en";
  client_app_version?: string;
  client_app_build?: string;
  client_platform?: string;
  api_contract_version?: number;
  client_capabilities?: Record<string, unknown>;
  request_id?: string;
  support_id?: string;
};

type AnalysisRow = {
  id: string;
  user_id: string;
  status: string;
  title: string | null;
  company_id: string | null;
  analysis_edit_version?: number | null;
  has_user_edits?: boolean | null;
  localization_snapshot?: Record<string, unknown> | null;
};

type CompanyRow = {
  id: string;
  user_id: string;
  name: string;
  hazard_class: string;
  logo_path: string | null;
  address: string | null;
  contact_person: string | null;
  department: string | null;
  default_responsible: string | null;
  default_due_days: number | null;
  is_archived: boolean | null;
};

type ReportSnapshotResult =
  | {
    ok: true;
    findings: unknown[];
    photos: unknown[];
    analysisEditVersion: number;
    hasUserEdits: boolean;
    sourcePhotoCount: number;
    visibleFindingsCount: number;
  }
  | {
    ok: false;
    code: "report_snapshot_fetch_failed";
    detail: string;
  };

const REPORT_ANALYSIS_SELECT =
  "id,user_id,status,title,company_id,analysis_edit_version,has_user_edits,localization_snapshot";

const REPORT_FINDINGS_SELECT =
  "id,analysis_id,ordinal,title,category,description,recommended_action,recommended_measures,references_text,root_cause_text,confidence,needs_field_verification,fk_probability,fk_frequency,fk_severity,fk_score,fk_band,m5_probability,m5_severity,m5_score,m5_band,origin,source_photo_indices,ai_confidence,last_user_edit_at,user_edit_count,finding_version,display_order";

const REPORT_PHOTOS_SELECT =
  "analysis_id,storage_path,width,height,mime_type,sequence_index,client_photo_id,is_primary,thumbnail_storage_path,annotation_storage_path,user_caption,ai_scene_summary";

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

function safeText(value: unknown, fallback = "", maxLength = 240): string {
  const text = typeof value === "string" ? value : fallback;
  return text.trim().slice(0, maxLength);
}

function safeLogText(value: unknown, maxLength = 180): string {
  return String(value)
    .replace(/Bearer\s+[^\s]+/gi, "Bearer [redacted]")
    .slice(0, maxLength);
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
  return value.map((item) => String(item ?? "").trim()).filter(Boolean);
}

function snapshotGateOpen(
  value: Record<string, unknown>,
  body: RegisterReportBody,
): boolean {
  if (bool(value.kill_switch, false)) return false;
  const platform = safeText(body.client_platform, "unknown", 40).toLowerCase();
  const build = safeText(body.client_app_build, "", 40);
  const buildNumber = optionalPositiveInt(build);
  const contractVersion = positiveInt(body.api_contract_version, 1);
  const capabilities = body.client_capabilities &&
      typeof body.client_capabilities === "object"
    ? body.client_capabilities
    : {};
  if (
    (platform !== "ios" && platform !== "android") ||
    contractVersion < 2 ||
    !build
  ) return false;
  if (capabilities.report_snapshot_v2 !== true) return false;

  const mode = safeText(value.rollout_mode, "off", 40).toLowerCase();
  if (mode === "all") return true;
  if (mode === "build_allowlist") {
    const allowed = stringArray(
      platform === "android"
        ? value.enabled_android_builds
        : value.enabled_ios_builds,
    );
    if (allowed.includes(build)) return true;
    return buildNumber != null &&
      allowed
        .map((item) => optionalPositiveInt(item))
        .some((item) => item === buildNumber);
  }
  if (mode === "min_build") {
    const minimum = optionalPositiveInt(
      platform === "android" ? value.min_android_build : value.min_ios_build,
    );
    return buildNumber != null && minimum != null && buildNumber >= minimum;
  }
  return false;
}

async function reportSnapshotV2Enabled(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  body: RegisterReportBody,
): Promise<boolean> {
  const { data, error } = await supabase
    .from("app_feature_flags")
    .select("value")
    .eq("key", "multi_photo_analysis")
    .maybeSingle();
  if (error) return false;
  const value = data?.value as Record<string, unknown> | undefined;
  if (!value || !snapshotGateOpen(value, body)) return false;
  const features = value.features && typeof value.features === "object"
    ? value.features as Record<string, unknown>
    : {};
  return bool(
    features.report_snapshot_v2,
    bool(value.enable_report_snapshot_v2, false),
  );
}

function isUUID(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

function normalizeKind(value: unknown): "standard" | "riskAnalysis" {
  return value === "riskAnalysis" || value === "risk_analysis"
    ? "riskAnalysis"
    : "standard";
}

function normalizeMethod(value: unknown): "fine_kinney" | "matrix_5x5" {
  return value === "matrix_5x5" ? "matrix_5x5" : "fine_kinney";
}

function companySnapshot(
  company: CompanyRow | null,
): Record<string, unknown> | null {
  if (!company) return null;
  return {
    id: company.id,
    name: company.name,
    hazard_class: company.hazard_class,
    logo_path: company.logo_path,
    address: company.address,
    contact_person: company.contact_person,
    department: company.department,
    default_responsible: company.default_responsible,
    default_due_days: company.default_due_days,
  };
}

function nonNegativeInt(value: unknown, fallback = 0): number {
  const number = Math.round(Number(value ?? fallback));
  return Number.isFinite(number) ? Math.max(0, number) : fallback;
}

// deno-lint-ignore no-explicit-any
async function loadServerReportSnapshot(params: {
  supabase: any;
  analysis: AnalysisRow;
  analysisID: string;
  userID: string;
}): Promise<ReportSnapshotResult> {
  const { data: findings, error: findingsError } = await params.supabase
    .from("findings")
    .select(REPORT_FINDINGS_SELECT)
    .eq("analysis_id", params.analysisID)
    .eq("user_id", params.userID)
    .eq("is_user_deleted", false)
    .eq("report_visibility", "visible")
    .order("display_order", { ascending: true, nullsFirst: false })
    .order("ordinal", { ascending: true });

  if (findingsError) {
    return {
      ok: false,
      code: "report_snapshot_fetch_failed",
      detail: `findings:${String(findingsError.message ?? findingsError)}`,
    };
  }

  const { data: photos, error: photosError } = await params.supabase
    .from("photos")
    .select(REPORT_PHOTOS_SELECT)
    .eq("analysis_id", params.analysisID)
    .eq("user_id", params.userID)
    .order("sequence_index", { ascending: true, nullsFirst: false })
    .order("storage_path", { ascending: true });

  if (photosError) {
    return {
      ok: false,
      code: "report_snapshot_fetch_failed",
      detail: `photos:${String(photosError.message ?? photosError)}`,
    };
  }

  const findingRows = Array.isArray(findings) ? findings : [];
  const photoRows = Array.isArray(photos) ? photos : [];
  return {
    ok: true,
    findings: findingRows,
    photos: photoRows,
    analysisEditVersion: nonNegativeInt(params.analysis.analysis_edit_version),
    hasUserEdits: params.analysis.has_user_edits === true,
    sourcePhotoCount: photoRows.length,
    visibleFindingsCount: findingRows.length,
  };
}

async function sendReportReadyPush(params: {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  supabaseUrl: string;
  serviceRoleKey: string;
  userID: string;
  reportID: string;
  analysisID: string;
  format: string;
  kind: string;
  requestID: string;
  supportID: string;
}) {
  const response = await fetch(
    `${params.supabaseUrl}/functions/v1/send-push-notification`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${params.serviceRoleKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        user_id: params.userID,
        kind: "report_ready",
        event_key: "report_ready",
        data: {
          report_id: params.reportID,
          analysis_id: params.analysisID,
          destination: "reports",
          format: params.format,
          kind: params.kind,
          request_id: params.requestID,
          support_id: params.supportID,
        },
      }),
    },
  );

  const responseText = await response.text();
  if (!response.ok) {
    console.warn(
      "Report ready push failed",
      JSON.stringify({
        request_id: params.requestID,
        support_id: params.supportID,
        report_id: params.reportID,
        status: response.status,
        body: safeLogText(responseText),
      }),
    );
    return;
  }

  let pushResult: { status?: string } = {};
  try {
    pushResult = responseText ? JSON.parse(responseText) : {};
  } catch {
    pushResult = {};
  }
  if (pushResult.status !== "sent") return;

  await params.supabase
    .from("reports")
    .update({ report_ready_push_sent_at: new Date().toISOString() })
    .eq("id", params.reportID)
    .eq("user_id", params.userID)
    .is("report_ready_push_sent_at", null);
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

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader) return json(401, { error: "auth_required" });

  let body: RegisterReportBody;
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

  if (!isUUID(body.analysis_id)) {
    return json(400, {
      error: "invalid_analysis_id",
      message: "Analiz doğrulanamadı.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  const storagePath = safeText(body.storage_path, "", 800);
  const fileName = safeText(body.file_name, "", 240);
  const mimeType = safeText(body.mime_type, PDF_MIME, 120);
  const fileSize = Number(body.file_size ?? body.size_bytes ?? 0);
  const pageCount = Math.max(1, Math.round(Number(body.page_count ?? 1)));
  if (
    !storagePath || !fileName || mimeType !== PDF_MIME ||
    !Number.isFinite(fileSize) || fileSize <= 0 || fileSize > MAX_PDF_BYTES
  ) {
    return json(400, {
      error: "invalid_report_metadata",
      message: "Rapor dosya bilgisi geçersiz.",
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

  const clientPlatform = safeText(body.client_platform, "unknown", 40)
    .toLowerCase();
  if (clientPlatform === "android") {
    const runtimeGates = await readAndroidRuntimeGates(
      supabase,
      clientPlatform,
      optionalPositiveInt(body.client_app_build),
    );
    const decision = runtimeGates?.pdf_reports;
    if (decision?.enabled !== true) {
      return json(503, {
        error: "android_pdf_reports_disabled",
        reason: decision?.reason ?? "gate_unavailable",
        request_id: requestID,
        support_id: supportID,
      });
    }
  }

  const analysisID = body.analysis_id;
  const expectedPrefix =
    `${user.id.toLowerCase()}/${analysisID.toLowerCase()}/`;
  const actualFileName = storagePath.split("/").pop() ?? "";
  if (
    !storagePath.toLowerCase().startsWith(expectedPrefix) ||
    actualFileName !== fileName
  ) {
    return json(403, {
      error: "report_path_not_authorized",
      message: "Rapor dosya yolu doğrulanamadı.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  const { data: analysis, error: analysisError } = await supabase
    .from("analyses")
    .select(REPORT_ANALYSIS_SELECT)
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

  const analysisRow = analysis as AnalysisRow;
  if (analysisRow.status !== "completed") {
    return json(409, {
      error: "analysis_not_completed",
      message: "Rapor arşivi için analiz tamamlanmış olmalı.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  const reportLocalization = resolveReportLocalization({
    localizationSnapshot: analysisRow.localization_snapshot,
    requestedLanguage: body.report_language,
  });
  if (!reportLocalization.ok) {
    await supabase.storage.from("reports").remove([storagePath]);
    return json(
      reportLocalization.code === "REPORT_LANGUAGE_MISMATCH" ? 409 : 422,
      {
        error: reportLocalization.code,
        message: reportLocalization.code === "REPORT_LANGUAGE_MISMATCH"
          ? "Requested report language does not match the analysis snapshot."
          : "The analysis localization snapshot is unavailable or invalid.",
        request_id: requestID,
        support_id: supportID,
      },
    );
  }

  const requestedCompanyID = isUUID(body.company_id) ? body.company_id : "";
  const resolvedCompanyID = requestedCompanyID || analysisRow.company_id || "";
  let company: CompanyRow | null = null;
  if (resolvedCompanyID) {
    const { data: companyRow, error: companyError } = await supabase
      .from("companies")
      .select(
        "id,user_id,name,hazard_class,logo_path,address,contact_person,department,default_responsible,default_due_days,is_archived",
      )
      .eq("id", resolvedCompanyID)
      .eq("user_id", user.id)
      .eq("is_archived", false)
      .maybeSingle();

    if (companyError || !companyRow) {
      return json(403, {
        error: "company_not_authorized",
        message: "Firma doğrulanamadı.",
        request_id: requestID,
        support_id: supportID,
      });
    }
    company = companyRow as CompanyRow;
  }

  const { data: storedFile, error: storageError } = await supabase.storage
    .from("reports")
    .download(storagePath);
  if (storageError || !storedFile) {
    return json(404, {
      error: "report_file_not_found",
      message: "Rapor dosyası arşivde bulunamadı.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  const storedBytes = (await storedFile.arrayBuffer()).byteLength;
  if (storedBytes !== fileSize) {
    return json(400, {
      error: "report_file_size_mismatch",
      message: "Rapor dosya boyutu doğrulanamadı.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  const shouldStoreSnapshot = await reportSnapshotV2Enabled(supabase, body);
  let snapshotColumns: Record<string, unknown> = {};
  if (shouldStoreSnapshot) {
    const snapshot = await loadServerReportSnapshot({
      supabase,
      analysis: analysisRow,
      analysisID,
      userID: user.id,
    });
    if (!snapshot.ok) {
      await supabase.storage.from("reports").remove([storagePath]);
      console.error(
        "PDF report snapshot fetch failed",
        JSON.stringify({
          request_id: requestID,
          support_id: supportID,
          analysis_id: analysisID,
          error: safeLogText(snapshot.detail),
        }),
      );
      return json(500, {
        error: snapshot.code,
        message: "Rapor arşiv verisi hazırlanamadı.",
        request_id: requestID,
        support_id: supportID,
      });
    }
    snapshotColumns = {
      findings_snapshot_json: snapshot.findings,
      photos_snapshot_json: snapshot.photos,
      analysis_edit_version: snapshot.analysisEditVersion,
      generated_from_user_edited_findings: snapshot.hasUserEdits,
      source_photo_count: snapshot.sourcePhotoCount,
      visible_findings_count: snapshot.visibleFindingsCount,
      report_page_count: pageCount,
    };
  }

  const { data: documentNo, error: documentNoError } = await supabase.rpc(
    "next_document_no",
    { p_user_id: user.id },
  );
  if (documentNoError || typeof documentNo !== "string") {
    return json(500, {
      error: "document_no_failed",
      message: "Rapor doküman numarası oluşturulamadı.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  const kind = normalizeKind(body.kind);
  const method = normalizeMethod(body.method);
  const { data: report, error: reportError } = await supabase
    .from("reports")
    .insert({
      user_id: user.id,
      analysis_id: analysisID,
      document_no: documentNo,
      format: "pdf",
      kind,
      method,
      title: safeText(
        body.title,
        analysisRow.title ?? "RiskDetected Report",
        240,
      ),
      storage_path: storagePath,
      file_name: fileName,
      mime_type: PDF_MIME,
      file_size: fileSize,
      size_bytes: fileSize,
      page_count: pageCount,
      company_id: company?.id ?? null,
      company_snapshot: companySnapshot(company),
      report_language: reportLocalization.context.language,
      report_locale: reportLocalization.context.locale,
      safety_profile_id: reportLocalization.context.safetyProfileID,
      safety_profile_version: reportLocalization.context.safetyProfileVersion,
      regulatory_sections_enabled:
        reportLocalization.context.regulatorySectionsEnabled,
      localization_snapshot: reportLocalization.context.snapshot,
      ...snapshotColumns,
      request_id: requestID,
      support_id: supportID,
    })
    .select(
      "id,user_id,analysis_id,company_id,company_snapshot,format,kind,method,title,storage_path,file_name,mime_type,file_size,request_id,support_id,report_language,report_locale,safety_profile_id,safety_profile_version,regulatory_sections_enabled,created_at",
    )
    .single();

  if (reportError) {
    await supabase.storage.from("reports").remove([storagePath]);
    const message = String(reportError.message ?? "");
    if (message.includes("free_risk_analysis_trial_exhausted")) {
      return json(429, {
        error: "free_risk_analysis_trial_exhausted",
        message: "Bir kez tanımlanan risk analizi tablosu hakkını kullandın.",
        request_id: requestID,
        support_id: supportID,
      });
    }
    if (message.includes("report_quota_exceeded")) {
      return json(429, {
        error: "report_quota_exceeded",
        message: "Aylık rapor kotan doldu.",
        request_id: requestID,
        support_id: supportID,
      });
    }
    console.error(
      "PDF report metadata failed",
      JSON.stringify({
        request_id: requestID,
        support_id: supportID,
        analysis_id: analysisID,
        error: safeLogText(message),
      }),
    );
    return json(500, {
      error: "report_metadata_failed",
      message: "Rapor arşiv kaydı tamamlanamadı.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  try {
    await sendReportReadyPush({
      supabase,
      supabaseUrl,
      serviceRoleKey,
      userID: user.id,
      reportID: report.id,
      analysisID,
      format: "pdf",
      kind,
      requestID,
      supportID,
    });
  } catch (pushError) {
    console.warn(
      "Report ready push dispatch threw after PDF persistence",
      JSON.stringify({
        request_id: requestID,
        support_id: supportID,
        report_id: report.id,
        analysis_id: analysisID,
        error: safeLogText(
          pushError instanceof Error ? pushError.message : pushError,
        ),
      }),
    );
  }

  return json(200, report);
});
