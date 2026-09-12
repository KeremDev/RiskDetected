#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { ROOT, parseCSV, policy } from './lib.mjs';

export function buildTestManifest(root = ROOT) {
  const source = readFileSync(resolve(root, 'docs/isg/source/ISG_ADASI_MASTER_INTEGRATION_PLAN_V5.md'), 'utf8');
  const plan = readFileSync(resolve(root, 'docs/isg/ISG_ADASI_TRANSITION_PLAN_2026-09-12.md'), 'utf8');
  if (createHash('sha256').update(source).digest('hex') !== policy.source_sha256) throw new Error('SOURCE_HASH_DRIFT');
  const rows = parseCSV(readFileSync(resolve(root, 'docs/isg/V5_ACCEPTANCE_TEST_REGISTRY.csv'), 'utf8'));
  const header = rows.shift();
  if (header.join(',') !== 'requirement_key,source_section,source_test_id,source_line,scenario,expected_result,planned_layers,implementation_status,execution_status,interpretation_note') throw new Error('REGISTRY_HEADER_DRIFT');
  const sourceLines = source.split('\n');
  const cases = rows.map(row => {
    if (row.length !== header.length) throw new Error('REGISTRY_COLUMN_DRIFT');
    const r = Object.fromEntries(header.map((key, i) => [key, row[i]]));
    const original = sourceLines[Number(r.source_line) - 1]?.match(/^\|\s*([A-Z]+[0-9]*-\d+)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|\s*$/);
    if (r.requirement_key !== `V5:${r.source_section}:${r.source_test_id}` || original?.[1] !== r.source_test_id || original?.[2] !== r.scenario || original?.[3] !== r.expected_result) throw new Error('REGISTRY_SOURCE_MISMATCH');
    return { id: r.requirement_key, kind: 'source', scenario: r.scenario, expected: r.expected_result, implementation_status: 'UNMAPPED', tests: [] };
  });
  const extras = [...plan.matchAll(/^\| (X\d{2}) \| ([^\n]+)$/gm)].map(m => {
    const columns = m[2].split('|').map(s => s.trim());
    return { id: `TRANSITION:${m[1]}`, kind: 'transition', scenario: columns[0], expected: columns[1], implementation_status: 'UNMAPPED', tests: [] };
  });
  if (cases.length !== policy.source_acceptance_count || extras.length !== policy.transition_acceptance_count) throw new Error('ACCEPTANCE_COUNT_DRIFT');
  if (extras.some((c,i) => c.id !== `TRANSITION:X${String(i+1).padStart(2,'0')}` || !c.scenario || !c.expected)) throw new Error('TRANSITION_SEQUENCE_DRIFT');
  const all = [...cases, ...extras];
  if (new Set(all.map(c => c.id)).size !== all.length) throw new Error('DUPLICATE_ACCEPTANCE_ID');
  return { schema_version: 1, source_sha256: policy.source_sha256, source_count: cases.length, transition_count: extras.length, total: all.length, release_ready: false, note: 'Inventory only; no acceptance test has been executed or mapped by this generator.', cases: all };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try { const r = buildTestManifest(); console.log(JSON.stringify(process.argv.includes('--full') ? r : { ...r, cases: undefined }, null, 2)); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
