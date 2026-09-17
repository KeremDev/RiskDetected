import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { ROOT } from './lib.mjs';
import { runtimeFiles, validateFunctionMap, verifyFunctionMap } from './verify_function_map.mjs';

const original = JSON.parse(readFileSync(resolve(ROOT, 'contracts/isg/v1/function-test-map.json'), 'utf8'));
const read = path => readFileSync(resolve(ROOT, path), 'utf8');
test('all sixteen ISG transport sources map to reviewed harnesses without claiming release readiness', () => {
  const result = verifyFunctionMap(); assert.equal(result.ok, true); assert.equal(result.runtime_files, 16);
  assert.equal(result.tests_executed, false); assert.equal(result.release_ready, false);
});
test('an added private function, changed parser, or changed test harness invalidates prior mapping', () => {
  for (const path of [original.bindings[0].source, original.bindings[1].source, original.bindings[2].harness]) {
    const result = validateFunctionMap(original, runtimeFiles(), file => read(file) + (file === path ? '\n// unreviewed code change\n' : ''));
    assert.equal(result.ok, false);
  }
});
test('new source, removed binding, duplicate binding and forged runner fail closed', () => {
  const files = runtimeFiles();
  assert.equal(validateFunctionMap(original, [...files, 'App/Services/ISG/NewAction.swift'], read).ok, false);
  for (const mutate of [m => m.bindings.pop(), m => m.bindings.push(m.bindings[0]), m => { m.bindings[0].runner = 'unapproved'; }]) {
    const map = structuredClone(original); mutate(map); assert.equal(validateFunctionMap(map, files, read).ok, false);
  }
});
test('fixture changes and duplicate case IDs cannot silently keep old coverage', () => {
  const changed = JSON.parse(read(original.fixture)); changed.cases.push(changed.cases[0]);
  const result = validateFunctionMap(original, runtimeFiles(), file => file === original.fixture ? JSON.stringify(changed) : read(file));
  assert.equal(result.ok, false); assert.ok(result.errors.includes('FIXTURE_HASH_DRIFT')); assert.ok(result.errors.includes('FIXTURE_INVENTORY_DRIFT'));
});
test('Gradle treats shared fixture files as test inputs, and outcome fixtures are hash bound',()=>{
  const build=read('android/core/data/build.gradle.kts');
  assert.match(build,/tasks\.withType<org\.gradle\.api\.tasks\.testing\.Test>\(\)\.configureEach/);
  assert.match(build,/inputs\.dir\(rootProject\.layout\.projectDirectory\.dir\("\.\.\/contracts\/isg\/v1\/fixtures"\)\)/);
  const result=validateFunctionMap(original,runtimeFiles(),file=>read(file)+(file==='contracts/isg/v1/fixtures/mutation-outcome.json'?'\n':''));
  assert.equal(result.ok,false);assert.ok(result.errors.includes('FIXTURE_HASH_DRIFT'));
});
