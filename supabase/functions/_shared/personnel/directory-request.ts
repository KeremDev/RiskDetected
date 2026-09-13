import { parseIsgMutationContext } from "../isg/mutation-context.ts";
import { employeeText, parseIsgEmployeeCreate, prepareIsgEmployeeCreate } from "./employee-create.ts";
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const id=(v:unknown):v is string=>typeof v==='string'&&v.length===36&&uuid.test(v);
const record=(v:unknown):v is Record<string,unknown>=>v!==null&&typeof v==='object'&&!Array.isArray(v);
export function preparePersonnelDirectory(input:unknown) {
  if(!record(input)||typeof input.action!=='string')return null;
  const {action,...body}=input;
  if(['employees','departments','detail'].includes(action)) {
    const allowed=action==='detail'?['company_id','employee_id']:['company_id','query','include_archived','cursor'];
    if(Object.keys(body).length!==allowed.length||!Object.keys(body).every(k=>allowed.includes(k))||!id(body.company_id))return null;
    if(action==='detail') {
      if(!id(body.employee_id))return null;
      return {kind:'read' as const,companyID:body.company_id,args:{p_company:body.company_id,p_kind:action,p_query:'',p_archived:false,p_after:null,p_id:body.employee_id}};
    }
    if(typeof body.query!=='string'||new TextEncoder().encode(body.query).length>200||typeof body.include_archived!=='boolean'||!(body.cursor===null||id(body.cursor))||(action==='departments'&&body.include_archived))return null;
    return {kind:'read' as const,companyID:body.company_id,args:{p_company:body.company_id,p_kind:action,p_query:body.query,p_archived:body.include_archived,p_after:body.cursor,p_id:null}};
  }
  if(action==='create') {
    const value=parseIsgEmployeeCreate(body),args=prepareIsgEmployeeCreate(body);
    if(!value||!args)return null;
    return {kind:'create' as const,companyID:args.p_company,operationID:args.p_operation,args};
  }
  if(action!=='edit'&&action!=='archive')return null;
  const allowed=action==='edit'?['context','employee_id','full_name','department']:['context','employee_id'];
  if(Object.keys(body).length!==allowed.length||!Object.keys(body).every(k=>allowed.includes(k))||!id(body.employee_id))return null;
  const context=parseIsgMutationContext(body.context);
  if(!context.ok||context.value.scope.kind!=='company'||context.value.scope.workplace_id!==undefined||context.value.expected_version>=9007199254740991)return null;
  let name:string|null=null,department:string|null=null,departmentName:string|null=null,change=false;
  if(action==='edit') {
    name=employeeText(body.full_name,200);if(!name)return null;
    if(record(body.department)&&body.department.kind==='keep'&&Object.keys(body.department).length===1)change=false;
    else {
      const validate=parseIsgEmployeeCreate({context:{...context.value,expected_version:0},full_name:name,department:body.department});
      if(!validate)return null;
      change=true;
      if(validate.department?.kind==='existing')department=validate.department.id;
      if(validate.department?.kind==='new')departmentName=validate.department.name;
    }
  }
  return {kind:'edit' as const,companyID:context.value.scope.company_id,operationID:context.value.operation_id,args:{
    p_operation:context.value.operation_id,p_mutation:context.value.client_mutation_id,p_company:context.value.scope.company_id,p_employee:body.employee_id,
    p_expected:context.value.expected_version,p_action:action,p_name:name,p_change_department:change,p_department:department,p_department_name:departmentName}};
}
