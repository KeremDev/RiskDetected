import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {setTimeout as delay} from 'node:timers/promises';
import {OSGB_CANDIDATE_MIGRATIONS} from './osgb_candidate_manifest.mjs';

const root=new URL('../../',import.meta.url),container=`isgada_osgb_integrated_${process.pid}`;
const read=path=>readFileSync(new URL(path,root),'utf8');
function docker(args,input){
  const result=spawnSync('docker',args,{input,encoding:'utf8',maxBuffer:30*1024*1024});
  if(result.status!==0)throw new Error(result.stderr||result.stdout||`docker exited ${result.status}`);
  return result.stdout+result.stderr;
}

let created=false;
try{
  docker(['run','-d','--name',container,'--network','none','-e','POSTGRES_PASSWORD=synthetic','postgres:17-alpine']);
  created=true;
  let ready=false;
  for(let i=0;i<40;i+=1){
    if(spawnSync('docker',['exec',container,'pg_isready','-h','127.0.0.1','-U','postgres'],{stdio:'ignore'}).status===0){ready=true;break;}
    await delay(250);
  }
  if(!ready)throw new Error('disposable postgres did not become ready');
  const sql=[
    "SET TIME ZONE 'Europe/Istanbul';",
    read('scripts/isg/osgb_workspace_fixture.sql'),
    read('scripts/isg/osgb_admin_authority_fixture.sql'),
    'BEGIN;',
    ...OSGB_CANDIDATE_MIGRATIONS.map(name=>read(`supabase/pilot-release/candidates/${name}`)),
    'COMMIT;',
    read('scripts/isg/osgb_integrated_rehearsal_check.sql'),
  ].join('\n');
  const output=docker(['exec','-i',container,'psql','-U','postgres','-X','-v','ON_ERROR_STOP=1'],sql);
  const evidence=output.split('\n').filter(line=>/NOTICE:.*ok integrated/.test(line)).join('\n');
  if(!evidence)throw new Error('integrated rehearsal produced no acceptance evidence');
  console.log(evidence);
  console.log('PASS: undeployed OSGB full candidate chain in one disposable PostgreSQL');
}finally{
  if(created)docker(['rm','-f',container]);
}
