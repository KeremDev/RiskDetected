/**
 * generate-excel-report — RiskDetected XLSX report generator.
 *
 * Authenticated users can generate an Excel risk analysis workbook for their own
 * completed analysis. The file is written to the private `reports` bucket and
 * metadata is stored in `public.reports` with `format = xlsx`.
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import JSZip from "npm:jszip@3.10.1";
import XLSX from "npm:xlsx-js-style@1.2.0";
import {
  analysisSectorLabel,
  normalizeAnalysisSector,
} from "../analyze/sector-context.ts";
import {
  englishDueTerm,
  englishRiskBand,
  nonTRReportTemplateLeak,
  reportDate,
  type ReportLocalizationContext,
  reportNumber,
  resolveReportLocalization,
} from "../_shared/report-localization.ts";

const XLSX_MIME =
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
const BUSINESS_TIME_ZONE = "Europe/Istanbul";

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
  report_language?: "tr" | "en";
  company_id?: string | null;
  company_name_override?: string | null;
  company_info_override?: string | null;
  prepared_by_override?: string | null;
  prepared_title_override?: string | null;
  certificate_number_override?: string | null;
  company_logo_base64?: string | null;
  client_app_version?: string;
  client_app_build?: string;
  client_platform?: string;
  api_contract_version?: number;
  client_capabilities?: Record<string, unknown>;
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
  company_id?: string | null;
  ai_summary?: string | null;
  total_score_fk?: number | null;
  total_score_m5?: number | null;
  highest_band_fk?: string | null;
  highest_band_m5?: string | null;
  finding_count?: number | null;
  created_at?: string | null;
  completed_at?: string | null;
  analysis_sector?: string | null;
  output_language?: string | null;
  output_locale?: string | null;
  work_jurisdiction_country?: string | null;
  safety_profile_id?: string | null;
  safety_profile_version?: number | null;
  regulatory_reference_policy?: string | null;
  localization_snapshot?: Record<string, unknown> | null;
};

type FindingRow = Record<string, unknown> & {
  ordinal?: number;
  title?: string;
  category?: string | null;
  description?: string | null;
  recommended_action?: string | null;
  recommended_measures?: unknown;
  references_text?: string | null;
  root_cause_text?: string | null;
  needs_field_verification?: boolean | null;
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
  company_logo_url?: string | null;
  company_info?: string | null;
  phone?: string | null;
};

type PlanTier = "free" | "plus" | "pro";
type RiskBand = "critical" | "high" | "medium" | "low" | "unknown";
type CompanyHazardClass = "low" | "medium" | "high";

type CompanyRow = {
  id: string;
  user_id: string;
  name: string;
  hazard_class: CompanyHazardClass;
  logo_path?: string | null;
  address?: string | null;
  contact_person?: string | null;
  department?: string | null;
  default_responsible?: string | null;
  default_due_days?: number | null;
  is_archived?: boolean | null;
};

type CompanySnapshot = {
  id: string;
  name: string;
  hazard_class: CompanyHazardClass;
  logo_path: string | null;
  address: string | null;
  contact_person: string | null;
  department: string | null;
  default_responsible: string | null;
  default_due_days: number | null;
};

const palette = {
  ink: "0B0F0E",
  charcoal: "1F2933",
  slate: "667085",
  line: "D9E1E2",
  tableBlue: "DDF3FB",
  tableLine: "6EAFC6",
  fog: "F4F7F6",
  white: "FFFFFF",
  green: "00B83E",
  greenDark: "087A2D",
  greenSoft: "E8F8EE",
  critical: "C62828",
  criticalSoft: "FDECEC",
  high: "D99000",
  highSoft: "FFF3CC",
  medium: "C4A000",
  mediumSoft: "FFF8D9",
  low: "1F8E46",
  lowSoft: "E9F7EF",
  unknown: "6B7280",
  unknownSoft: "F2F4F7",
};

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

function hasActiveSubscription(
  row:
    | { status?: string | null; current_period_ends_at?: string | null }
    | null,
): boolean {
  if (!row) return false;
  if (
    !["active", "trialing", "grace_period"].includes(String(row.status ?? ""))
  ) return false;
  if (!row.current_period_ends_at) return true;
  const expiresAt = Date.parse(row.current_period_ends_at);
  return Number.isFinite(expiresAt) && expiresAt > Date.now();
}

function resolvePlanTier(
  profileTier: unknown,
  subscription: {
    tier?: string | null;
    status?: string | null;
    current_period_ends_at?: string | null;
  } | null,
): PlanTier {
  void profileTier;
  return hasActiveSubscription(subscription)
    ? normalizeTier(subscription?.tier)
    : "free";
}

function monthlyReportLimit(tier: PlanTier): number | null {
  switch (tier) {
    case "pro":
      return 750;
    case "plus":
      return 150;
    case "free":
    default:
      return 3;
  }
}

function istanbulMonthStartISO(): string {
  const day = new Intl.DateTimeFormat("en-CA", {
    timeZone: BUSINESS_TIME_ZONE,
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

function safeLogText(value: unknown, maxLength = 180): string {
  return String(value)
    .replace(/Bearer\s+[^\s]+/gi, "Bearer [redacted]")
    .slice(0, maxLength);
}

function newSupportID(): string {
  return `RD-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
}

function safeLogError(error: unknown): Record<string, unknown> {
  if (error instanceof Error) {
    return {
      name: error.name || "Error",
      message: error.message.replace(/Bearer\s+[^\s]+/gi, "Bearer [redacted]")
        .slice(0, 160),
    };
  }
  if (typeof error === "object" && error !== null && "message" in error) {
    return {
      name: "ObjectError",
      message: String((error as { message?: unknown }).message).slice(0, 160),
    };
  }
  return { name: typeof error };
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
  const { data: reportRow } = await params.supabase
    .from("reports")
    .select("report_ready_push_sent_at")
    .eq("id", params.reportID)
    .eq("user_id", params.userID)
    .maybeSingle();
  if (reportRow?.report_ready_push_sent_at) return;

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
  if (pushResult.status !== "sent") {
    console.warn(
      "Report ready push not sent",
      JSON.stringify({
        request_id: params.requestID,
        support_id: params.supportID,
        report_id: params.reportID,
        body: safeLogText(responseText),
      }),
    );
    return;
  }

  await params.supabase
    .from("reports")
    .update({ report_ready_push_sent_at: new Date().toISOString() })
    .eq("id", params.reportID)
    .eq("user_id", params.userID)
    .is("report_ready_push_sent_at", null);
}

function safeText(value: unknown, fallback = ""): string {
  if (value === null || value === undefined) return fallback;
  return String(value);
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

function reportSnapshotV2GateOpen(
  value: Record<string, unknown>,
  body: RequestBody,
): boolean {
  if (bool(value.kill_switch, false)) return false;
  const platform = safeText(body.client_platform, "unknown").trim()
    .toLowerCase();
  const build = safeText(body.client_app_build, "").trim();
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

  const mode = safeText(value.rollout_mode, "off").trim().toLowerCase();
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
  body: RequestBody,
): Promise<boolean> {
  const { data, error } = await supabase
    .from("app_feature_flags")
    .select("value")
    .eq("key", "multi_photo_analysis")
    .maybeSingle();
  if (error) return false;
  const value = data?.value as Record<string, unknown> | undefined;
  if (!value || !reportSnapshotV2GateOpen(value, body)) return false;
  const features = value.features && typeof value.features === "object"
    ? value.features as Record<string, unknown>
    : {};
  return bool(
    features.report_snapshot_v2,
    bool(value.enable_report_snapshot_v2, false),
  );
}

function displayFindingTitle(title: unknown): string {
  const original = safeText(title);
  const qualifiers = [
    /\(sahada doğrulanmalı\)/giu,
    /\(sahada dogrulanmali\)/giu,
    /\(sahada doğrulanmalıdır\)/giu,
    /\(sahada dogrulanmalidir\)/giu,
    /sahada doğrulanmalı/giu,
    /sahada dogrulanmali/giu,
    /sahada doğrulanmalıdır/giu,
    /sahada dogrulanmalidir/giu,
  ];

  let cleaned = original;
  for (const qualifier of qualifiers) {
    cleaned = cleaned.replace(qualifier, "");
  }
  cleaned = cleaned
    .replace(/\s{2,}/gu, " ")
    .replace(/ \(\)/gu, "")
    .trim()
    .replace(/[-–—·,;:\s]+$/u, "");

  return cleaned || original;
}

function actionWithRootCause(finding: FindingRow): string {
  const rootCause = safeText(finding.root_cause_text).trim();
  const measures = controlMeasuresText(finding);
  return rootCause ? `${measures}\n\nKök neden: ${rootCause}` : measures;
}

function controlMeasuresText(finding: FindingRow): string {
  const rawMeasures = Array.isArray(finding.recommended_measures)
    ? finding.recommended_measures
    : [];
  const measures = rawMeasures
    .map((item) => {
      if (!item || typeof item !== "object") return null;
      const record = item as Record<string, unknown>;
      const kind = safeText(record.kind);
      const title = controlMeasureTitle(kind, record.title);
      const text = safeText(record.text).trim();
      return text ? { title, text } : null;
    })
    .filter((item): item is { title: string; text: string } => item !== null);

  if (measures.length === 0) {
    const fallback = safeText(finding.recommended_action).trim();
    return fallback ? `Düzeltici Önlem: ${fallback}` : "";
  }

  return measures
    .map((measure) => `${measure.title}: ${measure.text}`)
    .join("\n");
}

function controlMeasureTitle(kind: string, title: unknown): string {
  if (kind === "preventive") return "Önleyici Kontrol";
  if (kind === "corrective") return "Düzeltici Önlem";
  return safeText(title, "Kontrol Tedbiri");
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
    timeZone: BUSINESS_TIME_ZONE,
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

function suggestedTerm(value: unknown): string {
  switch (normalizeBand(value)) {
    case "critical":
      return "Acil / 1-3 gün";
    case "high":
      return "7 gün";
    case "medium":
      return "15 gün";
    case "low":
      return "30 gün";
    default:
      return "Değerlendirilecek";
  }
}

function hazardClassLabel(value: unknown): string {
  switch (value) {
    case "low":
      return "Az Tehlikeli";
    case "high":
      return "Çok Tehlikeli";
    case "medium":
    default:
      return "Tehlikeli";
  }
}

function companySnapshot(company: CompanyRow | null): CompanySnapshot | null {
  if (!company) return null;
  return {
    id: company.id,
    name: company.name,
    hazard_class: company.hazard_class,
    logo_path: company.logo_path ?? null,
    address: company.address ?? null,
    contact_person: company.contact_person ?? null,
    department: company.department ?? null,
    default_responsible: company.default_responsible ?? null,
    default_due_days: company.default_due_days ?? null,
  };
}

function profileWithCompany(
  profile: ProfileRow | null,
  company: CompanyRow | null,
): ProfileRow | null {
  if (!company) return profile;
  const companyInfo = [
    hazardClassLabel(company.hazard_class),
    safeText(company.address),
    safeText(company.contact_person)
      ? `İrtibat: ${safeText(company.contact_person)}`
      : "",
    safeText(company.department)
      ? `Birim: ${safeText(company.department)}`
      : "",
    safeText(company.default_responsible)
      ? `Sorumlu: ${safeText(company.default_responsible)}`
      : "",
    typeof company.default_due_days === "number"
      ? `Varsayılan termin: ${company.default_due_days} gün`
      : "",
  ].filter((value) => value.length > 0).join(" · ");
  return {
    ...(profile ?? {}),
    company_name: company.name,
    company_logo_url: company.logo_path ?? profile?.company_logo_url ?? null,
    company_info: companyInfo,
  };
}

function normalizeBand(value: unknown): RiskBand {
  const raw = safeText(value).toLowerCase();
  if (
    raw === "critical" || raw === "high" || raw === "medium" || raw === "low"
  ) {
    return raw;
  }
  return "unknown";
}

function bandStyle(value: unknown) {
  const band = normalizeBand(value);
  switch (band) {
    case "critical":
      return { fg: palette.critical, bg: palette.criticalSoft };
    case "high":
      return { fg: palette.high, bg: palette.highSoft };
    case "medium":
      return { fg: palette.medium, bg: palette.mediumSoft };
    case "low":
      return { fg: palette.low, bg: palette.lowSoft };
    case "unknown":
    default:
      return { fg: palette.unknown, bg: palette.unknownSoft };
  }
}

function analysisSectorLabelFromRow(analysis: AnalysisRow): string {
  const sector = normalizeAnalysisSector(analysis.analysis_sector);
  return sector ? analysisSectorLabel(sector, "tr") : "Belirtilmedi";
}

function canvasLabel(value: unknown): string {
  switch (safeText(value)) {
    case "general":
      return "Genel";
    case "ppe":
      return "KKD";
    case "machine":
      return "Makine";
    case "warning_signs":
      return "Uyarı Levhaları";
    case "electrical":
      return "Elektrik";
    case "sector":
      return "Sektör";
    case "fire":
      return "Yangın";
    case "ergonomics":
      return "Özel Ekipman";
    case "environment_measurement":
      return "Ortam Ölçümü";
    case "explosion":
      return "Patlama";
    case "environment":
      return "Çevre";
    case "legislation":
      return "Mevzuat";
    case "working_at_height":
      return "Yüksekte Çalışma";
    case "mobile_equipment":
      return "Hareketli Ekipman";
    case "general_premium":
      return "Genel Premium";
    case "construction_machinery":
      return "İş Makineleri";
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

function archiveFileSuffix(requestID: string): string {
  const timestamp = new Date()
    .toISOString()
    .replace(/\.\d{3}Z$/, "Z")
    .replace(/[-:]/g, "")
    .toLowerCase();
  const requestPart = requestID.replace(/[^a-zA-Z0-9]/g, "").slice(0, 8)
    .toLowerCase();
  return `${timestamp}-${requestPart || "request"}`;
}

function workbookBuffer(workbook: XLSX.WorkBook): Uint8Array {
  return XLSX.write(workbook, {
    bookType: "xlsx",
    type: "buffer",
    cellStyles: true,
  }) as Uint8Array;
}

function xmlEscape(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

function logoPathFromProfile(value: unknown): string {
  const raw = safeText(value).trim();
  if (!raw) return "";
  if (!raw.startsWith("http")) return raw.replace(/^\/+/, "");
  try {
    const url = new URL(raw);
    const marker = "/storage/v1/object/";
    const markerIndex = url.pathname.indexOf(marker);
    if (markerIndex === -1) return "";
    const objectPath = decodeURIComponent(
      url.pathname.slice(markerIndex + marker.length),
    );
    return objectPath.replace(/^public\/logos\//, "").replace(
      /^sign\/logos\//,
      "",
    ).replace(/^logos\//, "");
  } catch {
    return "";
  }
}

function isOwnedLogoPath(path: string, userID: string): boolean {
  const normalizedPath = path.replace(/^\/+/, "").toLowerCase();
  const ownerPrefix = `${userID.toLowerCase()}/`;
  if (!normalizedPath.startsWith(ownerPrefix)) return false;
  return normalizedPath === `${ownerPrefix}profile-logo.jpg` ||
    /^([0-9a-f-]+)\/companies\/([0-9a-f-]+)\/logo\.jpg$/i.test(
      normalizedPath,
    );
}

async function loadCompanyLogo(
  supabase: any,
  profile: ProfileRow | null,
  userID: string,
): Promise<{ bytes: Uint8Array; extension: "jpg" | "png" } | null> {
  const path = logoPathFromProfile(profile?.company_logo_url);
  if (!path) return null;
  if (!isOwnedLogoPath(path, userID)) {
    console.warn(
      "Company logo skipped because path is outside current user prefix",
    );
    return null;
  }

  const { data, error } = await supabase.storage.from("logos").download(path);
  if (error || !data) {
    console.warn(
      "Company logo could not be downloaded for Excel",
      JSON.stringify({
        error: error ? safeLogError(error) : { name: "empty_logo_data" },
      }),
    );
    return null;
  }

  const mime = safeText(data.type).toLowerCase();
  const extension: "jpg" | "png" =
    mime.includes("png") || path.toLowerCase().endsWith(".png") ? "png" : "jpg";
  return {
    bytes: new Uint8Array(await data.arrayBuffer()),
    extension,
  };
}

function inlineCompanyLogo(
  value: unknown,
): { bytes: Uint8Array; extension: "jpg" | "png" } | null {
  if (
    typeof value !== "string" || value.length === 0 || value.length > 4_000_000
  ) return null;
  try {
    const binary = atob(value);
    if (binary.length === 0 || binary.length > 3_000_000) return null;
    const bytes = Uint8Array.from(
      binary,
      (character) => character.charCodeAt(0),
    );
    const png = bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 &&
      bytes[2] === 0x4e && bytes[3] === 0x47;
    const jpeg = bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 &&
      bytes[2] === 0xff;
    if (!png && !jpeg) return null;
    return { bytes, extension: png ? "png" : "jpg" };
  } catch {
    return null;
  }
}

function appendXmlRelationship(
  xml: string,
  id: string,
  type: string,
  target: string,
): string {
  const relationship = `<Relationship Id="${xmlEscape(id)}" Type="${
    xmlEscape(type)
  }" Target="${xmlEscape(target)}"/>`;
  if (xml.includes(`Id="${id}"`)) return xml;
  return xml.replace("</Relationships>", `${relationship}</Relationships>`);
}

function appendContentTypeDefault(
  xml: string,
  extension: string,
  contentType: string,
): string {
  if (xml.includes(`Extension="${extension}"`)) return xml;
  return xml.replace(
    "</Types>",
    `<Default Extension="${xmlEscape(extension)}" ContentType="${
      xmlEscape(contentType)
    }"/></Types>`,
  );
}

function appendContentTypeOverride(
  xml: string,
  partName: string,
  contentType: string,
): string {
  if (xml.includes(`PartName="${partName}"`)) return xml;
  return xml.replace(
    "</Types>",
    `<Override PartName="${xmlEscape(partName)}" ContentType="${
      xmlEscape(contentType)
    }"/></Types>`,
  );
}

function readUint32BE(bytes: Uint8Array, offset: number): number {
  return (
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3]
  ) >>> 0;
}

function logoDimensions(
  bytes: Uint8Array,
  extension: "jpg" | "png",
): { width: number; height: number } | null {
  if (extension === "png" && bytes.length > 24) {
    return {
      width: readUint32BE(bytes, 16),
      height: readUint32BE(bytes, 20),
    };
  }

  if (extension === "jpg" && bytes.length > 4) {
    let offset = 2;
    while (offset + 9 < bytes.length) {
      if (bytes[offset] !== 0xff) break;
      const marker = bytes[offset + 1];
      const length = (bytes[offset + 2] << 8) + bytes[offset + 3];
      if (length < 2) break;
      if (
        (marker >= 0xc0 && marker <= 0xc3) || (marker >= 0xc5 && marker <= 0xc7)
      ) {
        return {
          height: (bytes[offset + 5] << 8) + bytes[offset + 6],
          width: (bytes[offset + 7] << 8) + bytes[offset + 8],
        };
      }
      offset += 2 + length;
    }
  }

  return null;
}

function logoExtents(
  bytes: Uint8Array,
  extension: "jpg" | "png",
): { cx: number; cy: number } {
  const maxCx = 1450000;
  const maxCy = 420000;
  const dimensions = logoDimensions(bytes, extension);
  if (!dimensions || dimensions.width <= 0 || dimensions.height <= 0) {
    return { cx: maxCx, cy: maxCy };
  }

  const ratio = dimensions.width / dimensions.height;
  const maxRatio = maxCx / maxCy;
  if (ratio >= maxRatio) {
    return { cx: maxCx, cy: Math.round(maxCx / ratio) };
  }
  return { cx: Math.round(maxCy * ratio), cy: maxCy };
}

async function embedCompanyLogo(
  bytes: Uint8Array,
  logo: { bytes: Uint8Array; extension: "jpg" | "png" },
): Promise<Uint8Array> {
  const zip = await JSZip.loadAsync(bytes);
  const imageName = `company-logo.${logo.extension}`;
  const imageContentType = logo.extension === "png"
    ? "image/png"
    : "image/jpeg";
  const extents = logoExtents(logo.bytes, logo.extension);
  const drawingPath = "xl/drawings/drawing1.xml";
  const drawingRelsPath = "xl/drawings/_rels/drawing1.xml.rels";
  const sheetPath = "xl/worksheets/sheet1.xml";
  const sheetRelsPath = "xl/worksheets/_rels/sheet1.xml.rels";
  const contentTypesPath = "[Content_Types].xml";

  zip.file(`xl/media/${imageName}`, logo.bytes);
  zip.file(
    drawingPath,
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <xdr:oneCellAnchor>
    <xdr:from><xdr:col>6</xdr:col><xdr:colOff>180000</xdr:colOff><xdr:row>0</xdr:row><xdr:rowOff>130000</xdr:rowOff></xdr:from>
    <xdr:ext cx="${extents.cx}" cy="${extents.cy}"/>
    <xdr:pic>
      <xdr:nvPicPr>
        <xdr:cNvPr id="1" name="Firma Logosu"/>
        <xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr>
      </xdr:nvPicPr>
      <xdr:blipFill>
        <a:blip xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:embed="rId1"/>
        <a:stretch><a:fillRect/></a:stretch>
      </xdr:blipFill>
      <xdr:spPr><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr>
    </xdr:pic>
    <xdr:clientData/>
  </xdr:oneCellAnchor>
</xdr:wsDr>`,
  );
  zip.file(
    drawingRelsPath,
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/${
      xmlEscape(imageName)
    }"/>
</Relationships>`,
  );

  const sheetXmlFile = zip.file(sheetPath);
  if (!sheetXmlFile) return bytes;
  let sheetXml = await sheetXmlFile.async("string");
  if (!sheetXml.includes("xmlns:r=")) {
    sheetXml = sheetXml.replace(
      "<worksheet ",
      '<worksheet xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" ',
    );
  }
  if (!sheetXml.includes("<drawing ")) {
    sheetXml = sheetXml.replace(
      "</worksheet>",
      '<drawing r:id="rIdLogo"/></worksheet>',
    );
  }
  zip.file(sheetPath, sheetXml);

  const sheetRels = zip.file(sheetRelsPath)
    ? await zip.file(sheetRelsPath)!.async("string")
    : '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"></Relationships>';
  zip.file(
    sheetRelsPath,
    appendXmlRelationship(
      sheetRels,
      "rIdLogo",
      "http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing",
      "../drawings/drawing1.xml",
    ),
  );

  const contentTypesFile = zip.file(contentTypesPath);
  if (contentTypesFile) {
    let contentTypes = await contentTypesFile.async("string");
    contentTypes = appendContentTypeDefault(
      contentTypes,
      logo.extension,
      imageContentType,
    );
    contentTypes = appendContentTypeOverride(
      contentTypes,
      "/xl/drawings/drawing1.xml",
      "application/vnd.openxmlformats-officedocument.drawing+xml",
    );
    zip.file(contentTypesPath, contentTypes);
  }

  return await zip.generateAsync({
    type: "uint8array",
    compression: "DEFLATE",
  });
}

const borderThin = {
  top: { style: "thin", color: { rgb: palette.line } },
  bottom: { style: "thin", color: { rgb: palette.line } },
  left: { style: "thin", color: { rgb: palette.line } },
  right: { style: "thin", color: { rgb: palette.line } },
};

const styles = {
  title: {
    font: {
      name: "Aptos Display",
      sz: 24,
      bold: true,
      color: { rgb: palette.greenDark },
    },
    fill: { fgColor: { rgb: palette.greenSoft } },
    alignment: { horizontal: "left", vertical: "center" },
  },
  subtitle: {
    font: { name: "Aptos", sz: 12, color: { rgb: palette.slate } },
    fill: { fgColor: { rgb: palette.greenSoft } },
    alignment: { horizontal: "left", vertical: "center" },
  },
  label: {
    font: { name: "Aptos", sz: 10, bold: true, color: { rgb: palette.slate } },
    fill: { fgColor: { rgb: palette.fog } },
    alignment: { horizontal: "left", vertical: "top", wrapText: true },
    border: borderThin,
  },
  value: {
    font: { name: "Aptos", sz: 11, color: { rgb: palette.charcoal } },
    fill: { fgColor: { rgb: palette.white } },
    alignment: { horizontal: "left", vertical: "top", wrapText: true },
    border: borderThin,
  },
  kpiLabel: {
    font: { name: "Aptos", sz: 9, bold: true, color: { rgb: palette.slate } },
    fill: { fgColor: { rgb: palette.fog } },
    alignment: { horizontal: "center", vertical: "center", wrapText: true },
    border: borderThin,
  },
  kpiValue: {
    font: {
      name: "Aptos Display",
      sz: 16,
      bold: true,
      color: { rgb: palette.ink },
    },
    fill: { fgColor: { rgb: palette.white } },
    alignment: { horizontal: "center", vertical: "center", wrapText: true },
    border: borderThin,
  },
  tableHeader: {
    font: {
      name: "Aptos",
      sz: 10,
      bold: true,
      color: { rgb: palette.greenDark },
    },
    fill: { fgColor: { rgb: palette.tableBlue } },
    alignment: { horizontal: "center", vertical: "center", wrapText: true },
    border: borderThin,
  },
  tableCell: {
    font: { name: "Aptos", sz: 10, color: { rgb: palette.charcoal } },
    fill: { fgColor: { rgb: palette.white } },
    alignment: { horizontal: "left", vertical: "top", wrapText: true },
    border: borderThin,
  },
  tableNumber: {
    font: { name: "Aptos", sz: 10, color: { rgb: palette.charcoal } },
    fill: { fgColor: { rgb: palette.white } },
    alignment: { horizontal: "center", vertical: "top", wrapText: true },
    border: borderThin,
  },
  referenceTitle: {
    font: { name: "Aptos", sz: 13, bold: true, color: { rgb: palette.ink } },
    fill: { fgColor: { rgb: palette.greenSoft } },
    alignment: { horizontal: "center", vertical: "center", wrapText: true },
  },
  referenceHeader: {
    font: { name: "Aptos", sz: 9, bold: true, color: { rgb: palette.ink } },
    fill: { fgColor: { rgb: palette.tableBlue } },
    alignment: { horizontal: "center", vertical: "center", wrapText: true },
    border: borderThin,
  },
};

function appendSheet(
  workbook: XLSX.WorkBook,
  name: string,
  rows: unknown[][],
): XLSX.WorkSheet {
  const sheet = XLSX.utils.aoa_to_sheet(rows);
  XLSX.utils.book_append_sheet(workbook, sheet, name);
  return sheet;
}

function setCols(sheet: XLSX.WorkSheet, widths: number[]) {
  sheet["!cols"] = widths.map((wch) => ({ wch }));
}

function setRows(sheet: XLSX.WorkSheet, heights: number[]) {
  sheet["!rows"] = heights.map((hpt) => ({ hpt }));
}

function addMerges(sheet: XLSX.WorkSheet, ranges: string[]) {
  sheet["!merges"] = ranges.map((range) => XLSX.utils.decode_range(range));
}

function ensureCell(sheet: XLSX.WorkSheet, address: string) {
  if (!sheet[address]) sheet[address] = { t: "s", v: "" };
  return sheet[address] as XLSX.CellObject;
}

function setStyle(
  sheet: XLSX.WorkSheet,
  range: string,
  style: Record<string, unknown>,
) {
  const decoded = XLSX.utils.decode_range(range);
  for (let row = decoded.s.r; row <= decoded.e.r; row++) {
    for (let col = decoded.s.c; col <= decoded.e.c; col++) {
      const address = XLSX.utils.encode_cell({ r: row, c: col });
      ensureCell(sheet, address).s = style;
    }
  }
}

function clampNumber(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function estimatedLineCount(value: unknown, widthChars: number): number {
  const text = safeText(value).trim();
  if (!text) return 1;
  const usableWidth = Math.max(8, Math.floor(widthChars * 0.92));
  return text.split(/\r?\n/u).reduce((sum, line) => {
    const length = Math.max(1, line.trim().length);
    return sum + Math.max(1, Math.ceil(length / usableWidth));
  }, 0);
}

function estimatedRowHeight(
  cells: Array<{ value: unknown; width: number }>,
  options: {
    min?: number;
    max?: number;
    base?: number;
    lineHeight?: number;
  } = {},
): number {
  const maxLines = cells.reduce(
    (max, cell) => Math.max(max, estimatedLineCount(cell.value, cell.width)),
    1,
  );
  const base = options.base ?? 8;
  const lineHeight = options.lineHeight ?? 14;
  return clampNumber(
    base + maxLines * lineHeight,
    options.min ?? 24,
    options.max ?? 220,
  );
}

function totalColumnWidth(widths: number[]): number {
  return widths.reduce((sum, width) => sum + width, 0);
}

function methodBand(finding: FindingRow, method: string): RiskBand {
  return normalizeBand(
    method === "matrix_5x5" ? finding.m5_band : finding.fk_band,
  );
}

function methodScore(finding: FindingRow, method: string): number {
  return safeNumber(
    method === "matrix_5x5" ? finding.m5_score : finding.fk_score,
  );
}

function methodTotalScore(analysis: AnalysisRow, method: string): number {
  return safeNumber(
    method === "matrix_5x5" ? analysis.total_score_m5 : analysis.total_score_fk,
  );
}

function riskCounts(
  findings: FindingRow[],
  method: string,
): Record<RiskBand, number> {
  const counts: Record<RiskBand, number> = {
    critical: 0,
    high: 0,
    medium: 0,
    low: 0,
    unknown: 0,
  };
  for (const finding of findings) {
    counts[methodBand(finding, method)] += 1;
  }
  return counts;
}

function riskBar(count: number, total: number): string {
  if (total <= 0 || count <= 0) return "";
  const units = Math.max(1, Math.round((count / total) * 18));
  return "█".repeat(units);
}

function applyWorkbookDefaults(workbook: XLSX.WorkBook) {
  workbook.Props = {
    ...(workbook.Props ?? {}),
    Title: "RiskDetected Risk Analizi",
    Subject: "İSG risk analizi Excel raporu",
    Author: "RiskDetected",
    Company: "RiskDetected",
  };
}

function matrixBand(score: number): RiskBand {
  if (score >= 20) return "critical";
  if (score >= 10) return "high";
  if (score >= 5) return "medium";
  return "low";
}

function applyReferenceTableStyle(
  sheet: XLSX.WorkSheet,
  titleRange: string,
  headerRange: string,
  bodyRange: string,
) {
  setStyle(sheet, titleRange, styles.referenceHeader);
  setStyle(sheet, headerRange, {
    ...styles.tableHeader,
    font: { name: "Aptos", sz: 8, bold: true, color: { rgb: palette.ink } },
    fill: { fgColor: { rgb: palette.fog } },
  });
  setStyle(sheet, bodyRange, {
    ...styles.tableCell,
    font: { name: "Aptos", sz: 8, color: { rgb: palette.charcoal } },
    alignment: { horizontal: "center", vertical: "center", wrapText: true },
  });
}

function englishCanvasLabel(value: unknown): string {
  switch (safeText(value)) {
    case "general":
      return "General";
    case "ppe":
      return "Personal protective equipment";
    case "machine":
      return "Machinery";
    case "warning_signs":
      return "Safety signs";
    case "electrical":
      return "Electrical safety";
    case "sector":
      return "Sector-specific";
    case "fire":
      return "Fire safety";
    case "ergonomics":
      return "Ergonomics";
    case "environment_measurement":
      return "Work environment";
    case "explosion":
      return "Explosion hazards";
    case "environment":
      return "Environmental conditions";
    case "working_at_height":
      return "Work at height";
    case "mobile_equipment":
      return "Mobile equipment";
    case "general_premium":
      return "General";
    case "construction_machinery":
      return "Construction machinery";
    case "legislation":
      return "Unavailable for this safety profile";
    default:
      return safeText(value, "General");
  }
}

function englishSectorLabel(analysis: AnalysisRow): string {
  const sector = normalizeAnalysisSector(analysis.analysis_sector);
  return sector ? analysisSectorLabel(sector, "en") : "Not specified";
}

function englishMethodLabel(method: string): string {
  return method === "matrix_5x5" ? "5×5 matrix" : "Fine-Kinney";
}

function englishControlMeasuresText(finding: FindingRow): string {
  const rawMeasures = Array.isArray(finding.recommended_measures)
    ? finding.recommended_measures
    : [];
  const measures = rawMeasures
    .map((item) => {
      if (!item || typeof item !== "object") return null;
      const record = item as Record<string, unknown>;
      const kind = safeText(record.kind);
      const title = kind === "preventive"
        ? "Preventive control"
        : kind === "corrective"
        ? "Corrective action"
        : safeText(record.title, "Control measure");
      const text = safeText(record.text).trim();
      return text ? `${title}: ${text}` : null;
    })
    .filter((item): item is string => item !== null);
  if (measures.length > 0) return measures.join("\n");
  return safeText(finding.recommended_action);
}

function englishActionWithRootCause(finding: FindingRow): string {
  const measures = englishControlMeasuresText(finding);
  const rootCause = safeText(finding.root_cause_text);
  return rootCause ? `${measures}\n\nRoot cause: ${rootCause}` : measures;
}

function assertNoNonTRWorkbookTemplateLeak(workbook: XLSX.WorkBook) {
  for (const sheetName of workbook.SheetNames) {
    const sheet = workbook.Sheets[sheetName];
    const range = sheet?.["!ref"];
    if (!sheet || !range) continue;
    const decoded = XLSX.utils.decode_range(range);
    for (let row = decoded.s.r; row <= decoded.e.r; row++) {
      for (let col = decoded.s.c; col <= decoded.e.c; col++) {
        const cell = sheet[XLSX.utils.encode_cell({ r: row, c: col })];
        const leak = nonTRReportTemplateLeak(cell?.v);
        if (leak) {
          throw new Error(`NON_TR_REPORT_TEMPLATE_LEAK:${leak}:${sheetName}`);
        }
      }
    }
  }
}

export function makeEnglishWorkbook(
  analysis: AnalysisRow,
  findings: FindingRow[],
  profile: ProfileRow | null,
  method: string,
  requestID: string,
  supportID: string,
  documentNo: string,
  localization: ReportLocalizationContext,
): XLSX.WorkBook {
  const workbook = XLSX.utils.book_new();
  workbook.Props = {
    Title: "RiskDetected risk assessment",
    Subject: "Workplace-safety risk assessment report",
    Author: "RiskDetected",
    Company: "RiskDetected",
  };

  const preparedBy = safeText(
    profile?.display_name ?? profile?.full_name,
    "Not specified",
  );
  const companyName = safeText(profile?.company_name, "Not specified");
  const counts = riskCounts(findings, method);
  const highestBand = method === "matrix_5x5"
    ? analysis.highest_band_m5
    : analysis.highest_band_fk;
  const disclaimer =
    "This report supports workplace-safety review and risk prioritisation. It does not determine legal compliance and does not replace a competent person’s site assessment.";
  const summaryRows: unknown[][] = [
    ["RiskDetected", "", "", "", "", "", "", ""],
    ["Workplace-safety risk assessment", "", "", "", "", "", "", ""],
    [],
    [
      "Analysis",
      safeText(analysis.title, "Untitled analysis"),
      "",
      "Company",
      companyName,
      "",
      "Document no.",
      documentNo,
    ],
    [
      "Scope",
      englishSectorLabel(analysis),
      "",
      "Prepared by",
      preparedBy,
      "",
      "Created",
      reportDate(analysis.created_at, localization.locale),
    ],
    [
      "Focus",
      englishCanvasLabel(analysis.canvas),
      "",
      "Method",
      englishMethodLabel(method),
      "",
      "Generated",
      reportDate(new Date().toISOString(), localization.locale),
    ],
    [],
    [
      "TOTAL FINDINGS",
      "",
      "HIGHEST RISK",
      "",
      "METHOD",
      "",
      "TOTAL SCORE",
      "",
    ],
    [
      reportNumber(findings.length, localization.locale, 0),
      "",
      englishRiskBand(highestBand),
      "",
      englishMethodLabel(method),
      "",
      reportNumber(
        methodTotalScore(analysis, method),
        localization.locale,
      ),
      "",
    ],
    [],
    ["Risk level", "Count", "Share", "", "", "", "", ""],
    ...(["critical", "high", "medium", "low", "unknown"] as RiskBand[]).map(
      (band) => [
        englishRiskBand(band),
        counts[band],
        findings.length > 0
          ? `${Math.round((counts[band] / findings.length) * 100)}%`
          : "0%",
        "",
        "",
        "",
        "",
        "",
      ],
    ),
    [],
    ["Analysis summary", "", "", "", "", "", "", ""],
    [
      safeText(analysis.ai_summary, "No summary available."),
      "",
      "",
      "",
      "",
      "",
      "",
      "",
    ],
    [],
    ["Important notice", "", "", "", "", "", "", ""],
    [disclaimer, "", "", "", "", "", "", ""],
  ];
  const summary = appendSheet(workbook, "Summary", summaryRows);
  setCols(summary, [18, 28, 4, 18, 28, 4, 18, 28]);
  addMerges(summary, [
    "A1:H1",
    "A2:H2",
    "A8:B8",
    "C8:D8",
    "E8:F8",
    "G8:H8",
    "A9:B9",
    "C9:D9",
    "E9:F9",
    "G9:H9",
    "D11:H11",
    "D12:H12",
    "D13:H13",
    "D14:H14",
    "D15:H15",
    "A17:H17",
    "A18:H18",
    "A20:H20",
    "A21:H21",
  ]);
  setStyle(summary, "A1:H1", styles.title);
  setStyle(summary, "A2:H2", styles.subtitle);
  setStyle(summary, "A4:H6", styles.tableCell);
  setStyle(summary, "A4:A6", styles.label);
  setStyle(summary, "D4:D6", styles.label);
  setStyle(summary, "G4:G6", styles.label);
  setStyle(summary, "A8:H8", styles.kpiLabel);
  setStyle(summary, "A9:H9", styles.kpiValue);
  setStyle(summary, "A11:H11", styles.tableHeader);
  setStyle(summary, "A12:H15", styles.tableCell);
  setStyle(summary, "A17:H17", styles.tableHeader);
  setStyle(summary, "A18:H18", styles.value);
  setStyle(summary, "A20:H20", styles.tableHeader);
  setStyle(summary, "A21:H21", styles.value);
  setRows(summary, [
    32,
    24,
    8,
    26,
    26,
    26,
    10,
    32,
    28,
    10,
    26,
    24,
    24,
    24,
    24,
    10,
    28,
    72,
    10,
    28,
    72,
  ]);

  const metricHeaders = method === "matrix_5x5"
    ? ["Likelihood", "Severity", "Score", "Risk level"]
    : ["Likelihood", "Frequency", "Severity", "Score", "Risk level"];
  const metricValues = (finding: FindingRow) =>
    method === "matrix_5x5"
      ? [
        safeNumber(finding.m5_probability),
        safeNumber(finding.m5_severity),
        safeNumber(finding.m5_score),
        englishRiskBand(finding.m5_band),
      ]
      : [
        safeNumber(finding.fk_probability),
        safeNumber(finding.fk_frequency),
        safeNumber(finding.fk_severity),
        safeNumber(finding.fk_score),
        englishRiskBand(finding.fk_band),
      ];
  const headers = [
    "No.",
    "Hazard or unsafe condition",
    "Category",
    "Observed evidence",
    ...metricHeaders,
    "Recommended controls",
    "Root cause",
    "Target time",
    "Status",
  ];
  const rows: unknown[][] = [
    headers,
    ...findings.map((finding, index) => [
      finding.ordinal ?? index + 1,
      displayFindingTitle(finding.title),
      safeText(finding.category),
      safeText(finding.description),
      ...metricValues(finding),
      englishControlMeasuresText(finding),
      safeText(finding.root_cause_text),
      englishDueTerm(methodBand(finding, method)),
      "Open",
    ]),
  ];
  const findingsSheet = appendSheet(workbook, "Risk register", rows);
  const widths = method === "matrix_5x5"
    ? [7, 32, 20, 62, 12, 12, 12, 16, 72, 42, 18, 14]
    : [7, 32, 20, 62, 12, 12, 12, 12, 16, 72, 42, 18, 14];
  setCols(findingsSheet, widths);
  setRows(findingsSheet, [
    42,
    ...findings.map((finding) =>
      estimatedRowHeight(
        [
          { value: finding.title, width: widths[1] },
          { value: finding.description, width: widths[3] },
          { value: englishActionWithRootCause(finding), width: 72 },
        ],
        { min: 72, max: 260, base: 10, lineHeight: 14 },
      )
    ),
  ]);
  const lastColumn = XLSX.utils.encode_col(headers.length - 1);
  findingsSheet["!autofilter"] = {
    ref: `A1:${lastColumn}${Math.max(1, rows.length)}`,
  };
  findingsSheet["!freeze"] = { xSplit: 0, ySplit: 1 };
  setStyle(findingsSheet, `A1:${lastColumn}1`, styles.tableHeader);
  for (let index = 0; index < findings.length; index++) {
    const row = index + 2;
    const rowFill = index % 2 === 0 ? palette.white : palette.fog;
    setStyle(findingsSheet, `A${row}:${lastColumn}${row}`, {
      ...styles.tableCell,
      fill: { fgColor: { rgb: rowFill } },
    });
    setStyle(findingsSheet, `A${row}:A${row}`, styles.tableNumber);
  }

  const auditRows = [
    ["Field", "Value"],
    ["Analysis ID", analysis.id],
    ["Document no.", documentNo],
    ["Report language", localization.language],
    ["Report locale", localization.locale],
    ["Safety profile", localization.safetyProfileID],
    ["Safety profile version", localization.safetyProfileVersion],
    ["Regulatory sections", "Disabled"],
    ["Request ID", requestID],
    ["Support code", supportID],
    ["Notice", disclaimer],
  ];
  const audit = appendSheet(workbook, "Report information", auditRows);
  setCols(audit, [26, 88]);
  setStyle(audit, "A1:B1", styles.tableHeader);
  setStyle(audit, "A2:B11", styles.tableCell);
  setStyle(audit, "A2:A11", styles.label);

  assertNoNonTRWorkbookTemplateLeak(workbook);
  return workbook;
}

function appendMethodReferenceSheet(
  workbook: XLSX.WorkBook,
  analysis: AnalysisRow,
  profile: ProfileRow | null,
  method: string,
  documentNo: string,
) {
  if (method === "matrix_5x5") {
    appendMatrixReferenceSheet(workbook, analysis, profile, documentNo);
  } else {
    appendFineKinneyReferenceSheet(workbook, analysis, profile, documentNo);
  }
}

function appendFineKinneyReferenceSheet(
  workbook: XLSX.WorkBook,
  analysis: AnalysisRow,
  profile: ProfileRow | null,
  documentNo: string,
) {
  const preparedBy = profile?.display_name ?? profile?.full_name ?? "Kullanıcı";
  const companyName = profile?.company_name ?? "Firma belirtilmedi";
  const companyInfo = safeText(profile?.company_info, safeText(profile?.phone));
  const preparedTitle = safeText(profile?.title, "Belirtilmedi");
  const certificateNumber = safeText(
    profile?.certificate_number,
    "Belirtilmedi",
  );
  const companyLine = companyInfo.length > 0
    ? `${companyName} · ${companyInfo}`
    : companyName;
  const sheet = appendSheet(workbook, "Metot Referansı", [
    [
      "FINE-KINNEY METODU REFERANS TABLOSU",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
    ],
    [],
    [
      "OLASILIK (O)",
      "",
      "",
      "",
      "",
      "FREKANS (F)",
      "",
      "",
      "",
      "",
      "ŞİDDET (Ş)",
      "",
      "",
      "",
    ],
    [
      "Değer",
      "Zararın gerçekleşme olasılığı",
      "",
      "",
      "",
      "Değer",
      "Tehlikeye maruz kalma tekrarı",
      "",
      "",
      "",
      "Değer",
      "İnsan/çevre üzerinde tahmini zarar",
      "",
      "",
    ],
    [
      "10",
      "Beklenir, kesin",
      "",
      "",
      "",
      "10",
      "Hemen hemen sürekli / saatte birkaç defa",
      "",
      "",
      "",
      "100",
      "Birden fazla ölümlü kaza / çevresel felaket",
      "",
      "",
    ],
    [
      "6",
      "Yüksek, oldukça mümkün",
      "",
      "",
      "",
      "6",
      "Sık / günde bir veya birkaç defa",
      "",
      "",
      "",
      "40",
      "Ölümlü kaza / ciddi çevresel zarar",
      "",
      "",
    ],
    [
      "3",
      "Olası",
      "",
      "",
      "",
      "3",
      "Ara sıra / haftada birkaç defa",
      "",
      "",
      "",
      "15",
      "Kalıcı hasar veya iş kaybı",
      "",
      "",
    ],
    [
      "1",
      "Mümkün fakat düşük",
      "",
      "",
      "",
      "2",
      "Sık değil / ayda birkaç defa",
      "",
      "",
      "",
      "7",
      "Önemli yaralanma / dış ilk yardım",
      "",
      "",
    ],
    [
      "0.5",
      "Beklenmez fakat mümkün",
      "",
      "",
      "",
      "1",
      "Seyrek / yılda birkaç defa",
      "",
      "",
      "",
      "3",
      "Küçük yaralanma / iç ilk yardım",
      "",
      "",
    ],
    [
      "0.2",
      "Beklenmez",
      "",
      "",
      "",
      "0.5",
      "Çok seyrek / yılda bir veya daha az",
      "",
      "",
      "",
      "1",
      "Ucuz atlatma / çevresel zarar yok",
      "",
      "",
    ],
    [],
    [
      "RİSK DEĞERİ (R = O x F x Ş)",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
    ],
    [
      "Risk değeri",
      "Risk adı",
      "",
      "Eylem",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "Termin",
      "",
      "",
    ],
    [
      "1801 ≤ R",
      "Tolerans gösterilemez",
      "",
      "İş derhal durdurulur; tesis/çevre kapatılması düşünülebilir.",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "Hemen / 1 hafta",
      "",
      "",
    ],
    [
      "401 ≤ R < 1801",
      "En kısa sürede giderilecek",
      "",
      "Risk kabul edilebilir seviyeye düşene kadar faaliyet kısıtlanır.",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "1 aydan kısa",
      "",
      "",
    ],
    [
      "201 ≤ R < 401",
      "Esaslı risk",
      "",
      "Acil önlem alınır ve faaliyet izlenir.",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "1-3 ay",
      "",
      "",
    ],
    [
      "71 ≤ R < 201",
      "Önemli risk",
      "",
      "Düzeltici faaliyet planı başlatılır.",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "6 ay",
      "",
      "",
    ],
    [
      "21 ≤ R < 71",
      "Olası risk",
      "",
      "Kontroller sürdürülür ve izlenir.",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "1 yıl",
      "",
      "",
    ],
    [
      "R < 21",
      "Önemsiz risk",
      "",
      "İlave kontrole gerek olmayabilir.",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "Kontrol",
      "",
      "",
    ],
    [],
    [
      `Analiz: ${safeText(analysis.title)}`,
      "",
      "",
      "",
      "",
      `Hazırlayan: ${preparedBy}`,
      "",
      "",
      "",
      "",
      `Doküman No: ${documentNo}`,
      "",
      "",
      "",
    ],
    [
      `Firma: ${companyLine}`,
      "",
      "",
      "",
      "",
      `Ünvan / Belge: ${preparedTitle} / ${certificateNumber}`,
      "",
      "",
      "",
      "",
      `Tarih: ${formatDate(analysis.created_at)}`,
      "",
      "",
      "",
    ],
    [
      `Analiz kapsamı: ${analysisSectorLabelFromRow(analysis)}`,
      "",
      "",
      "",
      "",
      `Analiz odağı: ${canvasLabel(analysis.canvas)}`,
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
    ],
  ]);
  setCols(sheet, [12, 18, 18, 18, 4, 12, 18, 18, 18, 4, 12, 18, 18, 18]);
  setRows(sheet, [
    28,
    8,
    24,
    28,
    26,
    26,
    26,
    26,
    26,
    26,
    10,
    26,
    28,
    26,
    26,
    26,
    26,
    26,
    26,
    10,
    26,
    26,
  ]);
  addMerges(sheet, [
    "A1:N1",
    "A3:D3",
    "F3:I3",
    "K3:N3",
    "B4:D4",
    "G4:I4",
    "L4:N4",
    "B5:D5",
    "G5:I5",
    "L5:N5",
    "B6:D6",
    "G6:I6",
    "L6:N6",
    "B7:D7",
    "G7:I7",
    "L7:N7",
    "B8:D8",
    "G8:I8",
    "L8:N8",
    "B9:D9",
    "G9:I9",
    "L9:N9",
    "B10:D10",
    "G10:I10",
    "L10:N10",
    "A12:N12",
    "B13:C13",
    "D13:K13",
    "L13:N13",
    "B14:C14",
    "D14:K14",
    "L14:N14",
    "B15:C15",
    "D15:K15",
    "L15:N15",
    "B16:C16",
    "D16:K16",
    "L16:N16",
    "B17:C17",
    "D17:K17",
    "L17:N17",
    "B18:C18",
    "D18:K18",
    "L18:N18",
    "B19:C19",
    "D19:K19",
    "L19:N19",
    "A21:E21",
    "F21:J21",
    "K21:N21",
    "A22:E22",
    "F22:J22",
    "K22:N22",
  ]);
  setStyle(sheet, "A1:N1", styles.referenceTitle);
  applyReferenceTableStyle(sheet, "A3:D3", "A4:D4", "A5:D10");
  applyReferenceTableStyle(sheet, "F3:I3", "F4:I4", "F5:I10");
  applyReferenceTableStyle(sheet, "K3:N3", "K4:N4", "K5:N10");
  applyReferenceTableStyle(sheet, "A12:N12", "A13:N13", "A14:N19");
  setStyle(sheet, "A21:N22", {
    ...styles.tableCell,
    fill: { fgColor: { rgb: palette.fog } },
    font: { name: "Aptos", sz: 9, color: { rgb: palette.charcoal } },
  });
  const riskColors = [
    palette.critical,
    palette.critical,
    palette.high,
    palette.medium,
    palette.low,
    palette.green,
  ];
  for (let index = 0; index < riskColors.length; index++) {
    const row = 14 + index;
    setStyle(sheet, `A${row}:A${row}`, {
      ...styles.tableNumber,
      fill: { fgColor: { rgb: riskColors[index] } },
      font: { name: "Aptos", sz: 8, bold: true, color: { rgb: palette.white } },
    });
  }
}

function appendMatrixReferenceSheet(
  workbook: XLSX.WorkBook,
  analysis: AnalysisRow,
  profile: ProfileRow | null,
  documentNo: string,
) {
  const preparedBy = profile?.display_name ?? profile?.full_name ?? "Kullanıcı";
  const companyName = profile?.company_name ?? "Firma belirtilmedi";
  const companyInfo = safeText(profile?.company_info, safeText(profile?.phone));
  const preparedTitle = safeText(profile?.title, "Belirtilmedi");
  const certificateNumber = safeText(
    profile?.certificate_number,
    "Belirtilmedi",
  );
  const companyLine = companyInfo.length > 0
    ? `${companyName} · ${companyInfo}`
    : companyName;
  const matrixRows: unknown[][] = [];
  for (let probability = 0; probability <= 5; probability++) {
    const row: unknown[] = [];
    for (let severity = 0; severity <= 5; severity++) {
      if (probability === 0 && severity === 0) row.push("O / Ş");
      else if (probability === 0) row.push(severity);
      else if (severity === 0) row.push(probability);
      else row.push(probability * severity);
    }
    matrixRows.push(row);
  }

  const sheet = appendSheet(workbook, "Metot Referansı", [
    [
      "5x5 L-TİPİ RİSK MATRİSİ REFERANS TABLOSU",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
    ],
    [],
    ["OLASILIK (O)", "", "", "", "", "", "", "ŞİDDET (Ş)", "", "", "", "", ""],
    ["Derece", "Tanım", "", "", "", "", "", "Derece", "Tanım", "", "", "", ""],
    [
      "1",
      "Gerçekleşme ihtimali çok az",
      "",
      "",
      "",
      "",
      "",
      "1",
      "Hafif yaralanmalar / iş günü kaybı yok",
      "",
      "",
      "",
      "",
    ],
    [
      "2",
      "Gerçekleşme ihtimali az",
      "",
      "",
      "",
      "",
      "",
      "2",
      "İlk yardım gerektiren küçük yaralanma",
      "",
      "",
      "",
      "",
    ],
    [
      "3",
      "Gerçekleşme ihtimali var",
      "",
      "",
      "",
      "",
      "",
      "3",
      "İş günü kaybı veya tedavi gerektiren yaralanma",
      "",
      "",
      "",
      "",
    ],
    [
      "4",
      "Gerçekleşme ihtimali yüksek",
      "",
      "",
      "",
      "",
      "",
      "4",
      "Uzun süreli kayıp / ağır yaralanma",
      "",
      "",
      "",
      "",
    ],
    [
      "5",
      "Gerçekleşme ihtimali çok yüksek",
      "",
      "",
      "",
      "",
      "",
      "5",
      "Kalıcı iş göremezlik veya ölüm",
      "",
      "",
      "",
      "",
    ],
    [],
    [
      "5x5 Risk Matrisi - R = O x Ş",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
    ],
    ...matrixRows.map((row) => ["", "", ...row, "", "", "", "", ""]),
    [],
    [
      "Risk aralığı",
      "Risk adı",
      "",
      "Eylem",
      "",
      "",
      "",
      "Termin",
      "",
      "",
      "",
      "",
      "",
    ],
    [
      "20 ≤ R",
      "Tolerans dışı",
      "",
      "Çalışma derhal durdurulmalı.",
      "",
      "",
      "",
      "Hemen",
      "",
      "",
      "",
      "",
      "",
    ],
    [
      "10 ≤ R < 20",
      "Yüksek risk",
      "",
      "En kısa sürede önlem alınmalı.",
      "",
      "",
      "",
      "30 gün",
      "",
      "",
      "",
      "",
      "",
    ],
    [
      "5 ≤ R < 10",
      "Orta risk",
      "",
      "Plan dahilinde önlem alınmalı.",
      "",
      "",
      "",
      "90 gün",
      "",
      "",
      "",
      "",
      "",
    ],
    [
      "3 ≤ R < 5",
      "Düşük risk",
      "",
      "Gözetim altında izlenmeli.",
      "",
      "",
      "",
      "Kontrol",
      "",
      "",
      "",
      "",
      "",
    ],
    [
      "R < 3",
      "Önemsiz",
      "",
      "İzleme yeterli olabilir.",
      "",
      "",
      "",
      "Kontrol",
      "",
      "",
      "",
      "",
      "",
    ],
    [],
    [
      `Analiz: ${safeText(analysis.title)}`,
      "",
      "",
      "",
      "",
      `Hazırlayan: ${preparedBy}`,
      "",
      "",
      "",
      `Doküman No: ${documentNo}`,
      "",
      "",
      "",
    ],
    [
      `Firma: ${companyLine}`,
      "",
      "",
      "",
      "",
      `Ünvan / Belge: ${preparedTitle} / ${certificateNumber}`,
      "",
      "",
      "",
      `Tarih: ${formatDate(analysis.created_at)}`,
      "",
      "",
      "",
    ],
  ]);
  setCols(sheet, [12, 18, 12, 12, 12, 12, 12, 12, 18, 18, 18, 18, 18]);
  setRows(sheet, [
    28,
    8,
    24,
    28,
    26,
    26,
    26,
    26,
    26,
    10,
    26,
    26,
    26,
    26,
    26,
    26,
    26,
    10,
    28,
    26,
    26,
    26,
    26,
    26,
    10,
    26,
    26,
  ]);
  addMerges(sheet, [
    "A1:M1",
    "A3:F3",
    "H3:M3",
    "B4:F4",
    "I4:M4",
    "B5:F5",
    "I5:M5",
    "B6:F6",
    "I6:M6",
    "B7:F7",
    "I7:M7",
    "B8:F8",
    "I8:M8",
    "B9:F9",
    "I9:M9",
    "A11:M11",
    "B19:C19",
    "D19:G19",
    "H19:M19",
    "B20:C20",
    "D20:G20",
    "H20:M20",
    "B21:C21",
    "D21:G21",
    "H21:M21",
    "B22:C22",
    "D22:G22",
    "H22:M22",
    "B23:C23",
    "D23:G23",
    "H23:M23",
    "A26:E26",
    "F26:I26",
    "J26:M26",
    "A27:E27",
    "F27:I27",
    "J27:M27",
  ]);
  setStyle(sheet, "A1:M1", styles.referenceTitle);
  applyReferenceTableStyle(sheet, "A3:F3", "A4:F4", "A5:F9");
  applyReferenceTableStyle(sheet, "H3:M3", "H4:M4", "H5:M9");
  setStyle(sheet, "A11:M11", styles.referenceHeader);
  setStyle(sheet, "C12:H17", {
    ...styles.tableNumber,
    font: { name: "Aptos", sz: 10, bold: true, color: { rgb: palette.ink } },
  });
  for (let row = 12; row <= 17; row++) {
    for (let col = 2; col <= 7; col++) {
      const address = XLSX.utils.encode_cell({ r: row - 1, c: col });
      const value = Number(sheet[address]?.v ?? 0);
      if (row === 12 || col === 2) {
        setStyle(sheet, `${address}:${address}`, {
          ...styles.tableNumber,
          fill: { fgColor: { rgb: palette.fog } },
          font: {
            name: "Aptos",
            sz: 10,
            bold: true,
            color: { rgb: palette.ink },
          },
        });
      } else {
        const color = bandStyle(matrixBand(value));
        setStyle(sheet, `${address}:${address}`, {
          ...styles.tableNumber,
          fill: { fgColor: { rgb: color.fg } },
          font: {
            name: "Aptos",
            sz: 10,
            bold: true,
            color: { rgb: palette.white },
          },
        });
      }
    }
  }
  applyReferenceTableStyle(sheet, "A19:M19", "A19:M19", "A20:M24");
  setStyle(sheet, "A26:M27", {
    ...styles.tableCell,
    fill: { fgColor: { rgb: palette.fog } },
    font: { name: "Aptos", sz: 9, color: { rgb: palette.charcoal } },
  });
  const riskColors = [
    palette.critical,
    palette.high,
    palette.medium,
    palette.low,
    palette.green,
  ];
  for (let index = 0; index < riskColors.length; index++) {
    const row = 20 + index;
    setStyle(sheet, `A${row}:A${row}`, {
      ...styles.tableNumber,
      fill: { fgColor: { rgb: riskColors[index] } },
      font: { name: "Aptos", sz: 8, bold: true, color: { rgb: palette.white } },
    });
  }
}

function makeWorkbook(
  analysis: AnalysisRow,
  findings: FindingRow[],
  profile: ProfileRow | null,
  method: string,
  requestID: string,
  supportID: string,
  documentNo: string,
): XLSX.WorkBook {
  const workbook = XLSX.utils.book_new();
  applyWorkbookDefaults(workbook);
  const preparedBy = profile?.display_name ?? profile?.full_name ?? "";
  const companyName = profile?.company_name ?? "";
  const preparedTitle = safeText(profile?.title);
  const certificateNumber = safeText(profile?.certificate_number);
  const companyInfo = safeText(profile?.company_info, safeText(profile?.phone));
  const highestBand = method === "matrix_5x5"
    ? analysis.highest_band_m5
    : analysis.highest_band_fk;
  const counts = riskCounts(findings, method);
  const totalFindings = findings.length;
  const createdDate = formatDate(analysis.created_at);
  const completedDate = formatDate(analysis.completed_at);
  const generatedDate = formatDate(new Date().toISOString());
  const summaryAIText = safeText(analysis.ai_summary, "Özet bulunamadı.");
  const summaryColumnWidths = [18, 24, 4, 18, 24, 4, 18, 26];
  const riskOrder: RiskBand[] = [
    "critical",
    "high",
    "medium",
    "low",
    "unknown",
  ];

  const summary = appendSheet(workbook, "Kapak ve Özet", [
    ["RiskDetected", "", "", "", "", "", "", ""],
    ["İSG Risk Analizi Excel Raporu", "", "", "", "", "", "", ""],
    [],
    [
      "Firma",
      companyName || "Belirtilmedi",
      "",
      "Hazırlayan",
      preparedBy || "Belirtilmedi",
      "",
      "Oluşturma",
      generatedDate,
    ],
    [
      "Firma bilgisi",
      companyInfo || "Belirtilmedi",
      "",
      "Ünvan",
      preparedTitle || "Belirtilmedi",
      "",
      "Doküman No",
      documentNo,
    ],
    [
      "Analiz",
      safeText(analysis.title),
      "",
      "Belge No",
      certificateNumber || "Belirtilmedi",
      "",
      "Metot",
      methodLabel(method),
    ],
    [
      "Analiz kapsamı",
      analysisSectorLabelFromRow(analysis),
      "",
      "Analiz odağı",
      canvasLabel(analysis.canvas),
      "",
      "",
      "",
    ],
    [
      "Başlangıç",
      createdDate,
      "",
      "Tamamlanma",
      completedDate,
      "",
      "Destek Kodu",
      supportID,
    ],
    [],
    [
      "TOPLAM BULGU",
      "",
      "EN YÜKSEK RİSK",
      "",
      "METOT",
      "",
      "TOPLAM SKOR",
      "",
    ],
    [
      totalFindings,
      "",
      bandLabel(highestBand),
      "",
      methodLabel(method),
      "",
      methodTotalScore(analysis, method),
      "",
    ],
    [
      "KRİTİK",
      "",
      "YÜKSEK",
      "",
      "ORTA",
      "",
      "DÜŞÜK",
      "",
    ],
    [
      counts.critical,
      "",
      counts.high,
      "",
      counts.medium,
      "",
      counts.low,
      "",
    ],
    [],
    ["Risk Dağılımı", "Adet", "Oran", "Görsel", "", "", "", ""],
    ...riskOrder.map((band) => {
      const count = counts[band];
      const ratio = totalFindings > 0
        ? `${Math.round((count / totalFindings) * 100)}%`
        : "0%";
      return [
        bandLabel(band),
        count,
        ratio,
        riskBar(count, totalFindings),
        "",
        "",
        "",
        "",
      ];
    }),
    [],
    ["AI Özeti", "", "", "", "", "", "", ""],
    [
      summaryAIText,
      "",
      "",
      "",
      "",
      "",
      "",
      "",
    ],
  ]);
  setCols(summary, summaryColumnWidths);
  setRows(summary, [
    32,
    24,
    8,
    24,
    24,
    24,
    24,
    24,
    12,
    34,
    26,
    32,
    26,
    10,
    26,
    24,
    24,
    24,
    24,
    24,
    10,
    28,
    estimatedRowHeight(
      [{ value: summaryAIText, width: totalColumnWidth(summaryColumnWidths) }],
      { min: 64, max: 180, base: 8, lineHeight: 15 },
    ),
  ]);
  addMerges(summary, [
    "A1:H1",
    "A2:H2",
    "A10:B10",
    "C10:D10",
    "E10:F10",
    "G10:H10",
    "A11:B11",
    "C11:D11",
    "E11:F11",
    "G11:H11",
    "A12:B12",
    "C12:D12",
    "E12:F12",
    "G12:H12",
    "A13:B13",
    "C13:D13",
    "E13:F13",
    "G13:H13",
    "D15:H15",
    "D16:H16",
    "D17:H17",
    "D18:H18",
    "D19:H19",
    "D20:H20",
    "A22:H22",
    "A23:H23",
  ]);
  setStyle(summary, "A1:H1", styles.title);
  setStyle(summary, "A2:H2", styles.subtitle);
  setStyle(summary, "A4:H8", styles.tableCell);
  setStyle(summary, "A4:A8", styles.label);
  setStyle(summary, "D4:D8", styles.label);
  setStyle(summary, "G4:G8", styles.label);
  setStyle(summary, "A10:H10", styles.kpiLabel);
  setStyle(summary, "A11:H11", styles.kpiValue);
  setStyle(summary, "A12:H12", styles.kpiLabel);
  setStyle(summary, "A13:H13", styles.kpiValue);
  setStyle(summary, "A15:H15", styles.tableHeader);
  setStyle(summary, "A16:H20", styles.tableCell);
  setStyle(summary, "A22:H22", styles.tableHeader);
  setStyle(summary, "A23:H23", {
    ...styles.value,
    alignment: { horizontal: "left", vertical: "top", wrapText: true },
  });
  for (let i = 0; i < riskOrder.length; i++) {
    const row = 16 + i;
    const color = bandStyle(riskOrder[i]);
    setStyle(summary, `A${row}:A${row}`, {
      ...styles.tableCell,
      font: { name: "Aptos", sz: 10, bold: true, color: { rgb: color.fg } },
      fill: { fgColor: { rgb: color.bg } },
    });
    setStyle(summary, `D${row}:H${row}`, {
      ...styles.tableCell,
      font: { name: "Aptos", sz: 10, bold: true, color: { rgb: color.fg } },
    });
  }

  const metricHeaders = method === "matrix_5x5"
    ? ["Olasılık", "Şiddet", "Skor", "Risk Seviyesi"]
    : ["Olasılık (O)", "Frekans (F)", "Şiddet (Ş)", "Skor", "Risk Seviyesi"];
  const metricValues = (finding: FindingRow) =>
    method === "matrix_5x5"
      ? [
        safeNumber(finding.m5_probability),
        safeNumber(finding.m5_severity),
        safeNumber(finding.m5_score),
        bandLabel(finding.m5_band),
      ]
      : [
        safeNumber(finding.fk_probability),
        safeNumber(finding.fk_frequency),
        safeNumber(finding.fk_severity),
        safeNumber(finding.fk_score),
        bandLabel(finding.fk_band),
      ];
  const riskHeaders = [
    "No",
    "Tehlike",
    "Kategori",
    "Açıklama",
    ...metricHeaders,
    "Önlem / Kontrol Tedbirleri",
    "Kök Neden",
    "Referans / İzleme",
    "Termin",
    "Durum",
    "Not",
  ];
  const riskRows = [
    riskHeaders,
    ...findings.map((finding, index) => [
      finding.ordinal ?? index + 1,
      displayFindingTitle(finding.title),
      safeText(finding.category),
      safeText(finding.description),
      ...metricValues(finding),
      controlMeasuresText(finding),
      safeText(finding.root_cause_text),
      safeText(finding.references_text),
      suggestedTerm(methodBand(finding, method)),
      "Açık",
      "",
    ]),
  ];
  const riskSheet = appendSheet(workbook, "Risk Analiz Tablosu", riskRows);
  const riskColumnWidths = method === "matrix_5x5"
    ? [6, 28, 18, 62, 11, 11, 12, 16, 72, 40, 42, 16, 14, 32]
    : [6, 28, 18, 62, 11, 11, 11, 12, 16, 72, 40, 42, 16, 14, 32];
  const riskLastCol = XLSX.utils.encode_col(riskHeaders.length - 1);
  const riskLevelCol = XLSX.utils.encode_col(4 + metricHeaders.length - 1);
  const metricFirstCol = "E";
  const metricLastCol = XLSX.utils.encode_col(4 + metricHeaders.length - 2);
  const statusCol = XLSX.utils.encode_col(riskHeaders.length - 2);
  const measureColumnIndex = 4 + metricHeaders.length;
  const rootCauseColumnIndex = measureColumnIndex + 1;
  const referenceColumnIndex = measureColumnIndex + 2;
  setCols(riskSheet, riskColumnWidths);
  setRows(riskSheet, [
    42,
    ...riskRows.slice(1).map((row) =>
      estimatedRowHeight(
        [
          { value: row[1], width: riskColumnWidths[1] },
          { value: row[2], width: riskColumnWidths[2] },
          { value: row[3], width: riskColumnWidths[3] },
          {
            value: row[measureColumnIndex],
            width: riskColumnWidths[measureColumnIndex],
          },
          {
            value: row[rootCauseColumnIndex],
            width: riskColumnWidths[rootCauseColumnIndex],
          },
          {
            value: row[referenceColumnIndex],
            width: riskColumnWidths[referenceColumnIndex],
          },
        ],
        { min: 72, max: 260, base: 10, lineHeight: 14 },
      )
    ),
  ]);
  riskSheet["!autofilter"] = {
    ref: `A1:${riskLastCol}${Math.max(1, riskRows.length)}`,
  };
  riskSheet["!freeze"] = { xSplit: 0, ySplit: 1 };
  setStyle(riskSheet, `A1:${riskLastCol}1`, styles.tableHeader);
  for (let i = 0; i < findings.length; i++) {
    const row = i + 2;
    const color = bandStyle(methodBand(findings[i], method));
    const rowFill = i % 2 === 0 ? palette.white : palette.fog;
    setStyle(riskSheet, `A${row}:${riskLastCol}${row}`, {
      ...styles.tableCell,
      fill: { fgColor: { rgb: rowFill } },
    });
    setStyle(riskSheet, `A${row}:A${row}`, styles.tableNumber);
    setStyle(
      riskSheet,
      `${metricFirstCol}${row}:${metricLastCol}${row}`,
      styles.tableNumber,
    );
    setStyle(riskSheet, `${riskLevelCol}${row}:${riskLevelCol}${row}`, {
      ...styles.tableNumber,
      font: { name: "Aptos", sz: 10, bold: true, color: { rgb: color.fg } },
      fill: { fgColor: { rgb: color.bg } },
    });
    setStyle(riskSheet, `${statusCol}${row}:${statusCol}${row}`, {
      ...styles.tableNumber,
      font: { name: "Aptos", sz: 10, bold: true, color: { rgb: palette.high } },
      fill: { fgColor: { rgb: palette.highSoft } },
    });
  }

  const criticalHighFindings = findings
    .filter((finding) =>
      ["critical", "high"].includes(methodBand(finding, method))
    );
  const distribution = appendSheet(workbook, "Risk Dağılımı", [
    ["Risk Dağılımı", "", "", "", "", ""],
    ["Seviye", "Adet", "Oran", "Bar", "Metot", "Not"],
    ...riskOrder.map((band) => {
      const count = counts[band];
      return [
        bandLabel(band),
        count,
        totalFindings > 0
          ? `${Math.round((count / totalFindings) * 100)}%`
          : "0%",
        riskBar(count, totalFindings),
        methodLabel(method),
        "Seçilen metoda göre hesaplandı",
      ];
    }),
    [],
    ["Kritik/Yüksek Bulgular", "", "", "", "", ""],
    ...criticalHighFindings.map((finding) => [
      finding.ordinal ?? "",
      displayFindingTitle(finding.title),
      bandLabel(methodBand(finding, method)),
      methodScore(finding, method),
      actionWithRootCause(finding),
      "",
    ]),
  ]);
  const distributionColumnWidths = [20, 10, 10, 34, 58, 18];
  setCols(distribution, distributionColumnWidths);
  setRows(distribution, [
    32,
    28,
    24,
    24,
    24,
    24,
    24,
    8,
    28,
    ...criticalHighFindings.map((finding) =>
      estimatedRowHeight(
        [
          { value: displayFindingTitle(finding.title), width: 34 },
          { value: actionWithRootCause(finding), width: 58 },
        ],
        { min: 54, max: 190, base: 8, lineHeight: 14 },
      )
    ),
  ]);
  addMerges(distribution, ["A1:F1", "A8:F8"]);
  setStyle(distribution, "A1:F1", styles.title);
  setStyle(distribution, "A2:F2", styles.tableHeader);
  setStyle(distribution, "A3:F7", styles.tableCell);
  setStyle(distribution, "A8:F8", styles.tableHeader);
  setStyle(
    distribution,
    `A9:F${Math.max(9, findings.length + 8)}`,
    styles.tableCell,
  );
  for (let i = 0; i < riskOrder.length; i++) {
    const row = i + 3;
    const color = bandStyle(riskOrder[i]);
    setStyle(distribution, `A${row}:D${row}`, {
      ...styles.tableCell,
      font: { name: "Aptos", sz: 10, bold: true, color: { rgb: color.fg } },
      fill: { fgColor: { rgb: color.bg } },
    });
  }

  appendMethodReferenceSheet(workbook, analysis, profile, method, documentNo);

  const infoRows = [
    ["Alan", "Değer"],
    ["Analiz ID", analysis.id],
    ["Kullanıcı ID", analysis.user_id],
    ["Doküman No", documentNo],
    ["Firma", companyName],
    ["Hazırlayan", preparedBy],
    ["Ünvan", safeText(profile?.title)],
    ["Belge No", safeText(profile?.certificate_number)],
    ["Telefon", safeText(profile?.phone)],
    ["Oluşturma tarihi", formatDate(new Date().toISOString())],
    ["Request ID", requestID],
    ["Destek kodu", supportID],
  ];
  const info = appendSheet(workbook, "Rapor Bilgileri", infoRows);
  const infoColumnWidths = [24, 78];
  setCols(info, infoColumnWidths);
  setRows(info, [
    28,
    ...infoRows.slice(1).map((row) =>
      estimatedRowHeight(
        [{ value: row[1], width: infoColumnWidths[1] }],
        { min: 24, max: 72, base: 8, lineHeight: 14 },
      )
    ),
  ]);
  setStyle(info, "A1:B1", styles.tableHeader);
  setStyle(info, "A2:B12", styles.tableCell);
  setStyle(info, "A2:A12", styles.label);

  return workbook;
}

export async function handleGenerateExcelReportRequest(req: Request) {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json(405, {
      error: "method_not_allowed",
      message: "Yalnızca POST desteklenir.",
    });
  }

  const supabaseUrl = requiredEnv("SUPABASE_URL");
  const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
  const supabase = createClient(supabaseUrl, serviceRoleKey);

  let requestID = cleanTrace(
    req.headers.get("x-request-id"),
    crypto.randomUUID(),
  );
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

  const reportLocalization = resolveReportLocalization({
    localizationSnapshot: (analysis as AnalysisRow).localization_snapshot,
    requestedLanguage: body.report_language,
  });
  if (!reportLocalization.ok) {
    const status = reportLocalization.code === "REPORT_LANGUAGE_MISMATCH"
      ? 409
      : 422;
    return json(status, {
      error: reportLocalization.code,
      message: reportLocalization.code === "REPORT_LANGUAGE_MISMATCH"
        ? "Requested report language does not match the analysis snapshot."
        : "The analysis localization snapshot is unavailable or invalid.",
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

  const { data: photos, error: photosError } = await supabase
    .from("photos")
    .select("*")
    .eq("analysis_id", analysisID)
    .eq("user_id", user.id)
    .order("sequence_index", { ascending: true, nullsFirst: false })
    .order("storage_path", { ascending: true });

  if (photosError) {
    return json(500, {
      error: "photos_fetch_failed",
      message: "Analiz fotoğrafları Excel raporu için okunamadı.",
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

  const planTier = resolvePlanTier(
    (profile as ProfileRow | null)?.tier,
    subscription,
  );

  const requestedCompanyID = typeof body.company_id === "string"
    ? body.company_id.trim()
    : "";
  const resolvedCompanyID = requestedCompanyID ||
    safeText((analysis as AnalysisRow).company_id).trim();
  let company: CompanyRow | null = null;
  if (resolvedCompanyID.length > 0) {
    const { data: companyRow, error: companyError } = await supabase
      .from("companies")
      .select(
        "id,user_id,name,hazard_class,logo_path,address,contact_person,department,default_responsible,default_due_days,is_archived",
      )
      .eq("id", resolvedCompanyID)
      .eq("user_id", user.id)
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

  const companyProfile = profileWithCompany(
    profile as ProfileRow | null,
    company,
  );
  const overrideText = (value: unknown, maxLength: number): string | null => {
    if (typeof value !== "string") return null;
    const normalized = value.trim().slice(0, maxLength);
    return normalized.length > 0 ? normalized : null;
  };
  const effectiveProfile: ProfileRow = {
    ...(companyProfile ?? {}),
    company_name: overrideText(body.company_name_override, 180) ??
      companyProfile?.company_name ?? null,
    company_info: overrideText(body.company_info_override, 500) ??
      companyProfile?.company_info ?? null,
    phone: companyProfile?.phone ?? null,
    display_name: overrideText(body.prepared_by_override, 160) ??
      companyProfile?.display_name ?? null,
    full_name: overrideText(body.prepared_by_override, 160) ??
      companyProfile?.full_name ?? null,
    title: overrideText(body.prepared_title_override, 120) ??
      companyProfile?.title ?? null,
    certificate_number: overrideText(body.certificate_number_override, 120) ??
      companyProfile?.certificate_number ?? null,
  };

  let freeRiskAnalysisTrialAvailable = false;
  if (planTier === "free") {
    const { count: trialCount, error: trialCountError } = await supabase
      .from("usage_events")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id)
      .eq("feature", "report_risk_analysis_trial")
      .eq("event_type", "completed");

    if (trialCountError) {
      return json(500, {
        error: "risk_analysis_trial_check_failed",
        message: "Risk analizi hakkı kontrol edilemedi.",
        request_id: requestID,
        support_id: supportID,
      });
    }

    if ((trialCount ?? 0) >= 1) {
      return json(429, {
        error: "free_risk_analysis_trial_exhausted",
        message: "Bir kez tanımlanan risk analizi tablosu hakkını kullandın.",
        request_id: requestID,
        support_id: supportID,
      });
    }

    freeRiskAnalysisTrialAvailable = true;
  }

  const reportLimit = monthlyReportLimit(planTier);
  if (reportLimit !== null && !freeRiskAnalysisTrialAvailable) {
    const { count: reportCount, error: reportCountError } = await supabase
      .from("usage_events")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id)
      .eq("feature", "report_standard")
      .eq("event_type", "completed")
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

  const archiveSuffix = archiveFileSuffix(requestID);
  const methodCode = method === "matrix_5x5" ? "5X5" : "FK";
  const documentNo = `XLSX-${methodCode}-${
    analysisID.slice(0, 8).toUpperCase()
  }-${archiveSuffix.slice(-8).toUpperCase()}`;
  const workbook = reportLocalization.context.language === "en"
    ? makeEnglishWorkbook(
      analysis as AnalysisRow,
      (findings ?? []) as FindingRow[],
      effectiveProfile,
      method,
      requestID,
      supportID,
      documentNo,
      reportLocalization.context,
    )
    : makeWorkbook(
      analysis as AnalysisRow,
      (findings ?? []) as FindingRow[],
      effectiveProfile,
      method,
      requestID,
      supportID,
      documentNo,
    );
  const logo = inlineCompanyLogo(body.company_logo_base64) ??
    await loadCompanyLogo(supabase, effectiveProfile, user.id);
  const rawBytes = workbookBuffer(workbook);
  const bytes = logo ? await embedCompanyLogo(rawBytes, logo) : rawBytes;
  const fileStem = reportLocalization.context.language === "en"
    ? "risk-assessment"
    : "risk-analizi";
  const fileName = `${
    safeFilePart(safeText((analysis as AnalysisRow).title, fileStem))
  }-${method}-${fileStem}-${archiveSuffix}.xlsx`;
  const storagePath =
    `${user.id.toLowerCase()}/${analysisID.toLowerCase()}/${fileName}`;

  const { error: uploadError } = await supabase.storage
    .from("reports")
    .upload(storagePath, bytes, {
      contentType: XLSX_MIME,
      upsert: true,
    });

  if (uploadError) {
    console.error(
      "Excel upload failed",
      JSON.stringify({
        request_id: requestID,
        support_id: supportID,
        analysis_id: analysisID,
        error: safeLogError(uploadError),
      }),
    );
    return json(500, {
      error: "excel_upload_failed",
      message: "Excel dosyası rapor arşivine kaydedilemedi.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  const shouldStoreSnapshot = await reportSnapshotV2Enabled(supabase, body);
  const snapshotColumns = shouldStoreSnapshot
    ? {
      findings_snapshot_json: findings ?? [],
      photos_snapshot_json: photos ?? [],
      analysis_edit_version: Math.max(
        0,
        Math.round(
          Number(
            (analysis as Record<string, unknown>).analysis_edit_version ?? 0,
          ),
        ),
      ),
      generated_from_user_edited_findings:
        (analysis as Record<string, unknown>).has_user_edits === true,
      source_photo_count: Array.isArray(photos) ? photos.length : null,
      visible_findings_count: Array.isArray(findings) ? findings.length : null,
      report_page_count: 1,
    }
    : {};

  const { data: report, error: reportError } = await supabase
    .from("reports")
    .insert({
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
    .select()
    .single();

  if (reportError) {
    console.error(
      "Excel report metadata failed",
      JSON.stringify({
        request_id: requestID,
        support_id: supportID,
        analysis_id: analysisID,
        error: safeLogError(reportError),
      }),
    );
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
    return json(500, {
      error: "excel_metadata_failed",
      message: "Excel oluşturuldu ancak rapor arşiv kaydı tamamlanamadı.",
      request_id: requestID,
      support_id: supportID,
    });
  }

  if (company && !(analysis as AnalysisRow).company_id) {
    const { error: backfillError } = await supabase
      .from("analyses")
      .update({ company_id: company.id })
      .eq("id", analysisID)
      .eq("user_id", user.id)
      .is("company_id", null);
    if (backfillError) {
      console.warn(
        "Excel company backfill failed",
        JSON.stringify({
          request_id: requestID,
          support_id: supportID,
          analysis_id: analysisID,
          company_id: company.id,
          error: safeLogError(backfillError),
        }),
      );
    }
  }

  try {
    await sendReportReadyPush({
      supabase,
      supabaseUrl,
      serviceRoleKey,
      userID: user.id,
      reportID: report.id,
      analysisID,
      format: "xlsx",
      kind: "risk_analysis",
      requestID,
      supportID,
    });
  } catch (pushError) {
    console.warn(
      "Report ready push dispatch threw after Excel persistence",
      JSON.stringify({
        request_id: requestID,
        support_id: supportID,
        report_id: report.id,
        analysis_id: analysisID,
        error: safeLogError(pushError),
      }),
    );
  }

  return json(200, {
    report,
    request_id: requestID,
    support_id: supportID,
  });
}

if (import.meta.main) {
  serve(handleGenerateExcelReportRequest);
}
