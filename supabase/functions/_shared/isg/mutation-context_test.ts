import { parseIsgMutationContext } from "./mutation-context.ts";

const corpus = JSON.parse(await Deno.readTextFile(new URL("../../../../contracts/isg/v1/fixtures/mutation-context.json", import.meta.url)));
for (const fixture of corpus.cases) {
  Deno.test(`ISG context: ${fixture.id}`, () => {
    const result = parseIsgMutationContext(fixture.input);
    if (result.ok !== fixture.valid) throw new Error(`Unexpected validation outcome: ${fixture.id}`);
    if (!result.ok && result.error !== "VALIDATION_ERROR") throw new Error("Unbounded validation error");
  });
}
Deno.test("ISG context: rejects non-JSON numeric values and never authorizes an actor", () => {
  const input = structuredClone(corpus.cases[0].input);
  for (const value of [NaN, Infinity, -Infinity]) {
    if (parseIsgMutationContext({ ...input, expected_version: value }).ok) throw new Error("Unsafe version accepted");
  }
  const result = parseIsgMutationContext(input);
  if (!result.ok || "user_id" in result.value || "authorized" in result.value) throw new Error("Unexpected actor authorization");
  input.scope.kind = "invalid";
  if (result.value.scope.kind !== "company") throw new Error("Input mutation changed validated context");
});
