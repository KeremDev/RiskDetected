#!/usr/bin/env node

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { basename, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const requireFromEditor = createRequire(
  resolve(ROOT, "appstore/screenshots/editor/package.json"),
);
const sharp = requireFromEditor("sharp");
const appConfig = JSON.parse(
  readFileSync(resolve(ROOT, "appstore/app.json"), "utf8"),
);
const finalRoot = resolve(ROOT, appConfig.screenshots.final_root);
const outputDir = resolve(ROOT, "appstore/screenshots/qa");
const expectedWidth = 1290;
const expectedHeight = 2796;
const expectedCount = appConfig.screenshots.slides_per_locale;
const tileWidth = 258;
const tileHeight = 559;
const gap = 18;
const labelHeight = 48;
const topRegionHeight = 520;
const minimumTopRegionLuminance = 150;

const errors = [];
const files = [];

function sha256(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

function escapeXML(value) {
  return value.replace(/[&<>"']/g, (character) => {
    const replacements = {
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&apos;",
    };
    return replacements[character];
  });
}

for (const protectedLocale of appConfig.protected_locales) {
  for (let index = 1; index <= expectedCount; index += 1) {
    const path = resolve(
      finalRoot,
      protectedLocale,
      `${String(index).padStart(2, "0")}.png`,
    );
    if (existsSync(path)) {
      errors.push(`Protected locale screenshot must not exist: ${path}`);
    }
  }
}

for (const locale of appConfig.mutable_locales) {
  for (let index = 1; index <= expectedCount; index += 1) {
    const filename = `${String(index).padStart(2, "0")}.png`;
    const path = resolve(finalRoot, locale, filename);
    if (!existsSync(path)) {
      errors.push(`Missing screenshot: ${path}`);
      continue;
    }

    const image = sharp(path);
    const metadata = await image.metadata();
    if (
      metadata.width !== expectedWidth ||
      metadata.height !== expectedHeight ||
      metadata.format !== "png"
    ) {
      errors.push(
        `${path} is ${metadata.width}x${metadata.height} ${metadata.format}; ` +
          `expected ${expectedWidth}x${expectedHeight} png.`,
      );
    }

    const topStats = await sharp(path)
      .extract({
        left: 0,
        top: 0,
        width: expectedWidth,
        height: topRegionHeight,
      })
      .stats();
    const rgb = topStats.channels.slice(0, 3).map((channel) => channel.mean);
    const luminance = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2];
    if (luminance < minimumTopRegionLuminance) {
      errors.push(
        `${path} top-region luminance ${luminance.toFixed(1)} is below ` +
          `${minimumTopRegionLuminance}; light-theme export expected.`,
      );
    }

    files.push({
      locale,
      index,
      filename,
      path,
      width: metadata.width,
      height: metadata.height,
      format: metadata.format,
      top_region_luminance: Number(luminance.toFixed(1)),
      bytes: readFileSync(path).byteLength,
      sha256: sha256(path),
    });
  }
}

if (errors.length > 0) {
  console.error(errors.join("\n"));
  process.exit(1);
}

mkdirSync(outputDir, { recursive: true });
const sheetWidth = expectedCount * tileWidth + (expectedCount - 1) * gap;
const rowHeight = labelHeight + tileHeight;
const sheetHeight =
  appConfig.mutable_locales.length * rowHeight +
  (appConfig.mutable_locales.length - 1) * gap;
const composites = [];

for (let row = 0; row < appConfig.mutable_locales.length; row += 1) {
  const locale = appConfig.mutable_locales[row];
  const rowTop = row * (rowHeight + gap);
  const label = Buffer.from(
    `<svg width="${sheetWidth}" height="${labelHeight}">
      <rect width="100%" height="100%" fill="#ffffff"/>
      <text x="4" y="32" font-family="Arial, sans-serif" font-size="28"
        font-weight="700" fill="#171717">${escapeXML(locale)}</text>
    </svg>`,
  );
  composites.push({ input: label, left: 0, top: rowTop });

  for (let column = 0; column < expectedCount; column += 1) {
    const file = files.find(
      (entry) => entry.locale === locale && entry.index === column + 1,
    );
    const thumbnail = await sharp(file.path)
      .resize(tileWidth, tileHeight, { fit: "fill" })
      .png()
      .toBuffer();
    composites.push({
      input: thumbnail,
      left: column * (tileWidth + gap),
      top: rowTop + labelHeight,
    });
  }
}

const contactSheetPath = resolve(outputDir, "contact-sheet.png");
await sharp({
  create: {
    width: sheetWidth,
    height: sheetHeight,
    channels: 4,
    background: "#ffffff",
  },
})
  .composite(composites)
  .png()
  .toFile(contactSheetPath);

const manifest = {
  schema_version: 1,
  generated_at: new Date().toISOString(),
  valid: true,
  theme: "light",
  expected_dimensions: {
    width: expectedWidth,
    height: expectedHeight,
  },
  mutable_locales: appConfig.mutable_locales,
  protected_locales: appConfig.protected_locales,
  protected_locale_files_found: 0,
  file_count: files.length,
  files: files.map(({ path, ...entry }) => ({
    ...entry,
    relative_path: path.slice(ROOT.length + 1),
  })),
  contact_sheet: basename(contactSheetPath),
};
writeFileSync(
  resolve(outputDir, "manifest.json"),
  `${JSON.stringify(manifest, null, 2)}\n`,
);

console.log(
  `Validated ${files.length} light screenshots across ` +
    `${appConfig.mutable_locales.length} mutable locales.`,
);
console.log(`Contact sheet: ${contactSheetPath}`);
