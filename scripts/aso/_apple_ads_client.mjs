#!/usr/bin/env node
// Shared client for the Apple Ads Platform API (https://api.ads.apple.com/v1/).
//
// Credentials live in .secrets/ (gitignored). The private key never leaves the
// machine: it only signs the client secret JWT that is exchanged for a
// short-lived access token.

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const SECRETS_DIR = path.join(REPO_ROOT, ".secrets");
const CREDENTIALS_PATH = path.join(SECRETS_DIR, "apple-ads-credentials.json");
const TOKEN_CACHE_PATH = path.join(SECRETS_DIR, "apple-ads-token.json");

const TOKEN_ENDPOINT = "https://appleid.apple.com/auth/oauth2/token";
const API_BASE_URL = "https://api.ads.apple.com/v1";
const OAUTH_SCOPE = "searchadsorg";

// Apple caps the client secret at 180 days; keep it short since it is minted
// per invocation anyway.
const CLIENT_SECRET_TTL_SECONDS = 300;
// Refresh the access token slightly before Apple expires it.
const TOKEN_EXPIRY_SKEW_SECONDS = 60;

// Raw file contents, with paths left as written. Use this when rewriting the
// file so machine-specific absolute paths never get persisted.
export function readCredentialsFile() {
  if (!fs.existsSync(CREDENTIALS_PATH)) {
    throw new Error(`Missing ${path.relative(REPO_ROOT, CREDENTIALS_PATH)}.`);
  }
  return JSON.parse(fs.readFileSync(CREDENTIALS_PATH, "utf8"));
}

export function readCredentials() {
  if (!fs.existsSync(CREDENTIALS_PATH)) {
    throw new Error(
      `Missing ${path.relative(REPO_ROOT, CREDENTIALS_PATH)}. ` +
        "Copy scripts/aso/apple-ads-credentials.example.json into .secrets/ and fill in " +
        "clientId, teamId and keyId from Apple Ads > Account Settings > API.",
    );
  }

  const credentials = JSON.parse(fs.readFileSync(CREDENTIALS_PATH, "utf8"));
  for (const field of ["clientId", "teamId", "keyId"]) {
    if (!credentials[field] || typeof credentials[field] !== "string") {
      throw new Error(`Credential field "${field}" is missing or not a string.`);
    }
  }

  const privateKeyPath = path.resolve(
    REPO_ROOT,
    credentials.privateKeyPath ?? ".secrets/apple-ads-private-key.pem",
  );
  if (!fs.existsSync(privateKeyPath)) {
    throw new Error(`Private key not found at ${privateKeyPath}.`);
  }

  return { ...credentials, privateKeyPath };
}

export function writeCredentials(credentials) {
  fs.writeFileSync(CREDENTIALS_PATH, `${JSON.stringify(credentials, null, 2)}\n`, { mode: 0o600 });
}

function base64url(input) {
  return Buffer.from(input).toString("base64url");
}

// ES256 JWT, per Apple's "Create a client secret" step.
function createClientSecret(credentials) {
  const issuedAt = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: credentials.keyId };
  const payload = {
    iss: credentials.teamId,
    iat: issuedAt,
    exp: issuedAt + CLIENT_SECRET_TTL_SECONDS,
    aud: "https://appleid.apple.com",
    sub: credentials.clientId,
  };

  const unsigned = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(payload))}`;
  const signer = crypto.createSign("sha256");
  signer.update(unsigned);
  signer.end();
  const signature = signer.sign({
    key: fs.readFileSync(credentials.privateKeyPath, "utf8"),
    dsaEncoding: "ieee-p1363",
  });

  return `${unsigned}.${base64url(signature)}`;
}

function readCachedToken() {
  if (!fs.existsSync(TOKEN_CACHE_PATH)) return null;
  try {
    const cached = JSON.parse(fs.readFileSync(TOKEN_CACHE_PATH, "utf8"));
    if (typeof cached.accessToken !== "string" || typeof cached.expiresAt !== "number") return null;
    if (cached.expiresAt - TOKEN_EXPIRY_SKEW_SECONDS <= Math.floor(Date.now() / 1000)) return null;
    return cached.accessToken;
  } catch {
    return null;
  }
}

export async function getAccessToken({ forceRefresh = false } = {}) {
  if (!forceRefresh) {
    const cached = readCachedToken();
    if (cached) return cached;
  }

  const credentials = readCredentials();
  const body = new URLSearchParams({
    grant_type: "client_credentials",
    client_id: credentials.clientId,
    client_secret: createClientSecret(credentials),
    scope: OAUTH_SCOPE,
  });

  const response = await fetch(TOKEN_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });

  const text = await response.text();
  if (!response.ok) {
    throw new Error(`Token request failed (${response.status}): ${text}`);
  }

  const payload = JSON.parse(text);
  if (!payload.access_token) {
    throw new Error("Token response did not contain an access_token.");
  }

  fs.writeFileSync(
    TOKEN_CACHE_PATH,
    `${JSON.stringify(
      {
        accessToken: payload.access_token,
        expiresAt: Math.floor(Date.now() / 1000) + Number(payload.expires_in ?? 3600),
      },
      null,
      2,
    )}\n`,
    { mode: 0o600 },
  );

  return payload.access_token;
}

const MAX_RETRIES = 5;
const MAX_BACKOFF_SECONDS = 16;

const sleep = (seconds) => new Promise((resolve) => setTimeout(resolve, seconds * 1000));

// Paces requests using the RateLimit-* / Retry-After response headers, as the
// Apple Ads Platform API rate-limit guidance prescribes.
export async function apiRequest(pathname, { method = "GET", body, adAccountId } = {}) {
  let backoff = 2;

  for (let attempt = 0; attempt < MAX_RETRIES; attempt += 1) {
    const headers = {
      Authorization: `Bearer ${await getAccessToken()}`,
      Accept: "application/json",
    };
    // Org-level endpoints (/me, /acls, /orgs/{id}) must not carry X-AP-Context.
    if (adAccountId) headers["X-AP-Context"] = `adAccountId=${adAccountId}`;
    if (body !== undefined) headers["Content-Type"] = "application/json";

    const response = await fetch(`${API_BASE_URL}${pathname}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });

    if (response.status === 429) {
      const retryAfter =
        response.headers.get("Retry-After") ?? response.headers.get("RateLimit-Reset");
      await sleep(retryAfter === null ? backoff : Number(retryAfter));
      backoff = Math.min(backoff * 2, MAX_BACKOFF_SECONDS);
      continue;
    }

    if (response.status === 401 && attempt === 0) {
      await getAccessToken({ forceRefresh: true });
      continue;
    }

    const text = await response.text();
    if (!response.ok) {
      throw new Error(`${method} ${pathname} failed (${response.status}): ${text}`);
    }

    // Throttle proactively so the next call does not walk into a 429.
    const remaining = response.headers.get("RateLimit-Remaining");
    const reset = response.headers.get("RateLimit-Reset");
    if (remaining !== null && reset !== null && Number(remaining) < 5) {
      await sleep(Number(reset));
    }

    return text ? JSON.parse(text) : null;
  }

  throw new Error(`Exceeded ${MAX_RETRIES} retries for ${method} ${pathname}.`);
}

export { API_BASE_URL, CREDENTIALS_PATH, REPO_ROOT, SECRETS_DIR };
