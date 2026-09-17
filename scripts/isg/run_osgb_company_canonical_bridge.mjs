import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {setTimeout as delay} from 'node:timers/promises';
const root=new URL('../../',import.meta.url),container=`isgada_osgb_company_bridge_${process.pid}`;
const read=path=>readFileSync(new URL(path,root),'utf8');
function docker(args,input){const r=spawnSync('docker',args,{input,encoding:'utf8',maxBuffer:25*1024*1024});if(r.status!==0)throw new Error(r.stderr||r.stdout);return r.stdout+r.stderr;}
let created=false;
try{
  docker(['run','-d','--name',container,'--network','none','-e','POSTGRES_PASSWORD=synthetic','postgres:17-alpine']);created=true;
  let ready=false;for(let i=0;i<40;i+=1){if(spawnSync('docker',['exec',container,'pg_isready','-h','127.0.0.1','-U','postgres'],{stdio:'ignore'}).status===0){ready=true;break;}await delay(250);}if(!ready)throw new Error('disposable postgres did not become ready');
  const sql=[read('scripts/isg/osgb_workspace_fixture.sql'),'BEGIN;',
    read('supabase/pilot-release/candidates/20260917090000_osgb_workspace_foundation.sql'),
    read('supabase/pilot-release/candidates/20260917093000_osgb_company_assignments.sql'),
    read('supabase/pilot-release/candidates/20260917100000_osgb_seat_entitlements.sql'),
    read('supabase/pilot-release/candidates/20260917134500_osgb_workspace_operations.sql'),
    read('supabase/pilot-release/candidates/20260917143000_osgb_company_canonical_bridge.sql'),
    'COMMIT;',read('scripts/isg/osgb_company_canonical_bridge_check.sql')].join('\n');
  const output=docker(['exec','-i',container,'psql','-U','postgres','-X','-v','ON_ERROR_STOP=1'],sql);
  const evidence=output.split('\n').filter(line=>/NOTICE:.*ok personal legacy mapping/.test(line)).join('\n');
  if(!evidence)throw new Error('canonical company bridge checks produced no evidence');console.log(evidence);
  console.log('PASS: undeployed OSGB canonical company bridge in disposable PostgreSQL');
}finally{if(created)docker(['rm','-f',container]);}
