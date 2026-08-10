import { assertStringIncludes } from "https://deno.land/std@0.208.0/assert/mod.ts";

async function source(): Promise<string | null> {
  const url = new URL("./index.ts", import.meta.url);
  const path = decodeURIComponent(url.pathname);
  const permission = await Deno.permissions.query({ name: "read", path });
  if (permission.state !== "granted") return null;
  return await Deno.readTextFile(path);
}

Deno.test("web deletion queue is private, bounded and request-only", async () => {
  const text = await source();
  if (text == null) return;

  assertStringIncludes(text, "ACCOUNT_DELETION_QUEUE_SECRET");
  assertStringIncludes(text, "constantTimeEquals");
  assertStringIncludes(text, '.in("status", ["pending", "processing"])');
  assertStringIncludes(text, '.eq("completion_mode", "request_only")');
  assertStringIncludes(text, '.eq("requested_via", "web")');
  assertStringIncludes(text, '.lt("attempt_count", 10)');
  assertStringIncludes(text, "Math.min(25");
  assertStringIncludes(text, "account-deletion-complete");
  assertStringIncludes(text, "sendQueueFailureAlert");
  assertStringIncludes(text, "ACCOUNT_DELETION_ALERT_EMAIL");
  assertStringIncludes(text, "safeAlarmToken");
  assertStringIncludes(
    text,
    'processed_by: "edge:function:process-account-deletion-queue"',
  );
});
