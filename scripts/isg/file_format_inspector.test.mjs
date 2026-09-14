import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {deflateRawSync, inflateRawSync} from 'node:zlib';
import {inspect, detectType, readZipDirectory, readOleDirectoryNames, rasterPixels, LIMITS, SCANNER_NAME}
  from '../../supabase/functions/_shared/isg/file-format-inspector.ts';

const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const inflateRaw = (input, limit) => {
  const out = inflateRawSync(Buffer.from(input), {maxOutputLength: limit});
  return new Uint8Array(out);
};
const run = (bytes, extension, overrides = {}) => inspect({
  bytes, declaredExtension: extension, declaredBytes: bytes.length,
  declaredSha256: sha(bytes), actualSha256: sha(bytes), inflateRaw, ...overrides});

// ---------------------------------------------------------------------------
// Fixture builders. Real container bytes, hand-assembled, so a verdict is about
// the format and not about a library's opinion of it.
// ---------------------------------------------------------------------------

const ascii = value => new Uint8Array(Buffer.from(value, 'latin1'));

function pdf(body = '') {
  return ascii('%PDF-1.7\n1 0 obj<</Type/Catalog>>endobj\n' + body + '\n%%EOF\n');
}

/** A minimal but genuine zip: local headers plus a central directory. */
function zip(files, {encrypted = false, fakeUncompressed = null} = {}) {
  const locals = [], central = [];
  let offset = 0;
  for (const [name, content] of files) {
    const raw = typeof content === 'string' ? Buffer.from(content, 'utf8') : Buffer.from(content);
    const deflated = deflateRawSync(raw);
    const nameBytes = Buffer.from(name, 'utf8');
    const flags = encrypted ? 1 : 0;
    const uncompressed = fakeUncompressed ?? raw.length;
    const local = Buffer.alloc(30 + nameBytes.length);
    local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(20, 4); local.writeUInt16LE(flags, 6);
    local.writeUInt16LE(8, 8); local.writeUInt32LE(0, 14);
    local.writeUInt32LE(deflated.length, 18); local.writeUInt32LE(uncompressed, 22);
    local.writeUInt16LE(nameBytes.length, 26); local.writeUInt16LE(0, 28);
    nameBytes.copy(local, 30);
    locals.push(local, deflated);

    const entry = Buffer.alloc(46 + nameBytes.length);
    entry.writeUInt32LE(0x02014b50, 0); entry.writeUInt16LE(20, 4); entry.writeUInt16LE(20, 6);
    entry.writeUInt16LE(flags, 8); entry.writeUInt16LE(8, 10);
    entry.writeUInt32LE(deflated.length, 20); entry.writeUInt32LE(uncompressed, 24);
    entry.writeUInt16LE(nameBytes.length, 28); entry.writeUInt32LE(offset, 42);
    nameBytes.copy(entry, 46);
    central.push(entry);
    offset += local.length + deflated.length;
  }
  const directory = Buffer.concat(central);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(files.length, 8); eocd.writeUInt16LE(files.length, 10);
  eocd.writeUInt32LE(directory.length, 12); eocd.writeUInt32LE(offset, 16);
  return new Uint8Array(Buffer.concat([...locals, directory, eocd]));
}

const CONTENT_TYPES = '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
  '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>';
const MACRO_CONTENT_TYPES = CONTENT_TYPES.replace('document.main+xml',
  'document.macroEnabled.main+xml');
const RELS = '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
  '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>';
const EXTERNAL_RELS = '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
  '<Relationship Id="rId9" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/attachedTemplate" Target="http://example.invalid/t.dotm" TargetMode="External"/></Relationships>';
const DOCUMENT = '<?xml version="1.0"?><w:document xmlns:w="x"><w:body><w:p><w:r><w:t>Risk</w:t></w:r></w:p></w:body></w:document>';

const docx = (overrides = {}) => zip([
  ['[Content_Types].xml', overrides.contentTypes ?? CONTENT_TYPES],
  ['_rels/.rels', overrides.rels ?? RELS],
  ['word/document.xml', overrides.document ?? DOCUMENT],
  ...(overrides.extra ?? []),
]);

/** A compound file with one FAT sector, one directory sector and named streams. */
function ole(streamNames) {
  const sectorSize = 512, sectors = 4;
  const buffer = Buffer.alloc(512 + sectorSize * sectors);
  Buffer.from([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]).copy(buffer, 0);
  buffer.writeUInt16LE(9, 30);               // sector shift -> 512 bytes
  buffer.writeUInt32LE(0, 48);               // directory starts at sector 0
  buffer.writeUInt32LE(1, 76);               // the single FAT sector is sector 1
  for (let index = 80; index < 76 + 109 * 4; index += 4) buffer.writeUInt32LE(0xffffffff, index);
  const fatAt = 512 + 1 * sectorSize;
  for (let entry = 0; entry < sectorSize / 4; entry++) {
    buffer.writeUInt32LE(0xfffffffe, fatAt + entry * 4);   // every sector ends its chain
  }
  const directoryAt = 512;
  streamNames.forEach((name, index) => {
    const at = directoryAt + index * 128;
    for (let character = 0; character < name.length; character++) {
      buffer.writeUInt16LE(name.charCodeAt(character), at + character * 2);
    }
    buffer.writeUInt16LE((name.length + 1) * 2, at + 64);
  });
  return new Uint8Array(buffer);
}

function png(width, height) {
  const buffer = Buffer.alloc(33);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(buffer, 0);
  buffer.writeUInt32BE(13, 8); buffer.write('IHDR', 12, 'latin1');
  buffer.writeUInt32BE(width, 16); buffer.writeUInt32BE(height, 20);
  return new Uint8Array(buffer);
}

function jpeg(width, height) {
  const buffer = Buffer.alloc(20);
  Buffer.from([0xff, 0xd8, 0xff]).copy(buffer, 0);
  buffer[2] = 0xff; buffer[3] = 0xc0;         // SOF0 right after SOI
  buffer.writeUInt16BE(11, 4);
  buffer[6] = 8;
  buffer.writeUInt16BE(height, 7); buffer.writeUInt16BE(width, 9);
  return new Uint8Array(buffer.subarray(0, 20));
}

// ---------------------------------------------------------------------------
// The bytes that landed decide, not what the caller announced
// ---------------------------------------------------------------------------

test('the real type comes from the header, not the extension', () => {
  assert.equal(detectType(pdf()), 'application/pdf');
  assert.equal(detectType(docx()), 'application/zip');
  assert.equal(detectType(ole(['WordDocument'])), 'application/x-ole-storage');
  assert.equal(detectType(png(4, 4)), 'image/png');
  assert.equal(detectType(jpeg(4, 4)), 'image/jpeg');
  assert.equal(detectType(ascii('ad;soyad\nAli;Veli\n')), 'text/csv');
  assert.equal(detectType(new Uint8Array([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])), 'application/octet-stream');
});

test('a renamed package is refused rather than filed under its new name', () => {
  const result = run(docx(), 'pdf');
  assert.equal(result.verdict, 'rejected');
  assert.equal(result.findingCode, 'TYPE_MISMATCH');
  assert.equal(result.detectedType, 'application/zip');
});

test('an extension the product never accepts is refused before anything is parsed', () => {
  assert.equal(run(pdf(), 'exe').findingCode, 'UNKNOWN_TYPE');
});

test('size and hash are re-checked against the intent', () => {
  const bytes = pdf();
  assert.equal(run(bytes, 'pdf', {declaredBytes: bytes.length + 1}).findingCode, 'SIZE_MISMATCH');
  assert.equal(run(bytes, 'pdf', {declaredSha256: 'a'.repeat(64)}).findingCode, 'HASH_MISMATCH');
});

// ---------------------------------------------------------------------------
// PDF
// ---------------------------------------------------------------------------

test('an ordinary PDF is cleared and says what was checked', () => {
  const result = run(pdf(), 'pdf');
  assert.equal(result.verdict, 'clean');
  assert.equal(result.findingCode, null);
  assert.equal(result.evidence.inspector, SCANNER_NAME);
  // The cleared file never carries a claim that it was scanned for malware.
  assert.equal(result.evidence.malware_scanned, false);
});

test('an encrypted PDF is not cleared, because it cannot be inspected', () => {
  assert.equal(run(pdf('trailer<</Encrypt 9 0 R>>'), 'pdf').findingCode, 'ENCRYPTED_FILE');
});

for (const [marker, code] of [['/JavaScript', 'ACTIVE_CONTENT'], ['/Launch', 'ACTIVE_CONTENT'],
  ['/RichMedia', 'ACTIVE_CONTENT'], ['/XFA', 'ACTIVE_CONTENT'], ['/EmbeddedFile', 'EMBEDDED_FILE']]) {
  test(`a PDF carrying ${marker} is refused`, () => {
    assert.equal(run(pdf(`2 0 obj<<${marker} 3 0 R>>endobj`), 'pdf').findingCode, code);
  });
}

test('a file that only claims to be a PDF is refused', () => {
  // The magic bytes are there, so the version line is what gives it away.
  assert.equal(run(ascii('%PDF-nope\nhello'), 'pdf').findingCode, 'MALFORMED_FILE');
});

// ---------------------------------------------------------------------------
// OOXML
// ---------------------------------------------------------------------------

test('a plain docx is cleared and its declared parts are read', () => {
  const result = run(docx(), 'docx');
  assert.equal(result.verdict, 'clean');
  assert.equal(result.evidence.entries, 3);
  assert.equal(result.evidence.xml_parts_inspected, 3);
});

test('a macro part is refused even when the package is named .docx', () => {
  const result = run(docx({extra: [['word/vbaProject.bin', 'MZ binary']]}), 'docx');
  assert.equal(result.findingCode, 'MACRO_PRESENT');
});

test('a macro-enabled content type is refused even with no macro part present', () => {
  assert.equal(run(docx({contentTypes: MACRO_CONTENT_TYPES}), 'docx').findingCode, 'MACRO_PRESENT');
});

test('an external relationship is refused', () => {
  assert.equal(run(docx({rels: EXTERNAL_RELS}), 'docx').findingCode, 'EXTERNAL_REFERENCE');
});

test('an entity declaration is refused', () => {
  const rels = '<?xml version="1.0"?><!DOCTYPE r [<!ENTITY x SYSTEM "file:///etc/passwd">]><Relationships/>';
  assert.equal(run(docx({rels}), 'docx').findingCode, 'XML_ENTITY');
});

test('a DDE field is refused', () => {
  const document = '<?xml version="1.0"?><w:document xmlns:w="x"><w:instrText>DDEAUTO c:\\\\windows</w:instrText></w:document>';
  assert.equal(run(docx({document}), 'docx').findingCode, 'ACTIVE_CONTENT');
});

test('a traversal path inside the package is refused', () => {
  assert.equal(run(docx({extra: [['../../etc/passwd', 'x']]}), 'docx').findingCode, 'PATH_TRAVERSAL');
});

test('an encrypted zip entry is refused', () => {
  assert.equal(run(zip([['a.xml', 'x']], {encrypted: true}), 'docx').findingCode, 'ENCRYPTED_FILE');
});

test('a compression ratio far past the limit is refused', () => {
  const bytes = zip([['big.xml', 'a'.repeat(64)]], {fakeUncompressed: 64 * LIMITS.zipRatio * 10});
  assert.equal(run(bytes, 'xlsx').findingCode, 'ARCHIVE_BOMB');
});

test('a package with no directory at all is refused', () => {
  assert.equal(run(new Uint8Array([0x50, 0x4b, 0x03, 0x04, 0, 0, 0, 0]), 'docx').findingCode, 'MALFORMED_FILE');
});

test('the directory walk reports the entries it really found', () => {
  const entries = readZipDirectory(docx());
  assert.equal(entries.length, 3);
  assert.deepEqual(entries.map(entry => entry.name),
    ['[Content_Types].xml', '_rels/.rels', 'word/document.xml']);
});

// ---------------------------------------------------------------------------
// OLE
// ---------------------------------------------------------------------------

test('a macro-free DOC is a positive fixture, not a refusal', () => {
  const result = run(ole(['Root Entry', 'WordDocument', '1Table']), 'doc');
  assert.equal(result.verdict, 'clean');
  assert.equal(result.evidence.ole_streams, 3);
});

test('a VBA stream in an old DOC is refused', () => {
  assert.equal(run(ole(['Root Entry', 'WordDocument', '_VBA_PROJECT']), 'doc').findingCode, 'MACRO_PRESENT');
});

test('an encrypted OOXML wrapped in a compound file is refused', () => {
  assert.equal(run(ole(['Root Entry', 'EncryptedPackage']), 'xls').findingCode, 'ENCRYPTED_FILE');
});

test('an embedded object pool is refused', () => {
  assert.equal(run(ole(['Root Entry', 'ObjectPool']), 'xls').findingCode, 'EMBEDDED_FILE');
});

test('the compound directory walk reads the stream names it was given', () => {
  assert.deepEqual(readOleDirectoryNames(ole(['Root Entry', 'Workbook'])), ['Root Entry', 'Workbook']);
  assert.equal(readOleDirectoryNames(new Uint8Array(16)), null);
});

// ---------------------------------------------------------------------------
// Images and CSV
// ---------------------------------------------------------------------------

test('image dimensions are read from the header without decoding', () => {
  assert.equal(rasterPixels(png(1200, 800), 'image/png'), 960_000);
  assert.equal(rasterPixels(jpeg(640, 480), 'image/jpeg'), 307_200);
});

test('an ordinary photo is cleared with the pixel budget recorded as checked', () => {
  const result = run(jpeg(4032, 3024), 'jpg');
  assert.equal(result.verdict, 'clean');
  assert.equal(result.evidence.pixels, 4032 * 3024);
  assert.equal(result.evidence.pixel_budget_checked, true);
});

test('a header declaring more pixels than the budget is refused', () => {
  assert.equal(run(png(60_000, 60_000), 'png').findingCode, 'IMAGE_TOO_LARGE');
});

test('an image whose header cannot be read is refused rather than cleared', () => {
  const broken = new Uint8Array(png(10, 10));
  broken[12] = 0x58;                                   // IHDR -> XHDR
  assert.equal(run(broken, 'png').findingCode, 'MALFORMED_FILE');
});

test('HEIC is stored without claiming a pixel budget was verified', () => {
  const buffer = Buffer.alloc(32);
  buffer.write('ftyp', 4, 'latin1'); buffer.write('heic', 8, 'latin1');
  const result = run(new Uint8Array(buffer), 'heic');
  assert.equal(result.verdict, 'clean');
  assert.equal(result.evidence.pixel_budget_checked, false);
});

test('a CSV is stored and no formula is evaluated', () => {
  const result = run(ascii('ad;soyad\n=cmd|calc;Veli\n'), 'csv');
  assert.equal(result.verdict, 'clean');
  assert.equal(result.evidence.formulas_evaluated, false);
});

test('a CSV past the line budget is refused', () => {
  assert.equal(run(ascii('a\n'.repeat(LIMITS.csvLines + 10)), 'csv').findingCode, 'ARCHIVE_BOMB');
});

// ---------------------------------------------------------------------------
// The honesty invariant
// ---------------------------------------------------------------------------

test('no cleared verdict ever claims a malware scan', () => {
  for (const [bytes, extension] of [[pdf(), 'pdf'], [docx(), 'docx'],
    [ole(['Root Entry', 'WordDocument']), 'doc'], [png(20, 20), 'png'], [ascii('a;b\n'), 'csv']]) {
    const result = run(bytes, extension);
    assert.equal(result.verdict, 'clean', extension);
    assert.equal(result.evidence.malware_scanned, false, extension);
  }
});

test('every finding code matches the shape the database accepts', () => {
  const codes = [run(docx(), 'pdf'), run(pdf('/JS'), 'pdf'), run(pdf('/Encrypt'), 'pdf'),
    run(png(60_000, 60_000), 'png'), run(ole(['Root Entry', 'Macros']), 'doc')]
    .map(result => result.findingCode);
  assert.equal(codes.length, 5);
  for (const code of codes) assert.match(code, /^[A-Z][A-Z_]{2,39}$/);
});
