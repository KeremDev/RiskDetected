// Approved-book drafts: adapter -> eligibility -> cluster -> plan -> lint.
//
// Two stages, kept apart on purpose (plan §5.3). Stage A runs on the analysis
// alone and answers "what could be written about". Stage B needs the specialist
// to say how they observed the site, and only then is a sentence produced.
//
// The separation is the whole legal point of the feature: without it the system
// would write "saha incelemesinde gözlenmiştir" about a photograph nobody took
// on site. So `buildApprovedBookDrafts` with no observation basis returns
// blocked clusters -- never text.

import type {
  ApprovedBookBlocked,
  ApprovedBookCluster,
  ApprovedBookDraft,
  ApprovedBookRenderContext,
  BookSourceItem,
} from "./contracts.ts";
import { adaptV4Items, type V4ItemRow } from "./analysis-adapter.ts";
import { eligibleItems } from "./eligibility.ts";
import { clusterItems } from "./clusterer.ts";
import {
  CRITICAL_LANGUAGE_ENABLED,
  planSentences,
  renderParagraph,
} from "./renderer.ts";
import { lint } from "./linter.ts";
import {
  APPROVED_BOOK_ENGINE_VERSION,
  APPROVED_BOOK_TEMPLATE_VERSION,
  sha256Hex,
} from "./version-contract.ts";

export type ApprovedBookResult = {
  drafts: ApprovedBookDraft[];
  blocked: ApprovedBookBlocked[];
  clusters: ApprovedBookCluster[];
};

/** Stage A: what this analysis could support, before any user context. */
export function bookCandidates(rows: V4ItemRow[]): {
  items: BookSourceItem[];
  clusters: ApprovedBookCluster[];
} {
  const items = adaptV4Items(rows);
  const clusters = clusterItems(eligibleItems(items));
  return { items, clusters };
}

/** Stage B: render, once the specialist has stated the observation basis. */
export async function buildApprovedBookDrafts(
  rows: V4ItemRow[],
  context: ApprovedBookRenderContext,
): Promise<ApprovedBookResult> {
  const { clusters } = bookCandidates(rows);
  const drafts: ApprovedBookDraft[] = [];
  const blocked: ApprovedBookBlocked[] = [];

  for (const cluster of clusters) {
    if (!context.observationBasis) {
      blocked.push({
        clusterId: cluster.clusterId,
        entryClass: cluster.entryClass,
        reason: "BOOK_OBSERVATION_BASIS_REQUIRED",
        sourceItemIds: cluster.sourceItemIds,
        detail: "gözlem dayanağı seçilmedi",
      });
      continue;
    }

    // Critical wording is the wording an employer acts on within the hour, so it
    // stays behind an explicit per-cluster approval. That approval has no
    // control in the app yet, so the language is switched off in the renderer
    // and these clusters are written in standard language instead -- they are
    // never withheld. Blocking them would take the most severe findings out of
    // the record entirely, which is the one outcome worth avoiding above all.
    if (
      CRITICAL_LANGUAGE_ENABLED &&
      cluster.entryClass === "critical_immediate" &&
      !context.criticalLanguageApprovals.includes(cluster.clusterId)
    ) {
      blocked.push({
        clusterId: cluster.clusterId,
        entryClass: cluster.entryClass,
        reason: "BOOK_CRITICAL_LANGUAGE_APPROVAL_REQUIRED",
        sourceItemIds: cluster.sourceItemIds,
        detail: "kritik dil için ayrı uzman onayı gerekli",
      });
      continue;
    }

    const plan = planSentences(cluster, context);
    if (!plan) {
      blocked.push({
        clusterId: cluster.clusterId,
        entryClass: cluster.entryClass,
        reason: "BOOK_NO_LANGUAGE_SURFACE",
        sourceItemIds: cluster.sourceItemIds,
        detail: `katalogda yüzey yok: ${
          cluster.mechanismCode ?? cluster.assuranceTopicId ?? cluster.moduleId
        }`,
      });
      continue;
    }

    const copyText = renderParagraph(plan);
    const lintFindings = lint(copyText);
    if (lintFindings.length > 0) {
      blocked.push({
        clusterId: cluster.clusterId,
        entryClass: cluster.entryClass,
        reason: "BOOK_LINT_FAILED",
        sourceItemIds: cluster.sourceItemIds,
        detail: lintFindings.map((entry) => entry.rule).join(","),
      });
      continue;
    }

    drafts.push({
      clusterId: cluster.clusterId,
      entryClass: cluster.entryClass,
      urgency: cluster.urgency,
      copyText,
      sourceItemIds: cluster.sourceItemIds,
      sentenceSupport: plan.sentences.map((_, index) => ({
        sentence: index + 1,
        sourceItemIds: cluster.sourceItemIds,
      })),
      // Registry wiring lands with the legal-basis resolver; an empty list is
      // the honest state, and title_only never invents a reference.
      legalBasisIds: [],
      requiredConfirmations: [],
      warnings: [],
      templateId: plan.templateId,
      outputSha256: await sha256Hex(
        [
          APPROVED_BOOK_ENGINE_VERSION,
          APPROVED_BOOK_TEMPLATE_VERSION,
          cluster.clusterId,
          context.observationBasis,
          copyText,
        ].join("|"),
      ),
    });
  }

  return { drafts, blocked, clusters };
}

export type { V4ItemRow };
export * from "./contracts.ts";
export {
  APPROVED_BOOK_ENGINE_VERSION,
  APPROVED_BOOK_PROJECTION_VERSION,
  APPROVED_BOOK_TEMPLATE_VERSION,
  computeApprovedBookBundleSHA256,
} from "./version-contract.ts";
