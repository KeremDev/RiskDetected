import assert from 'node:assert/strict';

export async function runPersonnelProbe({query, concurrent, check, killSleepingTransaction}) {
  const id = n => `00000000-0000-4000-a000-${String(n).padStart(12,'0')}`;
  const a=id(1), b=id(2), c=id(10), c2=id(11), cb=id(12);
  const w=id(20), w2=id(21), wc2=id(22), wb=id(23);
  const d=id(30), d2=id(31), dc2=id(32), db=id(33), j=id(40), jc2=id(41), jb=id(42);
  const e=id(50), e2=id(51), ec2=id(52), eb=id(53);
  const worker = sql => `BEGIN; SET LOCAL ROLE isg_workplace_owner; ${sql} COMMIT;`;
  const reader = (sql,owner=a) => `BEGIN; SET LOCAL ROLE isg_workplace_reader; SET LOCAL request.jwt.claim.sub='${owner}'; ${sql} COMMIT;`;
  const assignment = (n, options={}) => {
    const p={company:c,owner:a,employee:e,workplace:w,department:d,job:j,start:'2026-01-01',end:'2026-02-01',kind:'primary',...options};
    return `INSERT INTO isg_workplace_fixture.employee_assignments(id,company_id,owner_id,employee_id,workplace_id,department_id,job_role_id,starts_on,ends_before,kind,department_name_snapshot,job_title_snapshot)
      VALUES ('${id(n)}','${p.company}','${p.owner}','${p.employee}','${p.workplace}','${p.department}','${p.job}','${p.start}',${p.end===null?'NULL':`'${p.end}'`},'${p.kind}','untrusted','untrusted');`;
  };
  const employee = (n,company=c,owner=a,code=`EMP-${n}`) => `INSERT INTO isg_workplace_fixture.employees(id,company_id,owner_id,employee_code,full_name,hired_on) VALUES ('${id(n)}','${company}','${owner}','${code}','Aynı İsim','2025-01-01');`;
  const count = () => query('SELECT count(*) FROM isg_workplace_fixture.employee_assignments;');
  query(worker(`INSERT INTO isg_workplace_fixture.legacy_companies(id,owner_id,name) VALUES ('${c}','${a}','Firma A'),('${c2}','${a}','Firma B'),('${cb}','${b}','Firma C');
    INSERT INTO isg_workplace_fixture.workplaces(id,company_id,owner_id,name) VALUES ('${w}','${c}','${a}','Tesis'),('${w2}','${c}','${a}','Tesis'),('${wc2}','${c2}','${a}','Tesis'),('${wb}','${cb}','${b}','Tesis');
    INSERT INTO isg_workplace_fixture.departments(id,company_id,owner_id,workplace_id,code,name) VALUES ('${d}','${c}','${a}','${w}','BAK','Bakım'),('${d2}','${c}','${a}','${w2}','BAK','Bakım'),('${dc2}','${c2}','${a}','${wc2}','BAK','Bakım'),('${db}','${cb}','${b}','${wb}','BAK','Bakım');
    INSERT INTO isg_workplace_fixture.job_roles(id,company_id,owner_id,code,title) VALUES ('${j}','${c}','${a}','TEK','Teknisyen'),('${jc2}','${c2}','${a}','TEK','Teknisyen'),('${jb}','${cb}','${b}','TEK','Teknisyen');
    ${employee(50)} ${employee(51)} ${employee(52,c2,a,'EMP-50')} ${employee(53,cb,b,'EMP-50')}`));
  await check('PER-01_explicit_read_grants_rls_and_no_client_functions', () => {
    assert.equal(query("SELECT count(*) FROM pg_tables WHERE schemaname='isg_workplace_fixture' AND NOT rowsecurity;"),'0');
    for (const fn of ['assignment_guard','employment_guard']) for(const role of ['anon','authenticated','isg_workplace_reader']) {
      assert.equal(query(`SELECT has_function_privilege('${role}','isg_workplace_fixture.${fn}()','EXECUTE');`),'f');
    }
    for(const table of ['departments','job_roles','employees','employee_assignments']) {
      for(const verb of ['INSERT','UPDATE','DELETE']) assert.equal(query(`SELECT has_table_privilege('isg_workplace_reader','isg_workplace_fixture.${table}','${verb}');`),'f');
    }
  });
  await check('PER-02_same_names_distinct_and_codes_scoped', () => {
    assert.equal(query(reader('SELECT count(*) FROM isg_workplace_fixture.employees;')),'3');
    assert.equal(query(reader('SELECT count(*) FROM isg_workplace_fixture.employees;',b)),'1');
    assert.equal(query(reader('SELECT count(*) FROM isg_workplace_fixture.employees;','')),'0');
    query(worker(employee(54,c,a,'EMP-50')),'unique constraint');
    query(worker(`INSERT INTO isg_workplace_fixture.departments(company_id,owner_id,workplace_id,code,name) VALUES ('${c}','${a}','${w}','BAK','Farklı ad');`),'unique constraint');
    query(worker(`INSERT INTO isg_workplace_fixture.job_roles(company_id,owner_id,code,title) VALUES ('${c}','${a}','TEK','Farklı ad');`),'unique constraint');
  });
  await check('PER-03_wrong_owner_and_workplace_fks_reject', () => {
    query(worker(employee(54,c,b)),'foreign key constraint');
    query(worker(`INSERT INTO isg_workplace_fixture.departments(company_id,owner_id,workplace_id,code,name) VALUES ('${c}','${a}','${wc2}','X','X');`),'foreign key constraint');
  });
  await check('PER-04_assignment_captures_server_labels_not_input', () => {
    query(worker(assignment(100)));
    assert.equal(query(`SELECT department_name_snapshot||':'||job_title_snapshot FROM isg_workplace_fixture.employee_assignments WHERE id='${id(100)}';`),'Bakım:Teknisyen');
  });
  await check('PER-05_same_owner_foreign_company_employee_job_rejected', () => {
    query(worker(assignment(101,{employee:ec2})),'ASSIGNMENT_SCOPE_INVALID');
    query(worker(assignment(101,{job:jc2})),'ASSIGNMENT_SCOPE_INVALID');
    query(worker(assignment(101,{owner:b,employee:e2})),'foreign key constraint');
  });
  await check('PER-06_wrong_department_workplace_pair_rejected', () => {
    query(worker(assignment(101,{department:d2})),'ASSIGNMENT_SCOPE_INVALID');
    query(worker(assignment(101,{workplace:wc2,department:dc2})),'ASSIGNMENT_SCOPE_INVALID');
  });
  await check('PER-07_overlap_any_workplace_or_department_rejected', () => {
    query(worker(assignment(101)),'exclusion constraint');
    query(worker(assignment(101,{workplace:w2,department:d2,start:'2026-01-31',end:'2026-03-01'})),'exclusion constraint');
    query(worker(assignment(101,{start:'2025-12-01',end:'2026-01-02'})),'exclusion constraint');
  });
  await check('PER-08_adjacent_half_open_intervals_and_leap_day', () => {
    query(worker(assignment(102,{start:'2026-02-01',end:'2026-03-01',workplace:w2,department:d2})));
    query(worker(employee(55)));
    query(worker(`UPDATE isg_workplace_fixture.employees SET hired_on='2024-01-01' WHERE id='${id(55)}'; ${assignment(103,{employee:id(55),start:'2024-02-29',end:'2024-03-01'})}`));
    assert.equal(query(`SELECT effective_dates @> '2024-02-29'::date AND NOT (effective_dates @> '2024-03-01'::date) FROM isg_workplace_fixture.employee_assignments WHERE id='${id(103)}';`),'t');
  });
  await check('PER-09_zero_reversed_and_infinite_dates_rejected', () => {
    query(worker(assignment(104,{employee:e2,end:'2026-01-01'})),'check constraint');
    query(worker(assignment(104,{employee:e2,end:'2025-12-01'})),'range lower bound');
    query(worker(assignment(104,{employee:e2,start:'-infinity'})),'EMPLOYMENT_INTERVAL_INVALID');
    query(worker(assignment(104,{employee:e2,end:'infinity'})),'check constraint');
  });
  await check('PER-10_before_hire_and_after_end_rejected', () => {
    query(worker(assignment(104,{employee:e2,start:'2024-12-31'})),'EMPLOYMENT_INTERVAL_INVALID');
    query(worker(`UPDATE isg_workplace_fixture.employees SET employment_ends_before='2026-04-01' WHERE id='${e2}';`));
    query(worker(assignment(104,{employee:e2,end:'2026-04-02'})),'EMPLOYMENT_INTERVAL_INVALID');
    query(worker(assignment(104,{employee:e2,end:null})),'EMPLOYMENT_INTERVAL_INVALID');
    query(worker(assignment(104,{employee:e2,end:'2026-04-01'})));
  });
  await check('PER-11_employment_edit_cannot_strand_existing_assignments', () => {
    query(worker(`UPDATE isg_workplace_fixture.employees SET hired_on='2026-01-02' WHERE id='${e2}';`),'EMPLOYMENT_INTERVAL_INVALID');
    query(worker(`UPDATE isg_workplace_fixture.employees SET employment_ends_before='2026-03-31' WHERE id='${e2}';`),'EMPLOYMENT_INTERVAL_INVALID');
  });
  await check('PER-12_secondary_kind_fails_closed_until_policy_defined', () => {
    query(worker(assignment(105,{employee:id(55),start:'2025-01-01',kind:'secondary'})),'check constraint');
  });
  await check('PER-13_open_ended_assignment_blocks_future_overlap', () => {
    query(worker(employee(56))); query(worker(assignment(106,{employee:id(56),end:null})));
    query(worker(assignment(107,{employee:id(56),start:'2030-01-01',end:'2030-02-01'})),'exclusion constraint');
  });
  await check('PER-14_twenty_parallel_overlaps_have_one_winner', async () => {
    query(worker(employee(57)));
    const results=await Promise.all(Array.from({length:20},(_,i)=>concurrent(worker(assignment(200+i,{employee:id(57)})))));
    assert.equal(results.filter(r=>r.ok).length,1);
    assert.equal(results.filter(r=>r.error==='EXCLUSION_CONFLICT').length,19);
  });
  await check('PER-15_different_employees_parallel_assignments_independent', async () => {
    query(worker(Array.from({length:20},(_,i)=>employee(300+i)).join('\n')));
    const results=await Promise.all(Array.from({length:20},(_,i)=>concurrent(worker(assignment(400+i,{employee:id(300+i)})))));
    assert.ok(results.every(r=>r.ok));
  });
  await check('PER-16_rename_preserves_history_and_snapshot_cannot_be_forged', () => {
    query(worker(`UPDATE isg_workplace_fixture.departments SET name='Yeni birim' WHERE id='${d}'; UPDATE isg_workplace_fixture.job_roles SET title='Yeni unvan' WHERE id='${j}';`));
    assert.equal(query(`SELECT department_name_snapshot||':'||job_title_snapshot FROM isg_workplace_fixture.employee_assignments WHERE id='${id(100)}';`),'Bakım:Teknisyen');
    query(worker(`UPDATE isg_workplace_fixture.employee_assignments SET job_title_snapshot='sahte' WHERE id='${id(100)}';`),'ASSIGNMENT_IMMUTABLE');
    query(worker(`UPDATE isg_workplace_fixture.employee_assignments SET job_role_id='${jc2}' WHERE id='${id(100)}';`),'ASSIGNMENT_IMMUTABLE');
  });
  await check('PER-17_referenced_people_departments_jobs_cannot_be_deleted', () => {
    for(const [table,value] of [['employees',e],['departments',d],['job_roles',j]]) query(worker(`DELETE FROM isg_workplace_fixture.${table} WHERE id='${value}';`),'foreign key constraint');
  });
  await check('PER-18_archived_parents_reject_new_assignment_keep_history', () => {
    query(worker(employee(58)));
    for(const [table,value,field] of [['employees',id(58),'employee'],['departments',d,'department'],['job_roles',j,'job']]) {
      query(worker(`UPDATE isg_workplace_fixture.${table} SET is_archived=true WHERE id='${value}';`));
      query(worker(assignment(500,{employee:id(58),[field]:value})),'ASSIGNMENT_PARENT_ARCHIVED');
      query(worker(`UPDATE isg_workplace_fixture.${table} SET is_archived=false WHERE id='${value}';`));
    }
    for(const [table,value] of [['legacy_companies',c],['workplaces',w]]) {
      query(worker(`UPDATE isg_workplace_fixture.${table} SET is_archived=true WHERE id='${value}';`));
      query(worker(assignment(500,{employee:id(58)})),'ASSIGNMENT_SCOPE_INVALID');
      query(worker(`UPDATE isg_workplace_fixture.${table} SET is_archived=false WHERE id='${value}';`));
    }
    assert.equal(query(`SELECT count(*) FROM isg_workplace_fixture.employee_assignments WHERE id='${id(100)}';`),'1');
  });
  await check('PER-19_close_old_assignment_then_open_new_in_one_transaction', () => {
    query(worker(`UPDATE isg_workplace_fixture.employee_assignments SET ends_before='2026-03-01' WHERE id='${id(106)}'; ${assignment(501,{employee:id(56),start:'2026-03-01',end:null,workplace:w2,department:d2})}`));
    assert.equal(query(`SELECT count(*) FROM isg_workplace_fixture.employee_assignments WHERE employee_id='${id(56)}';`),'2');
  });
  await check('PER-20_failed_transition_rolls_back_old_interval_close', () => {
    query(worker(`UPDATE isg_workplace_fixture.employee_assignments SET ends_before='2026-04-01' WHERE id='${id(501)}'; ${assignment(502,{employee:id(56),start:'2026-04-01',end:null,job:jc2})}`),'ASSIGNMENT_SCOPE_INVALID');
    assert.equal(query(`SELECT ends_before IS NULL FROM isg_workplace_fixture.employee_assignments WHERE id='${id(501)}';`),'t');
  });
  await check('PER-21_archived_employee_can_close_existing_interval_without_deleting_it', () => {
    query(worker(`UPDATE isg_workplace_fixture.employees SET is_archived=true WHERE id='${id(56)}'; UPDATE isg_workplace_fixture.employee_assignments SET ends_before='2026-05-01' WHERE id='${id(501)}';`));
    assert.equal(query(`SELECT count(*) FROM isg_workplace_fixture.employee_assignments WHERE employee_id='${id(56)}';`),'2');
  });
  await check('PER-22_owner_reader_cannot_see_foreign_assignment_or_mutate_history', () => {
    query(worker(assignment(503,{company:cb,owner:b,employee:eb,workplace:wb,department:db,job:jb})));
    for(const table of ['departments','job_roles','employees','employee_assignments']) {
      assert.equal(query(reader(`SELECT count(*) FROM isg_workplace_fixture.${table} WHERE company_id='${cb}';`)),'0');
    }
    query(reader(`UPDATE isg_workplace_fixture.employee_assignments SET ends_before=NULL;`),'permission denied');
    assert.equal(query(reader('SELECT count(*) FROM isg_workplace_fixture.employee_assignments;',b)),'1');
  });
  await check('PER-23_connection_loss_rolls_back_transition_and_allows_retry', async () => {
    const previous=count();
    const transition=`UPDATE isg_workplace_fixture.employee_assignments SET ends_before='2026-01-15' WHERE id='${id(104)}'; ${assignment(504,{employee:e2,start:'2026-01-15',end:'2026-04-01'})}`;
    await killSleepingTransaction(worker(`${transition} SELECT pg_sleep(7);`),'personnel');
    assert.equal(count(),previous);
    assert.equal(query(`SELECT ends_before FROM isg_workplace_fixture.employee_assignments WHERE id='${id(104)}';`),'2026-04-01');
    query(worker(transition));
  });
  await check('PER-24_non_health_schema_has_no_generic_payload_or_identity_number', () => {
    assert.equal(query("SELECT count(*) FROM information_schema.columns WHERE table_schema='isg_workplace_fixture' AND table_name IN ('employees','employee_assignments','departments','job_roles') AND (data_type IN ('json','jsonb') OR column_name ~ '(health|medical|diagnos|tc_identity|national_id)');"),'0');
  });
  await check('PER-25_closed_assignment_cannot_be_reopened_or_extended_silently', () => {
    query(worker(`UPDATE isg_workplace_fixture.employee_assignments SET ends_before=NULL WHERE id='${id(501)}';`),'ASSIGNMENT_EXTENSION_REQUIRES_REVIEW');
    query(worker(`UPDATE isg_workplace_fixture.employee_assignments SET ends_before='2026-06-01' WHERE id='${id(501)}';`),'ASSIGNMENT_EXTENSION_REQUIRES_REVIEW');
  });
  await check('PER-26_ten_employment_end_vs_assignment_races_preserve_containment', async () => {
    query(worker(Array.from({length:10},(_,i)=>employee(600+i)).join('\n')));
    const pairs=await Promise.all(Array.from({length:10},(_,i)=>Promise.all([
      concurrent(worker(assignment(700+i,{employee:id(600+i)}))),
      concurrent(worker(`UPDATE isg_workplace_fixture.employees SET employment_ends_before='2026-01-15' WHERE id='${id(600+i)}';`))
    ])));
    for(const pair of pairs) {
      assert.equal(pair.filter(r=>r.ok).length,1);
      assert.equal(pair.filter(r=>r.error==='EMPLOYMENT_INTERVAL_INVALID').length,1);
    }
    assert.equal(query('SELECT count(*) FROM isg_workplace_fixture.employee_assignments a JOIN isg_workplace_fixture.employees e ON e.company_id=a.company_id AND e.id=a.employee_id WHERE a.starts_on < e.hired_on OR (e.employment_ends_before IS NOT NULL AND (a.ends_before IS NULL OR a.ends_before > e.employment_ends_before));'),'0');
  });
}
