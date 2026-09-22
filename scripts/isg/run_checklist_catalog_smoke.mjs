#!/usr/bin/env node
// Staging-only authenticated acceptance. Credentials and JWTs stay in memory.
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";

const project = "qlymhrrlhklcudveknih";
const credentials = JSON.parse(readFileSync(
  process.env.OSGB_DEVICE_CREDENTIALS ?? "/tmp/isgada-osgb-device-123-credentials.json", "utf8"));
if (credentials.project_ref !== project) throw new Error("STAGING_REQUIRED");

const keys = JSON.parse(execFileSync("supabase", ["projects", "api-keys", "--project-ref", project, "-o", "json"],
  { encoding: "utf8" }));
const anon = keys.find((entry) => entry.name === "anon")?.api_key;
if (!anon) throw new Error("STAGING_ANON_KEY_REQUIRED");
async function login(account, label) {
  const response = await fetch(`https://${project}.supabase.co/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: anon, "content-type": "application/json" },
    body: JSON.stringify({ email: account.email, password: account.password }),
    signal: AbortSignal.timeout(30_000)
  });
  const session = await response.json().catch(() => null);
  if (!response.ok || !session?.access_token) throw new Error(`STAGING_${label}_LOGIN_FAILED`);
  return JSON.parse(Buffer.from(session.access_token.split(".")[1], "base64url").toString("utf8"));
}
const claims = await login(credentials.expert, "EXPERT");
const ownerClaims = await login(credentials.owner, "OWNER");
if (claims.sub !== credentials.expert.user_id || !claims.session_id) throw new Error("STAGING_SESSION_MISMATCH");
if (ownerClaims.sub !== credentials.owner.user_id || !ownerClaims.session_id) throw new Error("STAGING_OWNER_SESSION_MISMATCH");

const root = path.resolve(import.meta.dirname, "../..");
let sql = readFileSync(path.join(root, "scripts/isg/checklist_catalog_staging_acceptance.sql"), "utf8");
for (const [marker, value] of Object.entries({
  __EXPERT_ID__: claims.sub,
  __SESSION_ID__: claims.session_id,
  __OWNER_ID__: ownerClaims.sub,
  __OWNER_SESSION_ID__: ownerClaims.session_id,
  __EXPERT_MEMBERSHIP_ID__: credentials.expert_membership_id,
  __WORKSPACE_ID__: credentials.workspace.id,
  __COMPANY_ID__: credentials.company.id
})) {
  if (!sql.includes(marker)) throw new Error(`SQL_MARKER_MISSING_${marker}`);
  sql = sql.replaceAll(marker, value);
}

const managementToken = readFileSync(`${process.env.HOME}/.supabase/access-token`, "utf8").trim();
const checked = await fetch(`https://api.supabase.com/v1/projects/${project}/database/query`, {
  method: "POST", headers: { authorization: `Bearer ${managementToken}`, "content-type": "application/json" },
  body: JSON.stringify({ query: sql }), signal: AbortSignal.timeout(60_000)
});
if (!checked.ok) {
  const error = await checked.text();
  throw new Error(`CHECKLIST_ACCEPTANCE_FAILED_${checked.status}_${error.slice(0, 500)}`);
}
console.log("PASS staging OSGB checklist catalogue: list/item search, 15 company-free custom lists, immutable question snapshot, independent run, cross-list composition, duplicate guard, reorder, two-company assignment and independent answers, revision conflict, explicit nonconformity, cross-user denial; mutations rolled back");
