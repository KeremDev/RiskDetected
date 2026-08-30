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

/**
 * Regulation, standard and article references.
 *
 * The app renders citations from an approved registry, and a model-written
 * "6331 sayılı kanun madde 5" reads to a safety officer exactly like one that
 * was checked. This is the one claim class where being wrong is worse than
 * saying nothing.
 */
const CITES_AUTHORITY =
  /(?:\b\d{4,5}\s*say[ıi]l[ıi]|\bmadde\s*\d|\bmd\.\s*\d|\bTS\s?EN\b|\bTSE\b|\bEN\s?\d{3}|\bISO\s?\d|\bIEC\s?\d|\bOSHA\b|\bNFPA\b|\bAPI\s?\d|y[öo]netmeli[ğg]i|\bmevzuat|\bkanun|\btebli[ğg]i|\bgenelge)/iu;

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
export function sanitizeFreeText(raw: string): SanitizeResult {
  const value = text(raw);
  if (!value) return { text: "", removed: [] };
  const sentences = value.split(/(?<=[.!?])\s+/u).filter(Boolean);
  const removed: string[] = [];
  const kept = sentences.filter((sentence) => {
    if (CITES_AUTHORITY.test(sentence)) {
      removed.push("cites_authority");
      return false;
    }
    if (ASSERTS_INVISIBLE_ABSENCE.test(sentence)) {
      removed.push("asserts_invisible_absence");
      return false;
    }
    return true;
  });
  return { text: kept.join(" ").trim(), removed };
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
      const path = (finding.event_path ?? {}) as Record<string, unknown>;
      const kinney = (finding.fine_kinney ?? {}) as Record<string, unknown>;
      const region = (finding.evidence_region ?? {}) as Record<string, unknown>;
      const hasRegion = ["x", "y", "width", "height"].every((key) =>
        Number.isFinite(Number(region[key]))
      );
      return {
        finding_key: text(finding.finding_key, 120),
        title: text(finding.title, 200),
        category: text(finding.category, 80),
        description: text(finding.description, 1200),
        event_path: {
          source: text(path.source, 300),
          contact_or_failure: text(path.contact_or_failure, 300),
          consequence: text(path.consequence, 300),
        },
        root_cause: text(finding.root_cause, 600),
        fine_kinney: {
          probability: Number(kinney.probability),
          frequency: Number(kinney.frequency),
          severity: Number(kinney.severity),
          rationale: text(kinney.rationale, 400),
        },
        immediate_control: text(finding.immediate_control, 400),
        corrective_steps: textList(finding.corrective_steps, 5),
        preventive_measure: text(finding.preventive_measure, 600),
        training_recommendation: text(finding.training_recommendation, 300),
        ppe_recommendation: text(finding.ppe_recommendation, 300),
        evidence_region: hasRegion
          ? {
            x: Number(region.x),
            y: Number(region.y),
            width: Number(region.width),
            height: Number(region.height),
            description: text(region.description, 200),
          }
          : undefined,
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
      const preventive = sanitizeFreeText(finding.preventive_measure);
      const steps = finding.corrective_steps.map(sanitizeFreeText);
      const training = sanitizeFreeText(finding.training_recommendation ?? "");
      const ppe = sanitizeFreeText(finding.ppe_recommendation ?? "");
      const removed = [
        title,
        description,
        control,
        rootCause,
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

      const p = snapToScale(finding.fine_kinney.probability, FK_PROBABILITY, 3);
      const f = snapToScale(finding.fine_kinney.frequency, FK_FREQUENCY, 3);
      const s = snapToScale(finding.fine_kinney.severity, FK_SEVERITY, 7);
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
        evidence_region: finding.evidence_region ?? null,
        affirmative_cues: [description.text],
        counter_cues: [],
        event_path: finding.event_path,
        resolvability: {
          confidence: finding.confidence,
          needs_field_verification: finding.needs_field_verification,
        },
        fine_kinney_rationale: finding.fine_kinney.rationale,
      });

      const correctiveText = [
        ...steps.map((entry) => entry.text).filter(Boolean),
        ...(ppe.text ? [`Kişisel koruyucu donanım: ${ppe.text}`] : []),
      ].map((line, index) => `${index + 1}. ${line}`).join("\n");
      const preventiveText = [
        preventive.text,
        ...(training.text ? [`Eğitim: ${training.text}`] : []),
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
          // The approved-reference renderer is a v4 component keyed by
          // mechanism, and this engine has no mechanism. Citations are left
          // empty rather than invented; the model is forbidden from writing
          // them and the server does not supply a substitute.
          references_text: "",
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
            fine_kinney_rationale: finding.fine_kinney.rationale,
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
