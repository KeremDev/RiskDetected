import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { ROOT } from './lib.mjs';

// Local pure-core test only: does not access Keychain, Supabase or an app account.
test('Swift production notebook queue: retry, identity isolation and conflict preservation', { skip: process.platform !== 'darwin' }, t => {
  const directory = mkdtempSync(join(tmpdir(), 'isg-notebook-core-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const binary = join(directory, 'check');
  const compiled = spawnSync('swiftc', ['-parse-as-library', 'App/Services/Notebook/NotebookOrganization.swift', 'App/Services/Notebook/NotebookQueue.swift', 'scripts/isg/NotebookQueueCheck.swift', '-o', binary], { cwd: ROOT, encoding: 'utf8', timeout: 60000 });
  assert.equal(compiled.status, 0, compiled.stderr);
  const executed = spawnSync(binary, [], { encoding: 'utf8', timeout: 10000 });
  assert.equal(executed.status, 0, executed.stderr);
  assert.match(executed.stdout, /32 checks PASS/);
});

test('Swift production notebook reader rejects stale and cross-session responses', { skip: process.platform !== 'darwin' }, t => {
  const directory = mkdtempSync(join(tmpdir(), 'isg-notebook-reader-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const binary = join(directory, 'check');
  const compiled = spawnSync('swiftc', ['-parse-as-library', 'App/Services/Notebook/NotebookOrganization.swift', 'App/Services/Notebook/NotebookQueue.swift', 'App/Services/Notebook/NotebookReader.swift', 'App/Services/Notebook/NotebookConflict.swift', 'scripts/isg/NotebookReaderCheck.swift', '-o', binary], { cwd: ROOT, encoding: 'utf8', timeout: 60000 });
  assert.equal(compiled.status, 0, compiled.stderr);
  const executed = spawnSync(binary, [], { encoding: 'utf8', timeout: 10000 });
  assert.equal(executed.status, 0, executed.stderr);
  assert.match(executed.stdout, /NotebookReader: PASS/);
});

test('Swift reminder contract keeps server-push ownership and explicit nulls', { skip: process.platform !== 'darwin' }, t => {
  const directory = mkdtempSync(join(tmpdir(), 'isg-notebook-reminder-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const binary = join(directory, 'check');
  const compiled = spawnSync('swiftc', ['-parse-as-library', 'App/Services/Notebook/NotebookOrganization.swift',
    'App/Services/Notebook/NotebookQueue.swift', 'App/Services/Notebook/NotebookReminder.swift',
    'scripts/isg/NotebookReminderCheck.swift', '-o', binary], { cwd: ROOT, encoding: 'utf8', timeout: 60000 });
  assert.equal(compiled.status, 0, compiled.stderr);
  const executed = spawnSync(binary, [], { encoding: 'utf8', timeout: 10000 });
  assert.equal(executed.status, 0, executed.stderr);
  assert.match(executed.stdout, /NotebookReminder: PASS/);
});
