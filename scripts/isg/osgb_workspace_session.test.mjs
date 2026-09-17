import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {ROOT} from './lib.mjs';

test('Swift host invalidates account-scoped work on workspace switch',()=>{
  const directory=mkdtempSync(join(tmpdir(),'isgada-workspace-session-'));
  try {
    const binary=join(directory,'workspace-session-check');
    const build=spawnSync('swiftc',['App/DesignSystem/ISG/NovaNavigation.swift','App/DesignSystem/ISG/NovaSessionHost.swift',
      'scripts/isg/WorkspaceSessionCheck.swift','-o',binary],{cwd:ROOT,encoding:'utf8',timeout:30000});
    assert.equal(build.status,0,build.stderr||build.stdout);
    const run=spawnSync(binary,[],{cwd:ROOT,encoding:'utf8',timeout:10000});
    assert.equal(run.status,0,run.stderr||run.stdout);
    assert.match(run.stdout,/PASS Swift workspace session/);
  } finally { rmSync(directory,{recursive:true,force:true}); }
});

test('iOS and Android hosts carry workspace, membership and permission revisions in stale-response guards',()=>{
  for(const path of ['App/DesignSystem/ISG/NovaSessionHost.swift',
    'android/core/designsystem/src/main/kotlin/com/riskdetectedan/core/designsystem/isg/NovaSessionHost.kt']) {
    const source=readFileSync(resolve(ROOT,path),'utf8');
    for(const token of ['NovaWorkspaceSelection','workspaceID','membershipID','permissionRevision','beginWorkspaceSwitch','workspace == ticket.workspace']) assert.ok(source.includes(token),`${path}: ${token}`);
  }
  assert.match(readFileSync(resolve(ROOT,'android/core/designsystem/src/test/kotlin/com/riskdetectedan/core/designsystem/isg/NovaWorkspaceSessionTest.kt'),'utf8'),/switchInvalidatesOldEpochAndRevision/);
});
