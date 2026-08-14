#!/usr/bin/env node
import { spawnSync } from "node:child_process";

const SERVICES = {
  supabaseAccessToken: "riskdetected_supabase_access_token",
  supabaseDBPassword: "riskdetected_supabase_db_password",
  revenueCatRestAPIKey: "riskdetected_revenuecat_rest_api_key",
};

const DEFAULT_EMAILS = [
  "isgadasi@gmail.com",
  "kayalar.kerem.game@gmail.com",
  "keremkayalar@icloud.com",
  "keremtiguan@gmail.com",
];

function readKeychain(service) {
  const result = spawnSync(
    "security",
    ["find-generic-password", "-a", process.env.USER ?? "", "-s", service, "-w"],
    { encoding: "utf8" },
  );
  if (result.status !== 0) return null;
  return result.stdout.trim() || null;
}

function parseArgs() {
  const args = process.argv.slice(2);
  return {
    confirmDelete: args.includes("--confirm-delete"),
    emails: args.filter((arg) => !arg.startsWith("--")).map((email) => email.trim().toLowerCase()).filter(Boolean),
  };
}

function sqlString(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function supabaseQuery(sql, env) {
  const result = spawnSync(
    "supabase",
    ["db", "query", "--linked", "--output", "json", sql],
    {
      encoding: "utf8",
      env,
      maxBuffer: 1024 * 1024 * 8,
    },
  );

  if (result.status !== 0) {
    throw new Error(result.stderr.trim() || result.stdout.trim() || "supabase query failed");
  }

  const text = result.stdout.trim();
  if (!text) return [];
  return JSON.parse(text);
}

function normalizeRows(payload) {
  if (Array.isArray(payload)) return payload;
  if (Array.isArray(payload?.rows)) return payload.rows;
  if (Array.isArray(payload?.data)) return payload.data;
  if (Array.isArray(payload?.result)) return payload.result;
  return [];
}

function findAppUserIDs(emails, env) {
  const values = emails.map((email) => `(${sqlString(email)})`).join(",");
  const sql = `
with input(email) as (
  values ${values}
),
candidate_ids as (
  select i.email, u.id::text as app_user_id, 'auth.users' as source
  from input i
  join auth.users u on lower(u.email) = lower(i.email)

  union all

  select i.email, r.target_user_id::text as app_user_id, 'account_deletion_requests.target_user_id' as source
  from input i
  join public.account_deletion_requests r
    on lower(coalesce(r.target_email, r.email)) = lower(i.email)
  where r.target_user_id is not null
)
select
  email,
  app_user_id,
  array_agg(distinct source order by source) as sources
from candidate_ids
group by email, app_user_id
order by email, app_user_id;
`;
  return normalizeRows(supabaseQuery(sql, env));
}

async function deleteRevenueCatCustomer(appUserID, apiKey) {
  const response = await fetch(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserID)}`,
    {
      method: "DELETE",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        Accept: "application/json",
        "Content-Type": "application/json",
      },
    },
  );

  const body = await response.text().catch(() => "");
  if (response.ok) {
    return { status: "deleted", httpStatus: response.status };
  }
  return {
    status: "failed",
    httpStatus: response.status,
    error: body.slice(0, 240),
  };
}

async function main() {
  const { confirmDelete, emails: argEmails } = parseArgs();
  const emails = argEmails.length ? argEmails : DEFAULT_EMAILS;
  const supabaseAccessToken = readKeychain(SERVICES.supabaseAccessToken);
  const supabaseDBPassword = readKeychain(SERVICES.supabaseDBPassword);
  const revenueCatRestAPIKey = readKeychain(SERVICES.revenueCatRestAPIKey);

  const missing = [
    ["Supabase access token", supabaseAccessToken],
    ["Supabase DB password", supabaseDBPassword],
    ["RevenueCat REST API key", revenueCatRestAPIKey],
  ].filter(([, value]) => !value).map(([name]) => name);

  if (missing.length) {
    console.error(`Missing credentials: ${missing.join(", ")}`);
    console.error("Run `node scripts/rd_ops_env.mjs status` for Keychain service names.");
    process.exit(1);
  }

  const env = {
    ...process.env,
    SUPABASE_ACCESS_TOKEN: supabaseAccessToken,
    SUPABASE_DB_PASSWORD: supabaseDBPassword,
  };

  const rows = findAppUserIDs(emails, env);
  const found = new Map();
  for (const row of rows) {
    const email = String(row.email ?? "").toLowerCase();
    const appUserID = String(row.app_user_id ?? "");
    if (!email || !appUserID) continue;
    if (!found.has(email)) found.set(email, []);
    found.get(email).push({
      appUserID,
      sources: Array.isArray(row.sources) ? row.sources : [],
    });
  }

  for (const email of emails) {
    const candidates = found.get(email) ?? [];
    if (!candidates.length) {
      console.log(`not_found ${email}`);
      continue;
    }

    for (const candidate of candidates) {
      const sourceText = candidate.sources.length ? candidate.sources.join(",") : "unknown_source";
      if (!confirmDelete) {
        console.log(`dry_run ${email} ${candidate.appUserID} sources=${sourceText}`);
        continue;
      }

      const result = await deleteRevenueCatCustomer(candidate.appUserID, revenueCatRestAPIKey);
      if (result.status === "deleted") {
        console.log(`deleted ${email} ${candidate.appUserID} sources=${sourceText}`);
      } else {
        console.log(`failed ${email} ${candidate.appUserID} http=${result.httpStatus} ${result.error ?? ""}`.trim());
      }
    }
  }
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
