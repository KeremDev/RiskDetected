import {
  assertCriticalCandidateFates,
  routeCandidates,
} from "../supabase/functions/analyze-v4/claim-router.ts";
import type {
  ProviderPhotoOutput,
  RoutedItem,
} from "../supabase/functions/analyze-v4/contracts.ts";
import {
  V4_PROMPT_VERSION,
  V4_ROUTER_VERSION,
} from "../supabase/functions/analyze-v4/contracts.ts";
import { normalizeCandidates } from "../supabase/functions/analyze-v4/evidence-normalizer.ts";

type ReplayRow = {
  photo_index?: number;
  analysis_sector?: string | null;
  normalized_output?: ProviderPhotoOutput;
};

function canonicalItem(item: RoutedItem) {
  return {
    item_class: item.item_class,
    is_scored: item.is_scored,
    criticality: item.criticality,
    title: item.title,
    description: item.description,
    recommended_action: item.recommended_action,
    root_cause_text: item.root_cause_text,
    source_photo_indices: [...item.source_photo_indices].sort(),
    display_group: item.display_group,
    display_order: item.display_order,
    fk_probability: item.fk_probability ?? null,
    fk_frequency: item.fk_frequency ?? null,
    fk_severity: item.fk_severity ?? null,
    fk_band: item.fk_band ?? null,
    m5_probability: item.m5_probability ?? null,
    m5_severity: item.m5_severity ?? null,
    m5_band: item.m5_band ?? null,
    route_reason: item.internal_priority.route_reason ?? null,
  };
}

function stable(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stable).join(",")}]`;
  if (value && typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, child]) => `${JSON.stringify(key)}:${stable(child)}`);
    return `{${entries.join(",")}}`;
  }
  return JSON.stringify(value);
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

const rawInput = JSON.parse(await new Response(Deno.stdin.readable).text());
const rows: ReplayRow[] = Array.isArray(rawInput)
  ? rawInput
  : Array.isArray(rawInput?.rows)
  ? rawInput.rows
  : [];
if (rows.length === 0) throw new Error("v4_replay_rows_required");

const photos = rows
  .filter((row) => row.normalized_output)
  .map((row) => ({
    photoIndex: Number(row.photo_index) || 1,
    output: row.normalized_output!,
  }))
  .sort((left, right) => left.photoIndex - right.photoIndex);
const candidates = photos.flatMap(({ photoIndex, output }) =>
  normalizeCandidates(output, photoIndex)
);
const routed = routeCandidates({
  candidates,
  photoOutputs: photos,
  sectorID: typeof rows[0]?.analysis_sector === "string"
    ? rows[0].analysis_sector
    : null,
});
assertCriticalCandidateFates(
  candidates,
  routed.items,
  routed.hardRejections,
  routed.ledger,
);

const semantic = {
  prompt_version: V4_PROMPT_VERSION,
  router_version: V4_ROUTER_VERSION,
  photo_count: photos.length,
  candidate_count: candidates.length,
  critical_candidate_count: candidates.filter((candidate) =>
    candidate.criticality === "fatal" || candidate.criticality === "permanent"
  ).length,
  items: routed.items.map(canonicalItem).sort((left, right) =>
    stable(left).localeCompare(stable(right))
  ),
  hard_rejections: routed.hardRejections.map((entry) => ({
    reason_code: entry.reason_code,
    criticality: entry.criticality,
  })).sort((left, right) => stable(left).localeCompare(stable(right))),
  ledger: routed.ledger.map((entry) => ({
    from_state: entry.from_state,
    to_state: entry.to_state,
    reason_code: entry.reason_code,
    evidence_level: entry.evidence_level ?? null,
  })).sort((left, right) => stable(left).localeCompare(stable(right))),
};

console.log(JSON.stringify({
  replay_version: "v4-provider-output-replay-v1",
  semantic_sha256: await sha256(stable(semantic)),
  ...semantic,
}, null, 2));
