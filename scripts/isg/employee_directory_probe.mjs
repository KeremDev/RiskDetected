import assert from 'node:assert/strict';
import {preparePersonnelDirectory} from '../../supabase/functions/_shared/personnel/directory-request.ts';
export async function runEmployeeDirectoryProbe({query,concurrent,check,killSleepingTransaction}) {
  const id=n=>`00000000-0000-4000-a200-${String(n).padStart(12,'0')}`;
  const actor=id(1),other=id(2),company=id(10),foreign=id(11),employee=id(100);
  const tx=(sql,user=actor,fault='')=>`BEGIN; SET LOCAL ROLE isg_workplace_owner; SET LOCAL request.jwt.claim.sub='${user}'; SET LOCAL isg_workplace_fixture.fail_at='${fault}'; ${sql} COMMIT;`;
  const sql=input=>{
    const p=preparePersonnelDirectory(input);assert.ok(p);
    const fn={read:'read_personnel',create:'create_employee',edit:'edit_employee'}[p.kind];
    return `SELECT isg_workplace_fixture.${fn}(${Object.entries(p.args).map(([k,v])=>`${k} => ${v===null?'NULL':typeof v==='string'?"'"+v.replaceAll("'","''")+"'":v}`).join(',')});`;
  };
  const edit=(key,version=0,department={kind:'keep'},name='Yeni Ad',action='edit')=>({action,context:{schema_version:1,operation_id:id(key+10000),client_mutation_id:id(key),platform:'ios',client_build:1,expected_version:version,scope:{kind:'company',company_id:company}},employee_id:employee,...(action==='edit'?{full_name:name,department}:{})});
  const list=(action='employees',cursor=null,search='',archived=false,c=company)=>({action,company_id:c,query:search,include_archived:archived,cursor});
  const detail={action:'detail',company_id:company,employee_id:employee};
  const snapshot=()=>query(`SELECT jsonb_build_array((SELECT jsonb_agg(to_jsonb(e) ORDER BY e.id) FROM isg_workplace_fixture.employees e WHERE company_id='${company}'),(SELECT count(*) FROM isg_workplace_fixture.departments),(SELECT count(*) FROM isg_workplace_fixture.employee_edit_audit),(SELECT count(*) FROM isg_workplace_fixture.employee_edit_outbox),(SELECT count(*) FROM isg_workplace_fixture.employee_edit_receipts));`);
  const deny=(input,error,user=actor,fault='')=>{const before=snapshot();query(tx(sql(input),user,fault),error);assert.equal(snapshot(),before);};
  query(tx(`INSERT INTO isg_workplace_fixture.personnel_write_access VALUES('${actor}',true),('${other}',true);
    INSERT INTO isg_workplace_fixture.legacy_companies(id,owner_id,name) VALUES('${company}','${actor}','Rehber firması'),('${foreign}','${other}','Diğer');
    INSERT INTO isg_workplace_fixture.employees(id,company_id,owner_id,employee_code,full_name) SELECT ('00000000-0000-4000-a200-'||lpad(n::text,12,'0'))::uuid,'${company}','${actor}','P-'||n,'Personel '||n FROM generate_series(100,222) n;`));
  await check('ED-01_private_functions_and_journals',()=>{
    for(const fn of ['read_personnel(uuid,text,text,boolean,uuid,uuid)','edit_employee(uuid,uuid,uuid,uuid,bigint,text,text,boolean,uuid,text)'])for(const role of ['authenticated','anon','isg_workplace_reader'])assert.equal(query(`SELECT has_function_privilege('${role}','isg_workplace_fixture.${fn}','EXECUTE');`),'f');
    assert.equal(query("SELECT count(*) FROM pg_tables WHERE schemaname='isg_workplace_fixture' AND NOT rowsecurity;"),'0');
  });
  await check('ED-02_keyset_pages_50_50_23_without_duplicates',()=>{
    const all=[];let cursor=null;const sizes=[];
    do {const result=JSON.parse(query(tx(sql(list('employees',cursor)))));sizes.push(result.rows.length);all.push(...result.rows.map(r=>r.id));cursor=result.next;}while(cursor);
    assert.deepEqual(sizes,[50,50,23]);assert.equal(new Set(all).size,123);
  });
  await check('ED-03_search_literal_and_scope_no_wildcard_expansion',()=>{
    assert.equal(JSON.parse(query(tx(sql(list('employees',null,'Personel 10'))))).rows.length,10);
    assert.equal(JSON.parse(query(tx(sql(list('employees',null,'%'))))).rows.length,0);
    deny(list(),'ACCESS_DENIED',other);deny({...detail,employee_id:id(999)},'ACCESS_DENIED');
  });
  await check('ED-04_detail_no_dates_or_health_payload',()=>{
    const row=JSON.parse(query(tx(sql(detail))));assert.equal(row.name,'Personel 100');assert.equal(row.department_id,null);
    assert.deepEqual(Object.keys(row).sort(),['id','owner_id','company_id','name','department_id','department_name','version','is_archived'].sort());
  });
  await check('ED-05_edit_name_inline_department_and_retry',()=>{
    const first=JSON.parse(query(tx(sql(edit(300,0,{kind:'new',name:'Bakım'})))));assert.equal(first.version,1);
    const row=JSON.parse(query(tx(sql(detail))));assert.equal(row.name,'Yeni Ad');assert.equal(row.department_name,'Bakım');assert.equal(row.version,1);
    const before=snapshot();assert.deepEqual(JSON.parse(query(tx(sql(edit(300,0,{kind:'new',name:'Bakım'}))))),first);assert.equal(snapshot(),before);
    deny(edit(300,0,{kind:'new',name:'Başka'}),'IDEMPOTENCY_CONFLICT');deny(edit(301,0),'VERSION_CONFLICT');
  });
  for(const [i,fault] of ['employee_edit_audit','employee_edit_outbox','employee_edit_receipts'].entries())await check(`ED-${6+i}_fault_rollback_${fault}`,()=>deny(edit(310+i,1,{kind:'new',name:'Hata birimi'}),'INJECTED_FAILURE',actor,fault));
  await check('ED-09_twenty_parallel_edits_one_version_winner',async()=>{
    const results=await Promise.all(Array.from({length:20},(_,i)=>concurrent(tx(sql(edit(400+i,1))))));assert.equal(results.filter(r=>r.ok).length,1);assert.equal(results.filter(r=>r.error==='VERSION_CONFLICT').length,19);
  });
  await check('ED-10_connection_loss_rolls_back_edit_and_department',async()=>{
    const before=snapshot();await killSleepingTransaction(tx(`${sql(edit(450,2,{kind:'new',name:'Kesinti'}))} SELECT pg_sleep(7);`),'directory_edit');assert.equal(snapshot(),before);
  });
  await check('ED-11_department_clear_and_search',()=>{
    const options=JSON.parse(query(tx(sql(list('departments',null,'BAKIM')))));assert.equal(options.rows.length,1);
    query(tx(sql(edit(451,2,null))));assert.equal(JSON.parse(query(tx(sql(detail)))).department_id,null);
  });
  await check('ED-12_archive_is_versioned_retryable_and_not_delete',()=>{
    const beforeCount=query(`SELECT count(*) FROM isg_workplace_fixture.employees WHERE company_id='${company}';`);
    const result=JSON.parse(query(tx(sql(edit(500,3,null,'','archive')))));assert.equal(result.version,4);
    assert.deepEqual(JSON.parse(query(tx(sql(edit(500,3,null,'','archive'))))),result);
    assert.equal(JSON.parse(query(tx(sql(detail)))).is_archived,true);
    assert.equal(query(`SELECT count(*) FROM isg_workplace_fixture.employees WHERE company_id='${company}';`),beforeCount);
    assert.ok(!JSON.parse(query(tx(sql(list())))).rows.some(r=>r.id===employee));
    assert.ok(JSON.parse(query(tx(sql(list('employees',null,'',true))))).rows.some(r=>r.id===employee));
    deny(edit(501,4),'ACCESS_DENIED');
  });
  await check('ED-13_archived_company_readable_but_write_and_replay_denied',()=>{
    query(tx(`UPDATE isg_workplace_fixture.legacy_companies SET is_archived=true WHERE id='${company}';`));
    assert.equal(JSON.parse(query(tx(sql(detail)))).id,employee);deny(edit(500,3,null,'','archive'),'ACCESS_DENIED');
  });
  await check('ED-14_historical_and_future_assignment_projection_preserves_snapshots',()=>{
    query(tx(`UPDATE isg_workplace_fixture.legacy_companies SET is_archived=false WHERE id='${company}';
      INSERT INTO isg_workplace_fixture.departments(id,company_id,owner_id,workplace_id,code,name)
        VALUES('${id(600)}','${company}','${actor}',isg_workplace_fixture.ensure_default('${company}'),'FIELD','Saha');
      INSERT INTO isg_workplace_fixture.job_roles(id,company_id,owner_id,code,title) VALUES('${id(601)}','${company}','${actor}','TECH','Teknisyen');
      UPDATE isg_workplace_fixture.employees SET intake_department_id=(SELECT id FROM isg_workplace_fixture.departments WHERE company_id='${company}' AND name='Bakım') WHERE id='${id(101)}';
      INSERT INTO isg_workplace_fixture.employee_assignments(id,company_id,owner_id,employee_id,workplace_id,department_id,job_role_id,starts_on,ends_before,department_name_snapshot,job_title_snapshot)
        VALUES('${id(602)}','${company}','${actor}','${id(101)}',isg_workplace_fixture.ensure_default('${company}'),'${id(600)}','${id(601)}','2030-01-01','2031-01-01','untrusted','untrusted');
      UPDATE isg_workplace_fixture.departments SET name='Yeni saha adı' WHERE id='${id(600)}';`));
    const at=date=>JSON.parse(query(tx(`SELECT isg_workplace_fixture.employee_row('${company}','${id(101)}','${date}');`)));
    assert.equal(at('2029-12-31').department_name,'Bakım');
    assert.equal(at('2030-01-01').department_name,'Saha');assert.equal(at('2030-12-31').department_name,'Saha');
    assert.equal(at('2031-01-01').department_name,'Bakım');
  });
  await check('ED-15_name_only_edit_keeps_dated_history_department_changes_require_assignment_flow',()=>{
    const request={...edit(610),employee_id:id(101)};
    const history=query(`SELECT to_jsonb(a) FROM isg_workplace_fixture.employee_assignments a WHERE id='${id(602)}';`);
    query(tx(sql(request)));
    assert.equal(JSON.parse(query(tx(sql({...detail,employee_id:id(101)})))).name,'Yeni Ad');
    deny({...request,context:{...request.context,client_mutation_id:id(611),operation_id:id(10611),expected_version:1},department:null},'ASSIGNMENT_CHANGE_REQUIRED');
    assert.equal(query(`SELECT to_jsonb(a) FROM isg_workplace_fixture.employee_assignments a WHERE id='${id(602)}';`),history);
  });
  await check('ED-16_revoked_write_access_rejects_cached_receipt',()=>{
    query(tx(`UPDATE isg_workplace_fixture.personnel_write_access SET enabled=false WHERE actor_id='${actor}';`));
    deny(edit(500,3,null,'','archive'),'ACCESS_DENIED');
    assert.equal(JSON.parse(query(tx(sql(detail)))).id,employee);
    query(tx(`UPDATE isg_workplace_fixture.personnel_write_access SET enabled=true WHERE actor_id='${actor}';`));
  });
  await check('ED-17_missing_department_rejected_without_partial_name_edit',()=>{
    deny({...edit(620,0,{kind:'existing',id:id(999)}),employee_id:id(102)},'DEPARTMENT_SCOPE_INVALID');
  });
}
