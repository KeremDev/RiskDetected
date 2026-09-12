import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';
import { createReadStream, createWriteStream } from 'node:fs';
import { open, appendFile, stat } from 'node:fs/promises';
import { Transform, Writable } from 'node:stream';
import { pipeline } from 'node:stream/promises';

// Format ISGBK001: 8-byte ASCII magic, 12-byte nonce, ciphertext, 16-byte GCM tag.
// The complete 20-byte header is authenticated as AAD. No plaintext archive on disk.
const magic = Buffer.from('ISGBK001');
function hashStream(hash) { return new Transform({ transform(chunk, _, done) { hash.update(chunk); done(null, chunk); } }); }
export async function encryptArchive(input, target, key) {
  if (!Buffer.isBuffer(key) || key.length !== 32) throw new Error('BACKUP_KEY_INVALID');
  const nonce = randomBytes(12), header = Buffer.concat([magic, nonce]);
  const cipher = createCipheriv('aes-256-gcm', key, nonce); cipher.setAAD(header);
  const output = createWriteStream(target, { flags: 'wx', mode: 0o600 });
  output.write(header);
  const hash = createHash('sha256');
  await pipeline(input, hashStream(hash), cipher, output);
  await appendFile(target, cipher.getAuthTag());
  return { plaintext_sha256: hash.digest('hex') };
}
export async function verifyArchive(target, key) {
  if (!Buffer.isBuffer(key) || key.length !== 32) throw new Error('BACKUP_KEY_INVALID');
  const size = (await stat(target)).size;
  if (size < 36) throw new Error('BACKUP_FORMAT_INVALID');
  const file = await open(target, 'r');
  const header = Buffer.alloc(20), tag = Buffer.alloc(16);
  try { await file.read(header, 0, 20, 0); await file.read(tag, 0, 16, size - 16); } finally { await file.close(); }
  if (!header.subarray(0, 8).equals(magic)) throw new Error('BACKUP_FORMAT_INVALID');
  const decipher = createDecipheriv('aes-256-gcm', key, header.subarray(8));
  decipher.setAAD(header); decipher.setAuthTag(tag);
  const hash = createHash('sha256'); let bytes = 0;
  const sink = new Writable({ write(chunk, _, done) { bytes += chunk.length; hash.update(chunk); done(); } });
  await pipeline(createReadStream(target, { start: 20, end: size - 17 }), decipher, sink);
  return { plaintext_sha256: hash.digest('hex'), plaintext_bytes: bytes, authenticated: true };
}
export async function hashFile(target) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(target)) hash.update(chunk);
  return hash.digest('hex');
}
