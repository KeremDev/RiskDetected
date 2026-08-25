import { V4_PROVIDER_RESPONSE_SCHEMA } from "./contracts.ts";
import {
  V4_COVERAGE_REPAIR_COMMON,
  V4_PROMPT_COMMON,
  V4_TARGETED_PROMPT_COMMON,
} from "./prompt.ts";

export async function sha256Text(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

function stable(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stable).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${
      Object.entries(value as Record<string, unknown>)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([key, item]) => `${JSON.stringify(key)}:${stable(item)}`).join(
          ",",
        )
    }}`;
  }
  return JSON.stringify(value);
}

export function canonicalV4PromptBundle(): string {
  return `${V4_PROMPT_COMMON.trim()}\n---COVERAGE-REPAIR---\n${V4_COVERAGE_REPAIR_COMMON.trim()}\n---TARGETED---\n${V4_TARGETED_PROMPT_COMMON.trim()}\n---SCHEMA---\n${
    stable(V4_PROVIDER_RESPONSE_SCHEMA)
  }`;
}

export async function computeV4PromptSHA256(): Promise<string> {
  return await sha256Text(canonicalV4PromptBundle());
}

export async function assertV4PromptIntegrity(
  expected: unknown,
): Promise<string> {
  const actual = await computeV4PromptSHA256();
  if (typeof expected !== "string" || expected !== actual) {
    throw new Error(`v4_prompt_integrity_mismatch:${actual}`);
  }
  return actual;
}
