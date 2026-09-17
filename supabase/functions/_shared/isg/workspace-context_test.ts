import {parseIsgWorkspaceContext} from "./workspace-context.ts";

const fixture=JSON.parse(await Deno.readTextFile(new URL("../../../../contracts/isg/v2/fixtures/workspace-context.json",import.meta.url)));
for(const item of fixture.cases) Deno.test(`workspace context: ${item.id}`,()=>{
  const parsed=parseIsgWorkspaceContext(item.input);
  if(parsed.ok!==item.valid) throw new Error(`Unexpected result: ${item.id}`);
});
