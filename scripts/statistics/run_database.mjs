import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync} from 'node:fs';
import {setTimeout as delay} from 'node:timers/promises';
const container=`nova_statistics_${process.pid}`;
const read=p=>readFileSync(p,'utf8');
function run(args,input){const r=spawnSync('docker',args,{input,encoding:'utf8',maxBuffer:8e6});if(r.status!==0)throw new Error(r.stderr||r.stdout);return r.stdout;}
const sql=s=>run(['exec','-i',container,'psql','-X','-U','postgres','-v','ON_ERROR_STOP=1','-At'],s);
let created=false;
try{
 run(['run','-d','--name',container,'--network','none','-e','POSTGRES_PASSWORD=synthetic-local-only','postgres:17-alpine']);created=true;
 let ready=false;for(let i=0;i<80;i++){if(spawnSync('docker',['exec',container,'pg_isready','-h','127.0.0.1','-U','postgres'],{stdio:'ignore'}).status===0){ready=true;break;}await delay(250);}if(!ready)throw Error('DB unavailable');
 sql('CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;'+read('scripts/isg/pilot_training_fixture.sql'));
 sql(read('supabase/migrations/20260914112522_isg_pilot_training_register.sql'));
 sql(read('scripts/isg/pilot_training_sessions_fixture.sql'));
 sql(read('supabase/migrations/20260914122517_isg_pilot_training_sessions.sql'));
 sql(read('scripts/statistics/fixture.sql'));
 sql(read('supabase/migrations/20260914170138_isg_statistics_read.sql'));
 console.log(sql(read('scripts/statistics/checks.sql')));
 const snapshot=sql("SET test.actor='20000000-0000-0000-0000-000000000001'; SELECT public.isg_statistics_v1(NULL,6);").trim().split('\n').at(-1);
 writeFileSync('artifacts/statistics/server-snapshot.json',snapshot+'\n');
 console.log('PASS: isolated statistics aggregation, >200 rows, owner/date/company guards and optional sources');
}finally{if(created)spawnSync('docker',['rm','-f',container],{stdio:'ignore'});}
