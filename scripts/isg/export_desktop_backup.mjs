#!/usr/bin/env node
import { spawn, spawnSync } from 'node:child_process';
import { randomBytes, randomUUID } from 'node:crypto';
import { chmodSync, copyFileSync, lstatSync, mkdtempSync, writeFileSync } from 'node:fs';
import { stat } from 'node:fs/promises';
import { resolve } from 'node:path';
import { ROOT } from './lib.mjs';
import { encryptArchive, verifyArchive, hashFile } from './backup_crypto.mjs';

// User-approved destination, fixed checkpoint scope. Never upload or replace a backup.
const desktop = '/Users/keremkayalar/Desktop';
const sources = [
  'backups/riskdetected-change-point-20260912-182850',
  'backups/isg-panel-checkpoint-20260912-IZgsfU',
  'backups/isg-managed-schema-20260912-HHgZf9',
  'backups/isg-managed-schema-20260912-v3faRK',
];
let target, key, tar;
let report = { schema_version: 1, started_at: new Date().toISOString(), status: 'IN_PROGRESS',
  checkpoint: 'riskdetected-change-point-20260912', sources,
  format: 'ISGBK001/AES-256-GCM', same_physical_disk: true, off_device_backup: false,
  contains_current_implementation_worktree: false,
  key_account: process.env.USER, key_service: `riskdetected_backup_20260912_${randomUUID().replaceAll('-', '')}` };
function saveReport() { writeFileSync(resolve(target, 'MANIFEST.json'), JSON.stringify(report, null, 2) + '\n', { mode: 0o600 }); }
try {
  if (process.argv.length !== 2) throw new Error('BACKUP_ARGUMENTS_NOT_ALLOWED');
  if (!lstatSync(desktop).isDirectory() || lstatSync(desktop).isSymbolicLink()) throw new Error('BACKUP_DESTINATION_INVALID');
  for (const source of sources) if (!lstatSync(resolve(ROOT, source)).isDirectory() || lstatSync(resolve(ROOT, source)).isSymbolicLink()) throw new Error('BACKUP_SOURCE_INVALID');
  target = mkdtempSync(resolve(desktop, 'ISG_Adasi_Yedek_2026-09-12_')); chmodSync(target, 0o700);
  const helper = resolve(target, 'backup-keychain');
  copyFileSync(resolve(ROOT, 'output/isg/p01/backup-keychain'), helper); chmodSync(helper, 0o700);
  for (const source of ['BackupKeychain.swift', 'backup_crypto.mjs', 'recover_desktop_backup.mjs']) {
    const destination = resolve(target, source); copyFileSync(resolve(ROOT, 'scripts/isg', source), destination); chmodSync(destination, 0o600);
  }
  saveReport();
  key = randomBytes(32);
  const stored = spawnSync(helper, ['store', report.key_service], { input: key.toString('base64'), encoding: 'utf8', timeout: 30_000 });
  if (stored.status !== 0) throw new Error('BACKUP_KEYCHAIN_STORE_FAILED');
  const retrieved = spawnSync(helper, ['get', report.key_service], { encoding: 'utf8', timeout: 30_000 });
  if (retrieved.status !== 0 || !Buffer.from(retrieved.stdout, 'base64').equals(key)) throw new Error('BACKUP_KEYCHAIN_VERIFY_FAILED');
  const archive = resolve(target, 'riskdetected-checkpoint.isgbk');
  tar = spawn('tar', ['-cf', '-', '-C', ROOT, ...sources], { stdio: ['ignore', 'pipe', 'pipe'] });
  tar.stderr.resume();
  const finished = new Promise(resolve => { tar.once('error', () => resolve(false)); tar.once('close', code => resolve(code === 0)); });
  const encrypted = await encryptArchive(tar.stdout, archive, key);
  if (!await finished) throw new Error('BACKUP_ARCHIVE_FAILED');
  const verified = await verifyArchive(archive, key);
  if (encrypted.plaintext_sha256 !== verified.plaintext_sha256) throw new Error('BACKUP_ROUNDTRIP_MISMATCH');
  report = { ...report, status: 'VERIFIED', finished_at: new Date().toISOString(), archive: 'riskdetected-checkpoint.isgbk',
    encrypted_bytes: (await stat(archive)).size, encrypted_sha256: await hashFile(archive), ...verified };
  saveReport();
  writeFileSync(resolve(target, 'OKU_BENI.md'), `# RiskDetected değişim noktası — şifreli ikinci kopya\n\nTarih: ${report.finished_at}\n\nBu kopya Masaüstü'ndedir, **aynı fiziksel disktedir; disk arızası yedeği değildir**. Kaynak checkpoint, iOS/Android dosya arşivleri, Git geçmişi, Supabase veri/Storage dosyaları, admin snapshot ve Auth/Storage DDL ekleri şifrelidir. Yeni P01 çalışma değişiklikleri bu baseline arşivine dahil değildir.\n\nAES-256-GCM doğrulaması ve decrypt→SHA256 karşılaştırması tamamlandı. Düz metin tar diske yazılmadı. Manifest hash'i şifreli dosyanın bütünlüğünü ayrıca kontrol eder. Anahtar dosyada/depo içinde değildir; macOS Anahtar Zinciri'nde servis: ${report.key_service}, hesap: ${report.key_account}. Anahtarın yalnız aynı Mac'te olması da ayrı bir kurtarma riskidir; taşınabilir kopya için anahtarı ayrıca onayladığınız parola yöneticisine güvenle kaydetmelisiniz. Anahtarı sohbet/log içine yapıştırmayın.\n\n## Geri açma\n\nBu klasörde Terminal açın. Node.js ile: \`node recover_desktop_backup.mjs /tam/yol/yeni-kurtarma.tar\`. Hedef dosya yeni olmalı; mevcut dosyanın üstüne yazılmaz. macOS Keychain izin sorabilir. Kod önce ciphertext SHA256 ve tam GCM doğrulamasını kontrol eder, sonra tar üretir. Bu işlem DB restore veya tar extraction yapmaz. Üretilen tar kişisel/gizli veri içerir: güvenli izin/konum kullanın.\n\nHelper binary yerine gerekiyorsa kaynak koddan yeniden derleyin: \`swiftc -parse-as-library BackupKeychain.swift -o backup-keychain\`. Anahtar Zinciri'nden gerekli erişim izni istenebilir. Başka bilgisayarda anahtar aktarımı ayrı güvenli bir işlemdir; bu klasör tek başına anahtarsız açılamaz.\n`, { mode: 0o600 });
  console.log(JSON.stringify({ ok: true, backup_directory: target, ...report }, null, 2));
} catch (error) {
  tar?.kill('SIGTERM');
  report = { ...report, status: 'FAILED', error: /^BACKUP_/.test(error.message) ? error.message : 'BACKUP_EXPORT_FAILED' };
  if (target) saveReport();
  console.error(JSON.stringify({ ok: false, backup_directory: target, error: report.error })); process.exitCode = 1;
} finally { key?.fill(0); }
