import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { ROOT } from './lib.mjs';

test('hostless iOS XCTest has one named test for every shared fixture', () => {
  const cases = JSON.parse(readFileSync(resolve(ROOT, 'contracts/isg/v1/fixtures/mutation-context.json'), 'utf8')).cases;
  const source = readFileSync(resolve(ROOT, 'tests/isg/ios/IsgMutationContextTests.swift'), 'utf8');
  const registered = [...source.matchAll(/func test_([a-z0-9_]+)\(\) throws \{ try check\("([a-z0-9_]+)"\) \}/g)];
  assert.deepEqual(registered.map(m => m[1]).sort(), cases.map(c => c.id).sort());
  assert.ok(registered.every(m => m[1] === m[2]));
  assert.deepEqual([...source.matchAll(/^import (.+)$/gm)].map(m => m[1]), ['XCTest']);
});
test('iOS test project remains hostless and references only shared model, harness and fixture', () => {
  const project = readFileSync(resolve(ROOT, 'tests/isg/ios/ISGContractTests.xcodeproj/project.pbxproj'), 'utf8');
  assert.equal((project.match(/TEST_HOST = ""/g) ?? []).length, 2);
  assert.equal((project.match(/isa = PBXNativeTarget/g) ?? []).length, 1);
  assert.equal(project.includes('PBXShellScriptBuildPhase'), false);
  assert.equal(project.includes('XCRemoteSwiftPackageReference'), false);
  assert.equal(project.includes('com.apple.product-type.application'), false);
  assert.ok(project.includes('../../../App/Services/ISG/IsgMutationContext.swift'));
  assert.ok(project.includes('../../../contracts/isg/v1/fixtures/mutation-context.json'));
});
