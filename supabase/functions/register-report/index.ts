/**
 * register-report — validates and stores PDF report archive metadata.
 *
 * The mobile app uploads the PDF to the private reports bucket under the
 * user-owned path, then calls this JWT-protected function to create the
 * public.reports row with service-role authority.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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
  request_id?: string;
  support_id?: string;
};

type AnalysisRow = {
  id: string;
  user_id: string;
  status: string;
  title: string | null;
  company_id: string | null;
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
        title: "Rapor Hazır",
        body: "Risk raporun oluşturuldu, raporlar bölümünden inceleyebilirsin.",
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
    .select("id,user_id,status,title,company_id")
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
      request_id: requestID,
      support_id: supportID,
    })
    .select(
      "id,user_id,analysis_id,company_id,company_snapshot,format,kind,method,title,storage_path,file_name,mime_type,file_size,request_id,support_id,created_at",
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

  return json(200, report);
});
