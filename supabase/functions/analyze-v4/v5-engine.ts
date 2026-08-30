import type { Criticality, RoutedItem } from "./contracts.ts";
import {
  FK_FREQUENCY,
  FK_PROBABILITY,
  FK_SEVERITY,
  V5_MAX_FINDINGS,
  V5_MAX_POSITIVE_CONTROLS,
  type V5Finding,
  type V5PhotoOutput,
} from "./v5-contracts.ts";

// The server's whole job in the free engine: check that what came back is
// usable, do the arithmetic the report's totals depend on, and remove the two
// things the model is not allowed to publish. It does not decide what the
// hazards are, how severe they are, or what to do about them.

function text(value: unknown, max = 1200): string {
  return typeof value === "string"
    ? value.replace(/\s+/gu, " ").trim().slice(0, max)
    : "";
}

function textList(value: unknown, max = 6): string[] {
  return Array.isArray(value)
    ? value.map((entry) => text(entry, 400)).filter(Boolean).slice(0, max)
    : [];
}

// Citations were stripped here until the operator decided the report should
// carry them: Turkish legislation, the regulations under it, and TS / TS EN /
// ISO / IEC standards, written by the model into its own field and rendered as
// the finding's "Dayanak". The prompt carries the guard that matters -- name
// the regulation you are sure of and never invent an article number -- and a
// wrong number is now visible in the report rather than silently deleted from
// it. What stays below is the other claim class, which is about the
// photograph rather than the law.

/**
 * A nonconformity asserted about something the photograph cannot show.
 *
 * Recommending a record is a control. Declaring that the record is missing is
 * a compliance finding made from a photograph, which is the one thing a
 * photograph cannot support.
 */
const ASSERTS_INVISIBLE_ABSENCE =
  /(?:e[ğg]itim|sertifika|belge|yetki\s*belges|periyodik\s*kontrol|muayene\s*raporu|[öo]l[çc][üu]m|kalibrasyon|risk\s*de[ğg]erlendirmes)\w*\s+(?:[^.]{0,24}?)(?:yok|yoktur|bulunmuyor|bulunmamakta|eksik|yap[ıi]lmam[ıi][şs]|al[ıi]nmam[ıi][şs]|mevcut\s*de[ğg]il|ge[çc]ersiz)/iu;

export type SanitizeResult = { text: string; removed: string[] };

/**
 * Sentence by sentence, so one bad clause costs a clause and not a finding.
 *
 * v4's linter rejected a whole control line and fell back to a catalog
 * sentence. That trade made sense when the catalog was the baseline. Here
 * there is no catalog to fall back to, and dropping the model's text would
 * leave the reader with nothing, so the offending sentence is removed and the
 * rest published.
 */
export function sanitizeFreeText(
  raw: string,
  keepLineBreaks = false,
): SanitizeResult {
  const value = keepLineBreaks
    ? String(raw ?? "").split("\n").map((line) => text(line, 400)).filter(
      Boolean,
    ).join("\n")
    : text(raw);
  if (!value) return { text: "", removed: [] };
  const sentences = keepLineBreaks
    ? value.split("\n")
    : value.split(/(?<=[.!?])\s+/u).filter(Boolean);
  const removed: string[] = [];
  const kept = sentences.filter((sentence) => {
    if (ASSERTS_INVISIBLE_ABSENCE.test(sentence)) {
      removed.push("asserts_invisible_absence");
      return false;
    }
    return true;
  });
  return { text: kept.join(keepLineBreaks ? "\n" : " ").trim(), removed };
}

/**
 * The model does not always end a sentence, and this text gets joined to
 * another one. Analysis 5eae6972 published "Yüksekte çalışma prosedürlerinin
 * uygulanması ve denetlenmesi Eğitim: Yüksekte güvenli çalışma eğitimi" --
 * two sentences run together, in the card the reader acts from.
 */
function endSentence(value: string): string {
  const trimmed = value.trim().replace(/[;,\s]+$/u, "");
  if (!trimmed) return "";
  return /[.!?:]$/u.test(trimmed) ? trimmed : `${trimmed}.`;
}

/** Nearest allowed value. An off-scale number is a slip, not a reason to drop. */
export function snapToScale(
  value: unknown,
  scale: readonly number[],
  fallback: number,
): { value: number; snapped: boolean } {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return { value: fallback, snapped: true };
  if (scale.includes(numeric)) return { value: numeric, snapped: false };
  const nearest = scale.reduce((best, candidate) =>
    Math.abs(candidate - numeric) < Math.abs(best - numeric) ? candidate : best
  );
  return { value: nearest, snapped: true };
}

export function bandsFor(fk: number, m5: number) {
  const fkBand = fk <= 70
    ? "low"
    : fk <= 200
    ? "medium"
    : fk <= 400
    ? "high"
    : "critical";
  const m5Band = m5 <= 4
    ? "low"
    : m5 <= 9
    ? "medium"
    : m5 <= 19
    ? "high"
    : "critical";
  return { fkBand, m5Band } as const;
}

/**
 * Criticality follows severity, because in this engine severity is the model's
 * statement about how bad the outcome is and nothing else carries that.
 */
export function criticalityForSeverity(severity: number): Criticality {
  if (severity >= 40) return "fatal";
  if (severity >= 15) return "permanent";
  if (severity >= 7) return "serious";
  return "ordinary";
}

/**
 * Corner box in, offset box out.
 *
 * The operator's contract asks the model for {x_min, y_min, x_max, y_max};
 * everything downstream -- the candidates table, the app's overlay -- has
 * always spoken {x, y, width, height}. Converting here keeps the change at the
 * boundary instead of spreading a second coordinate convention through the
 * report.
 */
function cornerBoxToRegion(
  value: unknown,
): { x: number; y: number; width: number; height: number } | undefined {
  const box = (value ?? {}) as Record<string, unknown>;
  const numbers = ["x_min", "y_min", "x_max", "y_max"].map((key) =>
    Number(box[key])
  );
  if (numbers.some((entry) => !Number.isFinite(entry))) return undefined;
  const [xMin, yMin, xMax, yMax] = numbers;
  const x = Math.min(xMin, xMax);
  const y = Math.min(yMin, yMax);
  const width = Math.abs(xMax - xMin);
  const height = Math.abs(yMax - yMin);
  if (width <= 0 || height <= 0) return undefined;
  return { x, y, width, height };
}

/**
 * Did the model echo the prompt's own example back at us?
 *
 * The operator's document carried a JSON skeleton with placeholder strings,
 * and in analysis 6f72a303 gemini-3.5-flash-lite returned "Tam iki cümle." as
 * the scene summary -- the placeholder, verbatim, straight into the analysis's
 * ai_summary where the reader sees it. The same run produced 860 output tokens
 * and two shallow findings, having spent its attention mirroring a skeleton
 * the response schema already enforced. The example is gone; this stays as the
 * tripwire, because a placeholder reaching the reader is the loudest possible
 * symptom of the model copying rather than looking.
 */
const PLACEHOLDER_TEXT =
  /^(?:tam iki c[üu]mle|k[ıi]sa ba[şs]l[ıi]k|g[öo]r[üu]n[üu]r kan[ıi]t, konum ve maruziyet|kaynak → temas|iki-[üu][çc] kelime|g[öo]r[üu]n[üu]r en yak[ıi]n neden|foto[ğg]rafa dayal[ıi] gerek[çc]e|birinci somut ad[ıi]m)/iu;

export function looksLikePlaceholder(value: string): boolean {
  return PLACEHOLDER_TEXT.test(value.trim());
}

export function parseV5Output(raw: string): V5PhotoOutput {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error("v5_output_not_json");
  }
  if (!parsed || typeof parsed !== "object") {
    throw new Error("v5_output_not_object");
  }
  const envelope = parsed as Record<string, unknown>;
  const findings = Array.isArray(envelope.findings) ? envelope.findings : null;
  if (!findings) throw new Error("v5_findings_missing");
  return {
    scene_summary: text(envelope.scene_summary, 600),
    findings: findings.slice(0, V5_MAX_FINDINGS).map((entry) => {
      const finding = (entry ?? {}) as Record<string, unknown>;
      const kinney = (finding.fine_kinney ?? {}) as Record<string, unknown>;
      return {
        finding_key: text(finding.finding_key, 120),
        title: text(finding.title, 200),
        category: text(finding.category, 80),
        description: text(finding.description, 1600),
        event_path: text(finding.event_path, 600),
        root_cause: text(finding.root_cause, 600),
        regulatory_references: textList(finding.regulatory_references, 4),
        fine_kinney: {
          "olasılık": Number(kinney["olasılık"]),
          frekans: Number(kinney.frekans),
          "şiddet": Number(kinney["şiddet"]),
          "gerekçe": text(kinney["gerekçe"], 400),
        },
        immediate_control: text(finding.immediate_control, 400),
        corrective_steps: textList(finding.corrective_steps, 5),
        preventive_measure: text(finding.preventive_measure, 600),
        training_recommendation: text(finding.training_recommendation, 300),
        ppe_recommendation: text(finding.ppe_recommendation, 300),
        evidence_region: finding
          .evidence_region as V5Finding["evidence_region"],
        confidence: Number.isFinite(Number(finding.confidence))
          ? Math.min(1, Math.max(0, Number(finding.confidence)))
          : 0.6,
        needs_field_verification: finding.needs_field_verification === true,
      } satisfies V5Finding;
    }),
    positive_controls:
      (Array.isArray(envelope.positive_controls)
        ? envelope.positive_controls
        : []).slice(0, V5_MAX_POSITIVE_CONTROLS).map((entry) => {
          const control = (entry ?? {}) as Record<string, unknown>;
          return {
            title: text(control.title, 200),
            description: text(control.description, 600),
          };
        }).filter((control) => control.title && control.description),
  };
}

export type V5Routed = {
  candidates: Record<string, unknown>[];
  items: RoutedItem[];
  droppedFindings: Array<{ finding_key: string; reason: string }>;
  sanitizedCount: number;
  snappedCount: number;
};

/**
 * The model's findings become the report's findings, in its own order of
 * severity, with the arithmetic done here.
 *
 * A finding is dropped only when it has no title, no description or no control
 * left after sanitising -- that is, when there is nothing to publish. It is
 * never dropped for being unusual, small, distant or hard to categorise, which
 * is the whole difference from the contract engine.
 */
export function routeV5Findings(
  outputs: Array<{ photoIndex: number; output: V5PhotoOutput }>,
): V5Routed {
  const candidates: Record<string, unknown>[] = [];
  const scored: Array<{ item: RoutedItem; fk: number }> = [];
  const droppedFindings: Array<{ finding_key: string; reason: string }> = [];
  let sanitizedCount = 0;
  let snappedCount = 0;

  for (const { photoIndex, output } of outputs) {
    for (const finding of output.findings) {
      const title = sanitizeFreeText(finding.title);
      const description = sanitizeFreeText(finding.description);
      const control = sanitizeFreeText(finding.immediate_control);
      const rootCause = sanitizeFreeText(finding.root_cause);
      // One dayanak per line. Joined with a space, analysis 6f72a303 published
      // "6331 Sayılı İSG Kanunu — Madde 4 Elle Taşıma İşleri Yönetmeliği":
      // two separate references read as one sentence naming the wrong article.
      const references = sanitizeFreeText(
        finding.regulatory_references.map(endSentence).filter(Boolean).join(
          "\n",
        ),
        true,
      );
      const preventive = sanitizeFreeText(finding.preventive_measure);
      const steps = finding.corrective_steps.map((step) => sanitizeFreeText(step));
      const training = sanitizeFreeText(finding.training_recommendation ?? "");
      const ppe = sanitizeFreeText(finding.ppe_recommendation ?? "");
      const removed = [
        title,
        description,
        control,
        rootCause,
        references,
        preventive,
        training,
        ppe,
        ...steps,
      ].flatMap((entry) => entry.removed);
      sanitizedCount += removed.length;

      if (!title.text || !description.text || !control.text) {
        droppedFindings.push({
          finding_key: finding.finding_key,
          reason: !title.text
            ? "empty_title"
            : !description.text
            ? "empty_description"
            : "empty_control",
        });
        continue;
      }

      const p = snapToScale(finding.fine_kinney["olasılık"], FK_PROBABILITY, 3);
      const f = snapToScale(finding.fine_kinney.frekans, FK_FREQUENCY, 3);
      const s = snapToScale(finding.fine_kinney["şiddet"], FK_SEVERITY, 7);
      snappedCount += [p, f, s].filter((entry) => entry.snapped).length;
      const m5p = p.value <= 0.5
        ? 1
        : p.value === 1
        ? 2
        : p.value === 3
        ? 3
        : p.value === 6
        ? 4
        : 5;
      const m5s = s.value <= 3
        ? 1
        : s.value === 7
        ? 2
        : s.value === 15
        ? 3
        : s.value === 40
        ? 4
        : 5;
      const fk = p.value * f.value * s.value;
      const band = bandsFor(fk, m5p * m5s);
      const criticality = criticalityForSeverity(s.value);
      const candidateID = crypto.randomUUID();

      candidates.push({
        id: candidateID,
        photo_index: photoIndex,
        candidate_key: finding.finding_key || `p${photoIndex}:${candidateID}`,
        module_id: "free_engine",
        raw_label: title.text,
        condition_code: "free_engine_finding",
        evidence_level: "E5",
        criticality,
        evidence_region: cornerBoxToRegion(finding.evidence_region) ?? null,
        affirmative_cues: [description.text],
        counter_cues: [],
        // The contract states the chain as one line rather than three fields.
        event_path: { summary: finding.event_path },
        resolvability: {
          confidence: finding.confidence,
          needs_field_verification: finding.needs_field_verification,
        },
        fine_kinney_rationale: finding.fine_kinney["gerekçe"],
      });

      const correctiveText = [
        ...steps.map((entry) => entry.text).filter(Boolean),
        ...(ppe.text ? [`Kişisel koruyucu donanım: ${ppe.text}`] : []),
      ].map((line, index) => `${index + 1}. ${endSentence(line)}`).join("\n");
      const preventiveText = [
        endSentence(preventive.text),
        ...(training.text ? [`Eğitim: ${endSentence(training.text)}`] : []),
      ].filter(Boolean).join(" ");

      scored.push({
        fk,
        item: {
          id: crypto.randomUUID(),
          candidate_id: candidateID,
          item_class: "observed_finding",
          is_scored: true,
          criticality,
          ordinal: 0,
          title: title.text.slice(0, 200),
          category: finding.category || "Genel",
          description: description.text,
          recommended_action: control.text,
          recommended_measures: [
            ...(correctiveText
              ? [{
                kind: "corrective" as const,
                title: "Düzeltici Önlem",
                text: correctiveText,
              }]
              : []),
            ...(preventiveText
              ? [{
                kind: "preventive" as const,
                title: "Önleyici Kontrol",
                text: preventiveText,
              }]
              : []),
          ],
          // The model's own citation, rendered in the app as "Dayanak".
          references_text: references.text,
          root_cause_text: rootCause.text,
          confidence: finding.confidence,
          ai_confidence: finding.confidence,
          needs_field_verification: finding.needs_field_verification,
          source_photo_indices: [photoIndex],
          display_group: "observed_finding",
          display_order: 0,
          fk_probability: p.value,
          fk_frequency: f.value,
          fk_severity: s.value,
          fk_band: band.fkBand,
          m5_probability: m5p,
          m5_severity: m5s,
          m5_band: band.m5Band,
          score_payload: {
            fk_probability: p.value,
            fk_frequency: f.value,
            fk_severity: s.value,
            fk_band: band.fkBand,
            m5_probability: m5p,
            m5_severity: m5s,
            m5_band: band.m5Band,
            fine_kinney_rationale: finding.fine_kinney["gerekçe"],
          },
          internal_priority: {
            engine_mode: "free",
            finding_key: finding.finding_key,
            control_source: "model",
            sanitized: removed,
            scale_snapped: [p, f, s].some((entry) => entry.snapped),
          },
        },
      });
    }
  }

  // The model was asked to order by severity; the arithmetic decides the
  // report. Where the two disagree the score wins, because the totals and the
  // bands the reader sees are computed from it.
  scored.sort((a, b) => b.fk - a.fk);
  const items: RoutedItem[] = scored.map((entry, index) => ({
    ...entry.item,
    ordinal: index + 1,
    display_order: index + 1,
  }));

  let order = items.length;
  for (const { photoIndex, output } of outputs) {
    for (const control of output.positive_controls) {
      const description = sanitizeFreeText(control.description);
      const title = sanitizeFreeText(control.title);
      if (!title.text || !description.text) continue;
      order += 1;
      items.push({
        id: crypto.randomUUID(),
        item_class: "positive_control",
        is_scored: false,
        criticality: "ordinary",
        ordinal: order,
        title: title.text.slice(0, 200),
        category: "Olumlu kontrol",
        description: description.text,
        recommended_action: "",
        recommended_measures: [],
        references_text: "",
        root_cause_text: "",
        confidence: 0.8,
        ai_confidence: 0.8,
        needs_field_verification: false,
        source_photo_indices: [photoIndex],
        display_group: "positive_control",
        display_order: order,
        internal_priority: { engine_mode: "free" },
      });
    }
  }

  return { candidates, items, droppedFindings, sanitizedCount, snappedCount };
}
