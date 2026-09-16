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
 sql+='BEGIN;\n'+read('supabase/migrations/20260915090001_isg_pilot_module_tracking.sql')+'\nCOMMIT;\n'+read('scripts/modules/tracking_check.sql');
 sql+='BEGIN;\n'+read('supabase/migrations/20260915090002_isg_pilot_checklist_plan_board.sql')+'\nCOMMIT;\n'+read('scripts/modules/checklist_plan_board_check.sql');
 if(process.argv.includes('--visit-details') || process.argv.includes('--completed-records')) {
  sql+='BEGIN;\n'+read('scripts/modules/visit_file_fixture.sql')+'\n'+read('supabase/pilot-release/candidates/20260916093000_isg_pilot_visit_meeting_details.sql')+'\nCOMMIT;\n'+read('scripts/modules/visit_details_check.sql');
  sql+='BEGIN;\n'+read('supabase/pilot-release/candidates/20260916094500_isg_pilot_notebook_images.sql')+'\nCOMMIT;\n'+read('scripts/modules/notebook_images_check.sql');
 }
 if(process.argv.includes('--completed-records')) {
  sql+='BEGIN;\n'+read('supabase/pilot-release/candidates/20260916110000_isg_pilot_completed_drills_certificates.sql')+'\nCOMMIT;\n'+read('scripts/modules/completed_records_check.sql');
  sql+='BEGIN;\n'+read('scripts/modules/learning_fixture.sql')+'\n'+read('supabase/pilot-release/candidates/20260916113000_isg_pilot_employee_learning.sql')+'\nCOMMIT;\n'+read('scripts/modules/employee_learning_check.sql');
  sql+='ALTER TABLE private_isg.file_library_entries ADD COLUMN title text DEFAULT \'Dosya\';\nBEGIN;\n'+read('supabase/migrations/20260915240000_isg_pilot_notice_feed.sql')+'\nCOMMIT;\nBEGIN;\n'+read('supabase/pilot-release/candidates/20260916120000_isg_pilot_unified_followup.sql')+'\nCOMMIT;\n'+read('scripts/modules/unified_followup_check.sql');
  sql+='BEGIN;\n'+read('scripts/modules/file_tags_fixture.sql')+'\n'+read('supabase/pilot-release/candidates/20260916123000_isg_pilot_file_tags.sql')+'\nCOMMIT;\n'+read('scripts/modules/file_tags_check.sql');
  sql+='BEGIN;\n'+read('supabase/pilot-release/candidates/20260916124500_isg_pilot_board_inline_decisions.sql')+'\nCOMMIT;\n'+read('scripts/modules/board_inline_check.sql');
  sql+='BEGIN;\n'+read('supabase/pilot-release/candidates/20260916130000_isg_pilot_learning_read_gate.sql')+'\nCOMMIT;\n'+read('scripts/modules/employee_learning_scope_check.sql');
  sql+="CREATE FUNCTION private_isg.file_library_gate(w bool) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF NOT EXISTS(SELECT 1 FROM private_isg.rollout WHERE feature='modules' AND read_enabled AND (NOT w OR write_enabled)) THEN RAISE EXCEPTION 'FEATURE_UNAVAILABLE'; END IF; END $$;\nBEGIN;\n"+read('supabase/pilot-release/candidates/20260916140000_isg_pilot_personal_files.sql')+'\nCOMMIT;\n'+read('scripts/modules/personal_files_check.sql');
  sql+='BEGIN;\n'+read('scripts/modules/finding_source_fixture.sql')+'\n'+read('supabase/pilot-release/candidates/20260916143000_isg_pilot_finding_source.sql')+'\nCOMMIT;\n'+read('scripts/modules/finding_source_check.sql');
  sql+='BEGIN;\n'+read('supabase/pilot-release/candidates/20260916144500_isg_pilot_shared_file_assets.sql')+'\nCOMMIT;\n'+read('scripts/modules/shared_file_assets_check.sql');
 }
 const out=run(['exec','-i',container,'psql','-U','postgres','-X','-v','ON_ERROR_STOP=1'],sql);
 console.log(out.split('\n').filter(l=>/NOTICE:.*ok|PASSED/.test(l)).join('\n'));
 console.log('PASS: pilot operational module regression');
}finally{if(created)run(['rm','-f',container]);}
