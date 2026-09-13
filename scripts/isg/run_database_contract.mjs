#!/usr/bin/env node
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { ROOT } from './lib.mjs';
import { validateEnvironment, validateContainerInspection } from './verify_environment.mjs';
import { legacyCapacityOracle } from './legacy_capacity_oracle.mjs';
import { runWorkplaceProbe } from './workplace_probe.mjs';
import { runPersonnelProbe } from './personnel_probe.mjs';
import { runPersonnelMutationProbe } from './personnel_mutation_probe.mjs';
import { runEmployeeIntakeProbe } from './employee_intake_probe.mjs';

// This lane creates and removes ONLY its own new synthetic container. No TCP, API,
// Supabase credentials, host mounts, migrations, existing container reuse or image pulls.
const image = 'public.ecr.aws/supabase/postgres@sha256:3866d94d8426927e8db3f1c5d790752292bfbe27b5f1f46e199ae1b7d3c1710b';
const runId = randomUUID(); let config, containerId, interrupted = false;
const report = { schema_version: 1, run_id: runId, started_at: new Date().toISOString(), image,
  suite: 'synthetic_postgres_transaction_prototype', production_contract_implemented: false,
  acceptance_complete: false, seed: 'fixed_uuid_counter_v1', node_version: process.version,
  source_sha256: Object.fromEntries(['scripts/isg/run_database_contract.mjs', 'scripts/isg/sql/transaction_fixture.sql', 'scripts/isg/sql/workplace_fixture.sql', 'scripts/isg/workplace_probe.mjs', 'scripts/isg/sql/personnel_fixture.sql', 'scripts/isg/personnel_probe.mjs', 'scripts/isg/sql/personnel_mutation_fixture.sql', 'scripts/isg/personnel_mutation_probe.mjs', 'supabase/functions/_shared/personnel/assignment-move.ts', 'supabase/functions/_shared/isg/mutation-context.ts', 'contracts/isg/v1/fixtures/assignment-move.json', 'scripts/isg/legacy_capacity_oracle.mjs', 'scripts/isg/verify_environment.mjs', 'contracts/isg/v1/safety-policy.json']
    .concat(['scripts/isg/sql/employee_intake_fixture.sql', 'scripts/isg/employee_intake_probe.mjs', 'supabase/functions/_shared/personnel/employee-create.ts', 'contracts/isg/v1/fixtures/employee-create.json'])
    .map(path => [path, createHash('sha256').update(readFileSync(resolve(ROOT, path))).digest('hex')])),
  cases: [], cleanup: 'NOT_NEEDED' };
const childEnv = { PATH: process.env.PATH ?? '', HOME: process.env.HOME ?? '', DOCKER_CONFIG: process.env.DOCKER_CONFIG ?? '', LANG: 'C.UTF-8' };
function docker(args, input) {
  return spawnSync('docker', args, { input, encoding: 'utf8', env: childEnv, timeout: 15_000, maxBuffer: 1024 * 1024 });
}
function inspect() {
  const result = docker(['inspect', containerId]);
  if (result.status !== 0) throw new Error('DB_CONTAINER_INSPECTION_FAILED');
  const info = JSON.parse(result.stdout)[0];
  if (info.Id !== containerId || info.Config.Labels?.['com.riskdetected.isg-test-run'] !== runId ||
      info.Config.Image !== image || info.HostConfig.NetworkMode !== 'none' || info.Mounts.length ||
      Object.values(info.NetworkSettings.Ports ?? {}).some(v => v !== null) ||
      !validateContainerInspection(info, config).ok) throw new Error('DB_CONTAINER_ISOLATION_FAILED');
}
const sqlArgs = () => ['exec', '-i', containerId, 'psql', '-X', '-U', 'supabase_admin', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-Atq'];
function query(sql, expectedError) {
  if (interrupted) throw new Error('DB_RUN_INTERRUPTED');
  inspect();
  const result = docker(sqlArgs(), `SET statement_timeout='8s'; SET lock_timeout='5s';\n${sql}`);
  // This container contains only this file's synthetic fixtures. Never reuse this
  // diagnostic for production/restore queries; no SQL statement or raw row is logged.
  if (result.status !== 0 && (!expectedError || !result.stderr.includes(expectedError))) {
    report.synthetic_sql_error = result.stderr.split('\n').find(line => line.includes('ERROR:'))?.slice(0, 240) ??
      { exit: result.status, signal: result.signal, system_error: result.error?.code, diagnostic: (result.stderr || result.stdout).slice(0, 600) };
  }
  if (expectedError) {
    assert.notEqual(result.status, 0, `expected ${expectedError}`);
    assert.ok(result.stderr.includes(expectedError), `missing ${expectedError}`);
    return;
  }
  if (result.status !== 0) throw new Error('DB_QUERY_FAILED');
  return result.stdout.trim();
}
async function concurrent(sql) {
  inspect();
  return await new Promise(resolve => {
    const child = spawn('docker', sqlArgs(), { env: childEnv, stdio: ['pipe', 'pipe', 'pipe'], timeout: 12_000 });
    let stdout = '', stderr = '';
    child.stdout.on('data', data => { stdout += data; }); child.stderr.on('data', data => { stderr += data; });
    child.on('error', () => resolve({ ok: false, error: 'CHILD_ERROR' }));
    child.on('close', code => resolve({ ok: code === 0, output: stdout.trim(), error: stderr.includes('VERSION_CONFLICT') ? 'VERSION_CONFLICT' : stderr.includes('exclusion constraint') ? 'EXCLUSION_CONFLICT' : stderr.includes('EMPLOYMENT_INTERVAL_INVALID') ? 'EMPLOYMENT_INTERVAL_INVALID' : 'DB_CONCURRENT_FAILURE' }));
    child.stdin.on('error', () => {});
    child.stdin.end(`SET statement_timeout='8s'; SET lock_timeout='5s';\n${sql}`);
  });
}
async function check(id, fn) {
  try { await fn(); report.cases.push({ id, status: 'PASS' }); }
  catch (error) { report.cases.push({ id, status: 'FAIL' }); throw error; }
}
async function killSleepingTransaction(sql, suffix) {
  // PostgreSQL truncates application_name at 63 bytes; bound the suffix too.
  const appName = `isg_fixture_crash_${runId.replaceAll('-', '')}_${createHash('sha256').update(suffix).digest('hex').slice(0,8)}`;
  const pending = concurrent(`SET application_name='${appName}'; ${sql}`);
  let waiting = false;
  for (let attempt = 0; attempt < 30; attempt++) {
    if (query(`SELECT count(*) FROM pg_stat_activity WHERE application_name='${appName}' AND wait_event='PgSleep' AND datname='postgres';`) === '1') { waiting = true; break; }
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  if (!waiting) { await pending; throw new Error('DB_CRASH_FIXTURE_NOT_WAITING'); }
  assert.equal(query(`SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name='${appName}' AND wait_event='PgSleep' AND datname='postgres' AND pid <> pg_backend_pid();`), 't');
  assert.equal((await pending).ok, false);
}
const uid = number => `00000000-0000-4000-8000-${number.toString().padStart(12, '0')}`;
const actor = uid(1), otherActor = uid(2), company = uid(10), otherCompany = uid(11), entity = uid(20);
const mutation = (key, expected = 0, delta = 1, companyId = company, entityId = entity) => `SELECT isg_fixture.mutate('${uid(key)}','${companyId}','${entityId}',${expected},${delta});`;
const client = (sql, user = actor, fault = '') => `BEGIN; SET LOCAL ROLE isg_fixture_client; SET LOCAL request.jwt.claim.sub='${user}'; SET LOCAL isg_fixture.fail_at='${fault}'; ${sql} COMMIT;`;
const worker = sql => `BEGIN; SET LOCAL ROLE isg_fixture_owner; ${sql} COMMIT;`;
const snapshot = () => JSON.parse(query(`SELECT jsonb_build_object('version',(SELECT version FROM isg_fixture.counters WHERE id='${entity}'),
  'value',(SELECT value FROM isg_fixture.counters WHERE id='${entity}'), 'receipts',(SELECT count(*) FROM isg_fixture.mutation_receipts),
  'audit',(SELECT count(*) FROM isg_fixture.audit), 'outbox',(SELECT count(*) FROM isg_fixture.outbox));`));
const claim = time => { const result = query(worker(`SELECT isg_fixture.claim('${time}');`)); return result ? JSON.parse(result) : null; };
const complete = (event, time) => worker(`SELECT isg_fixture.complete('${event.event_id}','${event.lease_token}','${time}');`);
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => { interrupted = true; });
try {
  const args = process.argv.slice(2);
  if (args.length !== 1) throw new Error('DB_EXPLICIT_MANIFEST_REQUIRED');
  config = JSON.parse(readFileSync(resolve(ROOT, args[0]), 'utf8'));
  if (!validateEnvironment(config).ok) throw new Error('DB_ENVIRONMENT_REJECTED');
  if (docker(['image', 'inspect', image]).status !== 0) throw new Error('DB_PINNED_IMAGE_NOT_LOCAL');
  if (docker(['inspect', config.database_container]).status === 0) throw new Error('DB_EXISTING_CONTAINER_REFUSED');
  const created = docker(['create', '--pull=never', '--name', config.database_container, '--network=none', '--memory=1g', '--cpus=2', '--pids-limit=256',
    '--label', `com.riskdetected.isg-test-project=${config.project_id}`, '--label', `com.riskdetected.isg-test-run=${runId}`,
    '--env', 'POSTGRES_HOST_AUTH_METHOD=trust', image, 'postgres', '-D', '/etc/postgresql', '-c', 'listen_addresses=localhost',
    '-c', 'cron.launch_active_jobs=off', '-c', 'logging_collector=off', '-c', 'log_statement=none', '-c', 'log_min_error_statement=panic']);
  if (created.status !== 0 || !/^[a-f0-9]{64}$/.test(created.stdout.trim())) throw new Error('DB_CONTAINER_CREATE_FAILED');
  containerId = created.stdout.trim(); report.cleanup = 'PENDING';
  if (docker(['start', containerId]).status !== 0) throw new Error('DB_CONTAINER_START_FAILED');
  let ready = false;
  for (let attempt = 0; attempt < 40; attempt++) {
    if (interrupted) throw new Error('DB_RUN_INTERRUPTED');
    inspect();
    // pg_isready also succeeds against the entrypoint's temporary bootstrap
    // server, which is then shut down. Wait for PID 1 to exec the pinned image's
    // final postgres wrapper before accepting SQL readiness.
    const processName = docker(['exec', containerId, 'cat', '/proc/1/comm']);
    if (processName.status === 0 && processName.stdout.trim() === '.postgres-wrapp' &&
        docker(['exec', containerId, 'pg_isready', '-U', 'supabase_admin', '-d', 'postgres']).status === 0) { ready = true; break; }
    await new Promise(resolve => setTimeout(resolve, 250));
  }
  if (!ready) throw new Error('DB_CONTAINER_READY_TIMEOUT');
  query(readFileSync(resolve(ROOT, 'scripts/isg/sql/transaction_fixture.sql'), 'utf8'));
  report.postgres_version = query('SHOW server_version;');
  query(`INSERT INTO isg_fixture.actors VALUES ('${actor}',true),('${otherActor}',true);
    INSERT INTO isg_fixture.companies VALUES ('${company}','${actor}'),('${otherCompany}','${otherActor}');
    INSERT INTO isg_fixture.counters(company_id,id) VALUES ('${company}','${entity}'),('${otherCompany}','${uid(21)}');`);
  await check('TX-01_private_tables_and_workers_not_callable_by_client', () => {
    assert.equal(query("SELECT count(*) FROM pg_tables WHERE schemaname='isg_fixture' AND NOT rowsecurity;"), '0');
    query(client('SELECT * FROM isg_fixture.mutation_receipts;'), 'permission denied');
    query(client("SELECT isg_fixture.claim('2026-09-12T00:00:00Z');"), 'permission denied');
    assert.equal(query("SELECT has_function_privilege('anon','isg_fixture.mutate(uuid,uuid,uuid,bigint,integer)','EXECUTE');"), 'f');
  });
  await check('TX-02_missing_actor_rejected', () => query(client(mutation(100), ''), 'AUTH_REQUIRED'));
  await check('TX-03_foreign_and_missing_company_indistinguishable', () => {
    query(client(mutation(101), otherActor), 'ACCESS_DENIED'); query(client(mutation(101, 0, 1, uid(999))), 'ACCESS_DENIED');
  });
  await check('TX-04_cross_company_entity_rejected', () => query(client(mutation(102, 0, 1, company, uid(21))), 'ACCESS_DENIED'));
  await check('TX-05_invalid_delta_rejected_without_side_effect', () => { query(client(mutation(103, 0, 101)), 'VALIDATION_ERROR'); assert.equal(snapshot().outbox, 0); });
  await check('TX-06_domain_audit_outbox_receipt_commit_together', () => {
    assert.deepEqual(JSON.parse(query(client(mutation(104)))), { version: 1, value: 1 });
    assert.deepEqual(snapshot(), { version: 1, value: 1, receipts: 1, audit: 1, outbox: 1 });
  });
  await check('TX-07_identical_retry_returns_original_no_extra_writes', () => {
    const before = snapshot(); assert.deepEqual(JSON.parse(query(client(mutation(104)))), { version: 1, value: 1 }); assert.deepEqual(snapshot(), before);
  });
  await check('TX-08_same_key_different_payload_conflict', () => { const before = snapshot(); query(client(mutation(104, 0, 2)), 'IDEMPOTENCY_CONFLICT'); assert.deepEqual(snapshot(), before); });
  await check('TX-09_stale_version_no_receipt_or_side_effect', () => { const before = snapshot(); query(client(mutation(105)), 'VERSION_CONFLICT'); assert.deepEqual(snapshot(), before); });
  for (const [index, fault] of ['audit', 'outbox'].entries()) await check(`TX-${10 + index}_${fault}_failure_rolls_back_every_write`, () => {
    const before = snapshot(); query(client(mutation(106 + index, 1), actor, fault), 'INJECTED_FAILURE'); assert.deepEqual(snapshot(), before);
  });
  await check('TX-12_failed_request_can_retry_successfully', () => { query(client(mutation(107, 1))); assert.equal(snapshot().version, 2); });
  await check('TX-13_revoked_actor_cannot_replay_cached_success', () => {
    query(`UPDATE isg_fixture.actors SET active=false WHERE id='${actor}';`);
    query(client(mutation(104)), 'AUTH_REQUIRED'); query(`UPDATE isg_fixture.actors SET active=true WHERE id='${actor}';`);
  });
  await check('TX-14_twenty_identical_parallel_retries_apply_once', async () => {
    const before = snapshot();
    const results = await Promise.all(Array.from({ length: 20 }, () => concurrent(client(mutation(108, 2)))));
    assert.ok(results.every(r => r.ok)); assert.ok(results.every(r => r.output === results[0].output));
    const after = snapshot(); for (const field of Object.keys(before)) assert.equal(after[field], before[field] + 1);
  });
  await check('TX-15_twenty_competing_versions_have_one_winner', async () => {
    const before = snapshot();
    const results = await Promise.all(Array.from({ length: 20 }, (_, i) => concurrent(client(mutation(200 + i, 3)))));
    assert.equal(results.filter(r => r.ok).length, 1); assert.equal(results.filter(r => !r.ok && r.error === 'VERSION_CONFLICT').length, 19);
    const after = snapshot(); for (const field of Object.keys(before)) assert.equal(after[field], before[field] + 1);
  });
  let first, reclaimed;
  await check('TX-16_lease_prevents_parallel_and_out_of_order_claim', () => {
    first = claim('2026-09-12T00:00:00Z'); assert.equal(first.attempts, 1); assert.equal(claim('2026-09-12T00:00:01Z'), null);
  });
  await check('TX-17_expiry_reclaims_same_event_with_new_fence', () => {
    reclaimed = claim('2026-09-12T00:00:30Z'); assert.equal(reclaimed.event_id, first.event_id); assert.notEqual(reclaimed.lease_token, first.lease_token); assert.equal(reclaimed.attempts, 2);
  });
  await check('TX-18_old_worker_cannot_ack_after_lease_loss', () => query(complete(first, '2026-09-12T00:00:31Z'), 'LEASE_LOST'));
  await check('TX-19_consumer_failure_rolls_back_receipt_and_projection', () => {
    query(worker(`SET LOCAL isg_fixture.fail_at='projections'; SELECT isg_fixture.complete('${reclaimed.event_id}','${reclaimed.lease_token}','2026-09-12T00:00:31Z');`), 'INJECTED_FAILURE');
    assert.equal(query('SELECT count(*) FROM isg_fixture.consumer_receipts;'), '0'); assert.equal(query('SELECT count(*) FROM isg_fixture.projections;'), '0');
  });
  await check('TX-20_commit_then_lost_ack_does_not_repeat_projection', () => {
    assert.equal(query(complete(reclaimed, '2026-09-12T00:00:31Z')), 't');
    assert.equal(query(complete(reclaimed, '2026-09-12T00:00:32Z')), 'f');
    assert.equal(query('SELECT applied_count FROM isg_fixture.projections;'), '1');
  });
  await check('TX-21_ordered_events_apply_exactly_once_per_receipt', () => {
    for (let version = 2; version <= 4; version++) {
      const event = claim('2026-09-12T00:01:00Z'); assert.ok(event); assert.equal(query(complete(event, '2026-09-12T00:01:01Z')), 't');
      assert.equal(query('SELECT version FROM isg_fixture.projections;'), String(version));
    }
    assert.equal(query('SELECT applied_count FROM isg_fixture.projections;'), '4'); assert.equal(claim('2026-09-12T00:01:02Z'), null);
  });
  await check('TX-22_expired_lease_cannot_complete_at_boundary', () => {
    query(client(mutation(300, 4))); const event = claim('2026-09-12T00:02:00Z');
    query(complete(event, '2026-09-12T00:02:30Z'), 'LEASE_LOST');
  });
  await check('TX-23_retry_budget_dead_letters_and_blocks_later_version', () => {
    query(client(mutation(301, 5)));
    assert.equal(claim('2026-09-12T00:02:30Z').attempts, 2); assert.equal(claim('2026-09-12T00:03:00Z').attempts, 3);
    assert.equal(claim('2026-09-12T00:03:30Z'), null);
    assert.equal(query("SELECT count(*) FROM isg_fixture.outbox WHERE status='dead';"), '1');
    assert.equal(query("SELECT count(*) FROM isg_fixture.outbox WHERE status='pending';"), '1');
  });
  await check('TX-24_composite_foreign_key_rejects_wrong_scope_even_for_owner', () => {
    query(`INSERT INTO isg_fixture.audit(actor_id,company_id,aggregate_id,version) VALUES ('${actor}','${company}','${uid(21)}',1);`, 'foreign key constraint');
  });
  await check('TX-25_mutation_key_is_scoped_to_actor', () => {
    assert.deepEqual(JSON.parse(query(client(mutation(104, 0, 1, otherCompany, uid(21)), otherActor))), { version: 1, value: 1 });
  });
  await check('TX-26_former_company_owner_cannot_replay_cached_result', () => {
    query(`UPDATE isg_fixture.companies SET owner_id='${otherActor}' WHERE id='${company}';`);
    query(client(mutation(104)), 'ACCESS_DENIED');
    query(`UPDATE isg_fixture.companies SET owner_id='${actor}' WHERE id='${company}';`);
  });
  await check('TX-27_parallel_workers_one_lease_other_company_not_blocked', async () => {
    const results = await Promise.all(Array.from({ length: 20 }, () => concurrent(worker("SELECT isg_fixture.claim('2026-09-12T00:04:00Z');"))));
    assert.ok(results.every(r => r.ok));
    const claims = results.filter(r => r.output !== '').map(r => JSON.parse(r.output));
    assert.equal(claims.length, 1); assert.equal(claims[0].attempts, 1);
  });
  await check('TX-28_null_test_clock_fails_closed', () => {
    query(worker('SELECT isg_fixture.claim(NULL);'), 'VALIDATION_ERROR');
    query(worker(`SELECT isg_fixture.complete('${uid(999)}','${uid(998)}',NULL);`), 'VALIDATION_ERROR');
  });
  await check('TX-29_connection_killed_before_commit_rolls_back_domain_and_all_side_effects', async () => {
    const before = snapshot();
    await killSleepingTransaction(client(`${mutation(303, 6)} SELECT pg_sleep(7);`), 'domain');
    assert.deepEqual(snapshot(), before);
  });
  await check('TX-30_worker_connection_killed_before_commit_can_retry_without_partial_projection', async () => {
    const event = JSON.parse(query(`SELECT jsonb_build_object('event_id',event_id,'lease_token',lease_token) FROM isg_fixture.outbox WHERE company_id='${otherCompany}' AND status='processing';`));
    const receipts = query('SELECT count(*) FROM isg_fixture.consumer_receipts;');
    await killSleepingTransaction(worker(`SELECT isg_fixture.complete('${event.event_id}','${event.lease_token}','2026-09-12T00:04:01Z'); SELECT pg_sleep(7);`), 'worker');
    assert.equal(query('SELECT count(*) FROM isg_fixture.consumer_receipts;'), receipts);
    assert.equal(query(`SELECT count(*) FROM isg_fixture.projections WHERE company_id='${otherCompany}';`), '0');
    assert.equal(query(complete(event, '2026-09-12T00:04:02Z')), 't');
    assert.equal(query(complete(event, '2026-09-12T00:04:03Z')), 'f');
    assert.equal(query(`SELECT applied_count FROM isg_fixture.projections WHERE company_id='${otherCompany}';`), '1');
  });
  await check('LEGACY-01_original_company_tier_and_limit_truth_table', () => {
    const oracle = legacyCapacityOracle();
    report.legacy_capacity = { ...JSON.parse(query(oracle.sql)), source_definitions: oracle.definitions };
    assert.equal(oracle.expected_cases, 329);
    assert.equal(report.legacy_capacity.case_count, oracle.expected_cases);
    assert.equal(report.legacy_capacity.passed, oracle.expected_cases);
    assert.deepEqual(report.legacy_capacity.failures, []);
    assert.equal(query("SELECT to_regclass('public.profiles') IS NULL AND to_regclass('public.user_subscriptions') IS NULL;"), 't');
  });
  query(readFileSync(resolve(ROOT, 'scripts/isg/sql/workplace_fixture.sql'), 'utf8'));
  await runWorkplaceProbe({ query, concurrent, check, killSleepingTransaction });
  query(readFileSync(resolve(ROOT, 'scripts/isg/sql/personnel_fixture.sql'), 'utf8'));
  report.personnel_btree_gist_version = query("SELECT extversion FROM pg_extension WHERE extname='btree_gist';");
  await runPersonnelProbe({ query, concurrent, check, killSleepingTransaction });
  query(readFileSync(resolve(ROOT, 'scripts/isg/sql/personnel_mutation_fixture.sql'), 'utf8'));
  await runPersonnelMutationProbe({ query, concurrent, check, killSleepingTransaction });
  query(readFileSync(resolve(ROOT, 'scripts/isg/sql/employee_intake_fixture.sql'), 'utf8'));
  await runEmployeeIntakeProbe({ query, concurrent, check, killSleepingTransaction });
  report.ok = true;
} catch (error) {
  report.ok = false; report.error_code = /^DB_/.test(error.message) ? error.message : 'DB_CONTRACT_ASSERTION_FAILED';
} finally {
  if (containerId) {
    // Exact ID + this run's label: never delete a pre-existing or foreign container.
    const result = docker(['inspect', containerId]);
    if (result.status === 0) {
      const info = JSON.parse(result.stdout)[0];
      if (info.Id === containerId && info.Name === `/${config.database_container}` && info.Config.Labels?.['com.riskdetected.isg-test-run'] === runId && !info.Mounts.length) {
        report.cleanup = docker(['rm', '-f', containerId]).status === 0 ? 'PASS' : 'FAILED';
      } else report.cleanup = 'REFUSED_SCOPE_MISMATCH';
    } else report.cleanup = 'UNVERIFIED';
    if (report.cleanup !== 'PASS') report.ok = false;
  }
  report.finished_at = new Date().toISOString(); report.passed = report.cases.filter(c => c.status === 'PASS').length;
  if (containerId) {
    const directory = resolve(ROOT, 'output/isg/runs', runId); mkdirSync(directory, { recursive: true });
    writeFileSync(resolve(directory, 'database-contract.json'), JSON.stringify(report, null, 2) + '\n');
  }
  console.log(JSON.stringify(report, null, 2)); process.exitCode = report.ok ? 0 : 1;
}
