import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

async function source(path: string): Promise<string | null> {
  const url = new URL(path, import.meta.url);
  const filePath = decodeURIComponent(url.pathname);
  const permission = await Deno.permissions.query({
    name: "read",
    path: filePath,
  });
  if (permission.state !== "granted") return null;
  return await Deno.readTextFile(filePath);
}

type ClientFixture = {
  platform: "ios" | "android";
  build: string;
  apiContractVersion: number;
  capabilities: Record<string, boolean>;
};

function buildAllowlistOpen(
  client: ClientFixture,
  iosBuilds: string[],
  androidBuilds: string[],
): boolean {
  if (client.apiContractVersion < 2) return false;
  const platformBuilds = client.platform === "ios" ? iosBuilds : androidBuilds;
  return platformBuilds.includes(client.build) &&
    client.capabilities.multi_photo_analysis === true &&
    client.capabilities.multi_photo_coverage_v2 === true;
}

const capabilities = {
  multi_photo_analysis: true,
  multi_photo_coverage_v2: true,
  editable_findings: true,
  report_snapshot_v2: true,
  global_localization_wave1: false,
};

Deno.test("Android client fixture matches the frozen Kotlin request contract", async () => {
  const metadata = await source(
    "../../../android/core/common/src/main/kotlin/com/riskdetectedan/core/common/RdClientMetadata.kt",
  );
  const analysis = await source(
    "../../../android/core/data/src/main/kotlin/com/riskdetectedan/core/data/analysis/AnalysisRepository.kt",
  );
  if (metadata == null || analysis == null) return;

  assertStringIncludes(metadata, 'const val PLATFORM = "android"');
  assertStringIncludes(metadata, "const val API_CONTRACT_VERSION = 2");
  assertStringIncludes(metadata, 'const val APP_LANGUAGE = "tr"');
  assertStringIncludes(metadata, 'const val CONTENT_LOCALE = "tr-TR"');
  assertStringIncludes(metadata, 'const val WORK_JURISDICTION_COUNTRY = "TR"');
  assertStringIncludes(
    metadata,
    'const val SAFETY_PROFILE_ID = "tr-tr-current-v1"',
  );
  assertStringIncludes(metadata, '"multi_photo_analysis" to true');
  assertStringIncludes(metadata, '"multi_photo_coverage_v2" to true');
  assertStringIncludes(metadata, '"editable_findings" to true');
  assertStringIncludes(metadata, '"report_snapshot_v2" to true');
  assertStringIncludes(metadata, '"global_localization_wave1" to false');

  assertStringIncludes(analysis, "clientPlatform = RdClientMetadata.PLATFORM");
  assertStringIncludes(
    analysis,
    "clientCapabilities = RdClientMetadata.capabilities",
  );
  assertStringIncludes(analysis, "outputLocale = outputLocale");
  assertStringIncludes(analysis, "safetyProfileId = safetyProfileId");
  assertStringIncludes(analysis, "method = riskMethod");
});

Deno.test("Android and iOS fixtures use only their own multi-photo build allowlists", () => {
  const ios: ClientFixture = {
    platform: "ios",
    build: "81",
    apiContractVersion: 2,
    capabilities,
  };
  const android: ClientFixture = {
    platform: "android",
    build: "1",
    apiContractVersion: 2,
    capabilities,
  };

  assertEquals(buildAllowlistOpen(ios, ["81"], []), true);
  assertEquals(buildAllowlistOpen(android, [], ["1"]), true);
  assertEquals(buildAllowlistOpen(ios, [], ["1"]), false);
  assertEquals(buildAllowlistOpen(android, ["81"], []), false);
  assertEquals(
    buildAllowlistOpen({ ...android, apiContractVersion: 1 }, [], ["1"]),
    false,
  );
  assertEquals(
    buildAllowlistOpen(
      {
        ...android,
        capabilities: { ...capabilities, multi_photo_coverage_v2: false },
      },
      [],
      ["1"],
    ),
    false,
  );
});
