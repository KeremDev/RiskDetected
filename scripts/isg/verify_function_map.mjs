#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { ROOT, isRecord } from './lib.mjs';

// Initial narrow gate, NOT an AST/call-graph or whole-application coverage claim.
// Entire-file fingerprints also reject newly added private functions that a
// lexical symbol scanner could miss. Updating fingerprints requires test review.
const roots = ['supabase/functions/_shared/isg', 'App/Services/ISG', 'android/core/data/src/main/kotlin/com/riskdetectedan/core/data/isg'];
const runners = {
  'deno-context': 'supabase/functions/_shared/isg/mutation-context_test.ts',
  'swift-context': 'scripts/isg/MutationContextCheck.swift',
  'android-context': 'android/core/data/src/test/kotlin/com/riskdetectedan/core/data/isg/IsgMutationContextTest.kt',
  'deno-outcome': 'supabase/functions/_shared/isg/mutation-outcome_test.ts',
  'swift-outcome': 'scripts/isg/MutationOutcomeCheck.swift',
  'android-outcome': 'android/core/data/src/test/kotlin/com/riskdetectedan/core/data/isg/IsgMutationOutcomeTest.kt',
  'node-notification': 'scripts/isg/notification_worker.test.mjs',
  'node-notification-repository': 'scripts/isg/notification_repository.test.mjs',
  'node-notification-journal': 'scripts/isg/notification_journal.test.mjs',
};
const digest = value => createHash('sha256').update(value).digest('hex');
export function runtimeFiles(root = ROOT) {
  const files = [];
  function visit(directory) {
    for (const entry of readdirSync(resolve(root, directory), { withFileTypes: true })) {
      if (entry.isSymbolicLink()) throw new Error('FUNCTION_MAP_SYMLINK_REFUSED');
      const name = `${directory}/${entry.name}`;
      if (entry.isDirectory()) visit(name);
      else if (/\.(ts|swift|kt)$/.test(name) && !/_test\.ts$/.test(name)) files.push(name);
    }
  }
  roots.forEach(visit); return files.sort();
}
export function validateFunctionMap(map, files, read) {
  const errors = [];
  try {
    if (!isRecord(map) || map.schema_version !== 1 || map.scope !== 'isg_transport_only' || !Array.isArray(map.bindings) ||
        map.fixture !== 'contracts/isg/v1/fixtures/mutation-context.json') throw new Error('FUNCTION_MAP_FORMAT');
    const fixture = read(map.fixture);
    if (digest(fixture) !== map.fixture_sha256) errors.push('FIXTURE_HASH_DRIFT');
    const cases = JSON.parse(fixture).cases;
    if (!Array.isArray(cases) || cases.length !== map.fixture_count || new Set(cases.map(c => c.id)).size !== cases.length) errors.push('FIXTURE_INVENTORY_DRIFT');
    const mapped = new Set(), ids = new Set();
    for (const binding of map.bindings) {
      if (!isRecord(binding) || !files.includes(binding.source) || !Object.hasOwn(runners, binding.runner) ||
          binding.harness !== runners[binding.runner] || binding.coverage !== (binding.runner.startsWith('node-notification') ? 'targeted_behavior_tests' : 'shared_corpus_all_cases') ||
          !Array.isArray(binding.symbols) || !binding.symbols.length || binding.symbols.some(s => typeof s !== 'string' || !s)) throw new Error('FUNCTION_MAP_BINDING_INVALID');
      if (mapped.has(binding.source) || ids.has(binding.id)) errors.push('DUPLICATE_BINDING');
      mapped.add(binding.source); ids.add(binding.id);
      if (binding.runner.endsWith('-outcome')) {
        if (binding.fixture !== 'contracts/isg/v1/fixtures/mutation-outcome.json') throw new Error('FUNCTION_MAP_BINDING_INVALID');
        const body = read(binding.fixture), corpus = JSON.parse(body);
        if (digest(body) !== binding.fixture_sha256) errors.push('FIXTURE_HASH_DRIFT');
        if (!Array.isArray(corpus.cases) || corpus.cases.length !== binding.fixture_count ||
            new Set(corpus.cases.map(c=>c.id)).size !== corpus.cases.length ||
            !Array.isArray(corpus.transitions) || corpus.transitions.length !== binding.transition_count ||
            new Set(corpus.transitions.map(c=>c.id)).size !== corpus.transitions.length) errors.push('FIXTURE_INVENTORY_DRIFT');
      }
      if (digest(read(binding.source)) !== binding.source_sha256) errors.push('SOURCE_FINGERPRINT_DRIFT');
      if (digest(read(binding.harness)) !== binding.harness_sha256) errors.push('HARNESS_FINGERPRINT_DRIFT');
    }
    if (files.some(file => !mapped.has(file))) errors.push('UNMAPPED_RUNTIME_FILE');
    if (map.bindings.length !== files.length) errors.push('BINDING_COUNT_DRIFT');
  } catch (error) { errors.push(/^FUNCTION_MAP_/.test(error.message) ? error.message : 'FUNCTION_MAP_UNREADABLE'); }
  return { ok: errors.length === 0, errors: [...new Set(errors)], scope: 'isg_transport_only',
    runtime_files: files.length, mapping_only: true, tests_executed: false, release_ready: false,
    limitation: 'File fingerprints and reviewed symbol labels; not complete AST coverage, legacy inventory, domain acceptance or execution evidence.' };
}
export function verifyFunctionMap(root = ROOT) {
  return validateFunctionMap(JSON.parse(readFileSync(resolve(root, 'contracts/isg/v1/function-test-map.json'), 'utf8')),
    runtimeFiles(root), path => readFileSync(resolve(root, path), 'utf8'));
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try { const result = verifyFunctionMap(); console.log(JSON.stringify(result, null, 2)); process.exitCode = result.ok ? 0 : 1; }
  catch { console.error('FUNCTION_MAP_SCAN_FAILED'); process.exitCode = 1; }
}
