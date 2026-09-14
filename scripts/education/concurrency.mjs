import {fixture} from './fixtures.mjs';
export function setupConcurrencySQL() {
 const first=fixture();const second=fixture('repeat_low');
 Object.assign(second.scopes[0],{id:'50000000-0000-0000-0000-000000000003',company_id:'10000000-0000-0000-0000-000000000003',workplace_id:'40000000-0000-0000-0000-000000000003'});
 second.scopes[0].participants[0].id='30000000-0000-0000-0000-000000000003';
 return `SET test.actor='20000000-0000-0000-0000-000000000001'; CREATE TABLE public.education_concurrency_requests(seq int,request jsonb);
 ${[first,second].map((p,i)=>`DO $$ DECLARE p jsonb:=$j$${JSON.stringify(p)}$j$; r jsonb; BEGIN r:=private_isg.education_save(gen_random_uuid(),p);
 INSERT INTO public.education_concurrency_requests VALUES(${i},jsonb_build_object('action','issue','session_id',r->'row'->>'id','scope_id',p->'scopes'->0->>'id','person_id',p->'scopes'->0->'participants'->0->>'id','expected_version',r->'row'->'version','mutation_id',gen_random_uuid())); END $$;`).join('\n')}`;
}
export function issueSQL(i){return `SET test.actor='20000000-0000-0000-0000-000000000001'; SELECT private_isg.education_certificate(request)->'snapshot'->>'number' FROM public.education_concurrency_requests WHERE seq=${i};`;}
