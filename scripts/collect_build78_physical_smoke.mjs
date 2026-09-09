#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import {
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import {
  ASC_BUILD_ID,
  CANDIDATE_BUILD,
  findForbiddenEvidenceKeys,
} from "./localization_testflight_rollout_lib.mjs";

export { ASC_BUILD_ID, CANDIDATE_BUILD } from "./localization_testflight_rollout_lib.mjs";

const BUNDLE_ID = "com.riskdetected.app";
const APP_STORE_CONFIG = JSON.parse(
  readFileSync(new URL("../appstore/app.json", import.meta.url), "utf8"),
);
export const RELEASE_VERSION =
  process.env.RD_RELEASE_VERSION ?? APP_STORE_CONFIG.release.version;
const reportNow = new Date();
const reportDate = [
  reportNow.getFullYear(),
  String(reportNow.getMonth() + 1).padStart(2, "0"),
  String(reportNow.getDate()).padStart(2, "0"),
].join("-");
const DEFAULT_OUTPUT =
  `output/app-review-physical-smoke/PHYSICAL_BUILD_${CANDIDATE_BUILD}_SMOKE_READINESS_${reportDate}.json`;

function readJSON(file) {
  return JSON.parse(readFileSync(file, "utf8"));
}

function writeJSON(file, value) {
  mkdirSync(path.dirname(file), { recursive: true });
  writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`, {
    encoding: "utf8",
    mode: 0o644,
  });
}

function runDevicectl(args, jsonOutput, trailing = []) {
  const result = spawnSync("xcrun", [
    "devicectl",
    ...args,
    "--quiet",
    "--timeout",
    "20",
    "--json-output",
    jsonOutput,
    ...trailing,
  ], {
    cwd: process.cwd(),
    encoding: "utf8",
    maxBuffer: 10 * 1024 * 1024,
  });
  return {
    ok: result.status === 0,
    payload: result.status === 0 ? readJSON(jsonOutput) : null,
  };
}

function parseArguments(argv) {
  const values = {
    output: DEFAULT_OUTPUT,
    launch: false,
    expectHold: false,
  };
  for (const argument of argv) {
    if (argument.startsWith("--output=")) {
      values.output = argument.slice("--output=".length);
    } else if (argument === "--launch") {
      values.launch = true;
    } else if (argument === "--expect-hold") {
      values.expectHold = true;
    } else {
      throw new Error(`unknown argument: ${argument}`);
    }
  }
  return values;
}

function objectsIn(value, result = []) {
  if (Array.isArray(value)) {
    for (const child of value) objectsIn(child, result);
    return result;
  }
  if (!value || typeof value !== "object") return result;
  result.push(value);
  for (const child of Object.values(value)) objectsIn(child, result);
  return result;
}

function firstString(record, keys) {
  for (const key of keys) {
    const value = record?.[key];
    if (
      (typeof value === "string" || typeof value === "number") &&
      String(value).trim().length > 0
    ) {
      return String(value).trim();
    }
  }
  return null;
}

export function findInstalledCandidate(payload) {
  const app = objectsIn(payload).find((record) =>
    firstString(record, [
      "bundleIdentifier",
      "bundleID",
      "bundleId",
      "appBundleIdentifier",
      "CFBundleIdentifier",
    ]) === BUNDLE_ID
  );
  if (!app) return null;
  const version = firstString(app, [
    "bundleShortVersion",
    "shortVersion",
    "appBundleShortVersion",
    "CFBundleShortVersionString",
    "version",
  ]);
  const build = firstString(app, [
    "bundleVersion",
    "appBundleVersion",
    "CFBundleVersion",
    "build",
  ]);
  return {
    version,
    build,
    is_candidate: version === RELEASE_VERSION && build === CANDIDATE_BUILD,
  };
}

export function normalizePhysicalDevices(payload) {
  const rawDevices = Array.isArray(payload?.result?.devices)
    ? payload.result.devices
    : [];
  return rawDevices
    .filter((device) =>
      device?.hardwareProperties?.reality === "physical" &&
      (
        device?.hardwareProperties?.platform === "iOS" ||
        device?.hardwareProperties?.deviceType === "iPhone"
      )
    )
    .map((device, index) => {
      const tunnelState = String(
        device?.connectionProperties?.tunnelState ?? "unavailable",
      );
      const ddiAvailable =
        device?.deviceProperties?.ddiServicesAvailable === true;
      return {
        internal_identifier: firstString(device, ["identifier"]),
        evidence: {
          device_slot: index + 1,
          model: firstString(device?.hardwareProperties, [
            "marketingName",
            "productType",
          ]),
          os_version: firstString(device?.deviceProperties, [
            "osVersionNumber",
            "osVersion",
          ]),
          paired:
            device?.connectionProperties?.pairingState === "paired",
          developer_mode:
            String(
              device?.deviceProperties?.developerModeStatus ?? "unknown",
            ),
          reachable:
            tunnelState === "connected" ||
            tunnelState === "available" ||
            ddiAvailable,
          reachability_source:
            tunnelState === "connected" ||
              tunnelState === "available" ||
              ddiAvailable
              ? "device_list"
              : "unconfirmed",
          candidate_app: null,
          app_inventory_status: "not_checked",
        },
      };
    });
}

export function applyActiveReachabilityProbe(device, probeSucceeded) {
  if (!probeSucceeded) return device;
  device.evidence.reachable = true;
  device.evidence.reachability_source = "active_probe";
  return device;
}

export function buildPhysicalSmokeEvidence({
  observedAt,
  devices,
  launchRequested,
  launchSucceeded,
}) {
  const candidateDevices = devices.filter((device) =>
    device.evidence?.candidate_app?.is_candidate === true
  );
  const reachableDevices = devices.filter((device) =>
    device.evidence?.reachable === true
  );
  const issues = [];
  if (devices.length === 0) {
    issues.push("No paired physical iPhone is known to CoreDevice.");
  } else if (reachableDevices.length === 0) {
    issues.push("All paired physical iPhones are offline.");
  } else if (candidateDevices.length === 0) {
    issues.push(`No reachable iPhone has ${RELEASE_VERSION} (${CANDIDATE_BUILD}) installed.`);
  }
  if (launchRequested && candidateDevices.length > 0 && !launchSucceeded) {
    issues.push("Candidate launch did not succeed on an unlocked device.");
  }
  const ready = candidateDevices.length > 0 &&
    (!launchRequested || launchSucceeded);
  const evidence = {
    schema_version: 1,
    candidate: {
      version: RELEASE_VERSION,
      build: CANDIDATE_BUILD,
      asc_build_id: ASC_BUILD_ID,
      bundle_id: BUNDLE_ID,
    },
    observed_at: new Date(observedAt).toISOString(),
    status: ready ? "passed" : "hold",
    launch_requested: launchRequested,
    launch_succeeded: launchRequested ? launchSucceeded : null,
    devices: devices.map((device) => device.evidence),
    summary: {
      paired_iphone_count: devices.length,
      reachable_iphone_count: reachableDevices.length,
      candidate_install_count: candidateDevices.length,
    },
    issues,
    privacy: {
      aggregate_only: true,
      device_names_included: false,
      device_identifiers_included: false,
      serial_numbers_included: false,
      user_or_account_data_included: false,
    },
  };
  const privacyIssues = findForbiddenEvidenceKeys(evidence);
  if (privacyIssues.length > 0) {
    throw new Error(
      `physical evidence contains forbidden keys: ${privacyIssues.join(", ")}`,
    );
  }
  return evidence;
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  const temporaryDirectory = mkdtempSync(
    path.join(tmpdir(), "riskdetected-physical-smoke-"),
  );
  try {
    const devicesPath = path.join(temporaryDirectory, "devices.json");
    const listed = runDevicectl(["list", "devices"], devicesPath);
    if (!listed.ok) {
      throw new Error("devicectl could not list physical devices");
    }
    const devices = normalizePhysicalDevices(listed.payload);
    for (const [index, device] of devices.entries()) {
      if (!device.internal_identifier) continue;
      if (!device.evidence.reachable) {
        const lockPath = path.join(
          temporaryDirectory,
          `lock-state-${index}.json`,
        );
        const lockState = runDevicectl([
          "device",
          "info",
          "lockState",
          "--device",
          device.internal_identifier,
        ], lockPath);
        applyActiveReachabilityProbe(device, lockState.ok);
      }
      if (!device.evidence.reachable) continue;
      const appsPath = path.join(temporaryDirectory, `apps-${index}.json`);
      const apps = runDevicectl([
        "device",
        "info",
        "apps",
        "--device",
        device.internal_identifier,
        "--bundle-id",
        BUNDLE_ID,
      ], appsPath);
      device.evidence.app_inventory_status = apps.ok
        ? "available"
        : "unavailable";
      device.evidence.candidate_app = apps.ok
        ? findInstalledCandidate(apps.payload)
        : null;
    }

    let launchSucceeded = false;
    const launchTarget = devices.find((device) =>
      device.evidence?.candidate_app?.is_candidate === true
    );
    if (options.launch && launchTarget?.internal_identifier) {
      const launchPath = path.join(temporaryDirectory, "launch.json");
      const launched = runDevicectl([
        "device",
        "process",
        "launch",
        "--device",
        launchTarget.internal_identifier,
        "--terminate-existing",
      ], launchPath, [BUNDLE_ID]);
      launchSucceeded = launched.ok;
    }
    const evidence = buildPhysicalSmokeEvidence({
      observedAt: new Date().toISOString(),
      devices,
      launchRequested: options.launch,
      launchSucceeded,
    });
    writeJSON(options.output, evidence);
    process.stdout.write(`${JSON.stringify({
      status: evidence.status,
      output: options.output,
      ...evidence.summary,
      launch_requested: evidence.launch_requested,
      launch_succeeded: evidence.launch_succeeded,
      issues: evidence.issues,
    }, null, 2)}\n`);
    process.exitCode = evidence.status === "passed" ||
        (options.expectHold && evidence.status === "hold")
      ? 0
      : 3;
  } finally {
    rmSync(temporaryDirectory, { recursive: true, force: true });
  }
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 2;
  }
}
