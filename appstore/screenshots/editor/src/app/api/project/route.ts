import { randomUUID } from "node:crypto";
import { promises as fs } from "node:fs";
import path from "node:path";
import { NextResponse } from "next/server";
import {
  validateLocalJsonMutation,
  validateScreenshotProjectState,
} from "@/lib/local-api-security";

export const dynamic = "force-dynamic";

const PROJECT_FILE = "app-store-screenshots.json";

function filePath() {
  return path.join(process.cwd(), PROJECT_FILE);
}

async function atomicWriteProjectFile(contents: string) {
  const target = filePath();
  const temporary = `${target}.${process.pid}.${randomUUID()}.tmp`;
  try {
    await fs.writeFile(temporary, contents, {
      encoding: "utf8",
      flag: "wx",
      mode: 0o600,
    });
    await fs.rename(temporary, target);
  } finally {
    await fs.rm(temporary, { force: true }).catch(() => undefined);
  }
}

export async function GET() {
  try {
    const raw = await fs.readFile(filePath(), "utf8");
    const parsed = JSON.parse(raw);
    return NextResponse.json({ ok: true, state: parsed });
  } catch (e) {
    const code = (e as NodeJS.ErrnoException).code;
    if (code === "ENOENT") {
      return NextResponse.json({ ok: true, state: null });
    }
    return NextResponse.json(
      { ok: false, error: e instanceof Error ? e.message : String(e) },
      { status: 500 },
    );
  }
}

export async function POST(req: Request) {
  const rejection = validateLocalJsonMutation(req);
  if (rejection) return rejection;

  const declaredLength = Number(req.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > 2 * 1024 * 1024) {
    return NextResponse.json(
      { ok: false, error: "Project payload too large" },
      { status: 413 },
    );
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ ok: false, error: "Invalid JSON" }, { status: 400 });
  }
  const schemaError = validateScreenshotProjectState(body);
  if (schemaError) {
    return NextResponse.json(
      { ok: false, error: schemaError },
      { status: 422 },
    );
  }
  try {
    const pretty = JSON.stringify(body, null, 2) + "\n";
    if (Buffer.byteLength(pretty, "utf8") > 2 * 1024 * 1024) {
      return NextResponse.json(
        { ok: false, error: "Project payload too large" },
        { status: 413 },
      );
    }
    await atomicWriteProjectFile(pretty);
    return NextResponse.json({ ok: true });
  } catch (e) {
    return NextResponse.json(
      { ok: false, error: e instanceof Error ? e.message : String(e) },
      { status: 500 },
    );
  }
}
