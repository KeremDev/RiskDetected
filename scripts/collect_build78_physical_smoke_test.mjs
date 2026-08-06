import assert from "node:assert/strict";
import test from "node:test";
import {
  CANDIDATE_BUILD,
  applyActiveReachabilityProbe,
  buildPhysicalSmokeEvidence,
  findInstalledCandidate,
  normalizePhysicalDevices,
} from "./collect_build78_physical_smoke.mjs";

const rawDevice = {
  identifier: "secret-coredevice-id",
  connectionProperties: {
    tunnelState: "connected",
    pairingState: "paired",
    potentialHostnames: ["private-hostname"],
  },
  deviceProperties: {
    name: "Owner iPhone",
    osVersionNumber: "26.5.2",
    developerModeStatus: "enabled",
    ddiServicesAvailable: true,
  },
  hardwareProperties: {
    reality: "physical",
    platform: "iOS",
    deviceType: "iPhone",
    marketingName: "iPhone 17 Pro Max",
    serialNumber: "private-serial",
    udid: "private-udid",
  },
};

test("physical device normalization keeps identifiers internal", () => {
  const devices = normalizePhysicalDevices({
    result: { devices: [rawDevice] },
  });
  assert.equal(devices.length, 1);
  assert.equal(devices[0].internal_identifier, "secret-coredevice-id");
  const rendered = JSON.stringify(devices[0].evidence);
  assert.doesNotMatch(
    rendered,
    /Owner iPhone|private-serial|private-udid|private-hostname|secret-coredevice-id/u,
  );
  assert.equal(devices[0].evidence.reachable, true);
});

test("installed app parser accepts bounded CoreDevice variants", () => {
  assert.deepEqual(findInstalledCandidate({
    result: {
      apps: [{
        bundleIdentifier: "com.riskdetected.app",
        bundleShortVersion: "1.3.0",
        bundleVersion: CANDIDATE_BUILD,
        path: "/private/application/path",
      }],
    },
  }), {
    version: "1.3.0",
    build: CANDIDATE_BUILD,
    is_candidate: true,
  });
});

test("offline evidence holds without exposing device identity", () => {
  const devices = normalizePhysicalDevices({
    result: {
      devices: [{
        ...rawDevice,
        connectionProperties: {
          ...rawDevice.connectionProperties,
          tunnelState: "unavailable",
        },
        deviceProperties: {
          ...rawDevice.deviceProperties,
          ddiServicesAvailable: false,
        },
      }],
    },
  });
  const evidence = buildPhysicalSmokeEvidence({
    observedAt: "2026-08-01T16:00:00Z",
    devices,
    launchRequested: false,
    launchSucceeded: false,
  });
  assert.equal(evidence.status, "hold");
  assert.equal(evidence.summary.reachable_iphone_count, 0);
  assert.doesNotMatch(
    JSON.stringify(evidence),
    /Owner iPhone|private-serial|private-udid|secret-coredevice-id/u,
  );
});

test("active probe overrides a stale disconnected tunnel snapshot", () => {
  const devices = normalizePhysicalDevices({
    result: {
      devices: [{
        ...rawDevice,
        connectionProperties: {
          ...rawDevice.connectionProperties,
          tunnelState: "disconnected",
        },
        deviceProperties: {
          ...rawDevice.deviceProperties,
          ddiServicesAvailable: false,
        },
      }],
    },
  });
  assert.equal(devices[0].evidence.reachable, false);
  applyActiveReachabilityProbe(devices[0], true);
  assert.equal(devices[0].evidence.reachable, true);
  assert.equal(
    devices[0].evidence.reachability_source,
    "active_probe",
  );
});

test("candidate install and launch produce a passing readiness artifact", () => {
  const devices = normalizePhysicalDevices({
    result: { devices: [rawDevice] },
  });
  devices[0].evidence.app_inventory_status = "available";
  devices[0].evidence.candidate_app = {
    version: "1.3.0",
    build: CANDIDATE_BUILD,
    is_candidate: true,
  };
  const evidence = buildPhysicalSmokeEvidence({
    observedAt: "2026-08-01T16:00:00Z",
    devices,
    launchRequested: true,
    launchSucceeded: true,
  });
  assert.equal(evidence.status, "passed");
  assert.equal(evidence.summary.candidate_install_count, 1);
  assert.deepEqual(evidence.issues, []);
});
