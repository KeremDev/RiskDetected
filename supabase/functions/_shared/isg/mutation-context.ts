/** Transport validation only. Never use a parsed scope as proof of authorization. */
export interface IsgMutationContext {
  schema_version: 1;
  operation_id: string;
  client_mutation_id: string;
  platform: "ios" | "android";
  client_build: number;
  expected_version: number;
  scope: { kind: "personal" } | { kind: "company"; company_id: string; workplace_id?: string };
}

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
function record(v: unknown): v is Record<string, unknown> { return v !== null && typeof v === "object" && !Array.isArray(v); }
function keys(v: Record<string, unknown>, allowed: string[]): boolean { return Object.keys(v).every(k => allowed.includes(k)); }
function id(v: unknown): v is string { return typeof v === "string" && v.length === 36 && uuid.test(v); }

export function parseIsgMutationContext(input: unknown): { ok: true; value: IsgMutationContext } | { ok: false; error: "VALIDATION_ERROR" } {
  const fail = { ok: false, error: "VALIDATION_ERROR" } as const;
  if (!record(input) || !keys(input, ["schema_version", "operation_id", "client_mutation_id", "platform", "client_build", "expected_version", "scope"])) return fail;
  if (input.schema_version !== 1 || !id(input.operation_id) || !id(input.client_mutation_id)) return fail;
  if (input.platform !== "ios" && input.platform !== "android") return fail;
  if (!Number.isInteger(input.client_build) || (input.client_build as number) < 1 || (input.client_build as number) > 2147483647) return fail;
  if (!Number.isSafeInteger(input.expected_version) || (input.expected_version as number) < 0) return fail;
  if (!record(input.scope)) return fail;
  const scope = input.scope;
  if (scope.kind === "personal") {
    if (!keys(scope, ["kind"])) return fail;
  } else if (scope.kind === "company") {
    if (!keys(scope, ["kind", "company_id", "workplace_id"]) || !id(scope.company_id)) return fail;
    if (Object.hasOwn(scope, "workplace_id") && !id(scope.workplace_id)) return fail;
  } else return fail;
  // Return a detached allowlisted value so caller mutation cannot change validation.
  const validatedScope: IsgMutationContext["scope"] = scope.kind === "personal" ? { kind: "personal" } : {
    kind: "company", company_id: scope.company_id as string,
    ...(Object.hasOwn(scope, "workplace_id") ? { workplace_id: scope.workplace_id as string } : {}),
  };
  return { ok: true, value: { schema_version: 1, operation_id: input.operation_id, client_mutation_id: input.client_mutation_id,
    platform: input.platform, client_build: input.client_build as number, expected_version: input.expected_version as number, scope: validatedScope } };
}
