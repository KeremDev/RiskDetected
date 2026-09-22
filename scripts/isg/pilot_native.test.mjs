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
  assert.match(source, /UUID\(uuidString: configured\) == userID/);
  assert.match(source, /Bundle\.main\.bundleIdentifier == "com\.riskdetected\.app\.osgbpilot"/);
  assert.match(source, /Self\.canOpenNovaPilot\(userID: session\.user\.id\)/);
  assert.match(source, /#if targetEnvironment\(simulator\)/);
  assert.doesNotMatch(source, /NovaCompanyManagementGate|CompanyManagementView|PaywallView/);
  const service = readFileSync(join(ROOT, 'App/Services/Company/NovaPilotCompanyService.swift'), 'utf8');
  assert.doesNotMatch(service, /\.from\(|\.insert\(payload|\.update\(payload/);
  assert.match(service, /isg_pilot_company_create_v1/);
});

test('OSGB pilot opens a scoped password login without changing production OTP', () => {
  const root = readFileSync(join(ROOT, 'App/RootView.swift'), 'utf8');
  const state = readFileSync(join(ROOT, 'App/AppState.swift'), 'utf8');
  const entry = readFileSync(join(ROOT, 'App/Views/Onboarding/Nova/NovaPilotEntryGate.swift'), 'utf8');
  const config = readFileSync(join(ROOT, 'App/Services/RDConfig.swift'), 'utf8');
  assert.match(root, /#if DEBUG && NOVA_PILOT_BUILD/);
  assert.match(root, /NovaPilotEntryGate\(\)/);
  assert.match(state, /isOSGBPilotBundle[\s\S]*com\.riskdetected\.app\.osgbpilot/);
  assert.match(state, /authError = Self\.isOSGBPilotBundle \? nil/);
  assert.match(entry, /signInWithPassword\(email: email, password: password\)/);
  assert.match(entry, /NovaLoginScreen\(auth: bridge\)/);
  assert.match(entry, /#if DEBUG && NOVA_PILOT_BUILD/);
  assert.match(root, /#else\s+AuthView\(\)/);
  assert.match(config, /osgbPilotSupabaseURLString = "https:\/\/qlymhrrlhklcudveknih\.supabase\.co"/);
  assert.match(config, /if isOSGBPilotBundle \{[\s\S]*return URL\(string: osgbPilotSupabaseURLString\)!/);
  assert.match(config, /if isOSGBPilotBundle \{[\s\S]*return osgbPilotPublishableKey/);
});

test('OSGB pilot Google token audience is accepted by Supabase Auth config', () => {
  const plist = readFileSync(join(ROOT, 'Config/RiskDetectedInfo.plist'), 'utf8');
  const supabaseConfig = readFileSync(join(ROOT, 'supabase/config.toml'), 'utf8');
  const serverClientID = plist.match(
    /<key>GIDServerClientID<\/key>\s*<string>([^<]+)<\/string>/,
  )?.[1];

  assert.ok(serverClientID, 'GIDServerClientID must be configured');
  assert.match(
    supabaseConfig,
    new RegExp(`\\[auth\\.external\\.google\\][\\s\\S]*client_id = "[^"]*${serverClientID}`),
    'Supabase must accept the audience emitted by the native Google sign-in flow',
  );
});
