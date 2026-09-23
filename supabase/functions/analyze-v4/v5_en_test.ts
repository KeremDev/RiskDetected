// deno-lint-ignore-file no-import-prefix -- Match the pinned Deno std used by the existing suite.
import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/testing/asserts.ts";
import {
  parseV5Output,
  routeV5Findings,
  sanitizeFreeText,
} from "./v5-engine.ts";
import {
  buildV5PromptEN,
  buildV5SplitPromptEN,
  V5_FREE_PROMPT_EN,
  V5_PROMPT_EN_VERSION,
  v5ProfileDirectives,
} from "./v5-prompt-en.ts";
import {
  buildV5Prompt,
  buildV5SplitPrompt,
  V5_FREE_PROMPT,
} from "./v5-prompt.ts";
import { V5_RESPONSE_SCHEMA } from "./v5-contracts.ts";
import { sendStructuredGemini } from "./provider.ts";
import { V4_GEMINI3_OUTPUT_LANGUAGE_LINE } from "./prompt.ts";
import {
  computeV5PromptENSHA256,
  computeV5PromptSHA256,
} from "./prompt-integrity.ts";
import {
  v5EnglishLanguageFailure,
  v5EnglishRetryPrompt,
} from "./v5-language.ts";

// ea39b232 (en-US) and 2f496b0a (en-GB): the Turkish prompt with a single
// "output language: en" line published every finding in Turkish, citing
// Turkish regulation to a site in the United States.

const TURKISH_LETTERS = /[çğıöşüÇĞİÖŞÜ]/u;
// Schema identifiers the English prompt must name verbatim.
const SCHEMA_IDENTIFIERS = /olasılık|şiddet|gerekçe/gu;

function finding(overrides: Record<string, unknown> = {}) {
  return {
    finding_key: "f1",
    layers: [3],
    title: "Unprotected slab edge on the upper floor.",
    category: "Work at height",
    description: "A worker stands at an open slab edge without a guardrail.",
    event_path: "Open slab edge → loss of balance → fatal fall.",
    root_cause: "Edge protection has not been installed.",
    regulatory_references: ["Regulation — 29 CFR 1926.501."],
    fine_kinney: {
      "olasılık": 6,
      frekans: 6,
      "şiddet": 40,
      "gerekçe": "The edge is open and the worker is standing at it.",
    },
    immediate_control: "Stop work at the upper-floor slab edge.",
    corrective_steps: ["Close the edge with guardrails.", "Restrict access."],
    preventive_measure: "Tie the edge-protection plan to the work programme.",
    training_recommendation: "Provide work-at-height training.",
    ppe_recommendation: "Full-body harness with a twin lanyard.",
    evidence_region: { x_min: 0.37, y_min: 0.29, x_max: 0.43, y_max: 0.33 },
    confidence: 0.8,
    needs_field_verification: false,
    ...overrides,
  };
}

function output(findings: unknown[], assets: string[] = []) {
  return parseV5Output(JSON.stringify({
    scene_summary: "A building site.",
    layer_scan: [{ layer: 3, result: "tehlike_var", note: "Open edge." }],
    observed_assets: assets,
    positive_controls: [{
      title: "Hard hats worn",
      description: "Both workers wear hard hats.",
    }],
    findings,
  }));
}

const RELEASED_V5_PROMPT_EN_SHA256 =
  "59f5a590e068627c4452d79d64bfb43bc1f065833a72a3ee2c7788ff707125f4";

Deno.test("English output gate rejects a Turkish finding even among English findings", () => {
  const mixed = output([
    finding(),
    finding({
      finding_key: "f2",
      title: "Sabitlenmemiş basınçlı gaz tüpü.",
      description:
        "Çalışma alanında bulunan gaz tüpü sabitlenmemiş olup yanında yanıcı malzemeler vardır.",
      immediate_control: "Gaz tüpünü güvenli bir yere alın ve sabitleyin.",
    }),
  ]);
  assertEquals(v5EnglishLanguageFailure(mixed), "finding_2");
});

Deno.test("English output gate allows English prose with a Turkish place name", () => {
  const english = output([finding({
    description:
      "The worker stands next to the İstanbul-labelled cabinet, where the exposed cable crosses the walkway.",
  })]);
  assertEquals(v5EnglishLanguageFailure(english), null);
});

Deno.test("English language retry keeps the base contract and explicitly corrects prose", () => {
  const base = buildV5PromptEN({
    photoIndex: 1,
    photoCount: 1,
    sectorID: "general",
    safetyProfileID: "en-us-generic-v1",
  });
  const retry = v5EnglishRetryPrompt(base);
  assertStringIncludes(retry, base);
  assertStringIncludes(retry, "previous response used Turkish prose");
  assertStringIncludes(
    retry,
    "Return only the complete JSON object in English",
  );
});

Deno.test("Gemini receives English V5 without Turkish suffix and Turkish V5 unchanged", async () => {
  const englishPrompts = [
    buildV5PromptEN({
      photoIndex: 1,
      photoCount: 1,
      sectorID: "general",
      safetyProfileID: "en-us-generic-v1",
    }),
    buildV5SplitPromptEN({
      photoIndex: 1,
      photoCount: 1,
      sectorID: "general",
      safetyProfileID: "en-us-generic-v1",
      packed: [{
        title: "Unprotected edge",
        layers: [3, 7],
        description: "Two distinct hazards are visible.",
      }],
      scanNotes: [],
    }),
  ];
  const turkishPrompts = [
    buildV5Prompt({
      photoIndex: 1,
      photoCount: 1,
      outputLanguage: "tr",
      sectorID: "general",
    }),
    buildV5SplitPrompt({
      photoIndex: 1,
      photoCount: 1,
      outputLanguage: "tr",
      sectorID: "general",
      packed: [{
        title: "Korunmasız kenar",
        layers: [3, 7],
        description: "İki farklı tehlike görünür.",
      }],
      scanNotes: [],
    }),
  ];
  const originalFetch = globalThis.fetch;
  let sentPrompt = "";
  globalThis.fetch = ((_url: string | URL | Request, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body ?? "{}"));
    sentPrompt = String(body.contents?.[0]?.parts?.[0]?.text ?? "");
    return Promise.resolve(
      new Response(
        JSON.stringify({
          candidates: [{
            finishReason: "STOP",
            content: { parts: [{ text: "{}" }] },
          }],
        }),
        { status: 200 },
      ),
    );
  }) as typeof fetch;
  try {
    for (const prompt of [...englishPrompts, ...turkishPrompts]) {
      const turkish = turkishPrompts.includes(prompt);
      await sendStructuredGemini({
        apiKey: "synthetic-key",
        model: "gemini-3.5-flash-lite",
        prompt,
        imageData: "AA==",
        mimeType: "image/png",
        timeoutMs: 10_000,
        thinkingBudget: 3072,
        thinkingLevel: "HIGH",
        maxOutputTokens: 32768,
        serviceTier: "standard",
        appendTurkishLanguageRule: turkish,
      }, V5_RESPONSE_SCHEMA);
      assertEquals(
        sentPrompt,
        turkish ? `${prompt}${V4_GEMINI3_OUTPUT_LANGUAGE_LINE}` : prompt,
      );
    }
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("English v5 prompt cannot change without a version bump", async () => {
  assertEquals(V5_PROMPT_EN_VERSION, "v7-free-core-multidisciplinary-en-v1");
  assertEquals(await computeV5PromptENSHA256(), RELEASED_V5_PROMPT_EN_SHA256);
});

Deno.test("English prompt leaves the Turkish hash where it was", async () => {
  assertEquals(
    await computeV5PromptSHA256(),
    "17092314b40c97e3e8e4894b01096bfdcc038960be4537b12dc73f32d6e0a985",
  );
  assert(V5_FREE_PROMPT !== V5_FREE_PROMPT_EN);
});

Deno.test("English prompt carries no Turkish outside schema identifiers", () => {
  for (
    const prompt of [
      buildV5PromptEN({
        photoIndex: 1,
        photoCount: 1,
        sectorID: "construction",
        safetyProfileID: "en-us-generic-v1",
        analysisContext: "general",
      }),
      buildV5SplitPromptEN({
        photoIndex: 1,
        photoCount: 1,
        sectorID: "manufacturing",
        safetyProfileID: "en-gb-generic-v1",
        packed: [{ title: "Cable", layers: [2, 5], description: "A cable." }],
        scanNotes: [{ layer: 5, note: "Cable in water." }],
      }),
    ]
  ) {
    const stripped = prompt.replace(SCHEMA_IDENTIFIERS, "");
    assert(
      !TURKISH_LETTERS.test(stripped),
      stripped.match(/.{0,40}[çğıöşüÇĞİÖŞÜ].{0,40}/u)?.[0],
    );
    assert(!/6331|Mevzuat|Yönetmelik/u.test(prompt));
    assertStringIncludes(prompt, "Site type:");
    assertStringIncludes(prompt, "no legal references");
  }
});

Deno.test("English prompt appends the profile's sealed directives", () => {
  const gb = buildV5PromptEN({
    photoIndex: 1,
    photoCount: 2,
    sectorID: null,
    safetyProfileID: "en-gb-generic-v1",
  });
  assertStringIncludes(gb, "British spelling");
  // A Turkish or unknown profile falls back to the international one.
  assertEquals(
    v5ProfileDirectives("tr-tr-current-v1"),
    v5ProfileDirectives("en-intl-generic-v1"),
  );
  assertEquals(
    v5ProfileDirectives(undefined),
    v5ProfileDirectives("en-intl-generic-v1"),
  );
});

Deno.test("English routing writes English labels and no references", () => {
  const routed = routeV5Findings(
    [{ photoIndex: 1, output: output([finding({ category: "" })]) }],
    { language: "en" },
  );
  const scored = routed.items.find((item) =>
    item.item_class === "observed_finding"
  )!;
  assertEquals(scored.category, "General");
  assertEquals(scored.references_text, "");
  const titles = scored.recommended_measures.map((entry) => entry.title);
  assertEquals(titles, ["Corrective Action", "Preventive Control"]);
  const text = scored.recommended_measures.map((entry) => entry.text).join(" ");
  assertStringIncludes(text, "Personal protective equipment:");
  assertStringIncludes(text, "Training:");
  const positive = routed.items.find((item) =>
    item.item_class === "positive_control"
  )!;
  assertEquals(positive.category, "Positive control");
  for (const item of routed.items) {
    assert(
      !TURKISH_LETTERS.test(JSON.stringify({
        title: item.title,
        category: item.category,
        description: item.description,
        measures: item.recommended_measures,
        references: item.references_text,
      })),
    );
  }
});

Deno.test("English routing skips the Turkish expert registry", () => {
  const records = finding({
    finding_key: "crane_records",
    layers: [19],
    category: "",
    title: "Overhead crane inspection record.",
    description: "An overhead crane is visible above the bay.",
    immediate_control: "Verify the crane's thorough examination report.",
  });
  const routed = routeV5Findings(
    [{ photoIndex: 1, output: output([records], ["overhead_crane"]) }],
    { language: "en" },
  );
  assertEquals(routed.expertCardCount, 0);
  const assurance = routed.items.filter((item) =>
    item.item_class === "assurance_requirement"
  );
  assertEquals(assurance.length, 1);
  assertEquals(assurance[0].category, "Periodic Inspections");
  assertEquals(assurance[0].internal_priority.control_source, "model");
});

Deno.test("Turkish routing is unchanged by default", () => {
  const routed = routeV5Findings([{
    photoIndex: 1,
    output: output([finding({ category: "" })], ["overhead_crane"]),
  }]);
  const scored = routed.items.find((item) =>
    item.item_class === "observed_finding"
  )!;
  assertEquals(scored.category, "Genel");
  assertEquals(scored.references_text, "Regulation — 29 CFR 1926.501.");
  assertEquals(routed.expertCardCount, 1);
});

Deno.test("English sentences claiming an invisible record is missing are cut", () => {
  const result = sanitizeFreeText(
    "The crane is visible. The periodic inspection certificate is missing. Verify the report.",
  );
  assertEquals(result.text, "The crane is visible. Verify the report.");
  assertEquals(result.removed, ["asserts_invisible_absence"]);
  const kept = sanitizeFreeText("Verify the periodic inspection record.");
  assertEquals(kept.removed, []);
});
