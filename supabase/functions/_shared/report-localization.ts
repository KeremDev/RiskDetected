export const REPORT_LOCALES = [
  "tr-TR",
  "en-001",
  "en-GB",
  "en-US",
  "en-AU",
  "en-CA",
] as const;

export type ReportLocale = (typeof REPORT_LOCALES)[number];
export type ReportLanguage = "tr" | "en";

export type ReportLocalizationSnapshot = Record<string, unknown> & {
  output_language?: unknown;
  output_locale?: unknown;
  work_jurisdiction_country?: unknown;
  safety_profile_id?: unknown;
  safety_profile_version?: unknown;
  regulatory_reference_policy?: unknown;
};

export type ReportLocalizationContext = {
  language: ReportLanguage;
  locale: ReportLocale;
  safetyProfileID: string;
  safetyProfileVersion: number;
  regulatorySectionsEnabled: boolean;
  snapshot: Record<string, unknown>;
};

export type ReportLocalizationResolution =
  | { ok: true; context: ReportLocalizationContext }
  | {
    ok: false;
    code:
      | "REPORT_LOCALIZATION_SNAPSHOT_MISSING"
      | "REPORT_LOCALIZATION_SNAPSHOT_INVALID"
      | "REPORT_LANGUAGE_MISMATCH";
  };

const reportLocaleSet = new Set<string>(REPORT_LOCALES);

function objectValue(value: unknown): Record<string, unknown> | null {
  return value != null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function positiveInteger(value: unknown): number | null {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

export function resolveReportLocalization(params: {
  localizationSnapshot: unknown;
  requestedLanguage: unknown;
}): ReportLocalizationResolution {
  const snapshot = objectValue(params.localizationSnapshot);
  if (!snapshot) {
    return { ok: false, code: "REPORT_LOCALIZATION_SNAPSHOT_MISSING" };
  }

  const language = snapshot.output_language;
  const locale = snapshot.output_locale;
  const safetyProfileID = snapshot.safety_profile_id;
  const safetyProfileVersion = positiveInteger(snapshot.safety_profile_version);
  const jurisdiction = snapshot.work_jurisdiction_country;
  const regulatoryPolicy = snapshot.regulatory_reference_policy;

  if (
    (language !== "tr" && language !== "en") ||
    typeof locale !== "string" ||
    !reportLocaleSet.has(locale) ||
    typeof safetyProfileID !== "string" ||
    safetyProfileID.length === 0 ||
    safetyProfileVersion == null ||
    typeof jurisdiction !== "string" ||
    typeof regulatoryPolicy !== "string"
  ) {
    return { ok: false, code: "REPORT_LOCALIZATION_SNAPSHOT_INVALID" };
  }

  if (
    params.requestedLanguage != null &&
    params.requestedLanguage !== "" &&
    params.requestedLanguage !== language
  ) {
    return { ok: false, code: "REPORT_LANGUAGE_MISMATCH" };
  }

  const regulatorySectionsEnabled = language === "tr" &&
    jurisdiction === "TR" &&
    regulatoryPolicy === "tr_current";

  return {
    ok: true,
    context: {
      language,
      locale: locale as ReportLocale,
      safetyProfileID,
      safetyProfileVersion,
      regulatorySectionsEnabled,
      snapshot,
    },
  };
}

export function reportDate(value: unknown, locale: ReportLocale): string {
  const timestamp = typeof value === "string" ? Date.parse(value) : NaN;
  if (!Number.isFinite(timestamp)) {
    return locale === "tr-TR" ? "Tarih yok" : "Date unavailable";
  }
  return new Intl.DateTimeFormat(locale === "en-001" ? "en" : locale, {
    dateStyle: "long",
    timeStyle: "short",
    timeZone: "UTC",
  }).format(new Date(timestamp));
}

export function reportNumber(
  value: unknown,
  locale: ReportLocale,
  maximumFractionDigits = 1,
): string {
  const parsed = Number(value);
  return new Intl.NumberFormat(locale === "en-001" ? "en" : locale, {
    maximumFractionDigits,
  }).format(Number.isFinite(parsed) ? parsed : 0);
}

export function englishRiskBand(value: unknown): string {
  switch (String(value ?? "").trim().toLowerCase()) {
    case "critical":
      return "Critical";
    case "high":
      return "High";
    case "medium":
      return "Medium";
    case "low":
      return "Low";
    default:
      return "Not assessed";
  }
}

export function englishDueTerm(value: unknown): string {
  switch (String(value ?? "").trim().toLowerCase()) {
    case "critical":
      return "Immediate / 1–3 days";
    case "high":
      return "7 days";
    case "medium":
      return "15 days";
    case "low":
      return "30 days";
    default:
      return "To be assessed";
  }
}

export const NON_TR_REPORT_TEMPLATE_FORBIDDEN_MARKERS = [
  "mevzuat",
  "osgb",
  "6331",
  "tehlike sınıfı",
  "belge no",
  "uygunluk sertifik",
  "regulatory compliance confirmed",
  "legally compliant",
] as const;

export function nonTRReportTemplateLeak(value: unknown): string | null {
  const text = String(value ?? "").toLocaleLowerCase("en");
  return NON_TR_REPORT_TEMPLATE_FORBIDDEN_MARKERS.find((marker) =>
    text.includes(marker)
  ) ?? null;
}
