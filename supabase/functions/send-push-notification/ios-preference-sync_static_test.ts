import { assert, assertMatch, assertNotMatch } from "jsr:@std/assert";

const notificationService = await Deno.readTextFile(
  new URL(
    "../../../App/Services/NotificationService.swift",
    import.meta.url,
  ),
);

Deno.test("system authorization denial preserves application category intent", () => {
  const permissionRequest = notificationService.slice(
    notificationService.indexOf("func requestPermissionAndRegister()"),
    notificationService.indexOf("func disableNotifications()"),
  );
  assertNotMatch(
    permissionRequest,
    /guard granted else \{\s*try\?? await setMasterPreference\(enabled: false\)/,
  );
  assertNotMatch(
    permissionRequest,
    /case \.denied:\s*try\?? await setMasterPreference\(enabled: false\)/,
  );
  assertMatch(
    permissionRequest,
    /guard granted else \{\s*await syncEngagementStateIfNeeded\(force: true\)/,
  );
});

Deno.test("token refresh reads preference intent without rewriting categories", () => {
  const tokenSync = notificationService.slice(
    notificationService.indexOf("private func saveDeviceToken"),
    notificationService.indexOf("private func setMasterPreference"),
  );
  assert(tokenSync.includes("notificationPreferences?.enabled ?? false"));
  assert(tokenSync.includes('.upsert(payload, onConflict: "user_id,token")'));
  assertNotMatch(tokenSync, /notification_preferences/);
  assertNotMatch(tokenSync, /setMasterPreference/);
});
