import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { evaluateAndroidRuntimeGate } from "./android-runtime-gates.ts";

Deno.test("android runtime gate is fail closed", () => {
  assertEquals(evaluateAndroidRuntimeGate(undefined, 7), {
    enabled: false,
    reason: "missing_flag",
  });
  assertEquals(
    evaluateAndroidRuntimeGate({ kill_switch: true, rollout_mode: "all" }, 7),
    {
      enabled: false,
      reason: "kill_switch",
    },
  );
  assertEquals(
    evaluateAndroidRuntimeGate({ kill_switch: false, rollout_mode: "off" }, 7),
    {
      enabled: false,
      reason: "rollout_off",
    },
  );
});

Deno.test("android runtime gate evaluates allowlist and minimum modes", () => {
  assertEquals(
    evaluateAndroidRuntimeGate({
      kill_switch: false,
      rollout_mode: "version_allowlist",
      enabled_android_version_codes: [6, "7"],
    }, 7),
    { enabled: true, reason: "version_allowlist" },
  );
  assertEquals(
    evaluateAndroidRuntimeGate({
      kill_switch: false,
      rollout_mode: "min_version",
      min_android_version_code: 8,
    }, 7),
    { enabled: false, reason: "below_minimum_version" },
  );
  assertEquals(
    evaluateAndroidRuntimeGate({
      kill_switch: false,
      rollout_mode: "all",
      min_android_version_code: 7,
    }, 7),
    { enabled: true, reason: "all" },
  );
});
