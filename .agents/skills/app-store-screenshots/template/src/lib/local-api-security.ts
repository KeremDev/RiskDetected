const LOOPBACK_HOSTS = new Set(["127.0.0.1", "::1", "localhost"]);
const DEVICES = new Set([
  "iphone",
  "ipad",
  "android",
  "android-7",
  "android-10",
  "feature-graphic",
]);
const ORIENTATIONS = new Set(["portrait", "landscape"]);
const LAYOUTS = new Set([
  "hero",
  "device-bottom",
  "device-top",
  "two-devices",
  "no-device",
  "split-landscape",
  "feature-graphic",
]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isBoundedString(
  value: unknown,
  maxLength: number,
  allowEmpty = false,
): value is string {
  return typeof value === "string" &&
    value.length <= maxLength &&
    (allowEmpty || value.trim().length > 0);
}

function isLocalizedText(value: unknown): boolean {
  if (!isRecord(value)) return false;
  const entries = Object.entries(value);
  return entries.length <= 64 &&
    entries.every(([locale, text]) =>
      isBoundedString(locale, 64) &&
      isBoundedString(text, 2_000, true)
    );
}

function isProjectSlide(value: unknown): boolean {
  if (!isRecord(value)) return false;
  return isBoundedString(value.id, 160) &&
    typeof value.layout === "string" &&
    LAYOUTS.has(value.layout) &&
    isLocalizedText(value.label) &&
    isLocalizedText(value.headline) &&
    isBoundedString(value.screenshot, 2_048);
}

export function validateScreenshotProjectState(value: unknown): string | null {
  if (!isRecord(value)) return "Project state must be an object";
  if (!isBoundedString(value.appName, 120)) return "Invalid appName";
  if (!isBoundedString(value.themeId, 80)) return "Invalid themeId";
  if (typeof value.connectedCanvas !== "boolean") {
    return "Invalid connectedCanvas";
  }
  if (
    value.schemaVersion !== undefined &&
    (!Number.isInteger(value.schemaVersion) ||
      Number(value.schemaVersion) < 1 ||
      Number(value.schemaVersion) > 100)
  ) {
    return "Invalid schemaVersion";
  }
  if (
    !Array.isArray(value.locales) ||
    value.locales.length === 0 ||
    value.locales.length > 64 ||
    !value.locales.every((locale) => isBoundedString(locale, 64))
  ) {
    return "Invalid locales";
  }
  if (
    !isBoundedString(value.locale, 64) ||
    !value.locales.includes(value.locale)
  ) {
    return "Invalid active locale";
  }
  if (typeof value.device !== "string" || !DEVICES.has(value.device)) {
    return "Invalid device";
  }
  if (
    typeof value.orientation !== "string" ||
    !ORIENTATIONS.has(value.orientation)
  ) {
    return "Invalid orientation";
  }
  if (
    value.appIcon !== undefined &&
    !isBoundedString(value.appIcon, 2_048)
  ) {
    return "Invalid appIcon";
  }
  if (!isRecord(value.slidesByDevice)) return "Invalid slidesByDevice";

  for (const [device, slides] of Object.entries(value.slidesByDevice)) {
    if (!DEVICES.has(device)) return "Invalid slide device";
    if (
      !Array.isArray(slides) ||
      slides.length > 64 ||
      !slides.every(isProjectSlide)
    ) {
      return "Invalid slides";
    }
  }
  return null;
}

export function validateLocalJsonMutation(req: Request): Response | null {
  const target = new URL(req.url);
  const hostHeader = req.headers.get("host");
  let requestOrigin: URL;
  try {
    requestOrigin = new URL(`${target.protocol}//${hostHeader ?? ""}`);
  } catch {
    return Response.json(
      { ok: false, error: "Invalid Host header" },
      { status: 403 },
    );
  }

  if (!LOOPBACK_HOSTS.has(requestOrigin.hostname)) {
    return Response.json(
      { ok: false, error: "Local editor API is loopback-only" },
      { status: 403 },
    );
  }

  const originHeader = req.headers.get("origin");
  if (!originHeader) {
    return Response.json(
      { ok: false, error: "Origin header is required" },
      { status: 403 },
    );
  }

  let origin: URL;
  try {
    origin = new URL(originHeader);
  } catch {
    return Response.json(
      { ok: false, error: "Invalid Origin header" },
      { status: 403 },
    );
  }

  if (
    !LOOPBACK_HOSTS.has(origin.hostname) ||
    origin.origin !== requestOrigin.origin
  ) {
    return Response.json(
      { ok: false, error: "Cross-origin mutation rejected" },
      { status: 403 },
    );
  }

  const contentType = req.headers
    .get("content-type")
    ?.split(";", 1)[0]
    .trim()
    .toLowerCase();
  if (contentType !== "application/json") {
    return Response.json(
      { ok: false, error: "Content-Type must be application/json" },
      { status: 415 },
    );
  }

  return null;
}
