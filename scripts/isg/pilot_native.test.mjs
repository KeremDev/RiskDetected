import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, rmSync, readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {ROOT} from './lib.mjs';

test('company score counts leaf sections equally without inventing unknown data', {skip: process.platform !== 'darwin'}, t => {
  const directory = mkdtempSync(join(tmpdir(), 'isg-score-check-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  const binary = join(directory, 'check');
  const compiled = spawnSync('swiftc', ['-parse-as-library',
    'App/DesignSystem/ISG/NovaCompanyProgress.swift', 'scripts/isg/NovaCompanyProgressCheck.swift', '-o', binary],
    {cwd: ROOT, encoding: 'utf8', timeout: 60000});
  assert.equal(compiled.status, 0, compiled.stderr);
  const result = spawnSync(binary, [], {encoding: 'utf8', timeout: 10000});
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /11 company score checks PASS/);
});

test('scene interruptions preserve forms; real background return revalidates once', {skip: process.platform !== 'darwin'}, t => {
  const directory = mkdtempSync(join(tmpdir(), 'isg-scene-check-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  const binary = join(directory, 'check');
  const compiled = spawnSync('swiftc', ['-parse-as-library',
    'App/DesignSystem/ISG/NovaSceneRevalidation.swift', 'scripts/isg/NovaSceneRevalidationCheck.swift', '-o', binary],
    {cwd: ROOT, encoding: 'utf8', timeout: 60000});
  assert.equal(compiled.status, 0, compiled.stderr);
  const result = spawnSync(binary, [], {encoding: 'utf8', timeout: 10000});
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /27 scene lifecycle checks PASS/);
  for (const name of ['NovaPilotMainGate', 'NovaCompanyManagementGate']) {
    const source = readFileSync(join(ROOT, `App/Views/Components/${name}.swift`), 'utf8');
    assert.match(source, /sceneRevalidation.update\(isBackground: phase == \.background, isActive: phase == \.active\)/);
  }
});

test('native pilot create: durable retry, owner/session isolation and fail-closed receipts', {skip: process.platform !== 'darwin'}, t => {
  const directory = mkdtempSync(join(tmpdir(), 'isg-pilot-company-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  const binary = join(directory, 'check');
  const result = spawnSync('swiftc', ['-parse-as-library',
    'App/DesignSystem/ISG/NovaNavigation.swift', 'App/DesignSystem/ISG/NovaSessionHost.swift',
    'App/DesignSystem/ISG/NovaPersonnel.swift', 'App/Services/Company/NovaPersonnelService.swift',
    'App/Services/Company/NovaPilotCompanyService.swift', 'scripts/isg/NovaPilotCompanyCheck.swift', '-o', binary],
    {cwd: ROOT, encoding: 'utf8', timeout: 60000});
  assert.equal(result.status, 0, result.stderr);
  const executed = spawnSync(binary, [], {encoding: 'utf8', timeout: 10000});
  assert.equal(executed.status, 0, executed.stderr);
  assert.match(executed.stdout, /44 pilot company checks PASS/);
});

test('pilot UI is private-build-only and has no legacy write/store escape', () => {
  const source = readFileSync(join(ROOT, 'App/Views/Components/NovaPilotMainGate.swift'), 'utf8');
  assert.match(source, /#if DEBUG && NOVA_PILOT_BUILD/);
  assert.match(source, /UUID\(uuidString: configured\) == session.user.id/);
  assert.match(source, /#if targetEnvironment\(simulator\)/);
  assert.doesNotMatch(source, /NovaCompanyManagementGate|CompanyManagementView|PaywallView/);
  const service = readFileSync(join(ROOT, 'App/Services/Company/NovaPilotCompanyService.swift'), 'utf8');
  assert.doesNotMatch(service, /\.from\(|\.insert\(payload|\.update\(payload/);
  assert.match(service, /isg_pilot_company_create_v1/);
});
