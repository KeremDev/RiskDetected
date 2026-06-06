const TEXT_REPORT_FALLBACK =
  "Saha gözlemiyle doğrulanması gereken risk göstergesi.";

const FORBIDDEN_REPORT_LANGUAGE = [
  "metinde",
  "metninde",
  "metin girdisinde",
  "kullanıcı",
  "kullanici",
  "kullanıcının",
  "kullanicinin",
  "ifadesi",
  "ifadesini",
  "ifadesinde",
  "belirtmiştir",
  "belirtmistir",
  "belirtilmiştir",
  "belirtilmistir",
  "belirtmiş",
  "belirtmis",
  "yazmıştır",
  "yazmistir",
  "yazmış",
  "yazmis",
  "demiş",
  "demis",
  "söylemiştir",
  "soylemistir",
  "söylemiş",
  "soylemis",
  "geçmektedir",
  "gecmektedir",
  "geçiyor",
  "geciyor",
  "senin",
  "sizin",
  "yazdığın",
  "yazdigin",
  "girdiğin",
  "girdigin",
];

const QUOTE_MARKERS = [`"`, "'", "“", "”", "‘", "’", "«", "»"];

function normalizeForMatch(value: string): string {
  return value
    .toLocaleLowerCase("tr-TR")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[ıİ]/g, "i")
    .replace(/[ğĞ]/g, "g")
    .replace(/[üÜ]/g, "u")
    .replace(/[şŞ]/g, "s")
    .replace(/[öÖ]/g, "o")
    .replace(/[çÇ]/g, "c")
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function tokenize(value: string): string[] {
  const normalized = normalizeForMatch(value);
  return normalized ? normalized.split(" ") : [];
}

function userNgrams(userText: string): Set<string> {
  const tokens = tokenize(userText);
  const grams = new Set<string>();
  for (let size = 3; size <= Math.min(7, tokens.length); size += 1) {
    for (let i = 0; i <= tokens.length - size; i += 1) {
      const gram = tokens.slice(i, i + size).join(" ");
      if (gram.length >= 8) grams.add(gram);
    }
  }
  return grams;
}

function userNumericTokens(userText: string): Set<string> {
  return new Set(tokenize(userText).filter((token) => /^\d+$/.test(token)));
}

function splitReportSentences(value: string): string[] {
  return value
    .split(/(?<=[.!?。])\s+|\n+/g)
    .map((part) => part.trim())
    .filter(Boolean);
}

export function containsForbiddenTextReportLanguage(
  value: string | null | undefined,
  userText: string | null | undefined,
): boolean {
  const raw = (value ?? "").trim();
  if (!raw) return false;

  if (QUOTE_MARKERS.some((marker) => raw.includes(marker))) {
    return true;
  }

  const normalized = normalizeForMatch(raw);
  if (!normalized) return false;

  if (
    FORBIDDEN_REPORT_LANGUAGE.some((phrase) =>
      normalized.includes(normalizeForMatch(phrase))
    )
  ) {
    return true;
  }

  if (userText) {
    for (const gram of userNgrams(userText)) {
      if (normalized.includes(gram)) return true;
    }
    const valueTokens = new Set(tokenize(raw));
    for (const numericToken of userNumericTokens(userText)) {
      if (valueTokens.has(numericToken)) return true;
    }
  }

  return false;
}

export function sanitizeTextReportLanguage(
  value: string | null | undefined,
  userText: string | null | undefined,
  fallback = TEXT_REPORT_FALLBACK,
): string {
  const raw = (value ?? "").trim();
  if (!raw) return fallback;

  const kept = splitReportSentences(raw).filter((sentence) =>
    !containsForbiddenTextReportLanguage(sentence, userText)
  );
  const sanitized = kept.join(" ").trim();
  if (!sanitized || containsForbiddenTextReportLanguage(sanitized, userText)) {
    return fallback;
  }
  return sanitized;
}

export function sanitizeTextAnalysisHazardForReportLanguage<
  T extends {
    title?: unknown;
    observed_evidence?: unknown;
    description?: unknown;
    corrective_action?: unknown;
    preventive_control?: unknown;
    root_cause?: unknown;
    references?: unknown;
  },
>(hazard: T, userText: string | null | undefined): T {
  if (!userText) return hazard;
  return {
    ...hazard,
    title: sanitizeTextReportLanguage(
      typeof hazard.title === "string" ? hazard.title : "",
      userText,
      "Saha doğrulaması gereken risk göstergesi",
    ),
    observed_evidence: sanitizeTextReportLanguage(
      typeof hazard.observed_evidence === "string"
        ? hazard.observed_evidence
        : "",
      userText,
    ),
    description: sanitizeTextReportLanguage(
      typeof hazard.description === "string" ? hazard.description : "",
      userText,
    ),
    corrective_action: sanitizeTextReportLanguage(
      typeof hazard.corrective_action === "string"
        ? hazard.corrective_action
        : "",
      userText,
      "Sahadaki uygunsuzluğu güvenli hale getirecek teknik kontrol uygulanmalıdır.",
    ),
    preventive_control: sanitizeTextReportLanguage(
      typeof hazard.preventive_control === "string"
        ? hazard.preventive_control
        : "",
      userText,
      "Tekrarı önlemek için periyodik kontrol ve saha doğrulama kaydı tanımlanmalıdır.",
    ),
    root_cause: sanitizeTextReportLanguage(
      typeof hazard.root_cause === "string" ? hazard.root_cause : "",
      userText,
      "Kontrol süreçlerinde saha doğrulaması gerektiren eksiklik olabilir.",
    ),
    references: sanitizeTextReportLanguage(
      typeof hazard.references === "string" ? hazard.references : "",
      userText,
      "Mevzuat karşılığı saha koşullarına göre doğrulanmalıdır.",
    ),
  };
}
