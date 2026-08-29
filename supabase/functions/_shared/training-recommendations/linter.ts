// Forbidden wording for training recommendations.
//
// Every sentence the engine produces comes from a hand-written template, so in
// principle none of these can fire. They exist for the day someone adds a
// template that reads well and claims too much -- which in this domain is the
// easy mistake, because the natural way to write a training recommendation is
// to say why it is needed, and "why" slides into "this person has no
// certificate" without anyone intending it.
//
// Each rule below is a claim the engine has no standing to make.

export type TrainingLintFinding = { rule: string; detail: string };

const FORBIDDEN: Array<{ rule: string; pattern: RegExp }> = [
  {
    // A photograph shows a person; it does not show their training file.
    rule: "personal_deficiency_claimed",
    pattern:
      /(?:belgesi (?:yok|bulunma)|eğitimsiz|egitimsiz|yetkisiz|sertifikasız|sertifikasiz|belgesiz)/iu,
  },
  {
    // "MYK kursu" does not exist: it is an examination and certification route.
    rule: "myk_as_course",
    pattern: /myk\s*(?:kurs|eğitim|egitim)/iu,
  },
  {
    // Obligation language the engine cannot establish from an image.
    rule: "obligation_asserted",
    pattern:
      /(?:zorunludur|almalıdır|almalidir|gönderilmelidir|gonderilmelidir|kesinlikle)/iu,
  },
  {
    rule: "deadline_or_assignment",
    pattern:
      /(?:\btermin\b|son tarih|sorumlu (?:firma|birim|kişi|kisi)|\d+\s*(?:gün|iş günü|hafta|ay)\s*(?:içinde|icinde))/iu,
  },
  {
    rule: "score_leaked",
    pattern:
      /(?:risk (?:skoru|puanı|puani)|eğitim önceliği|egitim onceligi|fine[ -]?kinney|önem puanı)/iu,
  },
  {
    // Training is never the answer to a missing guard.
    rule: "training_replaces_control",
    pattern:
      /(?:eğitim|egitim)\s+(?:verilerek|ile)\s+(?:risk|tehlike)\s+(?:ortadan kaldır|giderilir)/iu,
  },
  {
    rule: "photo_as_proof",
    pattern: /fotoğraftan anlaşıl|fotograftan anlasil|görüldüğü için zorunlu/iu,
  },
  {
    // Content-free advice. "Provide OHS training" tells a reader nothing.
    rule: "contentless_recommendation",
    pattern: /(?:isg|iş sağlığı) eğitimi verilsin/iu,
  },
];

/** Two sentences at most, per the writing standard. */
function sentenceCount(value: string): number {
  return value.split(/(?<=[.!?])\s+(?=[A-ZÇĞİÖŞÜ])/u).filter((part) =>
    part.trim()
  ).length;
}

export function lintTrainingText(value: string): TrainingLintFinding[] {
  const findings: TrainingLintFinding[] = [];
  const trimmed = value.trim();

  if (!trimmed) return [{ rule: "empty", detail: "metin boş" }];
  if (!/[.!?]$/u.test(trimmed)) {
    findings.push({ rule: "unterminated", detail: "metin noktalanmamış" });
  }
  const count = sentenceCount(trimmed);
  if (count > 2) {
    findings.push({ rule: "too_many_sentences", detail: `${count} cümle` });
  }
  if (!/önerilir|onerilir/iu.test(trimmed)) {
    findings.push({
      rule: "not_a_recommendation",
      detail: "öneri fiili yok",
    });
  }
  for (const { rule, pattern } of FORBIDDEN) {
    const match = trimmed.match(pattern);
    if (match) findings.push({ rule, detail: match[0].trim().slice(0, 80) });
  }
  return findings;
}
