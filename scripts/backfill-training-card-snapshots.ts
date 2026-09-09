import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import type { TrainingItemRow } from "../supabase/functions/_shared/training-recommendations/index.ts";
import {
  buildTrainingCardSnapshots,
  persistTrainingCardSnapshots,
} from "../supabase/functions/_shared/training-recommendations/snapshot.ts";

const apply = Deno.args.includes("--apply");
const url = Deno.env.get("SUPABASE_URL")?.trim();
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();

if (!url || !serviceRoleKey) {
  throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required");
}

const supabase = createClient(url, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const pageSize = 100;
let offset = 0;
let processed = 0;
let analysesWithCards = 0;
let cardCount = 0;
let failureCount = 0;

while (true) {
  const { data: analyses, error } = await supabase
    .from("analyses")
    .select("id,user_id,analysis_sector,companies(hazard_class)")
    .eq("status", "completed")
    .order("created_at", { ascending: true })
    .order("id", { ascending: true })
    .range(offset, offset + pageSize - 1);
  if (error) throw new Error(`analysis_page_failed:${error.message}`);
  if (!analyses?.length) break;

  for (const analysis of analyses) {
    try {
      const { data: metadata, error: metadataError } = await supabase.rpc(
        "result_hub_v4_metadata",
        {
          p_user_id: analysis.user_id,
          p_analysis_id: analysis.id,
        },
      );
      if (metadataError) {
        throw new Error(`metadata_failed:${metadataError.message}`);
      }
      const company = analysis.companies &&
          typeof analysis.companies === "object" &&
          !Array.isArray(analysis.companies)
        ? analysis.companies as Record<string, unknown>
        : {};
      const cards = buildTrainingCardSnapshots({
        analysisID: analysis.id,
        sectorID: typeof analysis.analysis_sector === "string"
          ? analysis.analysis_sector.trim() || null
          : null,
        hazardClass: company.hazard_class,
        rows: (Array.isArray(metadata) ? metadata : []) as TrainingItemRow[],
      });
      if (cards.length) analysesWithCards += 1;
      cardCount += cards.length;
      if (apply) {
        await persistTrainingCardSnapshots(supabase, {
          userID: analysis.user_id,
          analysisID: analysis.id,
          cards,
        });
      }
    } catch (error) {
      failureCount += 1;
      console.error(
        "training snapshot backfill row failed",
        error instanceof Error ? error.message.slice(0, 240) : "unknown",
      );
    }
    processed += 1;
  }

  offset += analyses.length;
  if (analyses.length < pageSize) break;
}

console.log(JSON.stringify({
  mode: apply ? "apply" : "dry_run",
  processed,
  analyses_with_cards: analysesWithCards,
  cards: cardCount,
  failures: failureCount,
}));

if (failureCount > 0) Deno.exit(1);
