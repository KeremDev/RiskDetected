#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { createDecipheriv } from 'node:crypto';
import { createReadStream, createWriteStream, readFileSync } from 'node:fs';
import { open, stat } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pipeline } from 'node:stream/promises';
import { verifyArchive, hashFile } from './backup_crypto.mjs';

// Run from the exported backup folder. No automatic extraction or database writes.
let key;
try {
  if (process.argv.length !== 3) throw new Error('RECOVERY_NEW_TAR_PATH_REQUIRED');
  const folder = import.meta.dirname, manifest = JSON.parse(readFileSync(resolve(folder, 'MANIFEST.json'), 'utf8'));
  if (manifest.status !== 'VERIFIED' || manifest.archive !== 'riskdetected-checkpoint.isgbk' || !/^riskdetected_backup_20260912_[a-f0-9]{32}$/.test(manifest.key_service)) throw new Error('RECOVERY_MANIFEST_INVALID');
  const archive = resolve(folder, manifest.archive);
  if (await hashFile(archive) !== manifest.encrypted_sha256) throw new Error('RECOVERY_CIPHERTEXT_HASH_MISMATCH');
  const result = spawnSync(resolve(folder, 'backup-keychain'), ['get', manifest.key_service], { encoding: 'utf8', timeout: 30_000 });
  if (result.status !== 0) throw new Error('RECOVERY_KEYCHAIN_UNAVAILABLE');
  key = Buffer.from(result.stdout, 'base64');
  const verified = await verifyArchive(archive, key);
  if (verified.plaintext_sha256 !== manifest.plaintext_sha256) throw new Error('RECOVERY_PLAINTEXT_HASH_MISMATCH');
  const size = (await stat(archive)).size, handle = await open(archive, 'r');
  const header = Buffer.alloc(20), tag = Buffer.alloc(16);
  try { await handle.read(header, 0, 20, 0); await handle.read(tag, 0, 16, size - 16); } finally { await handle.close(); }
  const decipher = createDecipheriv('aes-256-gcm', key, header.subarray(8)); decipher.setAAD(header); decipher.setAuthTag(tag);
  await pipeline(createReadStream(archive, { start: 20, end: size - 17 }), decipher,
    createWriteStream(resolve(process.argv[2]), { flags: 'wx', mode: 0o600 }));
  console.log('RECOVERY_TAR_VERIFIED: archive created; no extraction or database operation performed.');
} catch (error) {
  console.error(/^RECOVERY_/.test(error.message) ? error.message : 'RECOVERY_FAILED: target must be new and key/archive valid. Any incomplete output is not a verified restore.');
  process.exitCode = 1;
} finally { key?.fill(0); }
