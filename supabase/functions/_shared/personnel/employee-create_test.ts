import { parseIsgEmployeeCreate, prepareIsgEmployeeCreate } from "./employee-create.ts";
const corpus=JSON.parse(await Deno.readTextFile(new URL("../../../../contracts/isg/v1/fixtures/employee-create.json",import.meta.url)));
for(const c of corpus.cases)Deno.test(`Employee intake: ${c.id}`,()=>{
  const value=parseIsgEmployeeCreate(c.input), args=prepareIsgEmployeeCreate(c.input);
  if((value!==null)!==c.valid || (args!==null)!==c.valid)throw Error(`Wrong acceptance ${c.id}`);
  if(value?.full_name!==undefined && value.full_name!==c.normalized_name)throw Error(`Wrong normalization ${c.id}`);
  if(args && (!Object.isFrozen(args)||Object.keys(args).length!==6||args.p_operation!==c.input.context.operation_id||args.p_mutation!==c.input.context.client_mutation_id))throw Error("Wrong arguments");
});
