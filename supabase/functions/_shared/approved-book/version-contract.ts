// Version and integrity contract for the approved-book bundle.
//
// The same source items and the same versions must produce the same bytes. The
// bundle hash makes a silent catalogue edit impossible: change a Turkish
// surface form and the hash moves, the test fails, and the migration that
// writes the new hash is the record of what changed.
//
// ORDER MATTERS, and it cost three rounds to learn on the prompt bundle:
// APPROVED_BOOK_TEMPLATE_VERSION is itself hashed, so bump the version constant
// FIRST and read the hash SECOND. Reading it first yields a value that is
// already stale, which looks exactly like a flaky cache and is not.

import {
  ACTION_BY_MECHANISM,
  BARRIER_MEMBER_ORDER,
  BARRIER_MEMBER_TR,
  OBSERVATION_BASIS_TR,
  OBSERVATION_BY_MECHANISM,
  URGENCY_TR,
  VERIFICATION_BY_TOPIC,
} from "./catalogs.tr.ts";

export const APPROVED_BOOK_ENGINE_VERSION = "approved-book-v1";
export const APPROVED_BOOK_ADAPTER_VERSION = "book-source-v1";
export const APPROVED_BOOK_TEMPLATE_VERSION = "book-tr-templates-v4";
export const APPROVED_BOOK_LANGUAGE_CATALOG_VERSION = "book-tr-catalog-v2";

/**
 * Projection version for book paragraphs.
 *
 * Deliberately distinct from `approved-notebook-projection-v2`: rows written
 * under this version live beside the v2 rows rather than replacing them. Their
 * obsolete-marking is scoped per version, so nothing a user has already edited
 * moves, and clearing the observation basis returns them to exactly what they
 * had before.
 */
export const APPROVED_BOOK_PROJECTION_VERSION = "approved-book-v1";

/** Canonical JSON: sorted keys, so the hash tracks content and not key order. */
function canonical(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) {
    return `[${value.map(canonical).join(",")}]`;
  }
  const entries = Object.entries(value as Record<string, unknown>)
    .filter(([, entry]) => entry !== undefined)
    .sort(([left], [right]) => left.localeCompare(right, "en"));
  return `{${
    entries.map(([key, entry]) => `${JSON.stringify(key)}:${canonical(entry)}`)
      .join(",")
  }}`;
}

export function approvedBookBundleSource(): string {
  return canonical({
    engine: APPROVED_BOOK_ENGINE_VERSION,
    adapter: APPROVED_BOOK_ADAPTER_VERSION,
    template: APPROVED_BOOK_TEMPLATE_VERSION,
    catalog: APPROVED_BOOK_LANGUAGE_CATALOG_VERSION,
    observation: OBSERVATION_BY_MECHANISM,
    action: ACTION_BY_MECHANISM,
    verification: VERIFICATION_BY_TOPIC,
    barrier: BARRIER_MEMBER_TR,
    barrierOrder: BARRIER_MEMBER_ORDER,
    basis: OBSERVATION_BASIS_TR,
    urgency: URGENCY_TR,
  });
}

export async function computeApprovedBookBundleSHA256(): Promise<string> {
  const bytes = new TextEncoder().encode(approvedBookBundleSource());
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
