import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {ROOT} from './lib.mjs';

test('real Swift workspace store isolates post-mutation summaries across company switches', () => {
  const dir = mkdtempSync(join(tmpdir(), 'isgada-store-'));
  try {
    const binary = join(dir, 'check');
    const build = spawnSync('swiftc', ['-parse-as-library',
      'App/Services/ISG/IsgMutationContext.swift', 'App/DesignSystem/ISG/NovaNavigation.swift',
      'App/DesignSystem/ISG/NovaSessionHost.swift', 'App/Services/ISG/IsgWorkspaceAPI.swift',
      'App/Services/ISG/IsgWorkspaceStore.swift', 'scripts/isg/WorkspaceStoreCheck.swift', '-o', binary],
    {cwd: ROOT, encoding: 'utf8', timeout: 45000});
    assert.equal(build.status, 0, build.stderr || build.stdout);
    const run = spawnSync(binary, [], {cwd: ROOT, encoding: 'utf8', timeout: 10000});
    assert.equal(run.status, 0, run.stderr || run.stdout);
    assert.match(run.stdout, /PASS Swift workspace store/);
  } finally { rmSync(dir, {recursive: true, force: true}); }
});
