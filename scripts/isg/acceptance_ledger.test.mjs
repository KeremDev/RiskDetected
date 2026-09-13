import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,existsSync} from 'node:fs';
import {resolve} from 'node:path';
import {ROOT} from './lib.mjs';
import {buildLedger,collectClaims} from './acceptance_ledger.mjs';

const read=path=>readFileSync(resolve(ROOT,path),'utf8');
const ledger=buildLedger();

test('the ledger covers every acceptance case the manifest knows about',()=>{
  assert.equal(ledger.problems.length,0,ledger.problems.join('\n'));
  assert.equal(ledger.total,263);
  assert.equal(ledger.source_count,203);
  assert.equal(ledger.transition_count,60);
  const ids=new Set(ledger.cases.map(entry=>entry.id));
  assert.equal(ids.size,ledger.total,'an acceptance id appears twice');
  const sum=Object.values(ledger.counts).reduce((a,b)=>a+b,0);
  assert.equal(sum,ledger.total,'the status counts do not add up to the case count');
});

test('a case is covered only when every required layer is full',()=>{
  for(const entry of ledger.cases){
    assert.ok(entry.required_layers.length>0,`${entry.id} requires no layer`);
    if(entry.status==='covered'){
      assert.equal(entry.blocking_layers.length,0,`${entry.id} is covered with ${entry.blocking_layers}`);
      assert.ok(entry.claimed_by.length>0,`${entry.id} is covered with no evidence behind it`);
    }
    if(entry.claimed_by.length===0)assert.notEqual(entry.status,'covered');
  }
});

test('every claim points at an evidence file that exists and names the id',()=>{
  const claims=collectClaims();
  for(const [id,files] of claims){
    for(const file of files){
      assert.ok(existsSync(resolve(ROOT,file)),`${id} points at missing ${file}`);
      const parsed=JSON.parse(read(file));
      const ids=parsed.acceptance_ids_covered.map(value=>String(value).replace(/\s*\(.*\)$/,'').trim());
      assert.ok(ids.includes(id),`${file} does not actually name ${id}`);
    }
  }
  assert.ok(claims.size>=19,`expected the P14 to P17 claims, found ${claims.size}`);
});

test('a layer that is not full has to name what is missing',()=>{
  const layers=JSON.parse(read('docs/isg/acceptance/layer-evidence.json')).layers;
  for(const [name,entry] of Object.entries(layers)){
    if(entry.status==='full'){
      assert.ok(entry.evidence.length>0,`${name} is full without evidence`);
      continue;
    }
    assert.ok(entry.blocker&&entry.blocker.length>10,`${name} is not full and names no blocker`);
    if(entry.status==='none')assert.equal(entry.evidence.length,0,`${name} says none but lists evidence`);
  }
});

test('the release gate stays closed while anything is unproven',()=>{
  assert.equal(ledger.release_ready,false);
  assert.equal(ledger.counts.covered,0,'a case became covered without this gate being reviewed');
  // The layers that produced nothing at all are the release blockers to close.
  const nothing=ledger.blocking_layers.filter(entry=>entry.status==='none').map(entry=>entry.layer);
  assert.deepEqual(nothing.sort(),['ADMIN','COMPATIBILITY','CROSS_LAYER_ACCEPTANCE','DELETION','OPERATIONS','STORE_QA']);
  const report=JSON.parse(read('docs/isg/acceptance/coverage-report.json'));
  assert.equal(report.release_ready,false);
  assert.equal(report.total,ledger.total);
  assert.deepEqual(report.counts,ledger.counts,'the written report drifted from the ledger');
});

test('the registry never reports a run that did not happen',()=>{
  const rows=read('docs/isg/V5_ACCEPTANCE_TEST_REGISTRY.csv').split('\n').slice(1).filter(Boolean);
  assert.equal(rows.length,203);
  for(const row of rows){
    if(row.includes('"RUN"'))assert.ok(row.includes('"IMPLEMENTED"'),`a row claims RUN without IMPLEMENTED: ${row.slice(0,60)}`);
  }
});
