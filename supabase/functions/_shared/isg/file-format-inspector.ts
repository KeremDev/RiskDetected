/**
 * isg_format_inspector — the format safety inspection that clears an upload out
 * of quarantine.
 *
 * WHAT THIS IS: a real inspection of the bytes that actually landed. It decides
 * the true type from the file's own header, re-checks size and hash against the
 * upload intent, and refuses active content — macros, DDE, embedded programs,
 * external references, XML entity declarations, archive bombs and traversal
 * paths.
 *
 * WHAT THIS IS NOT: antivirus. It carries no signature database and no
 * behavioural analysis, so a hostile payload inside an otherwise well-formed
 * document is not something it can see. That is why it registers itself as
 * assurance 'format_inspection' with detects_malware=false, and why the plan's
 * wide-format release gate (§31.6) is not satisfied by this module alone.
 *
 * The module is pure: bytes in, verdict out. It opens no socket and reads no
 * environment, so the same function that runs in the worker runs in the tests.
 */

export type InspectorVerdict = "clean" | "rejected";

export type FindingCode =
  | "SIZE_MISMATCH"
  | "HASH_MISMATCH"
  | "TYPE_MISMATCH"
  | "UNKNOWN_TYPE"
  | "MALFORMED_FILE"
  | "ENCRYPTED_FILE"
  | "MACRO_PRESENT"
  | "ACTIVE_CONTENT"
  | "EMBEDDED_FILE"
  | "EXTERNAL_REFERENCE"
  | "XML_ENTITY"
  | "ARCHIVE_BOMB"
  | "PATH_TRAVERSAL"
  | "IMAGE_TOO_LARGE";

export type InspectionRequest = {
  bytes: Uint8Array;
  /** The extension the intent was opened with, already lowercased by the server. */
  declaredExtension: string;
  declaredBytes: number;
  declaredSha256: string;
  actualSha256: string;
  /** Raw-deflate decompressor; injected so the module stays free of a runtime. */
  inflateRaw?: (input: Uint8Array, limit: number) => Uint8Array;
};

export type InspectionResult = {
  verdict: InspectorVerdict;
  findingCode: FindingCode | null;
  detectedType: string;
  evidence: Record<string, unknown>;
};

export const SCANNER_NAME = "isg_format_inspector";
export const SCANNER_VERSION = "1";

/** Limits. Candidates until the plan's cost and performance gate approves them. */
export const LIMITS = {
  zipEntries: 2000,
  zipTotalUncompressed: 209_715_200,
  zipRatio: 120,
  zipInspectEntry: 4_194_304,
  imagePixels: 80_000_000,
  csvLines: 100_000,
  csvFieldLength: 32_768,
  oleDirectoryEntries: 4096,
};

const text = (bytes: Uint8Array, from: number, length: number) =>
  String.fromCharCode(...bytes.subarray(from, from + length));

const startsWith = (bytes: Uint8Array, signature: number[]) =>
  bytes.length >= signature.length && signature.every((value, index) => bytes[index] === value);

const u16 = (bytes: Uint8Array, at: number) => bytes[at] | (bytes[at + 1] << 8);
const u32 = (bytes: Uint8Array, at: number) =>
  (bytes[at] | (bytes[at + 1] << 8) | (bytes[at + 2] << 16) | (bytes[at + 3] << 24)) >>> 0;

/**
 * The real type, decided by the file's own header. A name and a declared MIME
 * type are both things the caller chose; these bytes are not.
 */
export function detectType(bytes: Uint8Array): string {
  if (startsWith(bytes, [0x25, 0x50, 0x44, 0x46, 0x2d])) return "application/pdf";
  if (startsWith(bytes, [0x50, 0x4b, 0x03, 0x04]) || startsWith(bytes, [0x50, 0x4b, 0x05, 0x06])) {
    return "application/zip";
  }
  if (startsWith(bytes, [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1])) {
    return "application/x-ole-storage";
  }
  if (startsWith(bytes, [0xff, 0xd8, 0xff])) return "image/jpeg";
  if (startsWith(bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return "image/png";
  if (bytes.length >= 12 && text(bytes, 0, 4) === "RIFF" && text(bytes, 8, 4) === "WEBP") {
    return "image/webp";
  }
  if (bytes.length >= 12 && text(bytes, 4, 4) === "ftyp") {
    const brand = text(bytes, 8, 4);
    if (["avif", "avis"].includes(brand)) return "image/avif";
    if (["heic", "heix", "hevc", "heim", "heis", "hevm", "hevs", "mif1", "msf1"].includes(brand)) {
      return "image/heic";
    }
    return "application/octet-stream";
  }
  if (isProbablyText(bytes)) return "text/csv";
  return "application/octet-stream";
}

/** A CSV has no signature, so the question is whether the bytes are text at all. */
function isProbablyText(bytes: Uint8Array): boolean {
  const window = bytes.subarray(0, Math.min(bytes.length, 4096));
  if (window.length === 0) return false;
  for (const byte of window) {
    if (byte === 0) return false;
    if (byte < 0x09) return false;
    if (byte > 0x0d && byte < 0x20) return false;
  }
  return true;
}

/** Which real types an extension is allowed to turn out to be. */
const EXTENSION_TYPES: Record<string, string[]> = {
  pdf: ["application/pdf"],
  doc: ["application/x-ole-storage"],
  xls: ["application/x-ole-storage"],
  docx: ["application/zip"],
  xlsx: ["application/zip"],
  csv: ["text/csv"],
  jpg: ["image/jpeg"],
  jpeg: ["image/jpeg"],
  png: ["image/png"],
  webp: ["image/webp"],
  avif: ["image/avif"],
  heic: ["image/heic"],
  heif: ["image/heic"],
};

/** The content type the asset is stored under once it is cleared. */
const STORED_TYPE: Record<string, string> = {
  pdf: "application/pdf",
  doc: "application/msword",
  xls: "application/vnd.ms-excel",
  docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  csv: "text/csv",
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
  webp: "image/webp",
  avif: "image/avif",
  heic: "image/heic",
  heif: "image/heic",
};

export function storedContentType(extension: string): string {
  return STORED_TYPE[extension] ?? "application/octet-stream";
}

const reject = (
  code: FindingCode,
  detectedType: string,
  evidence: Record<string, unknown> = {},
): InspectionResult => ({ verdict: "rejected", findingCode: code, detectedType, evidence });

export function inspect(request: InspectionRequest): InspectionResult {
  const { bytes, declaredExtension, declaredBytes, declaredSha256, actualSha256 } = request;
  const detected = detectType(bytes);
  const base = { inspector: SCANNER_NAME, version: SCANNER_VERSION, extension: declaredExtension };

  // What landed has to be what was announced, before anything else is believed.
  if (bytes.length !== declaredBytes) {
    return reject("SIZE_MISMATCH", detected, { ...base, bytes: bytes.length, declared: declaredBytes });
  }
  if (actualSha256.toLowerCase() !== declaredSha256.toLowerCase()) {
    return reject("HASH_MISMATCH", detected, { ...base });
  }
  const permitted = EXTENSION_TYPES[declaredExtension];
  if (!permitted) return reject("UNKNOWN_TYPE", detected, { ...base });
  if (!permitted.includes(detected)) {
    return reject("TYPE_MISMATCH", detected, { ...base, detected, permitted });
  }

  switch (detected) {
    case "application/pdf":
      return withType(inspectPdf(bytes, base), detected);
    case "application/zip":
      return withType(inspectOoxml(bytes, base, request.inflateRaw), detected);
    case "application/x-ole-storage":
      return withType(inspectOle(bytes, base), detected);
    case "text/csv":
      return withType(inspectCsv(bytes, base), detected);
    case "image/jpeg":
    case "image/png":
    case "image/webp":
      return withType(inspectRaster(bytes, detected, base), detected);
    default:
      // HEIF and AVIF are stored as the supplied original. No raster derivative
      // is produced here, so no pixel budget was verified; the evidence says so
      // rather than implying the file was measured.
      return {
        verdict: "clean",
        findingCode: null,
        detectedType: detected,
        evidence: { ...base, pixel_budget_checked: false, malware_scanned: false },
      };
  }
}

const withType = (result: InspectionResult, detected: string): InspectionResult => ({
  ...result,
  detectedType: detected,
  evidence: { ...result.evidence, malware_scanned: false },
});

const clean = (evidence: Record<string, unknown>): InspectionResult => ({
  verdict: "clean",
  findingCode: null,
  detectedType: "",
  evidence,
});

// ---------------------------------------------------------------------------
// PDF
// ---------------------------------------------------------------------------

/**
 * Object streams can be compressed, so a hostile action is not always visible
 * in the raw bytes. This refuses what it can see rather than certifying what it
 * cannot, which is exactly why the verdict is not called a malware scan.
 */
const PDF_ACTIVE = [
  "/JavaScript",
  "/JS",
  "/Launch",
  "/RichMedia",
  "/XFA",
  "/AA",
] as const;

function inspectPdf(bytes: Uint8Array, base: Record<string, unknown>): InspectionResult {
  const body = latin1(bytes);
  if (!/^%PDF-\d\.\d/.test(body.slice(0, 16))) {
    return reject("MALFORMED_FILE", "", { ...base });
  }
  // An encrypted document cannot be inspected, so it is not cleared. The plan
  // asks for an unlocked copy instead of assuming the locked one is safe.
  if (body.includes("/Encrypt")) return reject("ENCRYPTED_FILE", "", { ...base });
  if (body.includes("/EmbeddedFile")) return reject("EMBEDDED_FILE", "", { ...base });
  const active = PDF_ACTIVE.find((marker) => body.includes(marker));
  if (active) return reject("ACTIVE_CONTENT", "", { ...base, marker: active });
  return clean({ ...base, pdf_header: body.slice(0, 8), checks: "encryption,embedded,active_content" });
}

function latin1(bytes: Uint8Array): string {
  let out = "";
  const step = 8192;
  for (let at = 0; at < bytes.length; at += step) {
    out += String.fromCharCode(...bytes.subarray(at, Math.min(at + step, bytes.length)));
  }
  return out;
}

// ---------------------------------------------------------------------------
// OOXML (.docx / .xlsx) — a zip package
// ---------------------------------------------------------------------------

type ZipEntry = {
  name: string;
  compressedSize: number;
  uncompressedSize: number;
  method: number;
  localHeaderOffset: number;
  encrypted: boolean;
};

/** Central-directory walk. The local headers are not trusted for sizes. */
export function readZipDirectory(bytes: Uint8Array): ZipEntry[] | null {
  // End of central directory: scan backwards over the permitted comment length.
  let eocd = -1;
  const floor = Math.max(0, bytes.length - 65_557);
  for (let at = bytes.length - 22; at >= floor; at--) {
    if (u32(bytes, at) === 0x06054b50) { eocd = at; break; }
  }
  if (eocd < 0) return null;
  const count = u16(bytes, eocd + 10);
  let at = u32(bytes, eocd + 16);
  const entries: ZipEntry[] = [];
  for (let index = 0; index < count; index++) {
    if (at + 46 > bytes.length || u32(bytes, at) !== 0x02014b50) return null;
    const nameLength = u16(bytes, at + 28);
    const extraLength = u16(bytes, at + 30);
    const commentLength = u16(bytes, at + 32);
    entries.push({
      name: text(bytes, at + 46, nameLength),
      method: u16(bytes, at + 10),
      compressedSize: u32(bytes, at + 20),
      uncompressedSize: u32(bytes, at + 24),
      localHeaderOffset: u32(bytes, at + 42),
      encrypted: (u16(bytes, at + 8) & 0x0001) === 1,
    });
    at += 46 + nameLength + extraLength + commentLength;
    if (entries.length > LIMITS.zipEntries) break;
  }
  return entries;
}

const MACRO_ENTRIES = ["vbaproject.bin", "vbadata.xml", "macros"];
const INSPECT_XML = [
  "[content_types].xml",
  "_rels/.rels",
  "word/_rels/document.xml.rels",
  "xl/_rels/workbook.xml.rels",
  "word/document.xml",
];

function inspectOoxml(
  bytes: Uint8Array,
  base: Record<string, unknown>,
  inflateRaw?: (input: Uint8Array, limit: number) => Uint8Array,
): InspectionResult {
  const entries = readZipDirectory(bytes);
  if (!entries || entries.length === 0) return reject("MALFORMED_FILE", "", { ...base });
  if (entries.length > LIMITS.zipEntries) {
    return reject("ARCHIVE_BOMB", "", { ...base, entries: entries.length });
  }
  let total = 0;
  for (const entry of entries) {
    const lower = entry.name.toLowerCase();
    if (entry.encrypted) return reject("ENCRYPTED_FILE", "", { ...base, entry: entry.name });
    if (entry.name.includes("..") || entry.name.startsWith("/") || entry.name.includes("\\")) {
      return reject("PATH_TRAVERSAL", "", { ...base, entry: entry.name });
    }
    if (MACRO_ENTRIES.some((marker) => lower.endsWith(marker) || lower.includes("/" + marker))) {
      return reject("MACRO_PRESENT", "", { ...base, entry: entry.name });
    }
    total += entry.uncompressedSize;
    if (entry.compressedSize > 0 && entry.uncompressedSize / entry.compressedSize > LIMITS.zipRatio) {
      return reject("ARCHIVE_BOMB", "", {
        ...base,
        entry: entry.name,
        ratio: Math.round(entry.uncompressedSize / entry.compressedSize),
      });
    }
  }
  if (total > LIMITS.zipTotalUncompressed) {
    return reject("ARCHIVE_BOMB", "", { ...base, uncompressed: total });
  }

  // The declared part types decide whether this is a macro-enabled package,
  // whatever the extension says.
  let inspected = 0;
  if (inflateRaw) {
    for (const entry of entries) {
      const lower = entry.name.toLowerCase();
      if (!INSPECT_XML.includes(lower)) continue;
      if (entry.uncompressedSize > LIMITS.zipInspectEntry) {
        return reject("ARCHIVE_BOMB", "", { ...base, entry: entry.name });
      }
      const content = readEntry(bytes, entry, inflateRaw);
      if (content === null) return reject("MALFORMED_FILE", "", { ...base, entry: entry.name });
      inspected++;
      const failure = inspectPackageXml(lower, content);
      if (failure) return reject(failure.code, "", { ...base, entry: entry.name, marker: failure.marker });
    }
  }
  return clean({ ...base, entries: entries.length, uncompressed: total, xml_parts_inspected: inspected });
}

function readEntry(
  bytes: Uint8Array,
  entry: ZipEntry,
  inflateRaw: (input: Uint8Array, limit: number) => Uint8Array,
): string | null {
  const at = entry.localHeaderOffset;
  if (at + 30 > bytes.length || u32(bytes, at) !== 0x04034b50) return null;
  const start = at + 30 + u16(bytes, at + 26) + u16(bytes, at + 28);
  const body = bytes.subarray(start, start + entry.compressedSize);
  try {
    const raw = entry.method === 0 ? body : inflateRaw(body, LIMITS.zipInspectEntry);
    return new TextDecoder("utf-8", { fatal: false }).decode(raw);
  } catch {
    return null;
  }
}

function inspectPackageXml(
  name: string,
  content: string,
): { code: FindingCode; marker: string } | null {
  // An entity declaration is how an XML parser is talked into reading something
  // it was never given.
  if (/<!ENTITY/i.test(content) || /<!DOCTYPE/i.test(content)) {
    return { code: "XML_ENTITY", marker: "doctype_or_entity" };
  }
  if (name === "[content_types].xml" && /macroenabled/i.test(content)) {
    return { code: "MACRO_PRESENT", marker: "macroEnabled_content_type" };
  }
  if (name.endsWith(".rels")) {
    if (/TargetMode\s*=\s*"External"/i.test(content)) {
      return { code: "EXTERNAL_REFERENCE", marker: "external_relationship" };
    }
    if (/relationships\/(vbaProject|oleObject|package)/i.test(content)) {
      return { code: "EMBEDDED_FILE", marker: "embedded_relationship" };
    }
  }
  if (name === "word/document.xml" && /\bDDEAUTO\b|\bDDE\b/.test(content)) {
    return { code: "ACTIVE_CONTENT", marker: "dde_field" };
  }
  return null;
}

// ---------------------------------------------------------------------------
// OLE compound files (.doc / .xls)
// ---------------------------------------------------------------------------

const OLE_REFUSED: Array<{ name: string; code: FindingCode }> = [
  { name: "_vba_project", code: "MACRO_PRESENT" },
  { name: "vba", code: "MACRO_PRESENT" },
  { name: "macros", code: "MACRO_PRESENT" },
  { name: "_vba_project_cur", code: "MACRO_PRESENT" },
  { name: "encryptedpackage", code: "ENCRYPTED_FILE" },
  { name: "encryptioninfo", code: "ENCRYPTED_FILE" },
  { name: "objectpool", code: "EMBEDDED_FILE" },
  { name: "ole10native", code: "EMBEDDED_FILE" },
];

/**
 * A macro-free DOC or XLS is a positive fixture, not something to refuse for
 * being an old format. The directory is walked to find out which it is.
 */
export function readOleDirectoryNames(bytes: Uint8Array): string[] | null {
  if (bytes.length < 512) return null;
  const sectorShift = u16(bytes, 30);
  if (sectorShift < 7 || sectorShift > 12) return null;
  const sectorSize = 1 << sectorShift;
  const sectorAt = (sector: number) => 512 + sector * sectorSize;

  // The first 109 FAT sector numbers live in the header; deeper chains need the
  // DIFAT, which a document of the sizes this product accepts does not reach.
  const fat: number[] = [];
  for (let index = 0; index < 109; index++) {
    const sector = u32(bytes, 76 + index * 4);
    if (sector === 0xffffffff) break;
    const at = sectorAt(sector);
    if (at + sectorSize > bytes.length) return null;
    for (let entry = 0; entry < sectorSize / 4; entry++) fat.push(u32(bytes, at + entry * 4));
  }
  if (fat.length === 0) return null;

  const names: string[] = [];
  let sector = u32(bytes, 48);
  const seen = new Set<number>();
  while (sector !== 0xfffffffe && sector !== 0xffffffff && names.length < LIMITS.oleDirectoryEntries) {
    if (seen.has(sector) || sector >= fat.length) return null;
    seen.add(sector);
    const at = sectorAt(sector);
    if (at + sectorSize > bytes.length) return null;
    for (let entry = 0; entry + 128 <= sectorSize; entry += 128) {
      const nameLength = u16(bytes, at + entry + 64);
      if (nameLength < 2 || nameLength > 64) continue;
      let name = "";
      for (let index = 0; index + 1 < nameLength - 1; index += 2) {
        name += String.fromCharCode(u16(bytes, at + entry + index));
      }
      if (name) names.push(name);
    }
    sector = fat[sector];
  }
  return names;
}

function inspectOle(bytes: Uint8Array, base: Record<string, unknown>): InspectionResult {
  const names = readOleDirectoryNames(bytes);
  if (!names) return reject("MALFORMED_FILE", "", { ...base });
  for (const name of names) {
    const lower = name.toLowerCase();
    const refused = OLE_REFUSED.find((candidate) => lower === candidate.name);
    if (refused) return reject(refused.code, "", { ...base, stream: name });
  }
  return clean({ ...base, ole_streams: names.length, checks: "vba,encryption,embedded_objects" });
}

// ---------------------------------------------------------------------------
// CSV and rasters
// ---------------------------------------------------------------------------

function inspectCsv(bytes: Uint8Array, base: Record<string, unknown>): InspectionResult {
  const body = latin1(bytes);
  const lines = body.split(/\r\n|\n|\r/);
  if (lines.length > LIMITS.csvLines) {
    return reject("ARCHIVE_BOMB", "", { ...base, lines: lines.length });
  }
  const longest = lines.reduce((max, line) => Math.max(max, line.length), 0);
  if (longest > LIMITS.csvFieldLength) {
    return reject("MALFORMED_FILE", "", { ...base, longest_line: longest });
  }
  // No formula is evaluated anywhere: the file is stored, and the structured
  // import path is a separate capability with its own checks.
  return clean({ ...base, lines: lines.length, formulas_evaluated: false });
}

/** Header-only dimensions. The server never decodes the image. */
export function rasterPixels(bytes: Uint8Array, type: string): number | null {
  if (type === "image/png") {
    if (bytes.length < 24 || text(bytes, 12, 4) !== "IHDR") return null;
    const width = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
    const height = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
    return width > 0 && height > 0 ? width * height : null;
  }
  if (type === "image/jpeg") {
    let at = 2;
    while (at + 9 < bytes.length) {
      if (bytes[at] !== 0xff) return null;
      const marker = bytes[at + 1];
      const length = (bytes[at + 2] << 8) | bytes[at + 3];
      const isFrame = marker >= 0xc0 && marker <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(marker);
      if (isFrame) {
        const height = (bytes[at + 5] << 8) | bytes[at + 6];
        const width = (bytes[at + 7] << 8) | bytes[at + 8];
        return width > 0 && height > 0 ? width * height : null;
      }
      if (length < 2) return null;
      at += 2 + length;
    }
    return null;
  }
  if (type === "image/webp") {
    if (bytes.length < 30) return null;
    const chunk = text(bytes, 12, 4);
    if (chunk === "VP8X") {
      const width = 1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16));
      const height = 1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16));
      return width * height;
    }
    if (chunk === "VP8 ") {
      const width = u16(bytes, 26) & 0x3fff;
      const height = u16(bytes, 28) & 0x3fff;
      return width > 0 && height > 0 ? width * height : null;
    }
    return null;
  }
  return null;
}

function inspectRaster(
  bytes: Uint8Array,
  type: string,
  base: Record<string, unknown>,
): InspectionResult {
  const pixels = rasterPixels(bytes, type);
  if (pixels === null) {
    // A header this inspector cannot read is a malformed image, not a cleared
    // one: an unreadable header is exactly what a decode bomb looks like.
    return reject("MALFORMED_FILE", "", { ...base });
  }
  if (pixels > LIMITS.imagePixels) {
    return reject("IMAGE_TOO_LARGE", "", { ...base, pixels });
  }
  return clean({ ...base, pixels, pixel_budget_checked: true });
}
