#!/usr/bin/env node
// Pulls the Apple Ads Platform API search term popularity report (Insights) and
// stores one JSON snapshot per period under appstore/aso/search-terms/.
//
// The endpoint returns the top ~500 search terms per country/genre, not a
// lookup for arbitrary keywords. Terms below 500 searches are excluded by
// Apple, so long-tail keywords never appear here.
//
// Usage:
//   node scripts/aso/fetch_search_term_popularity.mjs \
//     --genre HEALTH_FITNESS [--granularity WEEKLY_SUN_SAT|MONTHLY] \
//     [--countries US,GB,CA,AU,TR] [--start YYYY-MM-DD] [--end YYYY-MM-DD]
//
// Defaults: the countries backing appstore/app.json locales, the most recently
// completed week, sorted by rankInGenre ascending.

import fs from "node:fs";
import path from "node:path";

import { apiRequest, readCredentials, REPO_ROOT } from "./_apple_ads_client.mjs";

const PAGE_SIZE = 500; // endpoint caps pagination.pageSize at 5000
const OUTPUT_DIR = path.join(REPO_ROOT, "appstore", "aso", "search-terms");

// App Store locales the release ships with, mapped to storefront countries.
const LOCALE_TO_COUNTRY = {
  tr: "TR",
  "en-GB": "GB",
  "en-AU": "AU",
  "en-US": "US",
  "en-CA": "CA",
};

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    if (!argv[i].startsWith("--")) continue;
    const key = argv[i].slice(2);
    const value = argv[i + 1];
    if (!value || value.startsWith("--")) throw new Error(`Missing value for --${key}`);
    args[key] = value;
    i += 1;
  }
  return args;
}

function defaultCountries() {
  const appJSON = JSON.parse(
    fs.readFileSync(path.join(REPO_ROOT, "appstore", "app.json"), "utf8"),
  );
  const countries = (appJSON.locales ?? [])
    .map((locale) => LOCALE_TO_COUNTRY[locale])
    .filter(Boolean);
  if (countries.length === 0) throw new Error("Could not derive countries from appstore/app.json.");
  return [...new Set(countries)];
}

// Apple generates weekly data on Mondays 07:00 UTC for the preceding
// Sunday-Saturday week, and monthly data on the 5th for the prior month.
function defaultTimeRange(granularity) {
  const now = new Date();
  if (granularity === "MONTHLY") {
    const month = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1));
    const iso = month.toISOString().slice(0, 10);
    return { start: iso, end: iso };
  }

  // Walk back to the Sunday that starts the last fully completed week.
  const end = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() - now.getUTCDay() - 1),
  );
  const start = new Date(end.getTime() - 6 * 24 * 60 * 60 * 1000);
  return { start: start.toISOString().slice(0, 10), end: end.toISOString().slice(0, 10) };
}

async function fetchAllRows({ adAccountId, countries, genre, timeRange }) {
  const rows = [];
  let offset = 0;

  for (;;) {
    const response = await apiRequest("/insights/apps/search-term-popularity/query", {
      method: "POST",
      adAccountId,
      body: {
        filters: [
          { field: "countryOrRegion", operator: "IN", value: countries },
          { field: "genre", operator: "EQUALS", value: genre },
        ],
        timeRange,
        sorting: [{ field: "rankInGenre", order: "ASC" }],
        pagination: { offset, pageSize: PAGE_SIZE },
      },
    });

    const page = response?.result?.rows ?? [];
    rows.push(...page);

    const total = response?.pagination?.totalCount ?? rows.length;
    offset += PAGE_SIZE;
    if (page.length === 0 || rows.length >= total) break;
  }

  return rows;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const credentials = readCredentials();
  if (!credentials.adAccountId) {
    throw new Error("adAccountId is unset. Run node scripts/aso/apple_ads_bootstrap.mjs first.");
  }

  const genre = args.genre;
  if (!genre) throw new Error("--genre is required (e.g. HEALTH_FITNESS, PRODUCTIVITY_UTILITIES).");

  const granularity = args.granularity ?? "WEEKLY_SUN_SAT";
  if (!["WEEKLY_SUN_SAT", "MONTHLY"].includes(granularity)) {
    throw new Error("--granularity must be WEEKLY_SUN_SAT or MONTHLY.");
  }

  const countries = args.countries ? args.countries.split(",") : defaultCountries();
  const fallbackRange = defaultTimeRange(granularity);
  const timeRange = {
    start: args.start ?? fallbackRange.start,
    end: args.end ?? fallbackRange.end,
    granularity,
  };

  console.log(
    `Querying ${genre} / ${countries.join(",")} / ${timeRange.start}..${timeRange.end} (${granularity})`,
  );

  const rows = await fetchAllRows({
    adAccountId: credentials.adAccountId,
    countries,
    genre,
    timeRange,
  });

  const label = granularity === "MONTHLY" ? timeRange.start.slice(0, 7) : timeRange.start;
  const outputPath = path.join(OUTPUT_DIR, genre.toLowerCase(), `${label}.json`);
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(
    outputPath,
    `${JSON.stringify({ genre, countries, timeRange, fetchedAt: new Date().toISOString(), rows }, null, 2)}\n`,
  );

  const perCountry = countries
    .map((country) => `${country}=${rows.filter((row) => row.countryOrRegion === country).length}`)
    .join(" ");
  console.log(`${rows.length} rows (${perCountry}) -> ${path.relative(REPO_ROOT, outputPath)}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
