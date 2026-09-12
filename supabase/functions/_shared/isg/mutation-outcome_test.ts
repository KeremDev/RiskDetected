import { parseIsgMutationOutcome, transitionIsgMutation } from './mutation-outcome.ts';
const corpus=JSON.parse(await Deno.readTextFile(new URL('../../../../contracts/isg/v1/fixtures/mutation-outcome.json',import.meta.url)));
for(const c of corpus.cases)Deno.test(`ISG outcome: ${c.id}`,()=>{
  const value=parseIsgMutationOutcome(c.status,c.input);
  if((value!==null)!==c.valid)throw Error(`Validation mismatch: ${c.id}`);
  if(value&&[value.outcome,value.code??'',value.version??'',value.current_version??'',value.projection??'',value.retry_after_seconds??''].join('|')!==c.summary)throw Error('Decoded value mismatch');
});
for(const c of corpus.transitions)Deno.test(`ISG transition: ${c.id}`,()=>{
  const result=transitionIsgMutation(c.phase,c.event,c.same_context);
  if(result.phase!==c.next_phase||result.effect!==c.effect)throw Error('Transition mismatch');
});
Deno.test('outcome rejects non-JSON numeric values and detaches response',()=>{
  const valid=corpus.cases.find((c:{id:string})=>c.id==='committed_ready').input;
  for(const version of [NaN,Infinity,-Infinity])if(parseIsgMutationOutcome(200,{...valid,version}))throw Error('Invalid number');
  const input=structuredClone(valid),value=parseIsgMutationOutcome(200,input);
  input.projection='failed';if(value?.projection!=='ready')throw Error('Mutable response alias');
});
