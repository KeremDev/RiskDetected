// Manual opt-in, synthetic image only. Key stays in memory; never written to artifacts.
import { sendStructuredGemini } from "../supabase/functions/analyze-v4/provider.ts";
import { V5_RESPONSE_SCHEMA } from "../supabase/functions/analyze-v4/v5-contracts.ts";
import { buildV5Prompt } from "../supabase/functions/analyze-v4/v5-prompt.ts";
import { parseV5Output } from "../supabase/functions/analyze-v4/v5-engine.ts";

if (Deno.env.get("RD_ALLOW_SYNTHETIC_FREE_CANARY") !== "1") {
  throw new Error("Explicit canary opt-in required");
}
const key = new TextDecoder().decode(
  (await new Deno.Command("/usr/bin/pbpaste", { stdout: "piped" }).output())
    .stdout,
).trim();
if (!/^AIza[\w-]{30,}$/.test(key)) {
  throw new Error("Expected scoped Gemini key in clipboard");
}
const bytes = await Deno.readFile("/tmp/rd-free-synthetic-scene.png");
const imageData = btoa(
  Array.from(bytes, (b) => String.fromCharCode(b)).join(""),
);
const start = Date.now();
try {
  const result = await sendStructuredGemini({
    apiKey: key,
    model: "gemini-3.5-flash-lite",
    prompt: buildV5Prompt({
      sectorID: null,
      photoIndex: 1,
      photoCount: 1,
      outputLanguage: "tr",
      analysisContext:
        "Sentetik test çizimi; gerçek bir işyeri değildir. Yalnız görünür unsurları değerlendir.",
    }),
    imageData,
    mimeType: "image/png",
    timeoutMs: 110_000,
    thinkingBudget: 32768,
    thinkingLevel: "HIGH",
    maxOutputTokens: 32768,
    serviceTier: "standard",
    billingTier: "free",
  }, V5_RESPONSE_SCHEMA);
  const parsed = parseV5Output(result.text);
  console.log(
    JSON.stringify(
      {
        check: "production_provider_schema_image",
        ok: true,
        http: result.httpStatus,
        durationMs: Date.now() - start,
        finishReason: result.finishReason,
        serviceTier: result.effectiveServiceTier,
        usage: result.usage,
        summary: parsed.scene_summary,
        layerCount: parsed.layer_scan.length,
        findingCount: parsed.findings.length,
      },
      null,
      2,
    ),
  );
} catch (error) {
  const e = error as { message?: string; code?: string; httpStatus?: number };
  console.log(
    JSON.stringify({
      ok: false,
      durationMs: Date.now() - start,
      error: e.message?.replaceAll(key, "[REDACTED]"),
      code: e.code,
      httpStatus: e.httpStatus,
    }),
  );
  Deno.exitCode = 1;
}
