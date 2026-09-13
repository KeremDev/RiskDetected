import assert from 'node:assert/strict';
import {prepareIsgEmployeeCreate} from '../../supabase/functions/_shared/personnel/employee-create.ts';
export async function runEmployeeIntakeProbe({query,concurrent,check,killSleepingTransaction}) {
  const id=n=>`00000000-0000-4000-a100-${String(n).padStart(12,'0')}`;
  const actor=id(1), other=id(2), company=id(10), foreign=id(11);
  const tx=(sql,user=actor,fault='')=>`BEGIN; SET LOCAL ROLE isg_workplace_owner; SET LOCAL request.jwt.claim.sub='${user}'; SET LOCAL isg_workplace_fixture.fail_at='${fault}'; ${sql} COMMIT;`;
  const input=(key,name='Ayşe Yılmaz',department=null,c=company)=>({context:{schema_version:1,operation_id:id(key+10000),client_mutation_id:id(key),platform:'ios',client_build:1,expected_version:0,scope:{kind:'company',company_id:c}},full_name:name,department});
  const call=(...args)=>{
    const p=prepareIsgEmployeeCreate(input(...args));assert.ok(p);
    return `SELECT isg_workplace_fixture.create_employee(${Object.entries(p).map(([k,v])=>`${k} => ${v===null?'NULL':"'"+v.replaceAll("'","''")+"'"}`).join(',')});`;
  };
  const snapshot=()=>query(`SELECT jsonb_build_array((SELECT count(*) FROM isg_workplace_fixture.employees),(SELECT count(*) FROM isg_workplace_fixture.departments),(SELECT count(*) FROM isg_workplace_fixture.workplaces),(SELECT count(*) FROM isg_workplace_fixture.employee_create_audit),(SELECT count(*) FROM isg_workplace_fixture.employee_create_outbox),(SELECT count(*) FROM isg_workplace_fixture.employee_create_receipts));`);
  const denied=(sql,error,user=actor,fault='')=>{const before=snapshot();query(tx(sql,user,fault),error);assert.equal(snapshot(),before);};
  query(tx(`INSERT INTO isg_workplace_fixture.personnel_write_access VALUES('${actor}',true),('${other}',true);
    INSERT INTO isg_workplace_fixture.legacy_companies(id,owner_id,name) VALUES('${company}','${actor}','Kolay kayıt firması'),('${foreign}','${other}','Yabancı firma');`));
  let first, withDepartment;
  await check('EI-01_private_acl_and_rls',()=>{
    for(const role of ['authenticated','anon','isg_workplace_reader'])assert.equal(query(`SELECT has_function_privilege('${role}','isg_workplace_fixture.create_employee(uuid,uuid,uuid,text,uuid,text)','EXECUTE');`),'f');
    assert.equal(query("SELECT count(*) FROM pg_tables WHERE schemaname='isg_workplace_fixture' AND NOT rowsecurity;"),'0');
  });
  await check('EI-02_name_only_no_dates_no_job_no_department',()=>{
    first=JSON.parse(query(tx(call(100))));assert.equal(first.department_id,null);assert.equal(first.version,0);
    assert.equal(query(`SELECT full_name||':'||(hired_on IS NULL AND employment_ends_before IS NULL AND intake_department_id IS NULL AND registered_at IS NOT NULL)::text FROM isg_workplace_fixture.employees WHERE id='${first.employee_id}';`),'Ayşe Yılmaz:true');
    assert.equal(query(`SELECT count(*) FROM isg_workplace_fixture.employee_assignments WHERE employee_id='${first.employee_id}';`),'0');
    assert.equal(query(`SELECT count(*) FROM isg_workplace_fixture.workplaces WHERE company_id='${company}';`),'0');
  });
  await check('EI-03_identical_retry_and_same_names_are_distinct_people',()=>{
    const before=snapshot();assert.deepEqual(JSON.parse(query(tx(call(100)))),first);assert.equal(snapshot(),before);
    const second=JSON.parse(query(tx(call(101))));assert.notEqual(second.employee_id,first.employee_id);
    denied(call(100,'Başka kişi'),'IDEMPOTENCY_CONFLICT');
  });
  await check('EI-04_manual_department_created_and_linked_atomically',()=>{
    withDepartment=JSON.parse(query(tx(call(102,' Mehmet  Kaya ',{kind:'new',name:'  İŞLER  Birimi '}))));
    assert.equal(withDepartment.department_created,true);
    assert.equal(query(`SELECT d.name||':'||e.full_name FROM isg_workplace_fixture.employees e JOIN isg_workplace_fixture.departments d ON d.id=e.intake_department_id WHERE e.id='${withDepartment.employee_id}' AND d.company_id='${company}';`),'İŞLER Birimi:Mehmet Kaya');
  });
  await check('EI-05_typed_existing_name_reused_with_Turkish_case_and_spaces',()=>{
    const result=JSON.parse(query(tx(call(103,'Ali',{kind:'new',name:'işler\tbirimi'}))));
    assert.equal(result.department_created,false);assert.equal(result.department_id,withDepartment.department_id);
    assert.equal(query(`SELECT isg_workplace_fixture.department_name_key('ISITMA ÇÖZÜM ŞĞ')=isg_workplace_fixture.department_name_key('ısıtma çözüm şğ');`),'t');
  });
  await check('EI-06_optional_selection_existing_or_none_when_list_nonempty',()=>{
    const result=JSON.parse(query(tx(call(104,'Can',{kind:'existing',id:withDepartment.department_id}))));assert.equal(result.department_id,withDepartment.department_id);
    assert.equal(JSON.parse(query(tx(call(105)))).department_id,null);
  });
  await check('EI-07_foreign_missing_and_archived_targets_denied',()=>{
    denied(call(106),'ACCESS_DENIED',other);denied(call(106,'Ali',null,id(999)),'ACCESS_DENIED');
    denied(call(106,'Ali',{kind:'existing',id:id(999)}),'DEPARTMENT_SCOPE_INVALID');
    query(tx(`UPDATE isg_workplace_fixture.departments SET is_archived=true WHERE id='${withDepartment.department_id}';`));
    denied(call(106,'Ali',{kind:'existing',id:withDepartment.department_id}),'DEPARTMENT_SCOPE_INVALID');
    query(tx(`UPDATE isg_workplace_fixture.departments SET is_archived=false WHERE id='${withDepartment.department_id}';`));
    denied(call(106,'Ali',{kind:'existing',id:withDepartment.department_id},foreign),'ACCESS_DENIED');
  });
  for(const [i,fault] of ['employee_create_audit','employee_create_outbox','employee_create_receipts'].entries())await check(`EI-${8+i}_inline_department_and_employee_rollback_${fault}`,()=>{
    denied(call(110+i,'Test',{kind:'new',name:`Rollback ${i}`}), 'INJECTED_FAILURE',actor,fault);
  });
  await check('EI-11_twenty_parallel_retries_one_employee_one_department',async()=>{
    const results=await Promise.all(Array.from({length:20},()=>concurrent(tx(call(120,'Paralel',{kind:'new',name:'Paketleme'})))));
    assert.ok(results.every(r=>r.ok));assert.equal(new Set(results.map(r=>r.output)).size,1);
    assert.equal(query(`SELECT count(*) FROM isg_workplace_fixture.departments WHERE company_id='${company}' AND name='Paketleme';`),'1');
  });
  await check('EI-12_twenty_people_same_new_department_no_duplicates',async()=>{
    const results=await Promise.all(Array.from({length:20},(_,i)=>concurrent(tx(call(200+i,`Çalışan ${i}`,{kind:'new',name:i%2?'Teknik Servis':' TEKNİK   SERVİS '})))));
    assert.ok(results.every(r=>r.ok));const values=results.map(r=>JSON.parse(r.output));
    assert.equal(new Set(values.map(r=>r.employee_id)).size,20);assert.equal(new Set(values.map(r=>r.department_id)).size,1);assert.equal(values.filter(r=>r.department_created).length,1);
  });
  await check('EI-13_real_connection_loss_no_orphans_retry_succeeds',async()=>{
    const before=snapshot();await killSleepingTransaction(tx(`${call(300,'Kesinti',{kind:'new',name:'Kesinti Birimi'})} SELECT pg_sleep(7);`),'employee_intake');assert.equal(snapshot(),before);
    assert.equal(JSON.parse(query(tx(call(300,'Kesinti',{kind:'new',name:'Kesinti Birimi'})))).department_created,true);
  });
  await check('EI-14_revoked_access_or_archived_employee_cannot_replay',()=>{
    query(tx(`UPDATE isg_workplace_fixture.personnel_write_access SET enabled=false WHERE actor_id='${actor}';`));denied(call(100),'ACCESS_DENIED');
    query(tx(`UPDATE isg_workplace_fixture.personnel_write_access SET enabled=true WHERE actor_id='${actor}'; UPDATE isg_workplace_fixture.employees SET is_archived=true WHERE id='${first.employee_id}';`));denied(call(100),'ACCESS_DENIED');
  });
  await check('EI-15_ambiguous_existing_department_requires_explicit_selection',()=>{
    query(tx(`INSERT INTO isg_workplace_fixture.departments(company_id,owner_id,workplace_id,code,name) SELECT company_id,owner_id,workplace_id,'DUPLICATE','işler birimi' FROM isg_workplace_fixture.departments WHERE id='${withDepartment.department_id}';`));
    denied(call(301,'Test',{kind:'new',name:'İşler Birimi'}),'DEPARTMENT_SELECTION_REQUIRED');
    assert.equal(JSON.parse(query(tx(call(302,'Test',{kind:'existing',id:withDepartment.department_id})))).department_id,withDepartment.department_id);
  });
  await check('EI-16_database_rejects_invalid_name_and_both_department_modes',()=>{
    for(const name of ["''","NULL","repeat('a',201)","E'\\001'","U&'\\00A0'"])denied(call(400).replace("'Ayşe Yılmaz'",name),'VALIDATION_ERROR');
    denied(call(400).replace('p_department_name => NULL',"p_department_name => U&'\\00A0'"),'VALIDATION_ERROR');
    denied(call(400).replace('p_department => NULL',`p_department => '${withDepartment.department_id}'`).replace('p_department_name => NULL',"p_department_name => 'Yeni'"),'VALIDATION_ERROR');
  });
  await check('EI-17_same_owner_foreign_company_department_cannot_cross_link',()=>{
    query(tx(`INSERT INTO isg_workplace_fixture.legacy_companies(id,owner_id,name) VALUES('${id(12)}','${actor}','İkinci firma');`));
    denied(call(401,'Test',{kind:'existing',id:withDepartment.department_id},id(12)),'DEPARTMENT_SCOPE_INVALID');
    const separate=JSON.parse(query(tx(call(402,'Test',null,id(12)))));
    denied(`UPDATE isg_workplace_fixture.employees SET intake_department_id='${withDepartment.department_id}' WHERE id='${separate.employee_id}';`,'foreign key constraint');
  });
  await check('EI-18_first_inline_department_failure_rolls_back_default_workplace',()=>{
    for(const [i,fault] of ['employee_create_audit','employee_create_outbox','employee_create_receipts'].entries())denied(call(410+i,'Test',{kind:'new',name:'İlk Departman'},id(12)),'INJECTED_FAILURE',actor,fault);
    assert.equal(query(`SELECT count(*) FROM isg_workplace_fixture.workplaces WHERE company_id='${id(12)}';`),'0');
  });
  await check('EI-19_company_archive_blocks_saved_result_and_employee_read_is_owner_scoped',()=>{
    query(tx(`UPDATE isg_workplace_fixture.legacy_companies SET is_archived=true WHERE id='${company}';`));denied(call(102,'Mehmet Kaya',{kind:'new',name:'işler birimi'}),'ACCESS_DENIED');
    assert.equal(query(`BEGIN; SET LOCAL ROLE isg_workplace_reader; SET LOCAL request.jwt.claim.sub='${other}'; SELECT count(*) FROM isg_workplace_fixture.employees WHERE company_id='${company}'; COMMIT;`),'0');
    assert.equal(query(`SELECT bool_and(hired_on IS NULL AND employment_ends_before IS NULL) FROM isg_workplace_fixture.employees WHERE company_id='${company}';`),'t');
  });
}
