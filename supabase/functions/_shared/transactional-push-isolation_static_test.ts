import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

async function readTextIfAllowed(url: URL): Promise<string | null> {
  const path = decodeURIComponent(url.pathname);
  const permission = await Deno.permissions.query({ name: "read", path });
  if (permission.state !== "granted") {
    console.warn(
      `Skipping static source assertion; rerun with --allow-read=${path}`,
    );
    return null;
  }
  return await Deno.readTextFile(path);
}

function assertBestEffortDispatch(params: {
  source: string;
  call: string;
  catchLabel: string;
  successResponse: string;
}) {
  const callIndex = params.source.lastIndexOf(params.call);
  assert(callIndex > 0, `${params.call} invocation is missing`);

  const tryIndex = params.source.lastIndexOf("try {", callIndex);
  assert(
    tryIndex > 0 && callIndex - tryIndex < 120,
    `${params.call} must be directly guarded by try/catch`,
  );

  const catchIndex = params.source.indexOf(
    "} catch (pushError) {",
    callIndex,
  );
  assert(
    catchIndex > callIndex && catchIndex - callIndex < 1_000,
    `${params.call} must catch transport/runtime errors`,
  );

  const successIndex = params.source.indexOf(
    params.successResponse,
    catchIndex,
  );
  assert(
    successIndex > catchIndex,
    `${params.call} failure must preserve the successful response`,
  );

  const catchBlock = params.source.slice(catchIndex, successIndex);
  assertStringIncludes(catchBlock, params.catchLabel);
  assertEquals(catchBlock.includes("throw pushError"), false);
  assertEquals(catchBlock.includes("return errorResponse("), false);
  assertEquals(catchBlock.includes("return json(500"), false);
}

Deno.test("transactional push failures cannot fail finalized analysis", async () => {
  const source = await readTextIfAllowed(
    new URL("../analyze/index.ts", import.meta.url),
  );
  if (source == null) return;

  const persistedIndex = source.lastIndexOf(
    'updateUsagePersistence(supabase, successUsageLogID, "persisted")',
  );
  const callIndex = source.lastIndexOf("await sendAnalysisCompletePush({");
  assert(persistedIndex > 0 && callIndex > persistedIndex);

  assertBestEffortDispatch({
    source,
    call: "await sendAnalysisCompletePush({",
    catchLabel: "after finalization",
    successResponse: "return new Response(",
  });
});

Deno.test("transactional push failures cannot fail persisted PDF report", async () => {
  const source = await readTextIfAllowed(
    new URL("../register-report/index.ts", import.meta.url),
  );
  if (source == null) return;

  const reportErrorIndex = source.lastIndexOf("if (reportError)");
  const callIndex = source.lastIndexOf("await sendReportReadyPush({");
  assert(reportErrorIndex > 0 && callIndex > reportErrorIndex);

  assertBestEffortDispatch({
    source,
    call: "await sendReportReadyPush({",
    catchLabel: "after PDF persistence",
    successResponse: "return json(200, report);",
  });
});

Deno.test("transactional push failures cannot fail persisted Excel report", async () => {
  const source = await readTextIfAllowed(
    new URL("../generate-excel-report/index.ts", import.meta.url),
  );
  if (source == null) return;

  const reportErrorIndex = source.lastIndexOf("if (reportError)");
  const callIndex = source.lastIndexOf("await sendReportReadyPush({");
  assert(reportErrorIndex > 0 && callIndex > reportErrorIndex);

  assertBestEffortDispatch({
    source,
    call: "await sendReportReadyPush({",
    catchLabel: "after Excel persistence",
    successResponse: "return json(200, {",
  });
});

Deno.test("three-photo UI fixture never references a fourth photo", async () => {
  const source = await readTextIfAllowed(
    new URL("../../../App/Services/AnalysisService.swift", import.meta.url),
  );
  const uiTests = await readTextIfAllowed(
    new URL(
      "../../../RiskDetectedUITests/RiskDetectedUITests.swift",
      import.meta.url,
    ),
  );
  if (source == null || uiTests == null) return;

  const fixtureStart = source.indexOf(
    "private static func uiTestResultBundle(",
  );
  const fixtureEnd = source.indexOf(
    "private static func uiTestFindingID(",
    fixtureStart,
  );
  assert(fixtureStart > 0 && fixtureEnd > fixtureStart);

  const fixture = source.slice(fixtureStart, fixtureEnd);
  assertStringIncludes(fixture, "let photos = (1...3).map");
  assertEquals(fixture.includes("defaultSourcePhotoIndices = [4]"), false);
  assertEquals(fixture.includes("defaultSourcePhotoIndices = [2, 4]"), false);
  assertEquals(uiTests.includes('waitFor("Foto 4"'), false);
  assertStringIncludes(uiTests, 'waitFor("result.hub.analysis_photo.3"');
});
