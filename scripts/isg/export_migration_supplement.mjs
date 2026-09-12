#!/usr/bin/env node
import { spawn, spawnSync } from 'node:child_process';
import { chmodSync, copyFileSync, lstatSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { stat } from 'node:fs/promises';
import { resolve } from 'node:path';
import { ROOT } from './lib.mjs';
import { encryptArchive, verifyArchive, hashFile } from './backup_crypto.mjs';

const parent = '/Users/keremkayalar/Desktop/ISG_Adasi_Yedek_2026-09-12_rX4mVI';
const source = 'backups/isg-managed-migrations-20260912-osigPE';
let key, tar, target;
try {
  if (process.argv.length !== 2) throw new Error('BACKUP_ARGUMENTS_NOT_ALLOWED');
  for (const path of [parent, resolve(ROOT, source)]) {
    if (!lstatSync(path).isDirectory() || lstatSync(path).isSymbolicLink()) throw new Error('BACKUP_PATH_INVALID');
  }
  if (await hashFile(resolve(ROOT, source, 'managed-migration-data.sql')) !== 'e027928e0d920f3cd616991af4a48378adb63daf33e53790c04bb90d4f384fe5') throw new Error('BACKUP_SOURCE_DRIFT');
  const original = JSON.parse(readFileSync(resolve(parent, 'MANIFEST.json'), 'utf8'));
  if (original.status !== 'VERIFIED' || original.key_service !== 'riskdetected_backup_20260912_2c6eecd79a9a489c90ce81bfdeb67854') throw new Error('BACKUP_PARENT_INVALID');
  target = mkdtempSync(resolve(parent, 'ek-servis-migration-20260912-')); chmodSync(target, 0o700);
  for (const name of ['backup-keychain', 'BackupKeychain.swift', 'backup_crypto.mjs', 'recover_desktop_backup.mjs']) {
    copyFileSync(resolve(parent, name), resolve(target, name)); chmodSync(resolve(target, name), name === 'backup-keychain' ? 0o700 : 0o600);
  }
  const r = spawnSync(resolve(parent, 'backup-keychain'), ['get', original.key_service], { encoding: 'utf8', timeout: 30_000 });
  if (r.status !== 0) throw new Error('BACKUP_KEY_UNAVAILABLE');
  key = Buffer.from(r.stdout, 'base64');
  const archive = resolve(target, 'riskdetected-checkpoint.isgbk');
  tar = spawn('tar', ['-cf', '-', '-C', ROOT, source], { stdio: ['ignore', 'pipe', 'pipe'] }); tar.stderr.resume();
  const ended = new Promise(resolve => { tar.once('error', () => resolve(false)); tar.once('close', code => resolve(code === 0)); });
  const encrypted = await encryptArchive(tar.stdout, archive, key);
  if (!await ended) throw new Error('BACKUP_TAR_FAILED');
  const verified = await verifyArchive(archive, key);
  if (verified.plaintext_sha256 !== encrypted.plaintext_sha256) throw new Error('BACKUP_ROUNDTRIP_MISMATCH');
  const manifest = { schema_version: 1, status: 'VERIFIED', finished_at: new Date().toISOString(),
    archive: 'riskdetected-checkpoint.isgbk', scope: 'Auth/Storage service migration ledger supplement ONLY', source,
    key_service: original.key_service, key_account: original.key_account, format: 'ISGBK001/AES-256-GCM',
    fresh_random_nonce: true, parent_archive_unchanged: true, same_physical_disk: true, off_device_backup: false,
    encrypted_bytes: (await stat(archive)).size, encrypted_sha256: await hashFile(archive), ...verified };
  writeFileSync(resolve(target, 'MANIFEST.json'), JSON.stringify(manifest, null, 2) + '\n', { mode: 0o600 });
  writeFileSync(resolve(target, 'OKU_BENI.md'), '# Ek servis migration yedeği\n\nYalnız 12 Eylül 2026 17:56 UTC tarihli Auth 77 / Storage 68 migration geçmişi ve manifest içerir. Ana checkpoint arşivinin yerine geçmez; ana yedek değiştirilmedi. Aynı Keychain anahtarı, yeni rastgele GCM nonce kullanıldı. Aynı disk korumasıdır; off-device değildir.\n\nBu klasörde `node recover_desktop_backup.mjs /tam/yol/yeni-ek-yedek.tar` ile doğrulanmış tar üretilebilir. Otomatik extraction veya DB işlemi yoktur. Ek SQL yalnız yeni izole restore üzerinde, mevcut ledger boşluğu ve şema uyumluluğu kontrol edilerek uygulanmalıdır. Production migration apply komutu değildir.\n', { mode: 0o600 });
  console.log(JSON.stringify({ ok: true, backup_directory: target, ...manifest }, null, 2));
} catch (error) {
  tar?.kill('SIGTERM'); console.error(/^BACKUP_/.test(error.message) ? error.message : 'BACKUP_SUPPLEMENT_FAILED'); process.exitCode = 1;
} finally { key?.fill(0); }
