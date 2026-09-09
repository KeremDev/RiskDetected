export const APPROVED_NOTEBOOK_ADVISORY_GENERATOR_VERSION =
  "approved-notebook-advisory-tr-v1";

export type ApprovedNotebookItemClass =
  | "observed_finding"
  | "verification_request"
  | "assurance_requirement";

const ADVISORY_ENDING = /(?:önerilmektedir|tavsiye edilmektedir)\.$/u;
const FORBIDDEN_LABEL = /(?:^|\s)(?:tespit|öneri)\s*:/iu;
const FORBIDDEN_OBLIGATION =
  /(?:^|[^\p{L}])(?:gerekmektedir|[\p{L}]+(?:malı|meli)(?:dır|dir|dur|dür|tır|tir|tur|tür))(?=$|[^\p{L}])/iu;
const KNOWN_IMPERATIVE = new RegExp(
  String.raw`\b(?:` + [
    "alın",
    "ayırın",
    "bağlayın",
    "belirleyin",
    "çıkarın",
    "değiştirin",
    "durdurun",
    "düzenleyin",
    "engelleyin",
    "indirin",
    "işaretleyin",
    "kaldırın",
    "kapatın",
    "kesin",
    "kilitleyin",
    "kontrol edin",
    "kurun",
    "kullanın",
    "monte edin",
    "sağlayın",
    "sabitleyin",
    "tamamlayın",
    "temizleyin",
    "uygulayın",
    "uzaklaştırın",
    "yerleştirin",
    "zorunlu kılın",
    "doğrulayın",
  ].join("|") + String.raw`)\b`,
  "iu",
);

function clean(value: unknown): string {
  return typeof value === "string"
    ? value.replace(/[\t\r\n]+/g, " ").replace(/\s+/g, " ").trim()
    : "";
}

export function isStrictTurkishNotebookAdvisory(value: unknown): boolean {
  const text = clean(value);
  return text.length >= 20 && text.length <= 1000 &&
    ADVISORY_ENDING.test(text) &&
    !FORBIDDEN_LABEL.test(text) &&
    !FORBIDDEN_OBLIGATION.test(text) &&
    !KNOWN_IMPERATIVE.test(text);
}

export function notebookAdvisoryFallback(
  itemClass: ApprovedNotebookItemClass,
): string {
  if (itemClass === "verification_request") {
    return "İlgili hususun yetkili kişi tarafından sahada doğrulanması ve uygunsuzluk belirlenmesi hâlinde uygun tedbirlerin uygulanması önerilmektedir.";
  }
  if (itemClass === "assurance_requirement") {
    return "İlgili kayıt, ölçüm ve yetkili saha kontrollerinin doğrulanması önerilmektedir.";
  }
  return "İlgili uygunsuzluğun yetkin kişilerce değerlendirilerek uygun mühendislik ve organizasyonel tedbirlerle giderilmesi önerilmektedir.";
}

export function strictTurkishNotebookAdvisoryOrFallback(
  value: unknown,
  itemClass: ApprovedNotebookItemClass,
): { text: string; usedFallback: boolean } {
  const text = clean(value);
  return isStrictTurkishNotebookAdvisory(text)
    ? { text, usedFallback: false }
    : { text: notebookAdvisoryFallback(itemClass), usedFallback: true };
}
