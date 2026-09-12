import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { assertNoExposedRestoreContainer } from './auth_restore_guard.mjs';
import { ROOT } from './lib.mjs';

const sample = () => ({ HostConfig: { Privileged: false, PidMode: '', PortBindings: {} }, Mounts: [],
  NetworkSettings: { Ports: { '5432/tcp': null }, Networks: { none: { IPAddress: '', GlobalIPv6Address: '' } } } });
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
