import assert from 'node:assert/strict';
import {test} from 'node:test';
import {preparePersonnelDirectory as prepare} from '../../supabase/functions/_shared/personnel/directory-request.ts';
import {beginAuthPersonnelProbe} from './auth_personnel_probe.mjs';
import {beginPersonnelMigrationProbe} from './personnel_migration_probe.mjs';
import {preparePersonnelRPC} from '../../supabase/functions/_shared/personnel/rpc-request.ts';
import {beginPersonnelHTTPProbe} from './personnel_http_probe.mjs';
import {probePersonnelAdvisors} from './personnel_advisor_probe.mjs';
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const context={schema_version:1,operation_id:id(1),client_mutation_id:id(2),platform:'ios',client_build:1,expected_version:0,scope:{kind:'company',company_id:id(3)}};
const read={action:'employees',company_id:id(3),query:'',include_archived:false,cursor:null};
const edit={action:'edit',context,employee_id:id(4),full_name:'  Ada   Kaya ',department:{kind:'keep'}};
test('directory maps explicit read, detail, edit, archive and create contracts',()=>{
  assert.equal(prepare(read).args.p_kind,'employees');
  assert.equal(prepare({...read,action:'departments'}).args.p_kind,'departments');
  assert.equal(prepare({action:'detail',company_id:id(3),employee_id:id(4)}).args.p_id,id(4));
  assert.equal(prepare(edit).args.p_name,'Ada Kaya');
  assert.equal(prepare(edit).args.p_change_department,false);
  assert.equal(prepare({...edit,department:null}).args.p_change_department,true);
  assert.equal(prepare({...edit,department:{kind:'existing',id:id(5)}}).args.p_department,id(5));
  assert.equal(prepare({...edit,department:{kind:'new',name:' Bakım '}}).args.p_department_name,'Bakım');
  const archive=prepare({action:'archive',context,employee_id:id(4)});
  assert.equal(archive.args.p_change_department,false);assert.equal(archive.args.p_name,null);
  assert.equal(prepare({action:'create',context,full_name:'Ada Kaya',department:null}).kind,'create');
});
for(const [label,input] of Object.entries({
  'null':null,'array':[],unknown:{...read,action:'delete'},owner:{...read,owner_id:id(1)},health:{...edit,medical_note:'x'},
  date:{...edit,hired_on:'2026-01-01'},queryNumber:{...read,query:1},queryUTF8:{...read,query:'ğ'.repeat(101)},
  wrongCursor:{...read,cursor:'x'},noCursor:{action:'employees',company_id:id(3),query:'',include_archived:false},
  archiveDepartments:{...read,action:'departments',include_archived:true},archiveText:{...read,include_archived:'false'},
  detailExtras:{...read,action:'detail',employee_id:id(4)},wrongEmployee:{...edit,employee_id:'x'},
  emptyName:{...edit,full_name:'\u00a0'},hiddenName:{...edit,full_name:'A\u200b'},longName:{...edit,full_name:'a'.repeat(201)},
  noDepartment:{action:'edit',context,employee_id:id(4),full_name:'Ada'},keepExtra:{...edit,department:{kind:'keep',name:'x'}},
  departmentDates:{...edit,department:{kind:'new',name:'Bakım',start:'x'}},emptyDepartment:{...edit,department:{kind:'new',name:''}},
  wrongDepartment:{...edit,department:{kind:'existing',id:'x'}},archiveName:{action:'archive',context,employee_id:id(4),full_name:'x'},
  maxVersion:{...edit,context:{...context,expected_version:Number.MAX_SAFE_INTEGER}},negativeVersion:{...edit,context:{...context,expected_version:-1}},
  workplace:{...edit,context:{...context,scope:{...context.scope,workplace_id:id(6)}}},createKeep:{action:'create',context,full_name:'Ada',department:{kind:'keep'}},
}))test(`directory rejects ${label}`,()=>assert.equal(prepare(input),null));
test('read accepts exact byte boundary and mutation keys remain stable',()=>{
  assert.ok(prepare({...read,query:'ğ'.repeat(100)}));
  const a=prepare(edit),b=prepare(structuredClone(edit));assert.deepEqual(a,b);
  assert.equal(a.args.p_mutation,context.client_mutation_id);assert.equal(a.args.p_operation,context.operation_id);
});
test('personnel Auth probe refuses non-synthetic modes before any SQL',()=>{
  let calls=0;
  for(const synthetic of [false,undefined,null,'true',1])assert.throws(()=>beginAuthPersonnelProbe({synthetic,sql:()=>calls++}),/AUTH_RESTORE_PERSONNEL_SYNTHETIC_REQUIRED/);
  assert.equal(calls,0);
});
test('personnel Auth probe refuses unverified token before DDL',()=>{
  let calls=0;
  assert.throws(()=>beginAuthPersonnelProbe({synthetic:true,token:'bad.token.signature',secret:'a'.repeat(64),sql:()=>calls++}),/AUTH_RESTORE_LOCAL_TOKEN_INVALID/);
  assert.equal(calls,0);
});
test('production RPC mapping preserves checked scope and mutation identity',()=>{
  assert.equal(preparePersonnelRPC({...read,owner_id:id(9)}),null);
  assert.equal(preparePersonnelRPC(read).functionName,'isg_personnel_read_v1');
  assert.equal(preparePersonnelRPC(edit).functionName,'isg_personnel_mutate_v1');
  assert.deepEqual(preparePersonnelRPC(edit).args,prepare(edit).args);
  const create=preparePersonnelRPC({action:'create',context,full_name:'Ada',department:null});
  assert.equal(create.args.p_expected,0);assert.equal(create.args.p_employee,null);
  assert.equal(create.args.p_change_department,true);assert.equal(create.args.p_action,'create');
  assert.equal(create.args.p_mutation,context.client_mutation_id);
  const archive=preparePersonnelRPC({action:'archive',context,employee_id:id(4)});
  assert.equal(archive.args.p_action,'archive');assert.equal(archive.args.p_name,null);
});
test('production migration probe requires synthetic mode before any SQL',async()=>{
  let calls=0;
  for(const synthetic of [false,undefined,null,'true',1])await assert.rejects(beginPersonnelMigrationProbe({synthetic,sql:()=>calls++}),/AUTH_RESTORE_PERSONNEL_MIGRATION_SYNTHETIC_REQUIRED/);
  assert.equal(calls,0);
});
test('production migration probe rejects unverified JWT before DDL',async()=>{
  let calls=0;
  await assert.rejects(beginPersonnelMigrationProbe({synthetic:true,token:'bad.token.signature',secret:'a'.repeat(64),sql:()=>calls++}),/AUTH_RESTORE_LOCAL_TOKEN_INVALID/);
  assert.equal(calls,0);
});
test('HTTP probe requires synthetic mode and verified token before any action',async()=>{
  let calls=0;const sql=()=>calls++,start=()=>calls++;
  for(const synthetic of [false,undefined,null,'true',1])await assert.rejects(beginPersonnelHTTPProbe({synthetic,sql,start}),/AUTH_RESTORE_PERSONNEL_HTTP_SYNTHETIC_REQUIRED/);
  await assert.rejects(beginPersonnelHTTPProbe({synthetic:true,sql,start,token:'bad.token.signature',secret:'a'.repeat(64)}),/AUTH_RESTORE_LOCAL_TOKEN_INVALID/);
  assert.equal(calls,0);
});
test('advisor bridge refuses other modes before SQL, socket, or containers',async()=>{
  let calls=0;
  for(const synthetic of [false,undefined,null,'true',1])await assert.rejects(probePersonnelAdvisors({synthetic,sql:()=>calls++,guard:()=>calls++}),/AUTH_RESTORE_ADVISOR_SYNTHETIC_REQUIRED/);
  assert.equal(calls,0);
});
