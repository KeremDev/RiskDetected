// Sentence plan, then paragraph. No model text on this path.
//
// A book paragraph is two to four sentences and carries, in order:
//
//   1. what was observed, and on what basis the specialist observed it
//   2. what it exposes people to        (omitted for planned, low-urgency work)
//   3. what must be done, strongest control first
//   4. what closing it looks like on paper
//
// The sentence count is decided by the entry class and the urgency, not by how
// much text happens to be available. A critical entry earns four sentences
// because it has to carry the exposure and the closure explicitly; a planned
// assurance item gets two, because padding a records question with a hazard
// sentence overstates it.
//
// Everything below reads from codes and the Turkish catalogue. If a code has no
// surface form the cluster is blocked rather than rendered with a generic
// sentence -- a vague book entry is worse than no book entry, because it looks
// like a record.

import type {
  ApprovedBookCluster,
  ApprovedBookRenderContext,
} from "./contracts.ts";
import {
  ACTION_BY_MECHANISM,
  BARRIER_MEMBER_ORDER,
  BARRIER_MEMBER_TR,
  OBSERVATION_BASIS_TR,
  OBSERVATION_BY_MECHANISM,
  URGENCY_TR,
  VERIFICATION_BY_TOPIC,
} from "./catalogs.tr.ts";

export type SentencePlan = {
  templateId: string;
  sentences: string[];
};

/** Location clause, or "" when the specialist has not supplied one. */
function locationClause(
  cluster: ApprovedBookCluster,
  context: ApprovedBookRenderContext,
): string {
  const raw = context.locationByCluster[cluster.clusterId] ?? "";
  const clean = raw.trim();
  // "Konum bilinmiyor" is a real state and the plan's answer is to leave the
  // clause out, not to invent "ilgili alanda". The specialist fills it in.
  return clean ? `${clean} bölümünde ` : "";
}

/**
 * Named barrier members, in the order they sit on the rail.
 *
 * "ana korkuluk ve topuk levhası" reads as a record; "top_rail, toeboard" does
 * not, and neither does a list in whatever order the set happened to hold.
 */
function barrierPhrase(components: string[]): string {
  const named = BARRIER_MEMBER_ORDER
    .filter((code) => components.includes(code))
    .map((code) => BARRIER_MEMBER_TR[code])
    .filter(Boolean);
  if (named.length === 0) return "";
  if (named.length === 1) return named[0];
  return `${named.slice(0, -1).join(", ")} ve ${named[named.length - 1]}`;
}

function observationSentence(
  cluster: ApprovedBookCluster,
  context: ApprovedBookRenderContext,
): string | null {
  const basis = context.observationBasis
    ? OBSERVATION_BASIS_TR[context.observationBasis]
    : null;
  if (!basis) return null;

  if (cluster.entryClass === "assurance_verification") {
    const surface = VERIFICATION_BY_TOPIC[cluster.assuranceTopicId ?? ""];
    if (!surface) return null;
    return `${basis} ${
      locationClause(cluster, context)
    }${surface.subject} incelenmiştir.`;
  }

  if (cluster.entryClass === "measurement_or_test_request") {
    const surface = VERIFICATION_BY_TOPIC[cluster.assuranceTopicId ?? ""] ??
      VERIFICATION_BY_TOPIC.asset_assurance_generic;
    return `${basis} ${
      locationClause(cluster, context)
    }${surface.subject} konusunda kesin bir tespit yapılamamıştır.`;
  }

  const surface = OBSERVATION_BY_MECHANISM[cluster.mechanismCode ?? ""];
  if (!surface) return null;
  const barrier = barrierPhrase(cluster.barrierComponentsAbsent);
  const condition = barrier
    ? `korkuluk sisteminde ${barrier} bulunmadığı`
    : surface.condition;
  return `${basis} ${locationClause(cluster, context)}${condition} gözlenmiştir.`;
}

function exposureSentence(cluster: ApprovedBookCluster): string | null {
  const surface = OBSERVATION_BY_MECHANISM[cluster.mechanismCode ?? ""];
  if (!surface) return null;
  // "Bir çalışan bulunmaktadır" is a fact the engine recorded; it is what turns
  // an exposed edge into an immediate one, so it is stated where it is true.
  const presence = cluster.peopleVisible > 0
    ? "Alanda çalışan bulunması nedeniyle "
    : "";
  return `${presence}bu durum ${surface.consequence} ile sonuçlanabilecek bir maruziyet oluşturmaktadır.`;
}

/** Urgency is empty for everything but the immediate class; tidy the gap. */
function collapse(sentence: string): string {
  return sentence.replace(/\s{2,}/g, " ").trim();
}

function actionSentence(cluster: ApprovedBookCluster): string | null {
  const urgency = URGENCY_TR[cluster.urgency] ?? "";
  if (cluster.entryClass === "assurance_verification") {
    const surface = VERIFICATION_BY_TOPIC[cluster.assuranceTopicId ?? ""];
    if (!surface) return null;
    return collapse(
      `Söz konusu kayıt ve ölçümler yetkili kişi tarafından ${urgency} doğrulanmalıdır.`,
    );
  }
  if (cluster.entryClass === "measurement_or_test_request") {
    return collapse(
      `Konu ${urgency} sahada yetkili kişi tarafından incelenmeli ve uygunsuzluk belirlenmesi hâlinde gerekli tedbir alınmalıdır.`,
    );
  }

  const surface = ACTION_BY_MECHANISM[cluster.mechanismCode ?? ""];
  if (!surface) return null;
  const parts = [`${surface.primary.charAt(0).toLocaleUpperCase("tr-TR")}${
    surface.primary.slice(1)
  }dır`];
  if (surface.supporting && cluster.entryClass === "critical_immediate") {
    parts.push(`${surface.supporting}dır`);
  }
  const prefix = cluster.entryClass === "critical_immediate"
    ? `Alana erişim ${urgency} durdurulmalı; `
    : "";
  const joined = parts.join("; ");
  return collapse(
    prefix
      ? `${prefix}${joined.charAt(0).toLocaleLowerCase("tr-TR")}${joined.slice(1)}.`
      : `${joined}.`,
  );
}

function closureSentence(cluster: ApprovedBookCluster): string | null {
  if (
    cluster.entryClass === "assurance_verification" ||
    cluster.entryClass === "measurement_or_test_request"
  ) {
    const surface = VERIFICATION_BY_TOPIC[cluster.assuranceTopicId ?? ""] ??
      VERIFICATION_BY_TOPIC.asset_assurance_generic;
    return `${surface.closure.charAt(0).toLocaleUpperCase("tr-TR")}${
      surface.closure.slice(1)
    }`;
  }
  const surface = ACTION_BY_MECHANISM[cluster.mechanismCode ?? ""];
  if (!surface) return null;
  return `${surface.closure.charAt(0).toLocaleUpperCase("tr-TR")}${
    surface.closure.slice(1)
  }`;
}

/**
 * Sentence count by entry class.
 *
 * Critical entries always carry exposure and closure; a two-sentence critical
 * record leaves the employer without the reason or the proof. Assurance entries
 * never carry an exposure sentence, because a records question is not a
 * statement that anyone is exposed.
 */
export function planSentences(
  cluster: ApprovedBookCluster,
  context: ApprovedBookRenderContext,
): SentencePlan | null {
  const observation = observationSentence(cluster, context);
  if (!observation) return null;
  const action = actionSentence(cluster);
  if (!action) return null;
  const closure = closureSentence(cluster);

  if (cluster.entryClass === "critical_immediate") {
    const exposure = exposureSentence(cluster);
    if (!exposure || !closure) return null;
    return {
      templateId: "critical-immediate-v1",
      sentences: [observation, exposure, action, closure],
    };
  }

  if (cluster.entryClass === "observed_corrective") {
    const exposure = exposureSentence(cluster);
    const sentences = [observation];
    if (exposure && cluster.urgency !== "planned") sentences.push(exposure);
    sentences.push(action);
    if (closure) sentences.push(closure);
    return { templateId: "observed-standard-v1", sentences };
  }

  if (cluster.entryClass === "assurance_verification") {
    const sentences = [observation, action];
    if (closure) sentences.push(closure);
    return { templateId: "assurance-verification-v1", sentences };
  }

  const sentences = [observation, action];
  if (closure) sentences.push(closure);
  return { templateId: "measurement-request-v1", sentences };
}

/**
 * Terminate every sentence.
 *
 * Catalogue entries are stored unpunctuated so they can be composed, and an
 * unterminated final clause reads as a truncated record rather than a written
 * one. The linter asserts this independently; here we make it true.
 */
function terminate(sentence: string): string {
  const trimmed = sentence.trim();
  if (!trimmed) return "";
  return /[.!?]$/u.test(trimmed) ? trimmed : `${trimmed}.`;
}

/**
 * Capital first letter, Turkish-aware.
 *
 * `toLocaleUpperCase("tr-TR")` matters here: a sentence beginning with "i"
 * must become "İ", not "I". The catalogue stores clauses lowercase so they can
 * be composed mid-sentence, so every sentence gets capitalised at the end.
 */
function capitalise(sentence: string): string {
  if (!sentence) return sentence;
  return `${sentence.charAt(0).toLocaleUpperCase("tr-TR")}${sentence.slice(1)}`;
}

export function renderParagraph(plan: SentencePlan): string {
  return plan.sentences
    .map((sentence) => capitalise(terminate(sentence)))
    .filter(Boolean)
    .join(" ")
    .replace(/\s{2,}/g, " ")
    .trim();
}
