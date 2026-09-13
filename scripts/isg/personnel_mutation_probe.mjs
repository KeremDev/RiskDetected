import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { prepareIsgAssignmentMove } from '../../supabase/functions/_shared/personnel/assignment-move.ts';
export async function runPersonnelMutationProbe({query,concurrent,check,killSleepingTransaction}) {
  const id=n=>`00000000-0000-4000-b000-${String(n).padStart(12,'0')}`;
  const actor=id(1), other=id(2), company=id(10), foreign=id(11), workplace=id(20), department=id(30), job=id(40), employee=id(50);
  const tx=(sql,user=actor,fault='')=>`BEGIN; SET LOCAL ROLE isg_workplace_owner; SET LOCAL request.jwt.claim.sub='${user}'; SET LOCAL isg_workplace_fixture.fail_at='${fault}'; ${sql} COMMIT;`;
  const call=(key,version=0,previous=null,on='2026-01-01',c=company,e=employee,j=job)=>`SELECT isg_workplace_fixture.move_primary('${id(key+10000)}','${id(key)}','${c}','${e}',${version},${previous?`'${previous}'`:'NULL'},'${workplace}','${department}','${j}','${on}');`;
  const snapshot=()=>query(`SELECT jsonb_build_object('version',(SELECT assignment_version FROM isg_workplace_fixture.employees WHERE id='${employee}'),'rows',(SELECT count(*) FROM isg_workplace_fixture.employee_assignments WHERE employee_id='${employee}'),'audit',(SELECT count(*) FROM isg_workplace_fixture.personnel_audit),'outbox',(SELECT count(*) FROM isg_workplace_fixture.personnel_outbox),'receipts',(SELECT count(*) FROM isg_workplace_fixture.personnel_receipts));`);
  query(tx(`INSERT INTO isg_workplace_fixture.personnel_write_access VALUES('${actor}',true),('${other}',true);
    INSERT INTO isg_workplace_fixture.legacy_companies(id,owner_id,name) VALUES('${company}','${actor}','Mutasyon firması'),('${foreign}','${other}','Diğer firma');
    INSERT INTO isg_workplace_fixture.workplaces(id,company_id,owner_id,name) VALUES('${workplace}','${company}','${actor}','Tesis');
    INSERT INTO isg_workplace_fixture.departments(id,company_id,owner_id,workplace_id,code,name) VALUES('${department}','${company}','${actor}','${workplace}','D','Birim');
    INSERT INTO isg_workplace_fixture.job_roles(id,company_id,owner_id,code,title) VALUES('${job}','${company}','${actor}','J','Görev');
    INSERT INTO isg_workplace_fixture.employees(id,company_id,owner_id,employee_code,full_name,hired_on) VALUES('${employee}','${company}','${actor}','E','Sentetik kişi','2025-01-01');`));
  let first, second;
  await check('PM-01_private_acl_and_rls',()=>{
    for(const role of ['anon','authenticated','isg_workplace_reader']) assert.equal(query(`SELECT has_function_privilege('${role}','isg_workplace_fixture.move_primary(uuid,uuid,uuid,uuid,bigint,uuid,uuid,uuid,uuid,date)','EXECUTE');`),'f');
    assert.equal(query("SELECT count(*) FROM pg_tables WHERE schemaname='isg_workplace_fixture' AND NOT rowsecurity;"),'0');
    for(const table of ['personnel_write_access','personnel_audit','personnel_outbox','personnel_receipts']) assert.equal(query(`SELECT has_table_privilege('isg_workplace_reader','isg_workplace_fixture.${table}','SELECT');`),'f');
  });
  await check('PM-02_foreign_missing_actor_company_rejected',()=>{
    query(tx(call(100),other),'ACCESS_DENIED'); query(tx(call(100),''),'ACCESS_DENIED');
    query(tx(call(100,0,null,'2026-01-01',id(999))),'ACCESS_DENIED');
  });
  await check('PM-03_assignment_version_audit_outbox_receipt_atomic',()=>{
    first=JSON.parse(query(tx(call(100)))); assert.equal(first.version,1); assert.equal(first.operation_id,id(10100));
    assert.deepEqual(JSON.parse(snapshot()),{version:1,rows:1,audit:1,outbox:1,receipts:1});
  });
  await check('PM-04_identical_retry_returns_original_without_writes',()=>{
    const before=snapshot();assert.deepEqual(JSON.parse(query(tx(call(100)))),first);assert.equal(snapshot(),before);
  });
  await check('PM-05_payload_change_conflict_before_version_check',()=>query(tx(call(100,0,null,'2026-02-01')),'IDEMPOTENCY_CONFLICT'));
  await check('PM-06_stale_version_does_not_change_intervals',()=>query(tx(call(101,0,first.assignment_id,'2026-02-01')),'VERSION_CONFLICT'));
  for(const [i,fault] of ['personnel_audit','personnel_outbox','personnel_receipts'].entries()) await check(`PM-${7+i}_${fault}_failure_rolls_back_everything`,()=>{
    const before=snapshot();query(tx(call(102+i,1,first.assignment_id,'2026-02-01'),actor,fault),'INJECTED_FAILURE');assert.equal(snapshot(),before);
    assert.equal(query(`SELECT ends_before IS NULL FROM isg_workplace_fixture.employee_assignments WHERE id='${first.assignment_id}';`),'t');
  });
  await check('PM-10_twenty_parallel_retries_apply_one_move',async()=>{
    const results=await Promise.all(Array.from({length:20},()=>concurrent(tx(call(105,1,first.assignment_id,'2026-02-01')))));
    assert.ok(results.every(r=>r.ok));assert.equal(new Set(results.map(r=>r.output)).size,1);second=JSON.parse(results[0].output);
    assert.deepEqual(JSON.parse(snapshot()),{version:2,rows:2,audit:2,outbox:2,receipts:2});
  });
  await check('PM-11_twenty_competing_versions_have_one_winner',async()=>{
    const results=await Promise.all(Array.from({length:20},(_,i)=>concurrent(tx(call(200+i,2,second.assignment_id,'2026-03-01')))));
    assert.equal(results.filter(r=>r.ok).length,1);assert.equal(results.filter(r=>r.error==='VERSION_CONFLICT').length,19);
    second=JSON.parse(results.find(r=>r.ok).output);
  });
  await check('PM-12_access_revocation_blocks_cached_replay',()=>{
    query(tx(`UPDATE isg_workplace_fixture.personnel_write_access SET enabled=false WHERE actor_id='${actor}';`));query(tx(call(100)),'ACCESS_DENIED');
    query(tx(`UPDATE isg_workplace_fixture.personnel_write_access SET enabled=true WHERE actor_id='${actor}';`));
    for(const [table,key] of [['legacy_companies',company],['employees',employee]]){
      query(tx(`UPDATE isg_workplace_fixture.${table} SET is_archived=true WHERE id='${key}';`));query(tx(call(100)),'ACCESS_DENIED');
      query(tx(`UPDATE isg_workplace_fixture.${table} SET is_archived=false WHERE id='${key}';`));
    }
  });
  await check('PM-13_invalid_destination_rolls_back_old_assignment_close',()=>{
    const before=snapshot();query(tx(call(300,3,second.assignment_id,'2026-04-01',company,employee,id(999))),'ASSIGNMENT_SCOPE_INVALID');assert.equal(snapshot(),before);
  });
  await check('PM-14_missing_previous_and_wrong_date_rejected',()=>{
    query(tx(call(301,3,id(999),'2026-04-01')),'ASSIGNMENT_SCOPE_INVALID');
    query(tx(call(301,3,second.assignment_id,'2026-03-01')),'VALIDATION_ERROR');
  });
  await check('PM-15_connection_loss_rolls_back_and_retry_commits',async()=>{
    const before=snapshot();await killSleepingTransaction(tx(`${call(302,3,second.assignment_id,'2026-04-01')} SELECT pg_sleep(7);`),'personnel_mutation');assert.equal(snapshot(),before);
    const result=JSON.parse(query(tx(call(302,3,second.assignment_id,'2026-04-01'))));assert.equal(result.version,4);
  });
  await check('PM-16_receipt_replays_after_later_moves_without_new_event',()=>{
    const before=snapshot();assert.deepEqual(JSON.parse(query(tx(call(100)))),first);assert.equal(snapshot(),before);
    assert.equal(query("SELECT count(*) FROM information_schema.columns WHERE table_schema='isg_workplace_fixture' AND table_name='personnel_outbox' AND data_type IN ('json','jsonb');"),'0');
  });
  await check('PM-17_finite_employment_end_survives_move',()=>{
    query(tx(`INSERT INTO isg_workplace_fixture.employees(id,company_id,owner_id,employee_code,full_name,hired_on,employment_ends_before) VALUES('${id(60)}','${company}','${actor}','E2','Sentetik iki','2025-01-01','2026-06-01');`));
    const initial=JSON.parse(query(tx(call(400,0,null,'2026-01-01',company,id(60)))));
    const moved=JSON.parse(query(tx(call(401,1,initial.assignment_id,'2026-03-01',company,id(60)))));
    assert.equal(query(`SELECT ends_before FROM isg_workplace_fixture.employee_assignments WHERE id='${moved.assignment_id}';`),'2026-06-01');
    assert.equal(query(`SELECT ends_before FROM isg_workplace_fixture.employee_assignments WHERE id='${initial.assignment_id}';`),'2026-03-01');
  });
  await check('PM-18_nulls_overflow_and_operation_change_fail_closed',()=>{
    for(const token of [`'${id(10100)}'`,`'${id(100)}'`,`'2026-01-01'`]) query(tx(call(100).replace(token,'NULL')),'VALIDATION_ERROR');
    for(const version of [-1,9007199254740991]) query(tx(call(100,version)),'VALIDATION_ERROR');
    query(tx(call(100).replace(`'${id(10100)}'`,`'${id(999)}'`)),'IDEMPOTENCY_CONFLICT');
  });

  // Trusted test adapter: only validated scalar arguments enter SQL. Not an API.
  const preparedCall=input=>{
    const args=prepareIsgAssignmentMove(input);
    if(!args)throw new Error('VALIDATION_ERROR');
    const values=Object.entries(args).map(([key,value])=>`${key} => ${value===null?'NULL':typeof value==='number'?String(value):"'"+value.replaceAll("'","''")+"'"}`);
    return `SELECT isg_workplace_fixture.move_primary(${values.join(',')});`;
  };
  const corpus=JSON.parse(readFileSync(new URL('../../contracts/isg/v1/fixtures/assignment-move.json',import.meta.url),'utf8'));
  await check('PM-19_actual_server_preparation_matches_all_61_mobile_fixtures',()=>{
    assert.equal(corpus.cases.length,61);
    for(const c of corpus.cases) assert.equal(prepareIsgAssignmentMove(c.input)!==null,c.valid,c.id);
  });
  const request={context:{schema_version:1,operation_id:id(10500),client_mutation_id:id(500),platform:'ios',client_build:1,
    expected_version:0,scope:{kind:'company',company_id:company,workplace_id:workplace}},employee_id:id(70),previous_assignment_id:null,
    department_id:department,job_role_id:job,starts_on:'2026-01-01'};
  await check('PM-20_prepared_mobile_request_commits_moves_and_replays',()=>{
    query(tx(`INSERT INTO isg_workplace_fixture.employees(id,company_id,owner_id,employee_code,full_name,hired_on) VALUES('${id(70)}','${company}','${actor}','E3','Sentetik üç','2025-01-01');`));
    const initial=JSON.parse(query(tx(preparedCall(request))));
    assert.equal(initial.operation_id,request.context.operation_id);assert.equal(initial.version,1);
    assert.deepEqual(JSON.parse(query(tx(preparedCall(request)))),initial);
    request.context={...request.context,operation_id:id(10501),client_mutation_id:id(501),platform:'android',expected_version:1};
    request.previous_assignment_id=initial.assignment_id;request.starts_on='2026-02-01';
    const moved=JSON.parse(query(tx(preparedCall(request))));
    assert.equal(moved.version,2);assert.equal(moved.operation_id,id(10501));
    assert.equal(query(`SELECT ends_before FROM isg_workplace_fixture.employee_assignments WHERE id='${initial.assignment_id}';`),'2026-02-01');
    assert.deepEqual(JSON.parse(query(tx(preparedCall(request)))),moved);
  });
  await check('PM-21_prepared_scope_is_not_authority_and_invalid_input_never_executes',()=>{
    const before=snapshot();
    query(tx(preparedCall(request),other),'ACCESS_DENIED');
    query(tx(preparedCall({...request,context:{...request.context,operation_id:id(10502),client_mutation_id:id(502)}})),'VERSION_CONFLICT');
    assert.throws(()=>preparedCall({...request,user_id:actor}),/VALIDATION_ERROR/);
    assert.throws(()=>preparedCall({...request,starts_on:"2026-01-01');SELECT 1;--"}),/VALIDATION_ERROR/);
    assert.equal(snapshot(),before);
  });
}
