import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { assertNoExposedRestoreContainer, resolvePinnedRestoreImage } from './auth_restore_guard.mjs';
import { ROOT } from './lib.mjs';

const sample = () => ({ HostConfig: { Privileged: false, PidMode: '', PortBindings: {} }, Mounts: [],
  NetworkSettings: { Ports: { '5432/tcp': null }, Networks: { none: { IPAddress: '', GlobalIPv6Address: '' } } } });
test('immutable registry digest resolves the actual classic/containerd image ID on ARM/x64', () => {
  const reference = 'public.ecr.aws/supabase/postgres@sha256:'+'a'.repeat(64);
  for (const architecture of ['arm64','amd64']) for(const id of ['a','b']) {
    const info = {Id:'sha256:'+id.repeat(64),RepoDigests:[reference],Os:'linux',Architecture:architecture};
    assert.equal(resolvePinnedRestoreImage(info,reference).id,info.Id);
  }
  const valid = {Id:'sha256:'+'b'.repeat(64),RepoDigests:[reference],Os:'linux',Architecture:'arm64'};
  for (const patch of [{Id:'invalid'},{RepoDigests:[]},{RepoDigests:null},{Os:'windows'},{Architecture:'unknown'}]) {
    assert.throws(()=>resolvePinnedRestoreImage({...valid,...patch},reference),/AUTH_RESTORE_PINNED_IMAGE_INVALID/);
  }
  assert.throws(()=>resolvePinnedRestoreImage(valid,'postgres:latest'),/AUTH_RESTORE_PINNED_IMAGE_INVALID/);
});
test('restore isolation accepts no-network DB and shared-namespace child with no bindings', () => {
  assert.doesNotThrow(() => assertNoExposedRestoreContainer(sample()));
  const child = sample(); child.NetworkSettings.Networks = {};
  assert.doesNotThrow(() => assertNoExposedRestoreContainer(child));
});
for (const [name, mutate] of [
  ['privileged', i => i.HostConfig.Privileged = true],
  ['host PID', i => i.HostConfig.PidMode = 'host'],
  ['mount', i => i.Mounts.push({ Type: 'bind', Source: '/unapproved' })],
  ['published port', i => i.NetworkSettings.Ports['5432/tcp'] = [{ HostIp: '127.0.0.1', HostPort: '64322' }]],
  ['pending port binding', i => i.HostConfig.PortBindings['5432/tcp'] = []],
  ['added external network despite original none mode', i => i.NetworkSettings.Networks.bridge = { IPAddress: '172.17.0.2' }],
  ['unexpected IPv4', i => i.NetworkSettings.Networks.none.IPAddress = '172.17.0.2'],
  ['unexpected IPv6', i => i.NetworkSettings.Networks.none.GlobalIPv6Address = '2001:db8::1'],
  ['missing mount inventory', i => delete i.Mounts],
  ['missing network inventory', i => delete i.NetworkSettings],
  ['missing privilege flag', i => delete i.HostConfig.Privileged],
  ['missing port bindings', i => delete i.HostConfig.PortBindings],
  ['missing ports', i => delete i.NetworkSettings.Ports],
  ['missing networks', i => delete i.NetworkSettings.Networks],
  ['malformed networks', i => i.NetworkSettings.Networks = []],
  ['missing address evidence', i => delete i.NetworkSettings.Networks.none.IPAddress],
]) test(`restore isolation rejects ${name}`, () => {
  const inspection = sample(); mutate(inspection);
  assert.throws(() => assertNoExposedRestoreContainer(inspection), /AUTH_RESTORE_ISOLATION_FAILED/);
});
test('sensitive P00 runners reject unsupported arguments before capture, key lookup or Docker work', () => {
  for (const path of ['capture_managed_migrations.mjs', 'export_migration_supplement.mjs', 'run_auth_restore.mjs']) {
    const r = spawnSync(process.execPath, [`scripts/isg/${path}`, '--not-approved'], {
      cwd: ROOT, encoding: 'utf8', timeout: 5000, env: { PATH: '/no-tools-available' },
    });
    assert.equal(r.status, 1);
    if (path === 'run_auth_restore.mjs') {
      const report = JSON.parse(r.stdout);
      assert.equal(report.error_code, 'AUTH_RESTORE_EXPLICIT_MODE_REQUIRED');
      assert.equal(report.evidence_directory, null);
      assert.deepEqual(report.checks, []);
    } else assert.match(r.stderr, /BACKUP_ARGUMENTS_NOT_ALLOWED/);
  }
});
test('synthetic mode cannot opt into a real backup, and reaches image preflight without source access', () => {
  for (const args of [['--synthetic-session','--with-storage'],['--synthetic-session','--isolated-copy'],['--isolated-copy','--synthetic-session']]) {
    const r=spawnSync(process.execPath,['scripts/isg/run_auth_restore.mjs',...args],{cwd:ROOT,encoding:'utf8',timeout:5000,env:{PATH:'/no-tools-available'}});
    const report=JSON.parse(r.stdout);
    assert.equal(r.status,1);assert.equal(report.error_code,'AUTH_RESTORE_EXPLICIT_MODE_REQUIRED');assert.equal(report.evidence_directory,null);
  }
  const r=spawnSync(process.execPath,['scripts/isg/run_auth_restore.mjs','--synthetic-session'],{cwd:ROOT,encoding:'utf8',timeout:5000,env:{PATH:'/no-tools-available'}});
  const report=JSON.parse(r.stdout);
  assert.equal(r.status,1);assert.equal(report.error_code,'AUTH_RESTORE_PINNED_IMAGE_MISSING');
  assert.equal(report.data_class,'synthetic');assert.equal(report.original_source_accessed,false);assert.equal(report.evidence_directory,null);
});
