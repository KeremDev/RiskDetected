// Canonical input and output types for the approved-book text engine.
//
// The engine's entire safety premise is that a book paragraph is PLANNED from
// codes rather than rewritten from the model's own sentences. So the source type
// below carries codes only. `rawForReview` exists for the expert's traceability
// panel and is deliberately typed `unknown`: nothing on the render path may read
// it, and a typed field would invite exactly that.
//
// Why this matters concretely: on one process-tank photograph the analysis
// engine produced, across five consecutive runs, five different guardrail
// claims -- missing toeboard, missing top rail, missing mid rail twice, then an
// unnamed gap -- on a frame where every platform carried all three members. The
// routing gates caught them. Rewriting any of those sentences into a more
// official register would have produced a well-written false record.

export type BookSourceClass =
  | "observed_finding"
  | "assurance_requirement"
  | "verification_request";

export type EvidenceTier = "E0" | "E1" | "E2" | "E3" | "E4" | "E5";

export type Criticality = "fatal" | "permanent" | "serious" | "ordinary";

/** How the specialist says they came by the observation. Never inferred. */
export type ObservationBasis =
  | "direct_site_observation"
  | "employer_supplied_visual_record"
  | "document_review"
  | "follow_up_check";

/**
 * What the section assumes when the specialist has not said otherwise.
 *
 * These photographs are taken by the specialist walking the site, so a site
 * inspection is the true basis in the ordinary case and asking for a tap before
 * showing anything would be friction over a question already answered.
 *
 * The stored column stays null while this default applies, so "defaulted" and
 * "explicitly stated" remain distinguishable in the record for free -- which
 * matters, because the sentence this produces asserts the specialist was there.
 */
export const DEFAULT_OBSERVATION_BASIS: ObservationBasis =
  "direct_site_observation";

export const OBSERVATION_BASES: ObservationBasis[] = [
  "direct_site_observation",
  "employer_supplied_visual_record",
  "document_review",
  "follow_up_check",
];

/** One analysis item, reduced to the codes a sentence planner may use. */
export interface BookSourceItem {
  sourceItemId: string;
  itemClass: BookSourceClass;

  moduleId: string;
  conditionCode: string;
  mechanismCode: string | null;
  assuranceTopicId: string | null;
  assetFamily: string;
  assetRef: string | null;
  barrierComponentsAbsent: string[];

  evidenceTier: EvidenceTier;
  criticality: Criticality;
  occlusion: string;
  confidence: {
    visibility: number;
    localization: number;
    mechanism: number;
  };
  visuallyResolvable: boolean;
  requiresDocumentOrMeasurement: boolean;
  accessibleEventPath: boolean;
  peopleVisible: number;

  photoIndices: number[];
  needsFieldVerification: boolean;

  /** Model prose. Traceability only; the render path must never read it. */
  rawForReview?: unknown;
}

export type BookEntryClass =
  | "observed_corrective"
  | "critical_immediate"
  | "assurance_verification"
  | "measurement_or_test_request";

export type BookUrgency = "immediate" | "short_term" | "planned";

export interface ApprovedBookCluster {
  clusterId: string;
  entryClass: BookEntryClass;
  urgency: BookUrgency;
  /** Highest criticality in the cluster; drives language, never a number. */
  criticality: Criticality;
  moduleId: string;
  mechanismCode: string | null;
  assuranceTopicId: string | null;
  assetFamily: string;
  barrierComponentsAbsent: string[];
  peopleVisible: number;
  sourceItemIds: string[];
  photoIndices: number[];
  /** Ranking only; never rendered. */
  priority: number;
}

export type BlockReason =
  | "BOOK_OBSERVATION_BASIS_REQUIRED"
  | "BOOK_CRITICAL_LANGUAGE_APPROVAL_REQUIRED"
  | "BOOK_EVIDENCE_TOO_WEAK"
  | "BOOK_NO_LANGUAGE_SURFACE"
  | "BOOK_LINT_FAILED";

export interface ApprovedBookDraft {
  clusterId: string;
  entryClass: BookEntryClass;
  urgency: BookUrgency;
  copyText: string;
  sourceItemIds: string[];
  /** Which sentence each source supports, for the review panel. */
  sentenceSupport: Array<{ sentence: number; sourceItemIds: string[] }>;
  legalBasisIds: string[];
  requiredConfirmations: BlockReason[];
  warnings: string[];
  templateId: string;
  outputSha256: string;
}

export interface ApprovedBookBlocked {
  clusterId: string;
  entryClass: BookEntryClass;
  reason: BlockReason;
  sourceItemIds: string[];
  detail: string;
}

export interface ApprovedBookRenderContext {
  observationBasis: ObservationBasis | null;
  /** Cluster ids the specialist has explicitly approved critical wording for. */
  criticalLanguageApprovals: string[];
  /** Free-text slots, already sanitised by the caller. */
  locationByCluster: Record<string, string>;
  legalReferenceMode: "none" | "title_only";
}

export const EMPTY_RENDER_CONTEXT: ApprovedBookRenderContext = {
  observationBasis: null,
  criticalLanguageApprovals: [],
  locationByCluster: {},
  legalReferenceMode: "title_only",
};
