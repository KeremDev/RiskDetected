import {
  assertCriticalCandidateFates,
  routeCandidates,
} from "../supabase/functions/analyze-v4/claim-router.ts";
import { adaptV3PhotoRunForV4Replay } from "../supabase/functions/analyze-v4/replay-adapter.ts";

type ReplayRow = {
  analysis_id?: string;
  photo_index?: number;
  analysis_sector?: string | null;
  normalized_output?: unknown;
};

const input = await new Response(Deno.stdin.readable).text();
const rows: ReplayRow[] = JSON.parse(input);
const counts: Record<string, number> = {};
let rawCandidates = 0;
let criticalCandidates = 0;
let criticalSilentDrops = 0;
for (const row of rows) {
  const photoIndex = Number(row.photo_index) || 1;
  const adapted = adaptV3PhotoRunForV4Replay(row.normalized_output, photoIndex);
  const routed = routeCandidates({
    candidates: adapted.candidates,
    photoOutputs: [{ photoIndex, output: adapted.output }],
    sectorID: typeof row.analysis_sector === "string"
      ? row.analysis_sector
      : null,
  });
  rawCandidates += adapted.candidates.length;
  criticalCandidates += adapted.candidates.filter((candidate) =>
    ["fatal", "permanent"].includes(candidate.criticality)
  ).length;
  try {
    assertCriticalCandidateFates(
      adapted.candidates,
      routed.items,
      routed.hardRejections,
      routed.ledger,
    );
  } catch {
    criticalSilentDrops += 1;
  }
  for (const item of routed.items) {
    counts[item.item_class] = (counts[item.item_class] ?? 0) + 1;
  }
  counts.hard_reject = (counts.hard_reject ?? 0) + routed.hardRejections.length;
}

console.log(JSON.stringify(
  {
    replay_version: "v4-shadow-replay-v1",
    photo_runs: rows.length,
    raw_candidates: rawCandidates,
    critical_candidates: criticalCandidates,
    critical_silent_drops: criticalSilentDrops,
    routed_counts: counts,
    provider_calls: 0,
  },
  null,
  2,
));
