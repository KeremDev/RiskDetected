import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";
import { scanContent, scanTypeScript } from "./localization_inventory.mjs";

function scan(source) {
  const directory = mkdtempSync(join(tmpdir(), "rd-localization-inventory-"));
  try {
    const path = join(directory, "send-welcome-email.ts");
    writeFileSync(path, source);
    const entries = [];
    scanTypeScript(path, entries);
    return entries;
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

test("multiline logs are ignored, following API errors retain text and line", () => {
  const entries = scan([
    'console.error(',
    '  "welcome email profile localization repair failed",',
    '  JSON.stringify({ reason: "Internal diagnostic (not copy)" }),',
    ');',
    'return { message: "E-posta gönderilemedi" };',
  ].join("\n"));
  assert.deepEqual(entries.map(({ source_tr, line }) => [source_tr, line]),
    [["E-posta gönderilemedi", 5]]);
});

test("console-like text in a user string is not suppressed", () => {
  assert.equal(scan('const message = "Use console.error() to report this issue";').length, 1);
});

test("comments and string parentheses do not swallow copy following logs", () => {
  const entries = scan('console.warn(/* ) */ "Internal (diagnostic)");\nreturn { message: "Rapor oluşturulamadı" };');
  assert.deepEqual(entries.map(x => x.source_tr), ["Rapor oluşturulamadı"]);
});

test("only marked machine prompts are ignored, surrounding API copy is kept", () => {
  const entries = scan([
    'const before = "İstek alınamadı";',
    '// localization-inventory: machine-prompt-begin',
    'const prompt = "Türkçe öneri üret";',
    '// localization-inventory: machine-prompt-end',
    'const after = "Rapor hazırlanamadı";',
  ].join("\n"));
  assert.deepEqual(entries.map(x => x.source_tr), ["İstek alınamadı", "Rapor hazırlanamadı"]);
});

test("malformed log cannot hide the remainder of the source", () => {
  assert.ok(scan('console.error(\nconst message = "İstek başarısız oldu";')
    .some(x => x.source_tr === "İstek başarısız oldu"));
});

test("versioned safety catalogues remain separate from application-copy inventory", () => {
  const files = [
    "expert-recommendations/registry.tr.ts",
    "expert-recommendations/engine.ts",
    "approved-notebook-advisory-language.ts",
  ];
  for (const file of files) {
    const entries = [];
    scanTypeScript(resolve("supabase/functions/_shared", file), entries);
    assert.deepEqual(entries, [], file);
  }
  assert.equal(scanContent().filter(x => x.surface === "backend").length, 248);
});
