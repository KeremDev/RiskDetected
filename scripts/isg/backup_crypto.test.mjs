import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomBytes } from 'node:crypto';
import { Readable } from 'node:stream';
import { encryptArchive, verifyArchive } from './backup_crypto.mjs';

test('encrypted backup authenticates round-trip and rejects tampering, wrong key, truncation and overwrite', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'isg-crypto-test-'));
  try {
    const path = join(directory, 'synthetic.enc'), key = randomBytes(32);
    const encoded = await encryptArchive(Readable.from([Buffer.alloc(200_000, 42)]), path, key);
    const verified = await verifyArchive(path, key);
    assert.equal(verified.plaintext_sha256, encoded.plaintext_sha256);
    assert.equal(verified.plaintext_bytes, 200_000);
    await assert.rejects(verifyArchive(path, randomBytes(32)));
    await assert.rejects(encryptArchive(Readable.from(['synthetic']), path, key));
    const original = await readFile(path);
    for (const position of [0, 9, 30, original.length - 1]) {
      const changed = Buffer.from(original); changed[position] ^= 1;
      const mutant = join(directory, `mutant-${position}`); await writeFile(mutant, changed);
      await assert.rejects(verifyArchive(mutant, key));
    }
    const truncated = join(directory, 'truncated'); await writeFile(truncated, original.subarray(0, 20));
    await assert.rejects(verifyArchive(truncated, key));
    await assert.rejects(verifyArchive(path, Buffer.alloc(4)));
  } finally { await rm(directory, { recursive: true }); }
});
