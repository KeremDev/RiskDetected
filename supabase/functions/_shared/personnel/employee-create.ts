import { parseIsgMutationContext, type IsgMutationContext } from "../isg/mutation-context.ts";

export type EmployeeDepartment = { kind: "existing"; id: string } | { kind: "new"; name: string };
export interface IsgEmployeeCreate {
  context: IsgMutationContext;
  full_name: string;
  department: EmployeeDepartment | null;
}
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const bytes = (s: string) => new TextEncoder().encode(s).length;
export function employeeText(input: unknown, limit: number): string | null {
  if (typeof input !== "string" || bytes(input) > 4096) return null;
  const value = input.normalize("NFC").replace(/[ \t\r\n]+/g, " ").replace(/^ | $/g, "");
  return value && bytes(value) <= limit && !/[\u0000-\u001f\u007f\u200b\ufeff]/.test(value) && !/^\s*$/.test(value) ? value : null;
}
/** Only name is user-required. Company and operation IDs come from the current session/form. */
export function parseIsgEmployeeCreate(input: unknown): IsgEmployeeCreate | null {
  if (!input || typeof input !== "object" || Array.isArray(input)) return null;
  const obj = input as Record<string, unknown>;
  if (!Object.keys(obj).every(k => ["context", "full_name", "department"].includes(k))) return null;
  const context = parseIsgMutationContext(obj.context);
  if (!context.ok || context.value.scope.kind !== "company" || context.value.scope.workplace_id !== undefined || context.value.expected_version !== 0) return null;
  const full_name = employeeText(obj.full_name, 200);
  if (!full_name) return null;
  let department: EmployeeDepartment | null = null;
  if (obj.department !== undefined && obj.department !== null) {
    if (typeof obj.department !== "object" || Array.isArray(obj.department)) return null;
    const d = obj.department as Record<string, unknown>;
    if (d.kind === "existing" && Object.keys(d).length === 2 && typeof d.id === "string" && uuid.test(d.id)) department = { kind: "existing", id: d.id };
    else if (d.kind === "new" && Object.keys(d).length === 2) {
      const name = employeeText(d.name, 120);
      if (!name) return null;
      department = { kind: "new", name };
    } else return null;
  }
  return { context: context.value, full_name, department };
}
/** No actor argument, auth claim or network side effect. SQL rechecks company ownership. */
export function prepareIsgEmployeeCreate(input: unknown) {
  const request = parseIsgEmployeeCreate(input);
  if (!request || request.context.scope.kind !== "company") return null;
  return Object.freeze({ p_operation: request.context.operation_id, p_mutation: request.context.client_mutation_id,
    p_company: request.context.scope.company_id, p_name: request.full_name,
    p_department: request.department?.kind === "existing" ? request.department.id : null,
    p_department_name: request.department?.kind === "new" ? request.department.name : null });
}
