#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { chmodSync, createReadStream, mkdirSync, mkdtempSync, realpathSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve, relative } from 'node:path';
import { ROOT } from './lib.mjs';

// Narrow local backup only: no staging/commit, reset, checkout, push, deploy or setup.
const source = resolve(ROOT, '../RiskDetected-OperasyonMerkezi');
function git(args, options = {}) {
  const r = spawnSync('git', args, { cwd: source, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, ...options });
  if (r.status !== 0) throw new Error('PANEL_GIT_READ_FAILED');
  return r.stdout;
}
async function sha256(file) { const h = createHash('sha256'); for await (const c of createReadStream(file)) h.update(c); return h.digest('hex'); }
try {
  if (process.argv.length !== 2) throw new Error('PANEL_ARGUMENTS_NOT_ALLOWED');
  if (realpathSync(git(['rev-parse', '--show-toplevel']).trim()) !== realpathSync(source)) throw new Error('PANEL_REPO_MISMATCH');
  mkdirSync(resolve(ROOT, 'backups'), { recursive: true });
  const target = mkdtempSync(resolve(ROOT, 'backups/isg-panel-checkpoint-20260912-'));
  chmodSync(target, 0o700);
  const before = git(['status', '--porcelain=v1', '-z']);
  const files = [...new Set(git(['ls-files', '-z', '--cached', '--others', '--exclude-standard']).split('\0').filter(Boolean))];
  const excluded = /(^|\/)(\.git|node_modules|dist|test-results|\.vercel|\.env[^/]*)(\/|$)|\.(p8|pem|jks|keystore)$/i;
  const included = files.filter(f => !excluded.test(f));
  if (included.some(f => f.startsWith('/') || f.split('/').includes('..'))) throw new Error('UNSAFE_ARCHIVE_PATH');
  const outputs = ['working-tree.tar.gz', 'repository-history.bundle', 'working-tree.patch', 'tracked-and-untracked-paths.nul', 'git-status.nul'];
  writeFileSync(resolve(target, outputs[3]), included.join('\0') + '\0', { mode: 0o600 });
  writeFileSync(resolve(target, outputs[4]), before, { mode: 0o600 });
  writeFileSync(resolve(target, outputs[2]), git(['diff', '--binary', 'HEAD']), { mode: 0o600 });
  const archive = spawnSync('tar', ['--no-mac-metadata', '--no-xattrs', '-czf', resolve(target, outputs[0]), '-C', source, '--null', '-T', '-'], { input: included.join('\0') + '\0', encoding: 'utf8', timeout: 120_000 });
  if (archive.status !== 0) throw new Error('PANEL_ARCHIVE_FAILED');
  git(['bundle', 'create', resolve(target, outputs[1]), '--all'], { timeout: 120_000 });
  for (const file of outputs) chmodSync(resolve(target, file), 0o600);
  git(['bundle', 'verify', resolve(target, outputs[1])]);
  const check = spawnSync('tar', ['-tzf', resolve(target, outputs[0])], { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024, timeout: 120_000 });
  if (check.status !== 0) throw new Error('PANEL_ARCHIVE_CHECK_FAILED');
  if (before !== git(['status', '--porcelain=v1', '-z'])) throw new Error('PANEL_CHANGED_DURING_CAPTURE');
  const manifest = { captured_at: new Date().toISOString(), source, head: git(['rev-parse', 'HEAD']).trim(), source_files: included.length, excluded_paths: files.length - included.length,
    working_tree_preserved: true, tracked_secrets_audited: false, note: 'Restricted backup; historical Git contents may contain sensitive data. Do not commit or upload. Environment/signing files are not a complete external configuration backup.', files: [] };
  for (const file of outputs) manifest.files.push({ file, sha256: await sha256(resolve(target, file)) });
  writeFileSync(resolve(target, 'MANIFEST.json'), JSON.stringify(manifest, null, 2) + '\n', { mode: 0o600 });
  console.log(JSON.stringify({ ok: true, backup_root: relative(ROOT, target), head: manifest.head, source_files: included.length, working_tree_preserved: true, bundle_verified: true, archive_verified: true }, null, 2));
} catch (error) {
  console.error(/^PANEL_|^UNSAFE_/.test(error.message) ? error.message : 'PANEL_CHECKPOINT_FAILED');
  process.exitCode = 1;
}
