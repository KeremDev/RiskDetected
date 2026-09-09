import {
  assert,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

const analyzeSource = await Deno.readTextFile(
  new URL("./index.ts", import.meta.url),
);
const migrationSource = await Deno.readTextFile(
  new URL(
    "../../migrations/20260828142828_normalize_localized_onboarding_credentials.sql",
    import.meta.url,
  ),
);
const rawSanitizerMigrationSource = await Deno.readTextFile(
  new URL(
    "../../migrations/20260828172000_sanitize_english_onboarding_raw_answers.sql",
    import.meta.url,
  ),
);

Deno.test("English onboarding uses the localized professional role and ignores Turkish credentials", () => {
  assertStringIncludes(
    analyzeSource,
    '"certificate_class,hazard_classes,sectors,audit_frequency,raw_answers,updated_at"',
  );
  assertStringIncludes(
    analyzeSource,
    "const professionalRole = isEnglish ? onboardingProfessionalRole(row) : null;",
  );
  assertStringIncludes(
    analyzeSource,
    "const hazardClasses = isEnglish ? [] : safeStringArray(row?.hazard_classes);",
  );
  assertStringIncludes(
    analyzeSource,
    "professional_role_data: ${serializeUntrustedPromptValue(professionalRole)}",
  );
  assert(
    !analyzeSource.includes(
      "professional_role_data: ${serializeUntrustedPromptValue(certificateClass)}",
    ),
  );
});

Deno.test("English onboarding upsert clears stale Turkish-only credentials", () => {
  assertStringIncludes(
    migrationSource,
    "v_is_english := v_app_language = 'en';",
  );
  assertStringIncludes(migrationSource, "when v_is_english then null");
  assertStringIncludes(migrationSource, "when v_is_english then '{}'::text[]");
  assertStringIncludes(migrationSource, "answers.raw_answers->>'app_language'");
  assertStringIncludes(
    migrationSource,
    "nullif(btrim(profile.app_language), '')",
  );
});

Deno.test("English onboarding also removes stale Turkish terminology from raw JSON", () => {
  assertStringIncludes(
    rawSanitizerMigrationSource,
    "before insert or update on public.user_onboarding_answers",
  );
  assertStringIncludes(
    rawSanitizerMigrationSource,
    "'certificate_class', null",
  );
  assertStringIncludes(
    rawSanitizerMigrationSource,
    "'hazard_classes', '[]'::jsonb",
  );
});
