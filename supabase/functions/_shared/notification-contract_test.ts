import { assertEquals } from "https://deno.land/std@0.208.0/testing/asserts.ts";
import {
  classifyAPNsResponse,
  classifyAPNsTransportError,
  notificationContentError,
  notificationDestinationError,
  notificationKindContract,
  notificationPayloadError,
} from "./notification-contract.ts";

Deno.test("notification kind catalog keeps existing production kinds", () => {
  assertEquals(
    notificationKindContract("analysis_complete")?.preferenceKey,
    "analysis_complete",
  );
  assertEquals(
    notificationKindContract("report_ready")?.preferenceKey,
    "report_ready",
  );
  assertEquals(
    notificationKindContract("account_updates")?.preferenceKey,
    "account_updates",
  );
  assertEquals(
    notificationKindContract("trial_reminder")?.preferenceKey,
    "trial_reminder",
  );
  assertEquals(
    notificationDestinationError({
      contract: notificationKindContract("analysis_complete")!,
      destination: "history",
    }),
    null,
  );
});

Deno.test("engagement kinds share app_reminders and require preference row", () => {
  for (
    const kind of [
      "first_analysis_reminder",
      "inactivity_reminder",
      "manual_app_reminder",
    ]
  ) {
    const contract = notificationKindContract(kind);
    assertEquals(contract?.preferenceKey, "app_reminders");
    assertEquals(contract?.requiresPreferenceRow, true);
  }
});

Deno.test("unknown notification kinds fail closed", () => {
  assertEquals(notificationKindContract("unknown_kind"), null);
  assertEquals(notificationKindContract(undefined), null);
});

Deno.test("content and destinations enforce bounded contracts", () => {
  assertEquals(
    notificationContentError({ title: "Başlık", body: "Gövde" }),
    null,
  );
  assertEquals(
    notificationContentError({ title: "x".repeat(81), body: "Gövde" }),
    "title_too_long",
  );
  assertEquals(
    notificationContentError({ title: "Başlık", body: "x".repeat(241) }),
    "body_too_long",
  );

  const reminder = notificationKindContract("inactivity_reminder")!;
  assertEquals(
    notificationDestinationError({
      contract: reminder,
      destination: "new_analysis",
    }),
    null,
  );
  assertEquals(
    notificationDestinationError({
      contract: reminder,
      destination: "reports",
    }),
    "destination_not_allowed_for_kind",
  );
});

Deno.test("push data stays bounded and excludes sensitive analysis content", () => {
  assertEquals(
    notificationPayloadError({
      analysis_id: "analysis-id",
      destination: "history",
      nested: { event: "analysis_complete" },
    }),
    null,
  );
  assertEquals(
    notificationPayloadError({ raw_ai_response: { findings: [] } }),
    "sensitive_data_key_not_allowed",
  );
  assertEquals(
    notificationPayloadError({ safe: "x".repeat(2_600) }),
    "data_too_large",
  );
  assertEquals(notificationPayloadError([]), "data_must_be_object");
});

Deno.test("APNs response classification separates retry and token invalidation", () => {
  assertEquals(classifyAPNsResponse(200), {
    outcome: "accepted",
    retryable: false,
    disableToken: false,
    reason: "accepted",
  });
  assertEquals(classifyAPNsResponse(410, '{"reason":"Unregistered"}'), {
    outcome: "permanent",
    retryable: false,
    disableToken: true,
    reason: "Unregistered",
  });
  assertEquals(classifyAPNsResponse(400, '{"reason":"BadDeviceToken"}'), {
    outcome: "permanent",
    retryable: false,
    disableToken: true,
    reason: "BadDeviceToken",
  });
  assertEquals(classifyAPNsResponse(429, '{"reason":"TooManyRequests"}'), {
    outcome: "transient",
    retryable: true,
    disableToken: false,
    reason: "TooManyRequests",
  });
  assertEquals(classifyAPNsResponse(500, '{"reason":"InternalServerError"}'), {
    outcome: "transient",
    retryable: true,
    disableToken: false,
    reason: "InternalServerError",
  });
  assertEquals(classifyAPNsTransportError(), {
    outcome: "ambiguous",
    retryable: false,
    disableToken: false,
    reason: "ambiguous_transport",
  });
});
