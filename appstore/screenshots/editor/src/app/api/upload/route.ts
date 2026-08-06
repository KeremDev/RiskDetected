import { createHash } from "node:crypto";
import { promises as fs } from "node:fs";
import path from "node:path";
import { NextResponse } from "next/server";
import { validateLocalJsonMutation } from "@/lib/local-api-security";

export const dynamic = "force-dynamic";

const UPLOAD_DIR_REL = path.join("public", "screenshots", "uploaded");
const PUBLIC_PREFIX = "/screenshots/uploaded";
const MAX_IMAGE_BYTES = 8 * 1024 * 1024;
const MAX_UPLOAD_FILES = 64;
const MAX_UPLOAD_DIRECTORY_BYTES = 128 * 1024 * 1024;

const MIME_EXT: Record<string, string> = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/jpg": "jpg",
};

function parseDataUrl(dataUrl: string): { mime: string; bytes: Buffer } | null {
  const m = /^data:([^;]+);base64,(.+)$/.exec(dataUrl);
  if (!m) return null;
  const mime = m[1].toLowerCase();
  const bytes = Buffer.from(m[2], "base64");
  return { mime, bytes };
}

export async function POST(req: Request) {
  const rejection = validateLocalJsonMutation(req);
  if (rejection) return rejection;

  let body: { dataUrl?: string };
  try {
    body = (await req.json()) as { dataUrl?: string };
  } catch {
    return NextResponse.json({ ok: false, error: "Invalid JSON" }, { status: 400 });
  }
  if (!body?.dataUrl || typeof body.dataUrl !== "string") {
    return NextResponse.json({ ok: false, error: "Missing dataUrl" }, { status: 400 });
  }
  const parsed = parseDataUrl(body.dataUrl);
  if (!parsed) {
    return NextResponse.json({ ok: false, error: "Unsupported data URL" }, { status: 400 });
  }
  const ext = MIME_EXT[parsed.mime];
  if (!ext) {
    return NextResponse.json(
      { ok: false, error: `Unsupported mime: ${parsed.mime}` },
      { status: 400 },
    );
  }
  if (parsed.bytes.byteLength > MAX_IMAGE_BYTES) {
    return NextResponse.json({ ok: false, error: "Image too large (>8MB)" }, { status: 413 });
  }

  const hash = createHash("sha256").update(parsed.bytes).digest("hex").slice(0, 24);
  const filename = `${hash}.${ext}`;
  const absDir = path.join(process.cwd(), UPLOAD_DIR_REL);
  const absFile = path.join(absDir, filename);

  try {
    await fs.mkdir(absDir, { recursive: true });
    const entries = await fs.readdir(absDir, { withFileTypes: true });
    const files = entries.filter((entry) => entry.isFile());
    let directoryBytes = 0;
    for (const file of files) {
      directoryBytes += (await fs.stat(path.join(absDir, file.name))).size;
    }

    const alreadyExists = files.some((file) => file.name === filename);
    if (!alreadyExists && files.length >= MAX_UPLOAD_FILES) {
      return NextResponse.json(
        { ok: false, error: "Upload directory file limit reached" },
        { status: 507 },
      );
    }
    if (
      !alreadyExists &&
      directoryBytes + parsed.bytes.byteLength > MAX_UPLOAD_DIRECTORY_BYTES
    ) {
      return NextResponse.json(
        { ok: false, error: "Upload directory byte limit reached" },
        { status: 507 },
      );
    }

    try {
      await fs.access(absFile);
    } catch {
      await fs.writeFile(absFile, parsed.bytes);
    }
    return NextResponse.json({ ok: true, path: `${PUBLIC_PREFIX}/${filename}` });
  } catch (e) {
    return NextResponse.json(
      { ok: false, error: e instanceof Error ? e.message : String(e) },
      { status: 500 },
    );
  }
}
