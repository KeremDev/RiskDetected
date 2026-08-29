// Last gate before a paragraph is stored.
//
// The renderer builds only from vetted catalogue strings, so in principle none
// of these rules can fire. That is exactly why they exist: they are here to
// catch the day someone adds a catalogue entry that reads well and claims too
// much. Every rule below encodes a claim the engine is not entitled to make
// from a photograph.
//
// The v2 notebook projector already carries sanitisers for photo addresses,
// internal score language and assignment text. Those run on model prose; these
// run on our own output, and they are assertions rather than repairs -- if our
// own catalogue trips one, the entry is blocked, not quietly cleaned.

export type LintFinding = { rule: string; detail: string };

/**
 * Claims a photograph cannot support.
 *
 * "Periyodik kontrol yapılmamıştır" is the shape to watch: the image shows a
 * machine, not the absence of a record. The engine may ask for the record; it
 * may never report that the record does not exist.
 */
const FORBIDDEN: Array<{ rule: string; pattern: RegExp }> = [
  {
    rule: "absent_record_claimed",
    pattern:
      /(?:periyodik kontrol|muayene|ölçüm|olcum|test|belge|sertifika|eğitim|egitim|kayıt|kayit)\s+(?:yapılmamış|yapilmamis|bulunmamakta|yoktur|mevcut değil|mevcut degil)/iu,
  },
  {
    rule: "measurement_invented",
    pattern:
      /\b\d+(?:[.,]\d+)?\s*(?:mm|cm|m|kg|bar|volt|v\b|amper|lux|db|ppm|°c)\b/iu,
  },
  {
    // A book entry is a general recommendation. Who does the work and by when
    // is the specialist's to write in the book itself, and a system-proposed
    // deadline reads as an instruction the employer was given. The v2 notebook
    // projector strips these from model prose; here they are forbidden outright,
    // because our own catalogue has no business producing them.
    rule: "deadline_or_assignment_leaked",
    pattern:
      /(?:\btermin\b|son tarih|tamamlanma süresi|sorumlu birim|sorumlu kişi|sorumlusuyla|\bsorumlu\s*[:=]|\d+\s*(?:gün|iş günü|hafta|ay)\s*(?:içinde|içerisinde))/iu,
  },
  {
    rule: "internal_score_leaked",
    pattern:
      /\b(?:fine[ -]?kinney|fk\s*(?:skor|puan)|5\s*[x×]\s*5|risk\s*(?:skoru|puanı|puani))\b/iu,
  },
  {
    rule: "photo_address_leaked",
    pattern: /\b(?:fotoğraf|fotograf|görsel|gorsel|resim|photo|image)\s*[-#]?\s*\d/iu,
  },
  {
    rule: "legal_verdict_claimed",
    pattern:
      /(?:mevzuata aykırı|mevzuata aykiri|kanuna aykırı|kanuna aykiri|suç teşkil|suc teskil|kusurlu|ihmali bulun)/iu,
  },
  {
    rule: "liability_disclaimed",
    pattern: /(?:sorumluluktan kurtar|sorumlu tutulamaz|ibra eder)/iu,
  },
  {
    rule: "worker_blamed",
    pattern:
      /(?:çalışanın dikkatsizliği|calisanin dikkatsizligi|işçi hatası|isci hatasi|çalışan ihmali|calisan ihmali)/iu,
  },
  {
    rule: "advisory_hedge",
    pattern: /(?:önerilir|onerilir|tavsiye edilir|olabilir mi|belki)/iu,
  },
  {
    rule: "report_label_leaked",
    pattern: /(?:^|\s)(?:tehlike|risk|önlem|onlem|bulgu)\s*:/iu,
  },
];

/**
 * Sentence count.
 *
 * The next sentence has to start with a capital, and that requirement is doing
 * real work rather than being decorative: Turkish ordinals carry a full stop, so
 * a location like "A Blok 3. kat döşeme kenarı" splits into two "sentences"
 * under a naive rule and a correct four-sentence critical entry gets blocked for
 * being five. "kat" is lowercase, so it no longer opens a sentence.
 */
function sentenceCount(text: string): number {
  return text.split(/(?<=[.!?])\s+(?=[A-ZÇĞİÖŞÜ])/u).filter((part) =>
    part.trim()
  ).length;
}

export function lintParagraph(text: string): LintFinding[] {
  const findings: LintFinding[] = [];
  const trimmed = text.trim();

  if (!trimmed) {
    return [{ rule: "empty", detail: "paragraf boş" }];
  }
  if (!/[.!?]$/u.test(trimmed)) {
    findings.push({ rule: "unterminated", detail: "paragraf noktalanmamış" });
  }

  const count = sentenceCount(trimmed);
  if (count < 2 || count > 4) {
    findings.push({
      rule: "sentence_count",
      detail: `${count} cümle; 2-4 bekleniyor`,
    });
  }

  for (const { rule, pattern } of FORBIDDEN) {
    const match = trimmed.match(pattern);
    if (match) findings.push({ rule, detail: match[0].trim().slice(0, 80) });
  }

  return findings;
}

/**
 * Does the paragraph both state a condition and require an action?
 *
 * A record that describes without requiring is not a book entry, and one that
 * requires without describing gives the employer nothing to act on.
 */
export function lintClaimActionConsistency(text: string): LintFinding[] {
  const findings: LintFinding[] = [];
  const hasObservation =
    /(?:gözlenmiştir|gozlenmistir|tespit edilmiştir|tespit edilmistir|incelenmiştir|incelenmistir|yapılamamıştır|yapilamamistir)/u
      .test(text);
  const hasRequirement =
    /(?:sağlanmalıdır|saglanmalidir|doğrulanmalıdır|dogrulanmalidir|alınmalıdır|alinmalidir|takılmalıdır|takilmalidir|kaldırılmalıdır|kaldirilmalidir|onarılmalıdır|onarilmalidir|yapılmalıdır|yapilmalidir|geçirilmelidir|gecirilmelidir|edilmelidir|kapatılmalıdır|kapatilmalidir|ayrılmalıdır|ayrilmalidir|durdurulmalı|izlenmelidir|bulundurulmalıdır|işlenmelidir|islenmelidir|dosyalanmalıdır|dosyalanmalidir|imzalanmalıdır|imzalanmalidir|tutulmalıdır|tutulmalidir|kullandırılmalı|kullandirilmali)/u
      .test(text);
  if (!hasObservation) {
    findings.push({
      rule: "no_observation_verb",
      detail: "gözlem fiili yok",
    });
  }
  if (!hasRequirement) {
    findings.push({
      rule: "no_requirement_verb",
      detail: "gereklilik fiili yok",
    });
  }
  return findings;
}

export function lint(text: string): LintFinding[] {
  return [...lintParagraph(text), ...lintClaimActionConsistency(text)];
}
