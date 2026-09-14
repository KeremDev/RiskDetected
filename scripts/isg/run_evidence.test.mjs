import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { assertUnchangedSources, appendPassingCheck } from './run_evidence.mjs';

test('run evidence rejects changed, missing, extra and empty source hashes', () => {
  assert.doesNotThrow(() => assertUnchangedSources({ a: 'one' }, { a: 'one' }));
  for (const next of [{ a: 'two' }, {}, { a: 'one', b: 'two' }]) {
    assert.throws(() => assertUnchangedSources({ a: 'one' }, next), /SOURCE_CHANGED/);
  }
  assert.throws(() => assertUnchangedSources({}, {}), /SOURCE_CHANGED/);
});

test('passing checks must have unique identities and true conditions', () => {
  const checks = [];
  appendPassingCheck(checks, 'first', true);
  assert.throws(() => appendPassingCheck(checks, 'first', true), /DUPLICATE_CHECK_ID/);
  assert.throws(() => appendPassingCheck(checks, 'second', false), /CHECK_FAILED_second/);
  assert.equal(checks.length, 1);
});

test('restore runner fingerprints before execution and verifies before success', () => {
  const source = readFileSync(new URL('./run_auth_restore.mjs', import.meta.url), 'utf8');
  assert.ok(source.indexOf('report.source_sha256 = sourceFingerprints(mode)') < source.indexOf('report.data_class ='));
  assert.ok(source.indexOf('assertUnchangedSources(report.source_sha256, sourceFingerprints(mode))') < source.indexOf('report.ok = true;'));
});
