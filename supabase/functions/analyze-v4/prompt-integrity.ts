import {
  V4_GEMINI3_RESPONSE_SCHEMA,
  V4_PROVIDER_RESPONSE_SCHEMA,
} from "./contracts.ts";
import { V5_RESPONSE_SCHEMA } from "./v5-contracts.ts";
import { V5_FREE_PROMPT } from "./v5-prompt.ts";
import {
  V4_COVERAGE_REPAIR_COMMON,
  V4_GEMINI3_OUTPUT_LANGUAGE_LINE,
  V4_GEMINI3_PROMPT,
  V4_PROMPT_COMMON,
  V4_TARGETED_PROMPT_COMMON,
} from "./prompt.ts";
import { V4_VERIFICATION_PROMPT_COMMON } from "./verification-pass.ts";
import { V4_LANGUAGE_CORRECTION_COMMON } from "./language-contract.ts";

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
  return `${V4_PROMPT_COMMON.trim()}\n---COVERAGE-REPAIR---\n${V4_COVERAGE_REPAIR_COMMON.trim()}\n---TARGETED---\n${V4_TARGETED_PROMPT_COMMON.trim()}\n---VERIFICATION---\n${V4_VERIFICATION_PROMPT_COMMON.trim()}\n---LANGUAGE---\n${V4_LANGUAGE_CORRECTION_COMMON.trim()}\n---SCHEMA---\n${
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

/**
 * The Gemini 3 core prompt, hashed on its own.
 *
 * Deliberately not folded into the base bundle: gemini-2.5-flash never receives
 * this text, and mixing it in would move the SHA that its measured runs were
 * made under, for a change that cannot affect them.
 */
export async function computeV4Gemini3PromptSHA256(): Promise<string> {
  return await sha256Text(
    `${V4_GEMINI3_PROMPT.trim()}\n---LANG---\n${
      V4_GEMINI3_OUTPUT_LANGUAGE_LINE.trim()
    }\n---SCHEMA---\n${stable(V4_GEMINI3_RESPONSE_SCHEMA)}`,
  );
}

/**
 * The free engine's prompt and schema, hashed together and on their own.
 *
 * Same rule as the other two bundles: bump V5_PROMPT_VERSION first, then read
 * the hash from the test. Kept separate so neither the 2.5 baseline nor the
 * Gemini 3 contract core moves when this engine changes.
 */
export async function computeV5PromptSHA256(): Promise<string> {
  return await sha256Text(
    `${V5_FREE_PROMPT.trim()}\n---SCHEMA---\n${stable(V5_RESPONSE_SCHEMA)}`,
  );
}

export async function assertV5PromptIntegrity(
  expected: unknown,
): Promise<string> {
  const actual = await computeV5PromptSHA256();
  if (typeof expected !== "string" || expected !== actual) {
    throw new Error(`v5_prompt_integrity_mismatch:${actual}`);
  }
  return actual;
}
