import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  ANALYSIS_RESULT_CONTRACT_VERSION,
  ANALYSIS_RESULT_UI_VERSION,
  findingSection,
  isPaidTier,
  redactFindingForFree,
  redactNotebookForFree,
  redactTrainingForFree,
  resolveResultHubTier,
  resultHubGateOpen,
  type ResultHubSection,
  type ResultHubTier,
  safeObject,
  sectionAccess,
} from "../_shared/analysis-result-hub.ts";
import {
  APPROVED_NOTEBOOK_PROJECTION_VERSION,
  APPROVED_NOTEBOOK_TEMPLATE_TR,
  firstSentenceTeaser,
  projectApprovedNotebookEntries,
  type ProjectorFinding,
  type ResultHubLanguage,
  SAFETY_LOG_TEMPLATE_EN,
  sanitizeNotebookText,
  type V4ResultMetadata,
} from "../_shared/approved-notebook-projector.ts";
import {
  APPROVED_BOOK_PROJECTION_VERSION,
  APPROVED_BOOK_TEMPLATE_VERSION,
  buildApprovedBookDrafts,
  FIXED_OBSERVATION_BASIS,
  type V4ItemRow,
} from "../_shared/approved-book/index.ts";
import {
  hazardClassFrom,
  trainingRecommendationsFor,
  type TrainingItemRow,
} from "../_shared/training-recommendations/index.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const FINDINGS_SELECT = [
  "id",
  "analysis_id",
  "user_id",
  "ordinal",
  "title",
  "category",
  "description",
  "recommended_action",
  "recommended_measures",
  "references_text",
  "root_cause_text",
  "confidence",
  "needs_field_verification",
  "fk_probability",
  "fk_frequency",
  "fk_severity",
  "fk_score",
  "fk_band",
  "m5_probability",
  "m5_severity",
  "m5_score",
  "m5_band",
  "origin",
  "source_photo_indices",
  "ai_confidence",
  "finding_version",
  "display_order",
  "item_class",
  "is_scored",
].join(",");

const ALLOWED_EVENTS = new Set([
  "result_screen_viewed",
  "result_section_selected",
  "locked_teaser_impression",
  "locked_teaser_cta_tapped",
  "result_item_detail_opened",
  "result_feedback_set",
  "result_feedback_cleared",
  "report_selection_changed",
  "report_create_started",
  "report_create_completed",
  "report_create_failed",
  "paywall_viewed",
  "checkout_started",
  "purchase_completed",
]);

const ALLOWED_FEEDBACK_REASONS = new Set([
  "incorrect_detection",
  "missing_context",
  "wrong_score",
  "wrong_recommendation",
  "duplicate",
  "irrelevant",
  "unclear_text",
  "other",
]);

type Body = {
  action?:
    | "load"
    | "mutate_notebook"
    | "feedback"
    | "event"
    | "create_report_intent";
  analysis_id?: string;
  language?: string;
  client_capabilities?: Record<string, unknown>;
  client_platform?: string;
  client_app_version?: string;
  client_app_build?: string;
  entry_id?: string;
  mutation?: "edit" | "suppress" | "restore" | "reset";
  finding_text?: string;
  recommendation_text?: string;
  target_kind?: "finding" | "notebook_entry";
  target_key?: string;
  section?: ResultHubSection;
  rating?: number;
  reason_code?: string | null;
  note?: string | null;
  client_event_id?: string;
  funnel_session_id?: string | null;
  event_name?: string;
  metadata?: Record<string, unknown>;
  format?: "pdf" | "xlsx";
  report_kind?: "standard" | "riskAnalysis";
  selected_item_keys?: string[];
  request_id?: string;
};

type Context = {
  // deno-lint-ignore no-explicit-any
  supabase: any;
  userID: string;
  body: Body;
  analysis: Record<string, unknown>;
  tier: ResultHubTier;
  language: ResultHubLanguage;
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

function isUUID(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

function canonicalUUID(value: string): string {
  return value.toLowerCase();
}

function cleanString(value: unknown, maxLength = 200): string {
  return typeof value === "string" ? value.trim().slice(0, maxLength) : "";
}

function languageFor(
  body: Body,
  analysis: Record<string, unknown>,
): ResultHubLanguage {
  const value = cleanString(body.language || analysis.output_language, 20)
    .toLowerCase();
  return value.startsWith("en") ? "en" : "tr";
}

function reactionMap(rows: unknown): Map<string, Record<string, unknown>> {
  const map = new Map<string, Record<string, unknown>>();
  if (!Array.isArray(rows)) return map;
  for (const raw of rows) {
    const row = safeObject(raw);
    const kind = cleanString(row.target_kind, 40);
    const rawKey = cleanString(row.target_key, 200);
    const key = isUUID(rawKey) ? canonicalUUID(rawKey) : rawKey;
    if (kind && key) map.set(`${kind}:${key}`, row);
  }
  return map;
}

function withReaction(
  item: Record<string, unknown>,
  kind: string,
  reactions: Map<string, Record<string, unknown>>,
): Record<string, unknown> {
  const rawID = String(item.id ?? "");
  const itemID = isUUID(rawID) ? canonicalUUID(rawID) : rawID;
  const reaction = reactions.get(`${kind}:${itemID}`);
  return {
    ...item,
    user_reaction: reaction?.reaction ?? "none",
    feedback_reason_code: reaction?.reason_code ?? null,
  };
}

/**
 * Approved-book paragraphs for this analysis, or an empty list.
 *
 * Empty is the normal answer and covers every case where the deterministic text
 * is not available or not permitted: no observation basis chosen, an English
 * report, a v3 analysis with no canonical codes, or a set of items none of which
 * is writable. The caller falls back to the v2 projection, so the section never
 * goes blank.
 *
 * Rows are stored under the book engine's own projection version, beside the v2
 * rows rather than replacing them. Nothing a user has already edited moves, and
 * clearing the basis returns them to exactly what they had.
 *
 * `recommendation_text` is stored empty on purpose. A book entry is one flowing
 * paragraph; the finding/recommendation split belongs to v2 and reproducing it
 * here would let a reader mistake half a paragraph for a whole record.
 */
async function buildApprovedBookSection(
  context: Context,
  metadata: V4ResultMetadata[],
): Promise<Record<string, unknown>[]> {
  if (context.language !== "tr") return [];
  // One basis, fixed. Every photograph in this product is taken by the
  // specialist walking the site, so the other three were choices nobody needed
  // to make; offering them invited a wrong answer for no gain.
  const basis = FIXED_OBSERVATION_BASIS;

  try {
    const result = await buildApprovedBookDrafts(
      metadata as unknown as V4ItemRow[],
      {
        observationBasis: basis,
        criticalLanguageApprovals: [],
        locationByCluster: {},
        legalReferenceMode: "title_only",
      },
    );
    if (result.drafts.length === 0) return [];

    const entries = await Promise.all(
      result.drafts.map(async (draft, index) => ({
        id: await bookEntryID(String(context.analysis.id), draft.clusterId),
        grouping_key: draft.clusterId,
        source_finding_ids: draft.sourceItemIds,
        source_hash: draft.outputSha256,
        finding_text: draft.copyText,
        recommendation_text: "",
        reference_text: null,
        display_order: index,
      })),
    );

    const { data } = await context.supabase.rpc(
      "result_hub_upsert_notebook_entries",
      {
        p_user_id: context.userID,
        p_analysis_id: context.analysis.id,
        p_language: context.language,
        p_projection_version: APPROVED_BOOK_PROJECTION_VERSION,
        p_template_version: APPROVED_BOOK_TEMPLATE_VERSION,
        p_entries: entries,
      },
    );

    return (Array.isArray(data) ? data : [])
      .map(safeObject)
      .filter((row) =>
        row.is_suppressed !== true &&
        row.projection_version === APPROVED_BOOK_PROJECTION_VERSION
      );
  } catch (_error) {
    // Fall back to v2 rather than showing the reader an empty section.
    return [];
  }
}

/**
 * Stable id per catalogue code.
 *
 * Training cards are derived rather than stored, so their ids have to be a pure
 * function of the analysis and the catalogue code. That keeps a reaction on
 * "Yüksekte Güvenli Çalışma" pointing at the same card across reloads without
 * a table to keep in sync.
 */
function trainingCardID(analysisID: string, catalogCode: string): string {
  let hash = 0x811c9dc5;
  for (const char of `${analysisID}|${catalogCode}`) {
    hash ^= char.codePointAt(0) ?? 0;
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  const seed = hash.toString(16).padStart(8, "0");
  const body = `${seed}${analysisID.replace(/-/g, "").slice(0, 24)}`.slice(0, 32)
    .padEnd(32, "0");
  return `${body.slice(0, 8)}-${body.slice(8, 12)}-5${body.slice(13, 16)}-a${
    body.slice(17, 20)
  }-${body.slice(20, 32)}`;
}

/** Stable per-cluster id, distinct from the v2 id space. */
async function bookEntryID(
  analysisID: string,
  clusterID: string,
): Promise<string> {
  const bytes = new TextEncoder().encode(
    [APPROVED_BOOK_PROJECTION_VERSION, analysisID, clusterID].join("|"),
  );
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  const hex = [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
  const raw = (hex.slice(0, 32).match(/../g) ?? []).map((value) =>
    Number.parseInt(value, 16)
  );
  raw[6] = (raw[6] & 0x0f) | 0x50;
  raw[8] = (raw[8] & 0x3f) | 0x80;
  const value = raw.map((byte) => byte.toString(16).padStart(2, "0")).join("");
  return `${value.slice(0, 8)}-${value.slice(8, 12)}-${value.slice(12, 16)}-${
    value.slice(16, 20)
  }-${value.slice(20, 32)}`;
}

async function loadAuthoritativeSections(context: Context) {
  const { data: findingData, error: findingsError } = await context.supabase
    .from("findings")
    .select(FINDINGS_SELECT)
    .eq("analysis_id", context.analysis.id)
    .eq("user_id", context.userID)
    .eq("is_user_deleted", false)
    .eq("report_visibility", "visible")
    .order("display_order", { ascending: true, nullsFirst: false })
    .order("ordinal", { ascending: true });
  if (findingsError) {
    throw new Error(`findings_fetch_failed:${findingsError.message}`);
  }
  const findings = (Array.isArray(findingData) ? findingData : []) as Array<
    Record<string, unknown>
  >;

  const { data: metadataData, error: metadataError } = await context.supabase
    .rpc("result_hub_v4_metadata", {
      p_user_id: context.userID,
      p_analysis_id: context.analysis.id,
    });
  if (metadataError) {
    throw new Error(`metadata_fetch_failed:${metadataError.message}`);
  }
  const metadata =
    (Array.isArray(metadataData) ? metadataData : []) as V4ResultMetadata[];

  const projected = await projectApprovedNotebookEntries({
    analysisID: String(context.analysis.id),
    language: context.language,
    findings: findings as ProjectorFinding[],
    metadata,
  });
  const templateVersion = context.language === "tr"
    ? APPROVED_NOTEBOOK_TEMPLATE_TR
    : SAFETY_LOG_TEMPLATE_EN;
  const { data: notebookData, error: notebookError } = await context.supabase
    .rpc("result_hub_upsert_notebook_entries", {
      p_user_id: context.userID,
      p_analysis_id: context.analysis.id,
      p_language: context.language,
      p_projection_version: APPROVED_NOTEBOOK_PROJECTION_VERSION,
      p_template_version: templateVersion,
      p_entries: projected,
    });
  if (notebookError) {
    throw new Error(`notebook_projection_failed:${notebookError.message}`);
  }
  const notebookRows = (Array.isArray(notebookData) ? notebookData : [])
    .map(safeObject)
    .filter((row) => row.is_suppressed !== true)
    // The shadow projection writes rows beside these under its own version.
    // The list RPC does not filter by version, so the filter lives here: a
    // shadow paragraph must never reach a reader while its catalogues are
    // still being tuned.
    .filter((row) =>
      row.projection_version === APPROVED_NOTEBOOK_PROJECTION_VERSION
    );

  const book = await buildApprovedBookSection(context, metadata);

  // Training recommendations are derived, not stored: the same analysis and the
  // same catalogue always produce the same cards, so persisting them would only
  // add a copy to keep in sync. Ids are stable per catalogue code so reactions
  // and selections keep pointing at the same card.
  // The statutory hours split on the workplace hazard class, which no
  // photograph shows. It arrives only from a company the user bound to this
  // analysis; without one the card states all three classes rather than
  // asserting a class nobody declared.
  const training = trainingRecommendationsFor({
    sectorId: cleanString(context.analysis.analysis_sector, 64) || null,
    hazardClass: hazardClassFrom(
      safeObject(context.analysis.companies).hazard_class,
    ),
    rows: metadata as unknown as TrainingItemRow[],
  }).map((card) => ({
    id: trainingCardID(String(context.analysis.id), card.catalogCode),
    catalog_code: card.catalogCode,
    title: card.title,
    category_label: card.categoryLabel,
    audience_label: card.audienceLabel,
    text: card.text,
    group_code: card.groupCode,
    duration_label: card.duration?.label ?? null,
    duration_value: card.duration?.value ?? null,
    duration_note: card.duration?.note ?? null,
    source_finding_ids: card.sourceItemIds,
    display_order: card.displayOrder,
  }));

  const { data: feedbackData } = await context.supabase
    .rpc("result_hub_feedback_for_analysis", {
      p_user_id: context.userID,
      p_analysis_id: context.analysis.id,
    });
  const reactions = reactionMap(feedbackData);

  const risk = findings
    .filter((row) => findingSection(row) === "risk_analysis")
    .map((row) => withReaction(row, "finding", reactions));
  const expertFull = findings
    .filter((row) => findingSection(row) === "expert_recommendations")
    .map((row) => withReaction(row, "finding", reactions));
  // The specialist choosing an observation basis is what turns the book text on
  // for this analysis. Until they choose, `book` is empty and the v2 projection
  // is served exactly as before -- no hidden flag, and no paragraph claiming an
  // observation nobody stated.
  const notebookFull = (book.length > 0 ? book : notebookRows)
    .map((row) => withReaction(row, "notebook_entry", reactions));
  const trainingFull = training
    .map((row) => withReaction(row, "training_card", reactions));
  const paid = isPaidTier(context.tier);

  return {
    risk,
    expertFull,
    notebookFull,
    expert: paid ? expertFull : expertFull.map(redactFindingForFree),
    notebook: paid ? notebookFull : notebookFull.map(redactNotebookForFree),
    trainingFull,
    training: paid ? trainingFull : trainingFull.map(redactTrainingForFree),
    templateVersion,
    // Reported so the section can tell the reader what the entries assume,
    // not so anything can be picked.
    observationBasis: book.length > 0 ? FIXED_OBSERVATION_BASIS : null,
  };
}

function sectionPayload(
  section: ResultHubSection,
  tier: ResultHubTier,
  items: Record<string, unknown>[],
) {
  const access = sectionAccess(section, tier);
  return {
    id: section,
    access,
    count: items.length,
    // Training cards are advice about people, not findings about the site.
    // They are not editable -- editing one would mean editing the catalogue --
    // and not offered to the report builder.
    can_edit: section === "training_recommendations"
      ? false
      : isPaidTier(tier) && access === "full",
    can_report: section === "training_recommendations"
      ? false
      : section === "risk_analysis" || isPaidTier(tier),
    items,
  };
}

function contentForFeedback(
  item: Record<string, unknown>,
  section: ResultHubSection,
): Record<string, unknown> {
  if (section === "training_recommendations") {
    return {
      catalog_code: item.catalog_code,
      title: item.title,
      audience_label: item.audience_label,
      text: item.text,
      source_finding_ids: item.source_finding_ids,
    };
  }
  if (section === "approved_notebook") {
    return {
      finding_text: item.finding_text,
      recommendation_text: item.recommendation_text,
      reference_text: item.reference_text,
      source_finding_ids: item.source_finding_ids,
    };
  }
  return {
    title: item.title,
    description: item.description,
    recommended_action: item.recommended_action,
    recommended_measures: item.recommended_measures,
    item_class: item.item_class,
    is_scored: item.is_scored,
    fk_score: item.fk_score,
    fk_band: item.fk_band,
    m5_score: item.m5_score,
    m5_band: item.m5_band,
    source_photo_indices: item.source_photo_indices,
  };
}

async function handleLoad(context: Context) {
  const sections = await loadAuthoritativeSections(context);
  return json(200, {
    enabled: true,
    contract_version: ANALYSIS_RESULT_CONTRACT_VERSION,
    ui_version: ANALYSIS_RESULT_UI_VERSION,
    analysis_id: context.analysis.id,
    analysis_edit_version: context.analysis.analysis_edit_version ?? 0,
    tier: context.tier,
    language: context.language,
    versions: {
      projection: APPROVED_NOTEBOOK_PROJECTION_VERSION,
      template: sections.templateVersion,
      feedback: "analysis-item-feedback-v1",
      analytics: "analysis-result-events-v1",
    },
    disclaimers: {
      expert: context.language === "tr"
        ? "Bu içerik bağlayıcı uzman görüşü değildir; saha teyidi ve uzman değerlendirmesi gerekir."
        : "This content is not a binding expert opinion; field verification and expert review are required.",
      notebook: context.language === "tr"
        ? "Onaylı Defter önerisi/taslağıdır; uzman değerlendirmesi ve resmî deftere aktarım gerekir."
        : "This is a Safety Log recommendation; expert review and transfer to the applicable official record are required.",
    },
    sections: [
      sectionPayload("risk_analysis", context.tier, sections.risk),
      sectionPayload("expert_recommendations", context.tier, sections.expert),
      sectionPayload(
        "training_recommendations",
        context.tier,
        sections.training,
      ),
      {
        ...sectionPayload("approved_notebook", context.tier, sections.notebook),
        // Stated, not offered: the entries assume a site inspection and the
        // reader is told so, but there is nothing here to choose.
        observation_basis: sections.observationBasis,
      },
    ],
  });
}

async function handleNotebookMutation(context: Context) {
  if (!isPaidTier(context.tier)) {
    return json(403, { error: "premium_required" });
  }
  if (!isUUID(context.body.entry_id)) {
    return json(400, { error: "invalid_entry_id" });
  }
  const mutation = context.body.mutation;
  if (!["edit", "suppress", "restore", "reset"].includes(String(mutation))) {
    return json(400, { error: "invalid_notebook_mutation" });
  }
  const findingText = mutation === "edit"
    ? sanitizeNotebookText(context.body.finding_text).slice(0, 4000)
    : null;
  const recommendationText = mutation === "edit"
    ? sanitizeNotebookText(context.body.recommendation_text).slice(0, 6000)
    : null;
  if (mutation === "edit" && (!findingText || !recommendationText)) {
    return json(422, { error: "notebook_text_required" });
  }
  const { data, error } = await context.supabase.rpc(
    "result_hub_mutate_notebook_entry",
    {
      p_user_id: context.userID,
      p_analysis_id: context.analysis.id,
      p_entry_id: context.body.entry_id,
      p_action: mutation,
      p_finding_text: findingText,
      p_recommendation_text: recommendationText,
      p_reference_text: null,
    },
  );
  if (error) {
    return json(422, {
      error: "notebook_mutation_failed",
      detail: error.message,
    });
  }
  return json(200, { ok: true, entries: data });
}

async function handleFeedback(context: Context) {
  const section = context.body.section;
  const targetKind = context.body.target_kind;
  const rawTargetKey = cleanString(context.body.target_key, 200);
  const targetKey = isUUID(rawTargetKey)
    ? canonicalUUID(rawTargetKey)
    : rawTargetKey;
  const rating = Math.round(Number(context.body.rating ?? 0));
  if (!section || !targetKind || !targetKey || ![-1, 0, 1].includes(rating)) {
    return json(400, { error: "invalid_feedback" });
  }
  if (section !== "risk_analysis" && !isPaidTier(context.tier)) {
    return json(403, { error: "premium_required" });
  }
  const sections = await loadAuthoritativeSections(context);
  const candidates = section === "risk_analysis"
    ? sections.risk
    : section === "expert_recommendations"
    ? sections.expertFull
    : section === "training_recommendations"
    ? sections.trainingFull
    : sections.notebookFull;
  const item = candidates.find((row) => {
    const rawID = String(row.id ?? "");
    return (isUUID(rawID) ? canonicalUUID(rawID) : rawID) === targetKey;
  });
  if (!item) return json(404, { error: "feedback_target_not_found" });
  const reason = cleanString(context.body.reason_code, 80);
  if (reason && !ALLOWED_FEEDBACK_REASONS.has(reason)) {
    return json(422, { error: "invalid_feedback_reason" });
  }
  const { data, error } = await context.supabase.rpc(
    "result_hub_upsert_feedback",
    {
      p_user_id: context.userID,
      p_analysis_id: context.analysis.id,
      p_target_kind: targetKind,
      p_target_key: targetKey,
      p_public_finding_id: targetKind === "finding" ? targetKey : null,
      p_notebook_entry_id: targetKind === "notebook_entry" ? targetKey : null,
      p_section: section,
      p_item_class: item.item_class ??
        (targetKind === "notebook_entry" ? "approved_notebook" : null),
      p_rating: rating,
      p_reason_code: reason || null,
      p_note: cleanString(context.body.note, 1000) || null,
      p_content_snapshot: contentForFeedback(item, section),
      p_context_snapshot: {
        contract_version: ANALYSIS_RESULT_CONTRACT_VERSION,
        projection_version: APPROVED_NOTEBOOK_PROJECTION_VERSION,
        sector: context.analysis.analysis_sector ?? null,
        engine_variant:
          safeObject(context.analysis.rollout_snapshot).engine_variant ?? null,
        tier: context.tier,
        platform: context.body.client_platform ?? null,
        build: context.body.client_app_build ?? null,
      },
    },
  );
  if (error) {
    return json(422, { error: "feedback_write_failed", detail: error.message });
  }
  return json(200, { ok: true, feedback: data });
}

async function handleEvent(context: Context) {
  if (
    !isUUID(context.body.client_event_id) ||
    !ALLOWED_EVENTS.has(String(context.body.event_name ?? ""))
  ) {
    return json(400, { error: "invalid_result_event" });
  }
  const metadata = safeObject(context.body.metadata);
  if (JSON.stringify(metadata).length > 8192) {
    return json(413, { error: "event_metadata_too_large" });
  }
  const { data, error } = await context.supabase.rpc(
    "result_hub_insert_event",
    {
      p_user_id: context.userID,
      p_analysis_id: context.analysis.id,
      p_client_event_id: context.body.client_event_id,
      p_funnel_session_id: isUUID(context.body.funnel_session_id)
        ? context.body.funnel_session_id
        : null,
      p_event_name: context.body.event_name,
      p_section: context.body.section ?? null,
      p_target_kind: context.body.target_kind ?? null,
      p_target_key: cleanString(context.body.target_key, 200) || null,
      p_plan_snapshot: context.tier,
      p_client_platform: cleanString(context.body.client_platform, 40) || null,
      p_client_app_version: cleanString(context.body.client_app_version, 40) ||
        null,
      p_client_app_build: cleanString(context.body.client_app_build, 40) ||
        null,
      p_metadata: metadata,
    },
  );
  if (error) {
    return json(422, { error: "event_write_failed", detail: error.message });
  }
  return json(200, { ok: true, inserted: data === true });
}

async function handleReportIntent(context: Context) {
  const section = context.body.section;
  const format = context.body.format;
  const selected = [
    ...new Set(
      (context.body.selected_item_keys ?? [])
        .filter(isUUID)
        .map(canonicalUUID),
    ),
  ].slice(0, 100);
  if (!section || !format || selected.length === 0) {
    return json(400, { error: "invalid_report_selection" });
  }
  const reportKind = section === "risk_analysis" && format === "pdf" &&
      context.body.report_kind === "standard"
    ? "standard"
    : section === "risk_analysis"
    ? "riskAnalysis"
    : "standard";
  if (section !== "risk_analysis" && !isPaidTier(context.tier)) {
    return json(403, { error: "premium_required" });
  }
  const sections = await loadAuthoritativeSections(context);
  const candidates = section === "risk_analysis"
    ? sections.risk
    : section === "expert_recommendations"
    ? sections.expertFull
    : section === "training_recommendations"
    ? sections.trainingFull
    : sections.notebookFull;
  const byID = new Map(candidates.map((item) => {
    const rawID = String(item.id ?? "");
    return [isUUID(rawID) ? canonicalUUID(rawID) : rawID, item] as const;
  }));
  if (selected.some((key) => !byID.has(key))) {
    return json(422, { error: "report_selection_out_of_scope" });
  }
  const items = selected.map((key) => byID.get(key) as Record<string, unknown>);
  const quotaKind = reportKind;
  const { data: quota, error: quotaError } = await context.supabase.rpc(
    "check_report_quota_eligibility_v2",
    {
      p_user_id: context.userID,
      p_kind: quotaKind,
      p_format: format,
      p_content_scope: section,
    },
  );
  if (quotaError) return json(500, { error: "report_quota_check_failed" });
  if (safeObject(quota).allowed !== true) {
    return json(403, {
      error: safeObject(quota).error_code ?? "report_quota_exceeded",
      quota,
    });
  }
  const snapshot = {
    contract_version: "report-export-intent-v1",
    analysis: {
      id: context.analysis.id,
      title: context.analysis.title,
      created_at: context.analysis.created_at,
      analysis_sector: context.analysis.analysis_sector,
      output_language: context.language,
    },
    content_scope: section,
    report_kind: reportKind,
    items,
    disclaimers: section === "approved_notebook"
      ? (context.language === "tr"
        ? "Onaylı Defter önerisi/taslağıdır; uzman değerlendirmesi gerekir."
        : "Safety Log recommendation; expert review is required.")
      : section === "expert_recommendations"
      ? (context.language === "tr"
        ? "Bağlayıcı uzman görüşü değildir; saha teyidi gerekir."
        : "Not a binding expert opinion; field verification is required.")
      : null,
  };
  const { data, error } = await context.supabase.rpc(
    "result_hub_create_report_intent",
    {
      p_user_id: context.userID,
      p_analysis_id: context.analysis.id,
      p_content_scope: section,
      p_format: format,
      p_selected_item_keys: selected,
      p_content_snapshot: snapshot,
      p_source_edit_version: context.analysis.analysis_edit_version ?? 0,
      p_projection_version: section === "approved_notebook"
        ? APPROVED_NOTEBOOK_PROJECTION_VERSION
        : ANALYSIS_RESULT_CONTRACT_VERSION,
      p_tier_snapshot: context.tier,
      p_request_id: cleanString(context.body.request_id, 100) || null,
    },
  );
  if (error) {
    return json(422, { error: "report_intent_failed", detail: error.message });
  }
  return json(200, { ok: true, report_intent: data });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json(500, { error: "not_configured" });
  }
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader) return json(401, { error: "auth_required" });

  let body: Body;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }
  if (!isUUID(body.analysis_id)) {
    return json(400, { error: "invalid_analysis_id" });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const token = authHeader.replace(/^Bearer\s+/i, "");
  const { data: { user }, error: authError } = await supabase.auth.getUser(
    token,
  );
  if (authError || !user) return json(401, { error: "auth_invalid" });

  const [
    { data: flagRow },
    { data: allowlistRow, error: allowlistError },
    { data: subscription },
    { data: analysis },
  ] = await Promise.all([
    supabase.from("app_feature_flags").select("value")
      .eq("key", "analysis_result_hub_v1").maybeSingle(),
    supabase.rpc("result_hub_allowlist_decision", { p_user_id: user.id }),
    supabase.from("user_subscriptions")
      .select("tier,status,current_period_ends_at")
      .eq("user_id", user.id).maybeSingle(),
    supabase.from("analyses")
      .select(
        "id,user_id,status,title,created_at,analysis_edit_version,analysis_sector,output_language,rollout_snapshot,localization_snapshot,approved_book_observation_basis,companies(hazard_class)",
      )
      .eq("id", body.analysis_id).eq("user_id", user.id).maybeSingle(),
  ]);
  if (!analysis || analysis.status !== "completed") {
    return json(404, { error: "analysis_not_found" });
  }
  if (allowlistError) {
    console.error(
      "analysis-result-sections allowlist failed",
      cleanString(allowlistError.code, 40),
    );
    return json(503, { error: "rollout_authorization_failed" });
  }
  const tier = resolveResultHubTier(subscription);
  const flag = safeObject(flagRow?.value);
  const allowlisted = allowlistRow === true;
  const capability = body.client_capabilities?.analysis_result_hub_v1 === true;
  const enabled = resultHubGateOpen({
    flag,
    allowlisted,
    capability,
    platform: cleanString(body.client_platform, 40).toLowerCase(),
    build: cleanString(body.client_app_build, 40),
  });
  if (!enabled) {
    const mode = cleanString(flag.rollout_mode, 40).toLowerCase();
    const gateReason = flagRow?.value == null
      ? "feature_flag_missing"
      : flag.kill_switch === true
      ? "kill_switch_enabled"
      : !capability
      ? "client_capability_missing"
      : mode === "user_allowlist" && !allowlisted
      ? "user_allowlist_miss"
      : "rollout_gate_closed";
    return json(200, {
      enabled: false,
      contract_version: ANALYSIS_RESULT_CONTRACT_VERSION,
      reason: gateReason,
    });
  }

  const context: Context = {
    supabase,
    userID: user.id,
    body,
    analysis: analysis as Record<string, unknown>,
    tier,
    language: languageFor(body, analysis as Record<string, unknown>),
  };
  try {
    switch (body.action ?? "load") {
      case "load":
        return await handleLoad(context);
      case "mutate_notebook":
        return await handleNotebookMutation(context);
      case "feedback":
        return await handleFeedback(context);
      case "event":
        return await handleEvent(context);
      case "create_report_intent":
        return await handleReportIntent(context);
    }
  } catch (error) {
    console.error("analysis-result-sections failed", String(error));
    return json(500, { error: "result_hub_failed" });
  }
});
