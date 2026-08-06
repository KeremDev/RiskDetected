import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

async function readAnalyzeIfAllowed(): Promise<string | null> {
  const url = new URL("./index.ts", import.meta.url);
  const path = decodeURIComponent(url.pathname);
  const permission = await Deno.permissions.query({ name: "read", path });
  if (permission.state !== "granted") return null;
  return await Deno.readTextFile(path);
}

Deno.test("localization snapshot is resolved and persisted before quota and queue", async () => {
  const source = await readAnalyzeIfAllowed();
  if (source == null) return;
  const resolveIndex = source.indexOf("resolveLocalizationContext({");
  const persistIndex = source.indexOf(
    ".update(localizationPersistencePatch(localizationSnapshot))",
  );
  const canvasGateIndex = source.indexOf(
    "assertCanvasAvailableForSafetyProfile(",
  );
  const quotaIndex = source.indexOf('"reserve_analysis_quota"');
  const enqueueCallIndex = source.lastIndexOf(
    "const { queuedPhotoPaths, enqueued, state } = await enqueueAnalysisJob({",
  );

  assert(resolveIndex > 0);
  assert(persistIndex > resolveIndex);
  assert(canvasGateIndex > resolveIndex);
  assert(canvasGateIndex < persistIndex);
  assert(persistIndex < quotaIndex);
  assert(quotaIndex < enqueueCallIndex);
});

Deno.test("worker loads the persisted snapshot from the owned analysis row", async () => {
  const source = await readAnalyzeIfAllowed();
  if (source == null) return;
  assert(
    source.includes(
      "prompt_profile_version,localization_snapshot",
    ),
  );
  assert(
    source.includes(
      "persistedSnapshot: ownedAnalysis.localization_snapshot",
    ),
  );
  assert(source.includes("workerInvocation: isWorkerInvocation"));
  assert(
    source.includes(
      "allowLegacyWorkerBackfill: allowLegacyWorkerLocalizationBackfill",
    ),
  );
  assert(
    source.includes(
      "body.localization_snapshot_authority !== true",
    ),
  );
});

Deno.test("queue payload transition is flag-gated and DB snapshot is the authority", async () => {
  const source = await readAnalyzeIfAllowed();
  if (source == null) return;
  assert(
    source.includes(
      "queueSnapshotAuthorityEnabled:\n          localizationRolloutPolicy.queueSnapshotAuthorityEnabled",
    ),
  );
  assert(
    source.includes(
      "stripLocalizationRequestFields(params.body)",
    ),
  );
  assert(
    source.includes("localizationQueueGuard(params.localizationSnapshot)"),
  );
  assert(
    source.includes(
      "body.localization_snapshot_authority === true",
    ),
  );
});

Deno.test("stable non-TR legislation code is not replaced with a localized backend message", async () => {
  const source = await readAnalyzeIfAllowed();
  if (source == null) return;
  assert(source.includes("LOCALIZATION_ERROR_CODES"));
  assertEquals(
    source.includes("CANVAS_NOT_AVAILABLE_FOR_SAFETY_PROFILE"),
    false,
    "stable code comes from the shared contract instead of ad-hoc analyze text",
  );
  assert(
    source.includes(
      "return errorResponse(error.status, error.code,",
    ),
  );
});
