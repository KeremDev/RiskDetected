/**
 * generate-excel-report — RiskDetected XLSX report generator.
 *
 * Authenticated users can generate an Excel risk analysis workbook for their own
 * completed analysis. The file is written to the private `reports` bucket and
 * metadata is stored in `public.reports` with `format = xlsx`.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import * as XLSX from "npm:xlsx@0.18.5";

const XLSX_MIME =
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-request-id, x-support-id",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type RequestBody = {
  analysis_id?: string;
  method?: "fine_kinney" | "matrix_5x5";
  report_kind?: "risk_analysis" | "standard";
  request_id?: string;
  support_id?: string;
};

type AnalysisRow = Record<string, unknown> & {
  id: string;
  user_id: string;
  title?: string;
  canvas?: string;
  kind?: string;
  status?: string;
  ai_summary?: string | null;
  total_score_fk?: number | null;
  total_score_m5?: number | null;
  highest_band_fk?: string | null;
  highest_band_m5?: string | null;
  finding_count?: number | null;
  created_at?: string | null;
  completed_at?: string | null;
};

type FindingRow = Record<string, unknown> & {
  ordinal?: number;
  title?: string;
  category?: string | null;
  description?: string | null;
  recommended_action?: string | null;
  references_text?: string | null;
  confidence?: number | null;
  fk_probability?: number | null;
  fk_frequency?: number | null;
  fk_severity?: number | null;
  fk_score?: number | null;
  fk_band?: string | null;
  m5_probability?: number | null;
  m5_severity?: number | null;
  m5_score?: number | null;
  m5_band?: string | null;
};

type ProfileRow = Record<string, unknown> & {
  tier?: string | null;
  display_name?: string | null;
  full_name?: string | null;
  title?: string | null;
  certificate_number?: string | null;
  company_name?: string | null;
  phone?: string | null;
};

type PlanTier = "free" | "plus" | "pro";

function tierRank(tier: PlanTier): number {
  switch (tier) {
    case "pro":
      return 2;
    case "plus":
      return 1;
    case "free":
    default:
      return 0;
  }
}

function normalizeTier(raw: unknown): PlanTier {
  return raw === "pro" || raw === "plus" ? raw : "free";
}

function hasActiveSubscription(row: { status?: string | null; current_period_ends_at?: string | null } | null): boolean {
  if (!row) return false;
  if (!["active", "trialing", "grace_period"].includes(String(row.status ?? ""))) return false;
  if (!row.current_period_ends_at) return true;
  const expiresAt = Date.parse(row.current_period_ends_at);
  return Number.isFinite(expiresAt) && expiresAt > Date.now();
}

function resolvePlanTier(
  profileTier: unknown,
  subscription: { tier?: string | null; status?: string | null; current_period_ends_at?: string | null } | null,
): PlanTier {
  void profileTier;
  return hasActiveSubscription(subscription) ? normalizeTier(subscription?.tier) : "free";
}

function monthlyReportLimit(tier: PlanTier): number | null {
  switch (tier) {
    case "pro":
      return null;
    case "plus":
      return 150;
    case "free":
    default:
      return 3;
  }
}

function istanbulMonthStartISO(): string {
  const day = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Istanbul",
    year: "numeric",
    month: "2-digit",
  }).format(new Date());
  return `${day}-01T00:00:00+03:00`;
}

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

function newSupportID(): string {
  return `RD-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
}

function cleanTrace(value: unknown, fallback: string): string {
  if (typeof value !== "string") return fallback;
  const clean = value.trim().replace(/[^a-zA-Z0-9._:-]/g, "").slice(0, 80);
  return clean.length > 0 ? clean : fallback;
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not configured`);
  return value;
}

function safeText(value: unknown, fallback = ""): string {
  if (value === null || value === undefined) return fallback;
  return String(value);
}

function safeNumber(value: unknown, fallback = 0): number {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function formatDate(raw: unknown): string {
  if (typeof raw !== "string" || raw.length === 0) return "";
  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) return raw;
  return new Intl.DateTimeFormat("tr-TR", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "Europe/Istanbul",
  }).format(date);
}

function bandLabel(value: unknown): string {
  switch (safeText(value)) {
    case "critical":
      return "Kritik";
    case "high":
      return "Yüksek";
    case "medium":
      return "Orta";
    case "low":
      return "Düşük";
    default:
      return "Bilinmiyor";
  }
}

function canvasLabel(value: unknown): string {
  switch (safeText(value)) {
    case "general":
      return "Genel";
    case "ppe":
      return "KKD";
    case "mark":
      return "İşaretleme";
    case "sector":
      return "Sektör";
    case "ergonomics":
      return "Özel Ekipman";
    case "urgent":
      return "Acil";
    case "procedure":
      return "Prosedür";
    default:
      return safeText(value, "Genel");
  }
}

function methodLabel(method: string): string {
  return method === "matrix_5x5" ? "5x5 Matris" : "Fine-Kinney";
}

function safeFilePart(value: string): string {
  return value
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z0-9._-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 60)
    .toLowerCase() || "riskdetected";
}

function workbookBuffer(workbook: XLSX.WorkBook): Uint8Array {
  return XLSX.write(workbook, {
    bookType: "xlsx",
    type: "buffer",
    cellStyles: true,
  }) as Uint8Array;
}

function appendSheet(workbook: XLSX.WorkBook, name: string, rows: unknown[][]) {
  const sheet = XLSX.utils.aoa_to_sheet(rows);
  sheet["!cols"] = rows[0]?.map((_, index) => ({ wch: index === 0 ? 24 : 34 })) ?? [];
  XLSX.utils.book_append_sheet(workbook, sheet, name);
}

function makeWorkbook(
  analysis: AnalysisRow,
  findings: FindingRow[],
  profile: ProfileRow | null,
  method: string,
  requestID: string,
  supportID: string,
): XLSX.WorkBook {
  const workbook = XLSX.utils.book_new();
  const preparedBy = profile?.display_name ?? profile?.full_name ?? "";
  const companyName = profile?.company_name ?? "";
  const highestBand = method === "matrix_5x5"
    ? analysis.highest_band_m5
    : analysis.highest_band_fk;

  appendSheet(workbook, "Özet", [
    ["Alan", "Değer"],
    ["Analiz başlığı", safeText(analysis.title)],
    ["Analiz tarihi", formatDate(analysis.created_at)],
    ["Tamamlanma tarihi", formatDate(analysis.completed_at)],
    ["Analiz odağı", canvasLabel(analysis.canvas)],
    ["Analiz tipi", safeText(analysis.kind)],
    ["Hazırlayan", preparedBy],
    ["Firma", companyName],
    ["Risk metodu", methodLabel(method)],
    ["Toplam bulgu", findings.length],
    ["En yüksek risk", bandLabel(highestBand)],
    ["Fine-Kinney toplam", safeNumber(analysis.total_score_fk)],
    ["5x5 toplam", safeNumber(analysis.total_score_m5)],
    ["AI özeti", safeText(analysis.ai_summary)],
  ]);

  appendSheet(workbook, "Risk Analiz Tablosu", [
    [
      "No",
      "Tehlike",
      "Kategori",
      "Açıklama",
      "Fine-Kinney O",
      "Fine-Kinney F",
      "Fine-Kinney Ş",
      "Fine-Kinney Skor",
      "Fine-Kinney Seviye",
      "5x5 Olasılık",
      "5x5 Şiddet",
      "5x5 Skor",
      "5x5 Seviye",
      "Önerilen Önlem",
      "Referans / İzleme",
      "AI Güveni",
    ],
    ...findings.map((finding, index) => [
      finding.ordinal ?? index + 1,
      safeText(finding.title),
      safeText(finding.category),
      safeText(finding.description),
      safeNumber(finding.fk_probability),
      safeNumber(finding.fk_frequency),
      safeNumber(finding.fk_severity),
      safeNumber(finding.fk_score),
      bandLabel(finding.fk_band),
      safeNumber(finding.m5_probability),
      safeNumber(finding.m5_severity),
      safeNumber(finding.m5_score),
      bandLabel(finding.m5_band),
      safeText(finding.recommended_action),
      safeText(finding.references_text),
      `${Math.round(safeNumber(finding.confidence) * 100)}%`,
    ]),
  ]);

  appendSheet(workbook, "Aksiyon Planı", [
    ["No", "Tehlike", "Önerilen Önlem", "Sorumlu", "Termin", "Durum", "Not"],
    ...findings.map((finding, index) => [
      finding.ordinal ?? index + 1,
      safeText(finding.title),
      safeText(finding.recommended_action),
      "",
      "",
      "Açık",
      "",
    ]),
  ]);

  appendSheet(workbook, "Rapor Bilgileri", [
    ["Alan", "Değer"],
    ["Analiz ID", analysis.id],
    ["Kullanıcı ID", analysis.user_id],
    ["Firma", companyName],
    ["Hazırlayan", preparedBy],
    ["Ünvan", safeText(profile?.title)],
    ["Sertifika", safeText(profile?.certificate_number)],
    ["Telefon", safeText(profile?.phone)],
    ["Oluşturma tarihi", formatDate(new Date().toISOString())],
    ["Request ID", requestID],
    ["Destek kodu", supportID],
  ]);

  return workbook;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json(405, { error: "method_not_allowed", message: "Yalnızca POST desteklenir." });
  }

  const supabase = createClient(
    requiredEnv("SUPABASE_URL"),
    requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
  );

  let requestID = cleanTrace(req.headers.get("x-request-id"), crypto.randomUUID());
  let supportID = cleanTrace(req.headers.get("x-support-id"), newSupportID());

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json(401, {
      error: "auth_required",
      message: "Oturum doğrulanamadı.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  const { data: { user }, error: authError } = await supabase.auth.getUser(
    authHeader.replace("Bearer ", ""),
  );
  if (authError || !user) {
    return json(401, {
      error: "auth_invalid",
      message: "Oturum doğrulanamadı.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return json(400, {
      error: "invalid_json",
      message: "Geçersiz istek gövdesi.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  requestID = cleanTrace(body.request_id, requestID);
  supportID = cleanTrace(body.support_id, supportID);

  const analysisID = body.analysis_id;
  if (!analysisID) {
    return json(400, {
      error: "analysis_id_required",
      message: "Excel oluşturmak için analiz seçilmelidir.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  const method = body.method === "matrix_5x5" ? "matrix_5x5" : "fine_kinney";

  const { data: analysis, error: analysisError } = await supabase
    .from("analyses")
    .select("*")
    .eq("id", analysisID)
    .eq("user_id", user.id)
    .single();

  if (analysisError || !analysis) {
    return json(404, {
      error: "analysis_not_found",
      message: "Analiz bulunamadı veya bu işlem için yetki yok.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  if ((analysis as AnalysisRow).status !== "completed") {
    return json(409, {
      error: "analysis_not_completed",
      message: "Excel oluşturmak için analiz tamamlanmış olmalıdır.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  const { data: findings, error: findingsError } = await supabase
    .from("findings")
    .select("*")
    .eq("analysis_id", analysisID)
    .eq("user_id", user.id)
    .order("ordinal", { ascending: true });

  if (findingsError) {
    return json(500, {
      error: "findings_fetch_failed",
      message: "Bulgular Excel raporu için okunamadı.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", user.id)
    .maybeSingle();

  const { data: subscription } = await supabase
    .from("user_subscriptions")
    .select("tier,status,current_period_ends_at")
    .eq("user_id", user.id)
    .maybeSingle();

  const planTier = resolvePlanTier((profile as ProfileRow | null)?.tier, subscription);
  if (planTier === "free") {
    return json(402, {
      error: "plan_required",
      message: "Excel risk tablosu Plus veya Pro üyelik ile kullanılabilir.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  const reportLimit = monthlyReportLimit(planTier);
  if (reportLimit !== null) {
    const { count: reportCount, error: reportCountError } = await supabase
      .from("reports")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id)
      .gte("created_at", istanbulMonthStartISO());

    if (reportCountError) {
      return json(500, {
        error: "report_quota_check_failed",
        message: "Rapor kotası kontrol edilemedi.",
        request_id: requestID,
        support_id: supportID,
      });
    }

    if ((reportCount ?? 0) >= reportLimit) {
      return json(429, {
        error: "report_quota_exceeded",
        message: `Aylık rapor kotan doldu (${reportLimit}/ay).`,
        request_id: requestID,
        support_id: supportID,
      });
    }
  }

  const workbook = makeWorkbook(
    analysis as AnalysisRow,
    (findings ?? []) as FindingRow[],
    profile as ProfileRow | null,
    method,
    requestID,
    supportID,
  );
  const bytes = workbookBuffer(workbook);
  const fileName = `${safeFilePart(safeText((analysis as AnalysisRow).title, "risk-analizi"))}-${method}-risk-analizi.xlsx`;
  const storagePath = `${user.id.toLowerCase()}/${analysisID.toLowerCase()}/${fileName}`;

  const { error: uploadError } = await supabase.storage
    .from("reports")
    .upload(storagePath, bytes, {
      contentType: XLSX_MIME,
      upsert: true,
    });

  if (uploadError) {
    console.error("Excel upload failed", uploadError);
    return json(500, {
      error: "excel_upload_failed",
      message: "Excel dosyası rapor arşivine kaydedilemedi.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  const documentNo = `XLSX-${analysisID.slice(0, 8).toUpperCase()}`;
  const { data: report, error: reportError } = await supabase
    .from("reports")
    .upsert({
      user_id: user.id,
      analysis_id: analysisID,
      document_no: documentNo,
      format: "xlsx",
      kind: "risk_analysis",
      method,
      title: safeText((analysis as AnalysisRow).title, "Risk Analizi"),
      storage_path: storagePath,
      file_name: fileName,
      mime_type: XLSX_MIME,
      file_size: bytes.byteLength,
      size_bytes: bytes.byteLength,
      page_count: 1,
      request_id: requestID,
      support_id: supportID,
    }, { onConflict: "user_id,storage_path" })
    .select()
    .single();

  if (reportError) {
    console.error("Excel report metadata failed", reportError);
    return json(500, {
      error: "excel_metadata_failed",
      message: "Excel oluşturuldu ancak rapor arşiv kaydı tamamlanamadı.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  return json(200, {
    report,
    request_id: requestID,
    support_id: supportID,
  });
});
