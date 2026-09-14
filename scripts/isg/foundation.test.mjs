import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { ROOT, parseCSV } from './lib.mjs';
import { validateEnvironment, validateContainerInspection } from './verify_environment.mjs';
import { verifyIdentity, verifyIdentitySources } from './verify_identity.mjs';
import { buildTestManifest } from './build_test_manifest.mjs';

const fixture = JSON.parse(readFileSync(resolve(ROOT, 'contracts/isg/v1/local-test-environment.example.json'), 'utf8'));
test('explicit local synthetic environment is accepted, without contacting any service', () => {
  assert.equal(validateEnvironment(fixture).ok, true);
});

const invalid = [
  ['missing manifest', undefined], ['array manifest', []], ['empty manifest', {}],
  ['production environment', { ...fixture, environment: 'production' }],
  ['unapproved staging', { ...fixture, environment: 'staging', supabase_url: 'https://staging.example.com' }],
  ['production project', { ...fixture, project_id: 'isg_test_ppcrzemgiztzcgddbins' }],
  ['old local stack', { ...fixture, supabase_url: 'http://127.0.0.1:54321', database_port: 54322 }],
  ['production API', { ...fixture, supabase_url: 'https://ppcrzemgiztzcgddbins.supabase.co' }],
  ['DNS loopback alias', { ...fixture, supabase_url: 'http://localhost:61321' }],
  ['noncanonical IPv4', { ...fixture, supabase_url: 'http://127.1:61321' }],
  ['URL credentials', { ...fixture, supabase_url: 'http://user:do-not-log@127.0.0.1:61321' }],
  ['URL query', { ...fixture, supabase_url: 'http://127.0.0.1:61321?token=do-not-log' }],
  ['URL fragment', { ...fixture, supabase_url: 'http://127.0.0.1:61321#prod' }],
  ['URL path', { ...fixture, supabase_url: 'http://127.0.0.1:61321/proxy' }],
  ['wrong DB host', { ...fixture, database_host: 'host.docker.internal' }],
  ['string port', { ...fixture, database_port: '61322' }],
  ['wrong container', { ...fixture, database_container: 'supabase_db_ppcrzemgiztzcgddbins' }],
  ['real data in normal tests', { ...fixture, data_class: 'production_backup' }],
  ['store purchases', { ...fixture, store_mode: 'sandbox' }],
  ['real push', { ...fixture, push_mode: 'live' }],
  ['real email', { ...fixture, email_mode: 'live' }],
  ['paid AI', { ...fixture, ai_mode: 'live' }],
  ['outbound enabled', { ...fixture, outbound_mode: 'enabled' }],
  ['unknown secret field', { ...fixture, secret_key: 'do-not-log' }],
];
for (const [name, config] of invalid) test(`fail closed: ${name}`, () => {
  const result = validateEnvironment(config);
  assert.equal(result.ok, false);
  assert.ok(result.errors.length > 0);
  assert.equal(JSON.stringify(result).includes('do-not-log'), false);
});

function inspection() {
  return { Name: `/${fixture.database_container}`, Config: { Labels: { 'com.riskdetected.isg-test-project': fixture.project_id } },
    State: { Running: true }, HostConfig: { NetworkMode: 'none', PortBindings: {}, Privileged:false }, NetworkSettings: { Networks: { none: {} }, Ports:{} }, Mounts: [] };
}
test('no-network scoped database passes live-inspection guard', () => assert.equal(validateContainerInspection(inspection(), fixture).ok, true));
test('ordinary Docker bridge is not test isolation', () => {
  const info = inspection(); info.HostConfig.NetworkMode = 'bridge'; info.NetworkSettings.Networks = { bridge: {} };
  assert.equal(validateContainerInspection(info, fixture).ok, false);
});
test('internal network requires matching project label on every attached network', () => {
  const info = inspection(); info.HostConfig.NetworkMode = 'isg_test_p01_net'; info.NetworkSettings.Networks = { isg_test_p01_net: {} };
  const network = { Name: 'isg_test_p01_net', Internal: true, Labels: { 'com.riskdetected.isg-test-project': fixture.project_id } };
  assert.equal(validateContainerInspection(info, fixture, [network]).ok, true);
  assert.equal(validateContainerInspection(info, fixture, [{ ...network, Internal: false }]).ok, false);
  info.NetworkSettings.Networks.internet = {};
  assert.equal(validateContainerInspection(info, fixture, [network]).ok, false);
});
test('container ownership, network, ports and host mounts cannot be bypassed', () => {
  const mutations = [
    i => { i.Name = '/other'; }, i => { i.Config.Labels = {}; }, i => { i.State.Running = false; },
    i => { i.HostConfig.Privileged = true; }, i => { i.HostConfig.PidMode = 'host'; },
    i => { i.HostConfig.PortBindings = { '5432/tcp': [{ HostIp: '0.0.0.0', HostPort: '61322' }] }; },
    i => { i.Mounts = [{ Type: 'bind', Source: '/var/run/docker.sock' }]; },
    i => { i.Mounts = [{ Type: 'volume', Name: 'existing_user_database' }]; },
    i => { delete i.Mounts; }, i => { delete i.NetworkSettings.Networks; },
    i => { delete i.NetworkSettings.Ports; }, i => { delete i.HostConfig.PortBindings; },
    i => { delete i.HostConfig.Privileged; }, i => { i.HostConfig.CapAdd=['SYS_ADMIN']; },
    i => { i.HostConfig.SecurityOpt=['seccomp=unconfined']; },
    i => { i.HostConfig.Devices=[{PathOnHost:'/dev/sda'}]; },
    i => { i.HostConfig.IpcMode='host'; },
    i => { i.NetworkSettings.Ports={'5432/tcp':[{HostIp:'0.0.0.0',HostPort:'61322'}]}; },
    i => { i.Mounts=[{Type:'volume',Name:fixture.project_id+'_not_proof_of_ownership'}]; },
  ];
  for (const mutate of mutations) { const i = inspection(); mutate(i); assert.equal(validateContainerInspection(i, fixture).ok, false); }
});
test('actual source preserves both different app identities and auth/RC identifiers', () => assert.equal(verifyIdentity().ok, true));
test('identity gate rejects changed bundle/package/callback/entitlements and missing app configurations', () => {
  const sources = { project: readFileSync(resolve(ROOT, 'RiskDetected.xcodeproj/project.pbxproj'), 'utf8'), android: readFileSync(resolve(ROOT, 'android/app/build.gradle.kts'), 'utf8'), config: readFileSync(resolve(ROOT, 'App/Services/RDConfig.swift'), 'utf8') };
  const mutants = [
    { ...sources, project: sources.project.replaceAll('com.riskdetected.app', 'com.isgadasi.app') },
    { ...sources, project: '' },
    { ...sources, android: sources.android.replace('applicationId = "com.riskdetectedan.app"', 'applicationId = "com.riskdetected.app"') },
    { ...sources, android: sources.android.replace('namespace = "com.riskdetectedan.app"', 'namespace = "com.isgadasi.app"') },
    { ...sources, config: sources.config.replace('io.supabase.riskdetected://login-callback', 'isgadasi://login-callback') },
    { ...sources, config: sources.config.replace('plusEntitlementID = "plus"', 'plusEntitlementID = "plus_v2"') },
    { ...sources, config: sources.config.replace('proEntitlementID = "pro"', 'proEntitlementID = "pro_v2"') },
  ];
  for (const mutant of mutants) assert.equal(verifyIdentitySources(mutant).ok, false);
});
test('203 source cases plus 60 transitions are inventoried, never marked tested', () => {
  const result = buildTestManifest();
  assert.equal(result.total, 263);
  assert.equal(result.release_ready, false);
  assert.ok(result.cases.every(c => c.implementation_status === 'UNMAPPED' && c.tests.length === 0));
  assert.ok(result.cases.some(c => c.id === 'V5:24.2:DEL-01'));
  assert.ok(result.cases.some(c => c.id === 'V5:37.3:DEL-01'));
});
test('CSV parser preserves multiline fields, commas, quoted text and CRLF', () => {
  assert.deepEqual(parseCSV('"a","b"\r\n"line\n2","a,""b"""\r\n'), [['a','b'], ['line\n2','a,"b"']]);
  assert.throws(() => parseCSV('"not closed'), /CSV_UNCLOSED_QUOTE/);
});
