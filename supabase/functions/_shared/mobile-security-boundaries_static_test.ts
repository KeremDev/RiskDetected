import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

async function repositoryFile(relativePath: string): Promise<string> {
  return await Deno.readTextFile(
    new URL(`../../../${relativePath}`, import.meta.url),
  );
}

Deno.test("iOS OAuth callback cannot establish an implicit bearer-token session", async () => {
  const service = await repositoryFile("App/Services/SupabaseService.swift");

  assertStringIncludes(service, "flowType: .pkce");
  assertStringIncludes(service, '!fragment.contains("access_token=")');
  assertStringIncludes(service, '!fragment.contains("refresh_token=")');
  assertEquals(service.includes("flowType: .implicit"), false);
});

Deno.test("iOS account exports use protected temporary storage with cleanup", async () => {
  const service = await repositoryFile("App/Services/AnalysisService.swift");
  const profile = await repositoryFile("App/Views/Profile/ProfileView.swift");
  const plist = await repositoryFile("Config/RiskDetectedInfo.plist");
  const exportBlock = service.slice(
    service.indexOf("func exportUserData"),
    service.indexOf("func removeUserDataExport"),
  );

  assertStringIncludes(exportBlock, "FileManager.default.temporaryDirectory");
  assertStringIncludes(exportBlock, ".completeFileProtection");
  assertStringIncludes(exportBlock, "isExcludedFromBackup = true");
  assertEquals(exportBlock.includes(".documentDirectory"), false);
  assertStringIncludes(profile, "cleanupExportedDataFile");
  assertStringIncludes(profile, "cleanupPresentedExport");
  assert(
    /<key>LSSupportsOpeningDocumentsInPlace<\/key>\s*<false\/>/.test(plist),
  );
  assert(/<key>UIFileSharingEnabled<\/key>\s*<false\/>/.test(plist));
});

Deno.test("mobile support pickers expose only server-approved attachment types", async () => {
  const ios = await repositoryFile(
    "App/Views/Profile/SupportContactSheet.swift",
  );
  const android = await repositoryFile(
    "android/feature/profile/src/main/kotlin/com/riskdetectedan/feature/profile/SupportScreen.kt",
  );

  assertStringIncludes(ios, "allowedContentTypes: [.jpeg, .png, .pdf]");
  assertEquals(ios.includes("allowedContentTypes: [.item]"), false);
  assertStringIncludes(
    android,
    'arrayOf("image/jpeg", "image/png", "application/pdf")',
  );
  assertEquals(android.includes('arrayOf("*/*")'), false);
});

Deno.test("release input is validated before production secrets and never embedded in shell", async () => {
  const workflow = await repositoryFile(
    ".github/workflows/android-release-candidate.yml",
  );
  const validationJobIndex = workflow.indexOf("validate-release-inputs:");
  const productionJobIndex = workflow.indexOf("signed-aab:");

  assert(validationJobIndex >= 0 && validationJobIndex < productionJobIndex);
  assertStringIncludes(
    workflow,
    "needs: [validate-release-inputs, backend-contracts, android-quality]",
  );
  assertStringIncludes(
    workflow,
    "EXPECTED_VERSION_CODE: ${{ inputs.expected_version_code }}",
  );
  assertStringIncludes(workflow, 'test "$actual" = "$EXPECTED_VERSION_CODE"');
  assertEquals(
    workflow.includes('test "$actual" = "${{ inputs.expected_version_code }}"'),
    false,
  );
});
