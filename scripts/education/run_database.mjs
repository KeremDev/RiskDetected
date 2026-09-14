import {setupConcurrencySQL, issueSQL} from './concurrency.mjs';
import {spawn, spawnSync} from 'node:child_process';
import {readFileSync, readdirSync, writeFileSync, mkdirSync} from 'node:fs';
import {setTimeout as delay} from 'node:timers/promises';
const root=new URL('../../',import.meta.url); const container=`isg_education_${process.pid}`;
function run(args,input){const r=spawnSync('docker',args,{input,encoding:'utf8',maxBuffer:16*1024*1024});if(r.status!==0)throw new Error(r.stderr||r.stdout);return r.stdout;}
const read=p=>readFileSync(new URL(p,root),'utf8');
const sql=s=>run(['exec','-i',container,'psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-X'],s);
let created=false;
try {
 run(['run','-d','--name',container,'--network','none','--label','isg.education.synthetic=true','-e','POSTGRES_PASSWORD=synthetic-local-only','postgres:17-alpine']);created=true;
 let ready=false;for(let i=0;i<40;i++){if(spawnSync('docker',['exec',container,'pg_isready','-h','127.0.0.1','-U','postgres'],{stdio:'ignore'}).status===0){ready=true;break;}await delay(250);}if(!ready)throw new Error('Local DB not ready');
 sql("CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;\n"+read('scripts/isg/pilot_training_fixture.sql'));
 sql(read('supabase/migrations/20260914112522_isg_pilot_training_register.sql'));
 sql(read('scripts/isg/pilot_training_sessions_fixture.sql'));
 sql(read('supabase/migrations/20260914122517_isg_pilot_training_sessions.sql'));
 sql(`CREATE TABLE public.profiles(id uuid PRIMARY KEY REFERENCES auth.users(id)); INSERT INTO public.profiles SELECT id FROM auth.users;
 CREATE TABLE private_isg.workplaces(id uuid PRIMARY KEY,company_id uuid NOT NULL,owner_id uuid,name text,hazard_class text,UNIQUE(company_id,id),is_archived boolean DEFAULT false);
 CREATE TABLE private_isg.workplace_context_versions(company_id uuid,workplace_id uuid,starts_on date,ends_before date,hazard_class text);
 CREATE TABLE private_isg.employee_assignments(company_id uuid,employee_id uuid,starts_on date,ends_before date,job_title_snapshot text,department_name_snapshot text);
 INSERT INTO private_isg.workplaces VALUES('40000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Atölye','high',false);
 `);
 sql(read('supabase/migrations/20260914153220_isg_education_curriculum_certificates.sql'));
 console.log('Migration applied to isolated fixture');
 if(readdirSync(new URL('.',import.meta.url)).includes('checks.sql'))console.log(sql(read('scripts/education/checks.sql')));
 sql(setupConcurrencySQL());
 const concurrent=i=>new Promise((resolve,reject)=>{
  const child=spawn('docker',['exec','-i',container,'psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-X','-At']);let out='',err='';
  child.stdout.on('data',v=>out+=v);child.stderr.on('data',v=>err+=v);child.on('error',reject);child.on('exit',code=>code===0?resolve(out.trim().split('\n').at(-1)):reject(new Error(err)));child.stdin.end(issueSQL(i));
 });
 const numbers=await Promise.all([concurrent(0),concurrent(1)]);
 if(new Set(numbers).size!==2 || numbers.some(n=>!/^EG-\d{4}-\d+$/.test(n)))throw new Error('Concurrent certificate number collision');
 console.log('PASS: two PostgreSQL connections issue distinct numbers for different companies');
 mkdirSync(new URL('../../artifacts/education/',import.meta.url),{recursive:true});
 const snapshots=run(['exec','-i',container,'psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-X','-At'],"SELECT jsonb_agg(snapshot ORDER BY document_no) FROM private_isg.document_versions;");
 writeFileSync(new URL('../../artifacts/education/server-snapshots.json',import.meta.url),snapshots);
} finally {if(created)spawnSync('docker',['rm','-f',container],{stdio:'ignore'});}
