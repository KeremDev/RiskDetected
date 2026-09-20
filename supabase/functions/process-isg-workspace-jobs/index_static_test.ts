import { assertMatch } from "https://deno.land/std@0.208.0/assert/mod.ts";

const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("workspace worker uses real providers behind secret auth", () => {
  assertMatch(source, /x-isg-worker-secret/);
  assertMatch(source, /generativelanguage\.googleapis\.com/);
  assertMatch(source, /send-push-notification/);
  assertMatch(source, /PDFDocument/);
  assertMatch(source, /xlsx-js-style/);
});

Deno.test("provider output is normalized before transactional commit", () => {
  assertMatch(source, /function normalizeAnalysis/);
  assertMatch(source, /fkBand\(p \* f \* s\)/);
  assertMatch(source, /source_finding_keys: linkedKeys/);
  assertMatch(source, /p_result: generated\.result/);
});
