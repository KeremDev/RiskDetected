import {spawnSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {setTimeout as delay} from 'node:timers/promises';
const root=new URL('../../',import.meta.url), container=`nova_modules_${process.pid}`;
const read=p=>readFileSync(new URL(p,root),'utf8');
function run(args,input){const r=spawnSync('docker',args,{input,encoding:'utf8',maxBuffer:20*1024*1024});if(r.status!==0)throw Error(r.stderr||r.stdout);return r.stdout+r.stderr;}
let created=false;
try {
 run(['run','-d','--name',container,'--network','none','-e','POSTGRES_PASSWORD=synthetic','postgres:17-alpine']);created=true;
 for(let i=0;i<40;i++){if(spawnSync('docker',['exec',container,'pg_isready','-h','127.0.0.1','-U','postgres'],{stdio:'ignore'}).status===0)break;await delay(250);}
 const fixture=read('scripts/isg/module_slice_fixture.sql')+'\nDROP TABLE private_isg.file_assets;\n';
 const equipmentFixture=read('scripts/isg/pilot_equipment_fixture.sql');
 const gates=equipmentFixture.slice(equipmentFixture.indexOf('CREATE FUNCTION private_isg.p05_pilot_account_enabled'),equipmentFixture.indexOf('INSERT INTO public.companies'));
 let sql="SET TIME ZONE 'Europe/Istanbul';\n"+'CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;\n'+fixture+gates+
   "SELECT set_config('test.pilot','true',false); SELECT set_config('test.pilot_write','true',false);\nBEGIN;\n"+
   read('supabase/pilot-release/supabase/migrations/20260914192452_isg_pilot_equipment_checks.sql')+'\nCOMMIT;\nBEGIN;\n'+
   read('supabase/migrations/20260914204842_isg_pilot_operational_modules.sql')+'\nCOMMIT;\n';
 for(const name of ['emergency_plans','drills','ppe_handovers','appointments']){
  sql+='BEGIN; UPDATE private_isg.rollout SET read_enabled=false,write_enabled=false WHERE feature=\'modules\'; UPDATE private_isg.module_registry SET read_enabled=false,write_enabled=false;\n'+read(`scripts/isg/${name}_check.sql`)+'\nROLLBACK;\n';
 }
 sql+=read('scripts/modules/pilot_scope_check.sql');
 sql+='BEGIN;\n'+read('supabase/pilot-release/supabase/migrations/20260914193516_isg_pilot_document_tracking.sql')+'\nCOMMIT;\nBEGIN;\n'+read('supabase/migrations/20260914210030_isg_pilot_module_management.sql')+'\nCOMMIT;\n'+read('scripts/modules/management_check.sql');
 sql+='BEGIN;\n'+read('supabase/migrations/20260914211910_isg_ppe_handover_only.sql')+'\nCOMMIT;\n'+read('scripts/modules/ppe_form_check.sql');
 sql+='BEGIN;\n'+read('scripts/modules/remaining_fixture.sql')+'\n'+read('scripts/modules/document_fixture.sql')+'\n'+read('supabase/migrations/20260914213023_isg_pilot_remaining_records.sql')+'\nCOMMIT;\n'+read('scripts/modules/remaining_check.sql');
 sql+='BEGIN;\n'+read('supabase/migrations/20260914215132_isg_pilot_findings_checklists.sql')+'\nCOMMIT;\nBEGIN;\n'+read('scripts/isg/checklist_runs_check.sql')+'\nROLLBACK;\n'+read('scripts/modules/findings_check.sql');
 sql+='BEGIN;\n'+read('supabase/migrations/20260914220355_isg_pilot_process_links.sql')+'\nCOMMIT;\n'+read('scripts/modules/process_links_check.sql');
 sql+='BEGIN;\n'+read('scripts/modules/training_reference_fixture.sql')+'\n'+read('supabase/migrations/20260914220753_isg_pilot_cross_module_links.sql')+'\nCOMMIT;\n'+read('scripts/modules/cross_links_check.sql');
 sql+='BEGIN;\n'+read('supabase/migrations/20260914221301_isg_pilot_risk_records.sql')+'\nCOMMIT;\n'+read('scripts/modules/risk_pilot_check.sql');
 sql+='BEGIN;\n'+"CREATE SCHEMA auth; CREATE TABLE auth.users(id uuid PRIMARY KEY); INSERT INTO auth.users SELECT id FROM public.profiles;\n"+read('supabase/migrations/20260914222916_isg_pilot_risk_draft_management.sql')+'\nCOMMIT;\n'+read('scripts/modules/risk_draft_check.sql');
 const out=run(['exec','-i',container,'psql','-U','postgres','-X','-v','ON_ERROR_STOP=1'],sql);
 console.log(out.split('\n').filter(l=>/NOTICE:.*ok|PASSED/.test(l)).join('\n'));
 console.log('PASS: pilot operational module regression');
}finally{if(created)run(['rm','-f',container]);}
