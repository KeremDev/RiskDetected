import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { ROOT } from './lib.mjs';
const read = p => readFileSync(resolve(ROOT, p), 'utf8');
test('workplace candidate stays isolated and does not alter production schemas or credentials', () => {
  const sql = read('scripts/isg/sql/workplace_fixture.sql');
  assert.doesNotMatch(sql, /(?:CREATE|ALTER|DROP)\s+(?:TABLE|FUNCTION|SCHEMA)\s+(?:public|auth|storage)\./i);
  assert.doesNotMatch(sql, /SECURITY DEFINER|service_role|user_metadata|https?:\/\//i);
  const created = [...sql.matchAll(/CREATE TABLE isg_workplace_fixture\.(\w+)/g)].map(m => m[1]);
  assert.equal(created.length, 5);
  for (const table of created) assert.ok(sql.includes(`ALTER TABLE isg_workplace_fixture.${table} ENABLE ROW LEVEL SECURITY`));
  assert.match(sql, /ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC/);
  assert.match(sql, /REVOKE ALL ON ALL FUNCTIONS IN SCHEMA isg_workplace_fixture FROM PUBLIC/);
});
test('workplace probe is executed and fingerprinted inside the guarded disposable runner', () => {
  const runner = read('scripts/isg/run_database_contract.mjs');
  for (const path of ['scripts/isg/sql/workplace_fixture.sql', 'scripts/isg/workplace_probe.mjs']) assert.ok(runner.includes(`'${path}'`));
  assert.match(runner, /await runWorkplaceProbe\(\{ query, concurrent, check, killSleepingTransaction \}\)/);
  assert.match(runner, /DB_EXISTING_CONTAINER_REFUSED/);
  assert.match(runner, /'--network=none'/);
  assert.match(read('.github/workflows/isg-foundation.yml'), /scripts\/isg\/\*\*/);
});
test('scope, parallel catch-up, rollback and preservation checks are not omitted', () => {
  const probe = read('scripts/isg/workplace_probe.mjs');
  for (const id of ['WP-01_', 'WP-04_', 'WP-07_', 'WP-09_', 'WP-10_', 'WP-12_', 'WP-17_', 'WP-18_', 'WP-20_', 'WP-21_']) assert.ok(probe.includes(id));
  assert.match(probe, /length: 20/);
  assert.match(probe, /\['audit','outbox'\]/);
  assert.match(probe, /legacySnapshot/);
  assert.doesNotMatch(probe, /spawn|fetch\(|process\.env|supabase\.co/);
});
