import { parseIsgAssignmentMove, prepareIsgAssignmentMove } from "./assignment-move.ts";
const corpus=JSON.parse(await Deno.readTextFile(new URL("../../../../contracts/isg/v1/fixtures/assignment-move.json",import.meta.url)));
for(const c of corpus.cases) Deno.test(`Assignment move: ${c.id}`,()=>{
  const result=parseIsgAssignmentMove(c.input);
  if((result!==null)!==c.valid)throw Error(`Unexpected validation: ${c.id}`);
  if(result && result.context.operation_id===result.context.client_mutation_id)throw Error("Operation and mutation collapsed");
  const args=prepareIsgAssignmentMove(c.input);
  if((args!==null)!==c.valid)throw Error(`Unexpected preparation: ${c.id}`);
  if(args) {
    const expected={p_operation:c.input.context.operation_id,p_mutation:c.input.context.client_mutation_id,
      p_company:c.input.context.scope.company_id,p_employee:c.input.employee_id,p_expected:c.input.context.expected_version,
      p_previous:c.input.previous_assignment_id,p_workplace:c.input.context.scope.workplace_id,
      p_department:c.input.department_id,p_job:c.input.job_role_id,p_on:c.input.starts_on};
    if(JSON.stringify(args)!==JSON.stringify(expected)||!Object.isFrozen(args))throw Error("Incorrect or mutable SQL arguments");
  }
});
Deno.test("assignment input is detached and non-JSON numeric values fail",()=>{
  const input=structuredClone(corpus.cases[0].input), result=parseIsgAssignmentMove(input);
  input.context.scope.workplace_id="changed";
  if(!result || result.context.scope.kind!=="company" || result.context.scope.workplace_id==="changed")throw Error("Mutable validated request");
  for(const value of [NaN,Infinity,-Infinity]) {
    const candidate=structuredClone(corpus.cases[0].input);candidate.context.expected_version=value;
    if(parseIsgAssignmentMove(candidate)!==null)throw Error("Non-finite accepted");
  }
});
