import {
  assertFalse,
  assertStringIncludes,
} from "https://deno.land/std@0.208.0/assert/mod.ts";

const source = await Deno.readTextFile(
  new URL("./index.ts", import.meta.url),
);

Deno.test("Android FCM data contains only typed record identifiers", () => {
  const contractStart = source.indexOf(
    "const fcmDataPayload: Record<string, string>",
  );
  const contractEnd = source.indexOf("const apnsResults", contractStart);
  const contract = source.slice(contractStart, contractEnd);

  assertStringIncludes(contract, "type: notificationKind");
  assertStringIncludes(contract, '["analysis_id", "report_id"]');
  assertStringIncludes(contract, "fcmDataPayload[key] = value");
  assertFalse(contract.includes("event_id"));
  assertFalse(contract.includes("title"));
  assertFalse(contract.includes("body"));
  assertFalse(contract.includes("payloadData,"));
});

Deno.test("iOS APNs payload remains on its existing compatibility shape", () => {
  assertStringIncludes(source, "data: payloadData");
  assertStringIncludes(source, "kind: notificationKind");
  assertStringIncludes(source, "event_id: eventID");
});
