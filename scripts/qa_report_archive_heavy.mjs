#!/usr/bin/env node

import assert from "node:assert/strict";

const LOCAL_PAGE_SIZE = 5;
const REMOTE_FETCH_PAGE_SIZE = 100;
const NOW = new Date("2026-05-15T12:00:00.000Z");

function makeReport(index) {
  const isExcel = index % 7 === 0;
  const isRisk = isExcel || index % 3 === 0;
  const method = index % 5 === 0 ? "matrix_5x5" : "fine_kinney";
  const createdAt = new Date(
    NOW.getTime() - index * 12 * 60 * 60 * 1000
  ).toISOString();
  const title = index % 11 === 0
    ? `İş Güvenliği Denetimi ${index + 1}`
    : `Saha Raporu ${index + 1}`;

  return {
    id: `00000000-0000-4000-8000-${String(index + 1).padStart(12, "0")}`,
    storagePath: `reports/qa/${index + 1}.${isExcel ? "xlsx" : "pdf"}`,
    format: isExcel ? "xlsx" : "pdf",
    kind: isRisk ? "risk_analysis" : "standard",
    method,
    title,
    fileName: `riskdetected_${index + 1}_${isExcel ? "xlsx" : "pdf"}`,
    mimeType: isExcel
      ? "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      : "application/pdf",
    createdAt,
  };
}

function isExcelReport(report) {
  return report.format === "xlsx" ||
    report.mimeType === "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
}

function isRiskAnalysisReport(report) {
  return report.kind === "riskAnalysis" || report.kind === "risk_analysis";
}

function normalizedReportSearch(value) {
  return value
    .toLocaleLowerCase("tr-TR")
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .trim();
}

function reportSearchText(report) {
  return [
    report.title,
    report.fileName,
    report.kind,
    report.method,
    report.format ?? "",
    report.mimeType,
    report.createdAt ?? "",
  ].join(" ");
}

function isThisWeek(report) {
  const date = new Date(report.createdAt);
  const diffMs = NOW.getTime() - date.getTime();
  return diffMs >= 0 && diffMs < 7 * 24 * 60 * 60 * 1000;
}

function matchesFilter(report, filter) {
  switch (filter) {
    case "all":
      return true;
    case "pdf":
      return !isExcelReport(report);
    case "excel":
      return isExcelReport(report);
    case "standard":
      return !isExcelReport(report) && !isRiskAnalysisReport(report);
    case "riskAnalysis":
      return isRiskAnalysisReport(report) || isExcelReport(report);
    case "thisWeek":
      return isThisWeek(report);
    default:
      throw new Error(`Unknown filter: ${filter}`);
  }
}

function filteredReports(reports, { search = "", filter = "all" } = {}) {
  const needle = normalizedReportSearch(search);
  return reports.filter((report) => {
    const matchesSearch = needle === "" ||
      normalizedReportSearch(reportSearchText(report)).includes(needle);
    return matchesSearch && matchesFilter(report, filter);
  });
}

function appendStoredReports(current, incoming) {
  const ids = new Set(current.map((report) => report.id));
  const paths = new Set(current.map((report) => report.storagePath));
  return current.concat(
    incoming.filter((report) => !ids.has(report.id) && !paths.has(report.storagePath))
  );
}

function fetchPage(allReports, offset) {
  return allReports.slice(offset, offset + REMOTE_FETCH_PAGE_SIZE);
}

function revealOrFetch(state, params = {}) {
  const filtered = filteredReports(state.storedReports, params);
  if (state.visibleCount < filtered.length) {
    return {
      ...state,
      visibleCount: Math.min(state.visibleCount + LOCAL_PAGE_SIZE, filtered.length),
    };
  }

  if (!state.canLoadMoreStoredReports) {
    return state;
  }

  const moreReports = fetchPage(state.allReports, state.storedReports.length);
  const storedReports = appendStoredReports(state.storedReports, moreReports);
  const nextFiltered = filteredReports(storedReports, params);

  return {
    ...state,
    storedReports,
    canLoadMoreStoredReports: moreReports.length === REMOTE_FETCH_PAGE_SIZE,
    visibleCount: Math.min(
      state.visibleCount + LOCAL_PAGE_SIZE,
      Math.max(nextFiltered.length, state.visibleCount)
    ),
  };
}

const allReports = Array.from({ length: 247 }, (_, index) => makeReport(index));

let state = {
  allReports,
  storedReports: fetchPage(allReports, 0),
  canLoadMoreStoredReports: true,
  visibleCount: LOCAL_PAGE_SIZE,
};

assert.equal(state.storedReports.length, 100, "initial remote page should be 100 rows");
assert.equal(filteredReports(state.storedReports).slice(0, state.visibleCount).length, 5);

while (state.visibleCount < filteredReports(state.storedReports).length) {
  state = revealOrFetch(state);
}

assert.equal(state.visibleCount, 100, "local load-more should reveal first 100 rows");

state = revealOrFetch(state);
assert.equal(state.storedReports.length, 200, "remote load-more should fetch second 100 rows");
assert.equal(state.visibleCount, 105, "remote fetch should keep local reveal incremental");
assert.equal(state.canLoadMoreStoredReports, true);

while (state.storedReports.length < allReports.length) {
  while (state.visibleCount < filteredReports(state.storedReports).length) {
    state = revealOrFetch(state);
  }
  state = revealOrFetch(state);
}

assert.equal(state.storedReports.length, 247, "final remote page should append remaining rows");
assert.equal(state.canLoadMoreStoredReports, false, "remote pagination should stop after short page");

const uniqueIDs = new Set(state.storedReports.map((report) => report.id));
const uniquePaths = new Set(state.storedReports.map((report) => report.storagePath));
assert.equal(uniqueIDs.size, 247, "merged archive rows must not duplicate ids");
assert.equal(uniquePaths.size, 247, "merged archive rows must not duplicate storage paths");

const counts = Object.fromEntries(
  ["all", "pdf", "excel", "standard", "riskAnalysis", "thisWeek"].map((filter) => [
    filter,
    filteredReports(state.storedReports, { filter }).length,
  ])
);

assert.deepEqual(counts, {
  all: 247,
  pdf: 211,
  excel: 36,
  standard: 140,
  riskAnalysis: 107,
  thisWeek: 14,
});

assert.equal(
  filteredReports(state.storedReports, { search: "is guvenligi" }).length,
  23,
  "Turkish diacritic-insensitive search should match İş Güvenliği titles"
);

let excelState = {
  allReports,
  storedReports: fetchPage(allReports, 0),
  canLoadMoreStoredReports: true,
  visibleCount: LOCAL_PAGE_SIZE,
};

while (excelState.visibleCount < filteredReports(excelState.storedReports, { filter: "excel" }).length) {
  excelState = revealOrFetch(excelState, { filter: "excel" });
}

assert.equal(excelState.visibleCount, 15, "first page should reveal all local Excel rows");
excelState = revealOrFetch(excelState, { filter: "excel" });
assert.equal(excelState.storedReports.length, 200, "Excel filter should still fetch remote continuation");
assert.equal(excelState.visibleCount, 20, "Excel filter should reveal incrementally after remote fetch");

console.log("Report archive dense QA passed", {
  syntheticRows: allReports.length,
  initialFetchSize: REMOTE_FETCH_PAGE_SIZE,
  localPageSize: LOCAL_PAGE_SIZE,
  counts,
});
