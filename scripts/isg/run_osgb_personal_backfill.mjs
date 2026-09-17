import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {setTimeout as delay} from 'node:timers/promises';

const root=new URL('../../',import.meta.url);const container=`isgada_osgb_backfill_${process.pid}`;
const read=path=>readFileSync(new URL(path,root),'utf8');
function docker(args,input){const result=spawnSync('docker',args,{input,encoding:'utf8',maxBuffer:20*1024*1024});
  if(result.status!==0)throw new Error(result.stderr||result.stdout||`docker exited ${result.status}`);return result.stdout+result.stderr;}
let created=false;
try{
  docker(['run','-d','--name',container,'--network','none','-e','POSTGRES_PASSWORD=synthetic','postgres:17-alpine']);created=true;
  let ready=false;for(let i=0;i<40;i+=1){if(spawnSync('docker',['exec',container,'pg_isready','-h','127.0.0.1','-U','postgres'],{stdio:'ignore'}).status===0){ready=true;break;}await delay(250);}
  if(!ready)throw new Error('disposable postgres did not become ready');
  const sql=[read('scripts/isg/osgb_workspace_fixture.sql'),'BEGIN;',read('supabase/pilot-release/candidates/20260917090000_osgb_workspace_foundation.sql'),
    read('supabase/pilot-release/candidates/20260917091500_osgb_personal_backfill.sql'),'COMMIT;',read('scripts/isg/osgb_personal_backfill_check.sql')].join('\n');
  const output=docker(['exec','-i',container,'psql','-U','postgres','-X','-v','ON_ERROR_STOP=1'],sql);
  const evidence=output.split('\n').filter(line=>/NOTICE:.*ok/.test(line)).join('\n');if(!evidence)throw new Error('backfill checks produced no evidence');
  console.log(evidence);console.log('PASS: undeployed personal workspace backfill in disposable PostgreSQL');
}finally{if(created)docker(['rm','-f',container]);}
