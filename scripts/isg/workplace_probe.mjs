import assert from 'node:assert/strict';

// Queries are supplied ONLY by the isolated runner; no endpoint/client/credential here.
export async function runWorkplaceProbe({ query, concurrent, check, killSleepingTransaction }) {
  const id = n => `00000000-0000-4000-9000-${String(n).padStart(12, '0')}`;
  const a = id(1), b = id(2), first = id(10), second = id(11), foreign = id(12);
  const worker = sql => `BEGIN; SET LOCAL ROLE isg_workplace_owner; ${sql} COMMIT;`;
  const reader = (sql, owner = a) => `BEGIN; SET LOCAL ROLE isg_workplace_reader; SET LOCAL request.jwt.claim.sub='${owner}'; ${sql} COMMIT;`;
  const init = company => `SELECT isg_workplace_fixture.ensure_default('${company}');`;
  const count = table => Number(query(`SELECT count(*) FROM isg_workplace_fixture.${table};`));
  const before = () => query(`SELECT jsonb_build_array((SELECT count(*) FROM isg_workplace_fixture.workplaces), (SELECT count(*) FROM isg_workplace_fixture.audit), (SELECT count(*) FROM isg_workplace_fixture.outbox));`);
  query(worker(`INSERT INTO isg_workplace_fixture.legacy_companies(id,owner_id,name,hazard_class,address,department,is_archived) VALUES
    ('${first}','${a}','Firma A','high','Adres A','Eski serbest birim',false),
    ('${second}','${a}','Firma B','unknown',NULL,NULL,false),
    ('${foreign}','${b}','Firma A','low','Adres B',NULL,true);`));
  const legacySnapshot = query('SELECT jsonb_agg(c ORDER BY id) FROM isg_workplace_fixture.legacy_companies c;');
  let firstWorkplace;
  await check('WP-01_private_invoker_initializer_not_client_api', () => {
    assert.equal(query("SELECT count(*) FROM pg_tables WHERE schemaname='isg_workplace_fixture' AND NOT rowsecurity;"), '0');
    for (const role of ['anon', 'authenticated', 'isg_workplace_reader']) {
      assert.equal(query(`SELECT has_function_privilege('${role}', 'isg_workplace_fixture.ensure_default(uuid)', 'EXECUTE');`), 'f');
    }
    query(reader(init(first)), 'permission denied');
    assert.equal(query("SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='isg_workplace_fixture' AND p.prosecdef;"), '0');
  });
  await check('WP-02_default_copies_known_context_without_legal_inference', () => {
    firstWorkplace = query(worker(init(first)));
    const row = JSON.parse(query(`SELECT row_to_json(w) FROM isg_workplace_fixture.workplaces w WHERE id='${firstWorkplace}';`));
    assert.equal(row.company_id, first); assert.equal(row.owner_id, a); assert.equal(row.name, 'Firma A');
    assert.equal(row.address, 'Adres A'); assert.equal(row.hazard_class, 'high');
    assert.equal(row.jurisdiction, null); assert.equal(row.needs_review, true); assert.equal(row.version, 1);
    assert.equal(row.legacy_company_id, first); assert.equal(count('audit'), 1); assert.equal(count('outbox'), 1);
    assert.equal(count('department_refs'), 0);
  });
  await check('WP-03_repeated_initializer_has_no_extra_side_effects', () => {
    const previous = before(); assert.equal(query(worker(init(first))), firstWorkplace); assert.equal(before(), previous);
  });
  await check('WP-04_twenty_parallel_backfill_catchup_calls_create_once', async () => {
    const results = await Promise.all(Array.from({length: 20}, () => concurrent(worker(init(second)))));
    assert.ok(results.every(r => r.ok)); assert.equal(new Set(results.map(r => r.output)).size, 1);
    assert.equal(count('workplaces'), 2); assert.equal(count('audit'), 2); assert.equal(count('outbox'), 2);
  });
  await check('WP-05_unknown_hazard_stays_null_needs_review', () => {
    assert.equal(query(`SELECT hazard_class IS NULL AND jurisdiction IS NULL AND needs_review FROM isg_workplace_fixture.workplaces WHERE company_id='${second}';`), 't');
  });
  await check('WP-06_archived_legacy_company_remains_archived', () => {
    query(worker(init(foreign)));
    assert.equal(query(`SELECT is_archived FROM isg_workplace_fixture.workplaces WHERE company_id='${foreign}';`), 't');
  });
  await check('WP-07_owner_read_isolation_same_owner_multiple_companies', () => {
    assert.equal(query(reader('SELECT count(*) FROM isg_workplace_fixture.workplaces;')), '2');
    assert.equal(query(reader('SELECT count(*) FROM isg_workplace_fixture.workplaces;', b)), '1');
    assert.equal(query(reader(`SELECT count(*) FROM isg_workplace_fixture.workplaces WHERE company_id='${foreign}';`)), '0');
    assert.equal(query(reader('SELECT count(*) FROM isg_workplace_fixture.workplaces;', '')), '0');
  });
  await check('WP-08_reader_has_no_direct_writes_or_private_journal_access', () => {
    query(reader(`UPDATE isg_workplace_fixture.workplaces SET name='x';`), 'permission denied');
    query(reader(`DELETE FROM isg_workplace_fixture.workplaces;`), 'permission denied');
    query(reader(`INSERT INTO isg_workplace_fixture.workplaces(company_id,owner_id,name) VALUES ('${first}','${a}','x');`), 'permission denied');
    for (const table of ['legacy_companies','audit','outbox','department_refs']) query(reader(`SELECT * FROM isg_workplace_fixture.${table};`), 'permission denied');
  });
  await check('WP-09_composite_owner_fk_rejects_foreign_owner_even_for_worker', () => {
    query(worker(`INSERT INTO isg_workplace_fixture.workplaces(company_id,owner_id,name) VALUES ('${first}','${b}','x');`), 'foreign key constraint');
  });
  await check('WP-10_same_owner_cross_company_department_link_rejected', () => {
    query(worker(`INSERT INTO isg_workplace_fixture.department_refs(company_id,workplace_id) VALUES ('${second}','${firstWorkplace}');`), 'foreign key constraint');
    query(worker(`INSERT INTO isg_workplace_fixture.department_refs(company_id,workplace_id) VALUES ('${first}','${firstWorkplace}');`));
  });
  await check('WP-11_same_name_second_workplace_is_distinct_and_does_not_replace_default', () => {
    const extra = query(worker(`INSERT INTO isg_workplace_fixture.workplaces(company_id,owner_id,name,hazard_class) VALUES ('${first}','${a}','Firma A','low') RETURNING id;`));
    assert.notEqual(extra, firstWorkplace); assert.equal(query(worker(init(first))), firstWorkplace);
    assert.equal(query(`SELECT count(DISTINCT hazard_class) FROM isg_workplace_fixture.workplaces WHERE company_id='${first}';`), '2');
  });
  await check('WP-12_archived_default_still_dedupes_and_does_not_unarchive', () => {
    query(worker(`UPDATE isg_workplace_fixture.workplaces SET is_archived=true WHERE id='${firstWorkplace}';`));
    const previous = before(); assert.equal(query(worker(init(first))), firstWorkplace); assert.equal(before(), previous);
    assert.equal(query(`SELECT is_archived FROM isg_workplace_fixture.workplaces WHERE id='${firstWorkplace}';`), 't');
  });
  await check('WP-13_duplicate_default_and_wrong_marker_rejected', () => {
    query(worker(`INSERT INTO isg_workplace_fixture.workplaces(company_id,owner_id,name,legacy_company_id) VALUES ('${first}','${a}','x','${first}');`), 'unique constraint');
    query(worker(`INSERT INTO isg_workplace_fixture.workplaces(company_id,owner_id,name,legacy_company_id) VALUES ('${first}','${a}','x','${id(999)}');`), 'check constraint');
  });
  await check('WP-14_missing_company_and_null_cannot_create_orphan', () => {
    const previous = before(); query(worker(init(id(999))), 'COMPANY_NOT_FOUND');
    query(worker('SELECT isg_workplace_fixture.ensure_default(NULL);'), 'COMPANY_NOT_FOUND'); assert.equal(before(), previous);
  });
  for (const [index, fault] of ['audit','outbox'].entries()) await check(`WP-${15+index}_${fault}_failure_rolls_back_and_retry_succeeds`, () => {
    const company = id(30+index);
    query(worker(`INSERT INTO isg_workplace_fixture.legacy_companies(id,owner_id,name) VALUES ('${company}','${a}','Catch-up');`));
    const previous = before();
    query(worker(`SET LOCAL isg_workplace_fixture.fail_at='${fault}'; ${init(company)}`), 'INJECTED_FAILURE');
    assert.equal(before(), previous); query(worker(init(company)));
    assert.equal(query(`SELECT count(*) FROM isg_workplace_fixture.workplaces WHERE legacy_company_id='${company}';`), '1');
  });
  await check('WP-17_old_client_company_after_backfill_is_caught_up', () => {
    query(worker(`INSERT INTO isg_workplace_fixture.legacy_companies(id,owner_id,name,hazard_class) VALUES ('${id(40)}','${a}','Yeni eski-client firması','medium');`));
    const previous = count('workplaces');
    query(worker('SELECT isg_workplace_fixture.ensure_default(id) FROM isg_workplace_fixture.legacy_companies ORDER BY id;'));
    assert.equal(count('workplaces'), previous+1);
    const after = before(); query(worker('SELECT isg_workplace_fixture.ensure_default(id) FROM isg_workplace_fixture.legacy_companies ORDER BY id;')); assert.equal(before(), after);
  });
  await check('WP-18_retries_preserve_new_workplace_context_and_legacy_rows', () => {
    query(worker(`UPDATE isg_workplace_fixture.workplaces SET name='Yeni tesis adı',hazard_class='low',version=2 WHERE id='${firstWorkplace}';`));
    query(worker(init(first)));
    assert.equal(query(`SELECT name||':'||hazard_class||':'||version FROM isg_workplace_fixture.workplaces WHERE id='${firstWorkplace}';`), 'Yeni tesis adı:low:2');
    assert.equal(query(`SELECT jsonb_agg(c ORDER BY id) FROM isg_workplace_fixture.legacy_companies c WHERE id IN ('${first}','${second}','${foreign}');`), legacySnapshot);
  });
  await check('WP-19_invalid_context_cannot_claim_review_complete', () => {
    query(worker(`UPDATE isg_workplace_fixture.workplaces SET needs_review=false WHERE company_id='${second}';`), 'check constraint');
    query(worker(`UPDATE isg_workplace_fixture.workplaces SET hazard_class='invalid' WHERE id='${firstWorkplace}';`), 'check constraint');
    query(worker(`UPDATE isg_workplace_fixture.workplaces SET version=0 WHERE id='${firstWorkplace}';`), 'check constraint');
  });
  await check('WP-20_referenced_workplace_and_owner_transfer_require_explicit_workflow', () => {
    query(worker(`DELETE FROM isg_workplace_fixture.workplaces WHERE id='${firstWorkplace}';`), 'foreign key constraint');
    query(worker(`UPDATE isg_workplace_fixture.legacy_companies SET owner_id='${b}' WHERE id='${first}';`), 'foreign key constraint');
  });
  await check('WP-21_connection_loss_before_commit_rolls_back_initializer_and_journals', async () => {
    const company = id(50);
    query(worker(`INSERT INTO isg_workplace_fixture.legacy_companies(id,owner_id,name) VALUES ('${company}','${a}','Bağlantı testi');`));
    const previous = before();
    await killSleepingTransaction(worker(`${init(company)} SELECT pg_sleep(7);`), 'workplace');
    assert.equal(before(), previous);
    query(worker(init(company)));
    assert.equal(query(`SELECT count(*) FROM isg_workplace_fixture.workplaces w JOIN isg_workplace_fixture.audit a ON a.workplace_id=w.id JOIN isg_workplace_fixture.outbox o ON o.workplace_id=w.id WHERE w.company_id='${company}';`), '1');
  });
}
