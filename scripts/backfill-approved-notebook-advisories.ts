import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { refreshApprovedNotebookAdvisories } from "../supabase/functions/_shared/approved-notebook-advisory-snapshot.ts";

const apply = Deno.args.includes("--apply");
const analysisArg = Deno.args.find((value) =>
  value.startsWith("--analysis-id=")
);
const analysisID = analysisArg?.slice("--analysis-id=".length).trim() || null;
const limitArg = Deno.args.find((value) => value.startsWith("--limit="));
const parsedLimit = Number.parseInt(
  limitArg?.slice("--limit=".length) ?? "",
  10,
);
const limit = Number.isFinite(parsedLimit) && parsedLimit > 0
  ? parsedLimit
  : Number.POSITIVE_INFINITY;

const url = Deno.env.get("SUPABASE_URL")?.trim();
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
if (!url || !serviceRoleKey) {
  throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required");
}

const supabase = createClient(url, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const pageSize = 50;
let offset = 0;
let processed = 0;
let candidates = 0;
let generated = 0;
let fallbacks = 0;
let reused = 0;
let skippedUserEdited = 0;
let registry = 0;
let failures = 0;
const sample: Array<Record<string, unknown>> = [];

while (processed < limit) {
  let query = supabase
    .from("analyses")
    .select("id,user_id,created_at")
    .eq("status", "completed")
    .order("created_at", { ascending: true })
    .order("id", { ascending: true });
  if (analysisID) query = query.eq("id", analysisID);
  const remaining = Math.min(pageSize, limit - processed);
  const { data: analyses, error } = await query.range(
    offset,
    offset + remaining - 1,
  );
  if (error) throw new Error(`analysis_page_failed:${error.message}`);
  if (!analyses?.length) break;

  for (const analysis of analyses) {
    try {
      const result = await refreshApprovedNotebookAdvisories(supabase, {
        userID: analysis.user_id,
        analysisID: analysis.id,
        apply,
      });
      candidates += result.candidateCount;
      generated += result.generatedCount;
      fallbacks += result.fallbackCount;
      reused += result.reusedCount;
      skippedUserEdited += result.skippedUserEditedCount;
      registry += result.registryCount;
      if (sample.length < 30) {
        sample.push(
          ...result.toUpsert.slice(0, 30 - sample.length).map((row) => ({
            analysis_id: analysis.id,
            source_finding_id: row.source_finding_id,
            advisory_text: row.advisory_text,
            generator_kind: row.generator_kind,
          })),
        );
      }
    } catch (error) {
      failures += 1;
      console.error(
        "notebook advisory backfill row failed",
        analysis.id,
        error instanceof Error ? error.message.slice(0, 300) : "unknown",
      );
    }
    processed += 1;
    if (processed >= limit) break;
  }

  offset += analyses.length;
  if (analysisID || analyses.length < remaining) break;
}

console.log(JSON.stringify(
  {
    mode: apply ? "apply" : "dry_run",
    analysis_id: analysisID,
    processed,
    candidates,
    generated,
    fallbacks,
    reused,
    skipped_user_edited: skippedUserEdited,
    registry,
    failures,
    sample,
  },
  null,
  2,
));

if (failures > 0) Deno.exit(1);
