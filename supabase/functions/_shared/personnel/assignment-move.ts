import { parseIsgMutationContext, type IsgMutationContext } from "../isg/mutation-context.ts";
export interface IsgAssignmentMove {
  context: IsgMutationContext; employee_id: string; previous_assignment_id: string | null;
  department_id: string; job_role_id: string; starts_on: string;
}
const fields=["context","employee_id","previous_assignment_id","department_id","job_role_id","starts_on"];
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
function id(v: unknown): v is string { return typeof v==="string" && v.length===36 && uuid.test(v); }
function date(v: unknown): v is string {
  if(typeof v!=="string" || v.length!==10 || !/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(v))return false;
  const [y,m,d]=v.split('-').map(Number);
  if(y<1 || m<1 || m>12)return false;
  const leap=y%4===0 && (y%100!==0 || y%400===0);
  return d>=1 && d<=[31,leap?29:28,31,30,31,30,31,31,30,31,30,31][m-1];
}
/** Parsed context is not a verified session/owner/capability. No network side effects. */
export function parseIsgAssignmentMove(input: unknown): IsgAssignmentMove | null {
  if(input===null || typeof input!=="object" || Array.isArray(input))return null;
  const obj=input as Record<string,unknown>;
  if(Object.keys(obj).length!==fields.length || !fields.every(f=>Object.hasOwn(obj,f)))return null;
  const context=parseIsgMutationContext(obj.context);
  if(!context.ok || context.value.scope.kind!=="company" || !context.value.scope.workplace_id || context.value.expected_version>=9007199254740991)return null;
  if(!id(obj.employee_id)||!id(obj.department_id)||!id(obj.job_role_id)||!(obj.previous_assignment_id===null||id(obj.previous_assignment_id))||!date(obj.starts_on))return null;
  return {context:context.value,employee_id:obj.employee_id,previous_assignment_id:obj.previous_assignment_id,
    department_id:obj.department_id,job_role_id:obj.job_role_id,starts_on:obj.starts_on};
}

export interface IsgAssignmentMoveArguments {
  p_operation: string; p_mutation: string; p_company: string; p_employee: string;
  p_expected: number; p_previous: string | null; p_workplace: string;
  p_department: string; p_job: string; p_on: string;
}

/** Prepare named arguments only. This does not authorize or execute a write. */
export function prepareIsgAssignmentMove(input: unknown): Readonly<IsgAssignmentMoveArguments> | null {
  const request = parseIsgAssignmentMove(input);
  if (!request || request.context.scope.kind !== "company" || !request.context.scope.workplace_id) return null;
  return Object.freeze({
    p_operation: request.context.operation_id,
    p_mutation: request.context.client_mutation_id,
    p_company: request.context.scope.company_id,
    p_employee: request.employee_id,
    p_expected: request.context.expected_version,
    p_previous: request.previous_assignment_id,
    p_workplace: request.context.scope.workplace_id,
    p_department: request.department_id,
    p_job: request.job_role_id,
    p_on: request.starts_on,
  });
}
