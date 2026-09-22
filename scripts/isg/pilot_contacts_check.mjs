// Disposable PostgreSQL only, no network/ports. Exercises real P05 authorization,
// create/replay/personnel/overview functions. Platform subscription/limit helpers
// are fixture dependencies; this does not replace the wider auth/restore suite.
import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
import {setTimeout as delay} from 'node:timers/promises';
import {compileP05PilotBundle} from './p05_pilot_bundle.mjs';
const root=new URL('../../',import.meta.url), container=`isgada_contacts_${process.pid}`;
const read=p=>readFileSync(new URL(p,root),'utf8');
function docker(args,input){const r=spawnSync('docker',args,{input,encoding:'utf8',maxBuffer:5*1024*1024});if(r.status!==0)throw Error(r.stderr||r.stdout);return r.stdout.trim();}
const sql=s=>docker(['exec','-i',container,'psql','-U','postgres','-XAtq','-v','ON_ERROR_STOP=1'],s);
const q=v=>v===null?'NULL':"'"+String(v).replaceAll("'","''")+"'";
const owner=randomUUID(), other=randomUUID(), session=randomUUID(), otherSession=randomUUID();
function claims(actor=owner,sid=session){return `SELECT set_config('request.jwt.claims',${q(JSON.stringify({role:'authenticated',sub:actor,session_id:sid,exp:Math.floor(Date.now()/1000)+3600}))},false);`;}
function asActor(s,actor=owner,sid=session){return sql(claims(actor,sid)+'SET ROLE authenticated;'+s).split('\n').at(-1);}
let created=false, count=0;
const check=(name,body)=>{body();count++;console.log('PASS '+name);};
const fail=(s,message,actor=owner,sid=session)=>assert.throws(()=>asActor(s,actor,sid),e=>e.message.includes(message));
try {
 docker(['run','-d','--name',container,'--network','none','-e','POSTGRES_PASSWORD=synthetic','postgres:17-alpine']);created=true;
 for(let i=0;i<80;i++){if(spawnSync('docker',['exec',container,'pg_isready','-U','postgres'],{stdio:'ignore'}).status===0)break;await delay(250);}
 sql(`CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role;
 CREATE SCHEMA auth;CREATE SCHEMA private;CREATE SCHEMA extensions;
 CREATE TABLE auth.users(id uuid PRIMARY KEY,deleted_at timestamptz,banned_until timestamptz,is_anonymous boolean DEFAULT false);
 CREATE TABLE auth.sessions(id uuid PRIMARY KEY,user_id uuid,not_after timestamptz);
 CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql AS $$ SELECT current_setting('request.jwt.claims')::jsonb $$;
 CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$ SELECT (current_setting('request.jwt.claims')::jsonb->>'sub')::uuid $$;
 CREATE TABLE public.companies(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid NOT NULL,name text NOT NULL,hazard_class text,is_archived boolean DEFAULT false);
 CREATE TABLE public.user_subscriptions(user_id uuid PRIMARY KEY,tier text,status text,current_period_ends_at timestamptz);
 CREATE FUNCTION private.user_plan_tier(p uuid) RETURNS text LANGUAGE sql AS $$ SELECT tier FROM public.user_subscriptions WHERE user_id=p $$;
 CREATE FUNCTION private.company_limit_for_user(p uuid) RETURNS integer LANGUAGE sql AS $$ SELECT 100 $$;
 INSERT INTO auth.users(id) VALUES(${q(owner)}),(${q(other)});
 INSERT INTO auth.sessions(id,user_id) VALUES(${q(session)},${q(owner)}),(${q(otherSession)},${q(other)});
 INSERT INTO public.user_subscriptions VALUES(${q(owner)},'pro','active',null),(${q(other)},'pro','active',null);`);
 sql(compileP05PilotBundle().sql);
 sql('BEGIN;'+read('supabase/pilot-release/candidates/20260913203710_isg_p05_company_profile_overview.sql')+'COMMIT;');
 sql('BEGIN;'+read('supabase/pilot-release/candidates/20260916090000_isg_pilot_company_contacts.sql')+'COMMIT;');
 sql(`UPDATE private_isg.rollout SET read_enabled=true,write_enabled=true WHERE feature='personnel';
 INSERT INTO private_isg.p05_pilot_accounts(actor_id,read_enabled,write_enabled,approved_reference,expires_at) VALUES(${q(owner)},true,true,'synthetic.contacts',clock_timestamp()+interval '1 hour');`);
 const mutation=randomUUID();
 function create({m=mutation,phone='+90 (532) 123-4567',email='responsible@example.test',name='Ada Kaya'}={}){return `SELECT public.isg_pilot_company_create_v3(${q(m)},'Firma','high','Metal',NULL,10,${q(name)},${q(phone)},${q(email)});`;}
 const first=JSON.parse(asActor(create())), company=first.company.id;
 const overview=()=>JSON.parse(asActor(`SELECT public.isg_pilot_overview_v2(${q(company)});`));
 check('contact, employee, default workplace saved atomically',()=>{const r=overview().companies[0];assert.equal(first.schema_version,3);assert.equal(r.responsible_phone,'+905321234567');assert.equal(r.responsible_email,'responsible@example.test');assert.equal(r.responsible_name,'Ada Kaya');assert.equal(r.personnel_count,1);assert.equal(r.workplace_count,1);});
 check('same normalized intent replays without duplicate people',()=>{const r=JSON.parse(asActor(create({phone:'+905321234567'})));assert.equal(r.company.id,company);assert.equal(r.replayed,true);assert.equal(overview().companies[0].personnel_count,1);});
 check('changed contact conflicts',()=>{fail(create({phone:'+905321234568'}),'IDEMPOTENCY_CONFLICT');fail(create({email:'other@example.test'}),'IDEMPOTENCY_CONFLICT');});
 check('required contact validation and atomic failure',()=>{const before=sql('SELECT count(*) FROM public.companies;');for(const x of [{phone:null},{phone:'abc'},{email:'bad'},{phone:'1234567890123456'}])fail(create({...x,m:randomUUID()}),'VALIDATION_ERROR');assert.equal(sql('SELECT count(*) FROM public.companies;'),before);});
 check('contact email is optional',()=>{const r=JSON.parse(asActor(create({m:randomUUID(),email:null})));assert.equal(r.schema_version,3);assert.equal(overview().companies.find(x=>x.id===r.company.id).responsible_email,null);});
 check('no responsible person means no contact is allowed',()=>{fail(create({m:randomUUID(),name:null}),'VALIDATION_ERROR');const r=JSON.parse(asActor(create({m:randomUUID(),name:null,phone:null,email:null})));assert.equal(r.schema_version,3);});
 check('V2 stays usable but cannot reuse its mutation for V3',()=>{const m=randomUUID();const r=JSON.parse(asActor(`SELECT public.isg_pilot_company_create_v2(${q(m)},'Firma','high','Metal',NULL,10,'Ada Kaya');`));assert.equal(r.schema_version,2);fail(create({m}),'IDEMPOTENCY_CONFLICT');assert.equal(JSON.parse(asActor(`SELECT public.isg_pilot_overview_v1(${q(company)});`)).schema_version,1);});
 check('write pause blocks replay while reads remain available',()=>{sql(`UPDATE private_isg.p05_pilot_accounts SET write_enabled=false WHERE actor_id=${q(owner)};`);fail(create(),'FEATURE_UNAVAILABLE');assert.equal(overview().schema_version,2);sql(`UPDATE private_isg.p05_pilot_accounts SET write_enabled=true WHERE actor_id=${q(owner)};`);});
 check('other account cannot read contacts or create via pilot',()=>{fail(`SELECT public.isg_pilot_overview_v2(${q(company)});`,'FEATURE_UNAVAILABLE',other,otherSession);fail(create(),'FEATURE_UNAVAILABLE',other,otherSession);});
 check('revocation and session deletion deny reads',()=>{sql(`UPDATE private_isg.p05_pilot_accounts SET revoked_at=clock_timestamp() WHERE actor_id=${q(owner)};`);fail(`SELECT public.isg_pilot_overview_v2(${q(company)});`,'FEATURE_UNAVAILABLE');sql(`UPDATE private_isg.p05_pilot_accounts SET revoked_at=NULL WHERE actor_id=${q(owner)}; DELETE FROM auth.sessions WHERE id=${q(session)};`);fail(`SELECT public.isg_pilot_overview_v2(${q(company)});`,'AUTH_REQUIRED');});
 check('no direct data or anonymous/service role RPC access',()=>{assert.equal(sql("SELECT NOT has_table_privilege('authenticated','private_isg.p05_company_profiles','SELECT,INSERT,UPDATE,DELETE') AND NOT has_function_privilege('anon','public.isg_pilot_overview_v2(uuid)','EXECUTE') AND NOT has_function_privilege('service_role','public.isg_pilot_company_create_v3(uuid,text,text,text,text,integer,text,text,text)','EXECUTE');"),'t');});
 console.log(`${count} pilot contact database checks PASS`);
} finally {if(created)docker(['rm','-f',container]);}
