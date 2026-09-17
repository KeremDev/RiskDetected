import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {ROOT} from './lib.mjs';
import {parseIsgWorkspaceContext} from '../../supabase/functions/_shared/isg/workspace-context.ts';

const fixturePath=resolve(ROOT,'contracts/isg/v2/fixtures/workspace-context.json');
const corpus=JSON.parse(readFileSync(fixturePath,'utf8'));

test('TypeScript workspace context rejects forged or inconsistent capabilities',()=>{
  for(const item of corpus.cases) assert.equal(parseIsgWorkspaceContext(item.input).ok,item.valid,item.id);
});

test('Swift workspace context has the same strict fixture outcomes',()=>{
  const directory=mkdtempSync(join(tmpdir(),'isgada-workspace-context-'));
  try {
    const binary=join(directory,'workspace-context-check');
    const build=spawnSync('swiftc',['App/Services/ISG/IsgMutationContext.swift','scripts/isg/WorkspaceContextCheck.swift','-o',binary],
      {cwd:ROOT,encoding:'utf8',timeout:30000});
    assert.equal(build.status,0,build.stderr||build.stdout);
    const run=spawnSync(binary,[fixturePath],{cwd:ROOT,encoding:'utf8',timeout:10000});
    assert.equal(run.status,0,run.stderr||run.stdout);
    assert.match(run.stdout,/PASS Swift workspace context: 8 shared fixtures/);
  } finally { rmSync(directory,{recursive:true,force:true}); }
});

test('Android source implements the shared workspace identity and revision fields',()=>{
  const source=readFileSync(resolve(ROOT,'android/core/data/src/main/kotlin/com/riskdetectedan/core/data/isg/IsgMutationContext.kt'),'utf8');
  for(const token of ['data class IsgWorkspaceContext','workspaceId','permissionRevision','isPracticingExpert','canManageBilling']) assert.match(source,new RegExp(token));
  assert.match(readFileSync(resolve(ROOT,'android/core/data/src/test/kotlin/com/riskdetectedan/core/data/isg/IsgWorkspaceContextTest.kt'),'utf8'),/workspace-context\.json/);
});
