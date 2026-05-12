#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";

function usage() {
  console.error(
    [
      "Usage:",
      "  node scripts/generate_apple_client_secret.mjs \\",
      "    --team-id <APPLE_TEAM_ID> \\",
      "    --key-id <APPLE_KEY_ID> \\",
      "    --client-id <APPLE_CLIENT_ID> \\",
      "    --p8 <PATH_TO_PRIVATE_KEY.p8> \\",
      "    [--expires-in-days 180]",
    ].join("\n"),
  );
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith("--")) continue;
    const key = token.slice(2);
    const value = argv[i + 1];
    if (!value || value.startsWith("--")) {
      throw new Error(`Missing value for --${key}`);
    }
    args[key] = value;
    i += 1;
  }
  return args;
}

function base64url(input) {
  return Buffer.from(input)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

try {
  const args = parseArgs(process.argv.slice(2));
  const teamID = args["team-id"];
  const keyID = args["key-id"];
  const clientID = args["client-id"];
  const p8Path = args["p8"];
  const expiresInDays = Number(args["expires-in-days"] ?? "180");

  if (!teamID || !keyID || !clientID || !p8Path) {
    usage();
    process.exit(1);
  }

  if (!Number.isFinite(expiresInDays) || expiresInDays <= 0 || expiresInDays > 180) {
    throw new Error("--expires-in-days must be between 1 and 180");
  }

  const privateKey = fs.readFileSync(p8Path, "utf8");
  const now = Math.floor(Date.now() / 1000);
  const exp = now + expiresInDays * 24 * 60 * 60;

  const header = {
    alg: "ES256",
    kid: keyID,
    typ: "JWT",
  };

  const payload = {
    iss: teamID,
    iat: now,
    exp,
    aud: "https://appleid.apple.com",
    sub: clientID,
  };

  const encodedHeader = base64url(JSON.stringify(header));
  const encodedPayload = base64url(JSON.stringify(payload));
  const unsignedToken = `${encodedHeader}.${encodedPayload}`;

  const signer = crypto.createSign("sha256");
  signer.update(unsignedToken);
  signer.end();

  const signature = signer.sign({
    key: privateKey,
    dsaEncoding: "ieee-p1363",
  });

  const token = `${unsignedToken}.${base64url(signature)}`;
  console.log(token);
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
